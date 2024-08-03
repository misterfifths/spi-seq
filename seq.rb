# I don't understand how to get a sane set of SonicPi functions in external
# scripts, so this is intended to be eval'd so we get access to the context that
# the sketch is running inside. Namely:
$spi ||= self

# Depends on NoteUtils, NoteLength, Prob, and Arp


# Immutable!
# TODO: legato?
# TODO: microtiming?
class Step
  attr_reader :note, :note_number, :octave, :vel, :gate, :prob

  # note can be a string, symbol, integer MIDI note. It is always normalized
  # to a lower-case symbol of the Sonic Pi note name, and sharps and flats are
  # standardized into sharps. If you need to compare against a Step's note, make
  # sure you use such a normalized symbol, or use the has_note? method.
  # vel is the MIDI velocity for the note, 0 - 127. It is only used when the
  # note is played via MIDI, obviously.
  # gate is the percentage of the duration of the step for which the note will
  # be triggered. The note will not be played with a gate of 0, and will be
  # tied to the following step (if any) with a gate of 1.
  # prob is the probability that the step will trigger. It should be either:
  # 1. nil - the Step will always trigger
  # 2. a number between 0 and 1 inclusive that represents the chance that the
  #    Step will trigger
  # 3. a callable predicate lambda/proc that takes the arguments described by
  #    Prob.custom. If the predicate returns true, the step will trigger.
  # 4. an instance of Prob. See that class for some common cases.
  def initialize(note, vel: 127, gate: 1.0, prob: nil)
    @note, @note_number, @octave = NoteUtils.normalize(note)

    @vel = vel.to_i
    if @vel < 0
      @vel = 0
    elsif @vel > 127
      @vel = 127
    end

    # TODO: quantize this?
    @gate = gate.to_f
    if @gate < 0.0
      @gate = 0.0
    elsif @gate > 1.0
      @gate = 1.0
    end

    if prob.nil?
      @prob = nil
    elsif prob.is_a?(Numeric)
      @prob = Prob.chance(prob)
    elsif prob.is_a?(Prob)
      @prob = prob
    else
      @prob = Prob.custom(prob)  # this will raise if this isn't an appropriate predicate
    end
  end

  def mutate(**mutations)
    note = mutations.delete(:note) || @note
    [:vel, :gate, :prob].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Step.new(note, **mutations)
  end

  def with_note(new_note)
    mutate(note: new_note)
  end

  def with_vel(new_vel)
    mutate(vel: new_vel)
  end

  def with_velf(new_velf)
    mutate(vel: new_velf * 127)  # this is clamped to 0-127 in the ctor
  end

  def with_gate(new_gate)
    mutate(gate: new_gate)
  end

  def with_prob(new_prob)
    mutate(prob: new_prob)
  end

  def with_octave(new_octave)
    with_note(NoteUtils.set_octave(@note, new_octave))
  end

  def shift_octave(shift)
    with_note(NoteUtils.shift_octave(@note, shift))
  end

  # Adjusts the note by the given number of semitones.
  def shift_tone(shift)
    with_note(NoteUtils.shift_tone(@note, shift))
  end

  def velf
    @vel / 127.0
  end

  def tied?
    @gate == 1.0
  end

  # Returns whether this Step has the given note, which may be a MIDI note
  # number, a string, or a symbol. You can compare directly against the note
  # attribute if you use a normalized note symbol as returned from NoteUtils.sym
  # (lowercase, with sharps and flats standardized into sharps). Otherwise, this
  # function makes sure to do the normalization for you.
  def has_note?(n)
    @note == NoteUtils.sym(n)
  end

  # Returns whether this Step's note matches the given note. See
  # NoteUtils.match? for the definition of "match".
  def matches_note?(n)
    NoteUtils.match?(@note, n)
  end

  # Returns whether this step should play in the given cycle of playback, with
  # the given set of notes played in the previous slot. This evaluates the
  # step's probability predicate.
  def should_trigger?(cycle, prev_steps)
    return true if @prob.nil?
    @prob.should_trigger?(cycle, self, prev_steps)
  end

  def inspect
    if @prob.nil?
      prob_desc = ""
    else
      prob_desc = " prob=#{@prob}"
    end
    "<Step #{@note}/#{@note_number} vel=#{@vel} gate=#{@gate}#{prob_desc}>"
  end
end

def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


# Set global Track behaviors.
# strict_track_merging: If true, Tracks with mismatched granularities or
# timescales cannot interact with one another. That is, they cannot be merged,
# joined, zipped, or otherwise commingle. If false, generally speaking, the
# track on which a method is being called is the one that will determine the
# granularity and timescale of the result. E.g., in t1.zip(t2), the result will
# have the properties of t1. Default: false.
def use_track_defaults(strict_track_merging:)
  $spi.set(:__track_defaults, { strict_track_merging: strict_track_merging })
end


# A Track is mostly a "grid" of Steps together with a granularity. The grid is a
# 2d array, each element of which is a "slot". A slot contains some number
# (possibly 0) of Steps. Those are the Steps that should trigger (subject to
# their probabilities) when that slot is played. The order of Steps within a
# slot is not significant. There should not be more than one Step with the same
# note in a given slot; if there is, one with the longest gate will be used.
# Each slot represents the Steps for a timespan equal to the Track's
# granularity, which is some fraction of a beat (e.g. 1/4 for sixteenth note
# granularity). An empty slot represents a rest for the same duration. Thus the
# length of a Track in beats is the granularity multiplied by the number of
# slots in the grid.
# Tracks also have a timescale, which is the speed at which this track will play
# relative to the global bpm. A timescale of 2 means that this track will play
# at twice the global bpm, e.g., and 0.5 means half-speed.
# TODO: does timescale belong here? really only effects the Player, so it could
# live there, but this feels like a convenient place for it (& to mutate it)
class Track
  attr_reader :granularity, :grid, :timescale


  ### Basic constructors

  # Constructs a track with the given "gridish" definition. gridish will be
  # converted into a proper grid, an array of "slots". A slot is itself an
  # array of Steps, which all play simultaneously for a duration of the
  # granularity. A slot may be empty to represent a rest.
  # gridish is converted to a grid in the following way:
  # - A single MIDI note (symbol, string, or number) becomes grid with one slot
  #   containing a single Step created with that note and the default arguments
  #   to Step.new.
  # - A single Step becomes a grid with one slot containing just that Step.
  # - A single rest (see NoteUtils.rest?) becomes a grid with one empty slot.
  # - Each element of an array-like value is converted to a slot. Conversion
  #   rules for each child element:
  #   1. Rests become empty slots.
  #   2. Single steps become slots containing just that step.
  #   3. Single MIDI notes become slots containing a single step created with
  #      that note and the default arguments to Step.new.
  #   4. Each element of an array-like child is converted into an array of
  #      Steps using rules analogous to the above, except that rests are
  #      ignored.
  # If, after all the above conversions, there is more than one Step with the
  # same note in the same slot, a warning is printed, and only the Step with the
  # longest gate is chosen.
  # The resulting grid must have at least one slot.
  # In the end, gridish should do what you expect. For example:
  # - Pass a single note to get a one-slot track with just that note.
  # - Pass a 1-d array of notes or Steps to get a mono track where each element
  #   becomes its own slot.
  # - Pass a 2-d array of notes or Steps to get a poly track where each subarray
  #   represents the contents of a slot.
  # - Pass an array with some mixure of solitary notes and arrays to easily
  #   express a track with some slots that contain multiple Steps and some that
  #   only contain one. E.g. if gridish is [:a1, [:b2, :c3], :d4], the result
  #   will be a Track with three slots, :a1 in the first, :b2 + :c3 in the
  #   second, and :d4 in the third.
  def initialize(gridish, granularity: NoteLength::Eighth, timescale: 1)
    @grid = Track.gridify(gridish)
    raise "A Track's grid must have at least one slot" if @grid.empty?
    @granularity = NoteLength.normalize(granularity)

    raise "Timescale must be a number greater than 0" unless timescale.is_a?(Numeric) && timescale > 0
    @timescale = timescale
  end

  # Constructs a track with the given array, each element of which represents
  # a step or a rest. The elements will be played one at a time, in the given
  # order, each for a duration equal to the granularity (in other words, each
  # element of steps defines a slot with a single step). The elements of steps
  # must each be either:
  # - a Step object,
  # - a MIDI note number or symbol, which will be converted to a Step with the
  #   default arguments, or
  # - nil, :r, or :rest to represent a rest.
  # NOTE: This method is deprecated. Use the Track initializer instead.
  def self.mono(steps, granularity: NoteLength::Eighth, timescale: 1)
    # Handing off directly to the initializer will do the right thing as long
    # as each element is as described above, but will actually make a poly track
    # if any element is an array. It doesn't seem worth trying to prevent that
    # case; the method is deprecated anyway in favor of Track.new which
    # documents that behavior.
    new(steps, granularity: granularity, timescale: timescale)
  end

  # Constructs a track with the given grid. grid is a two-dimensional array,
  # each element of which is a "slot". A slot is an array, each element of which
  # represents the steps to play simultaneously for a duration of the
  # granularity. A slot may be empty to represent a rest. Non-empty slots must
  # contain some number of
  # - Step objects,
  # - MIDI note numbers or symbols, which will be converted to Steps with the
  #   default arguments, or
  # - nil, :r, or :rest to represent a rest (though this is generally
  #   unnecessary and you should just use an empty array instead)
  # NOTE: This method is deprecated. Use the Track initializer instead.
  def self.poly(grid, granularity: NoteLength::Eighth, timescale: 1)
    # Calling the initializer directly has a similar issue to that of `mono`:
    # it will do the right thing with a 2d array but will also accept non-array
    # elements. Likewise doesn't seem worth checking.
    new(grid, granularity: granularity, timescale: timescale)
  end

  # Constructs an empty track that rests for the given number of slots.
  def self.rest(num_slots = 1, granularity: NoteLength::Eighth, timescale: 1)
    grid = [[]] * num_slots
    new(grid, granularity: granularity, timescale: timescale)
  end


  ### More interesting constructors

  # Constructs a track that arpeggiates the given notes. extra_octaves is an
  # array of octave shifts. The arpeggiation will include all the notes from the
  # note array in addition to copies of them with the given octave shifts.
  # If pulses and slots are given, the arpeggiated notes are spread in a
  # Euclidean rhythm. The track will repeat the Euclidean pattern (while cycling
  # through the arpeggiated notes) however many times is needed to ensure that
  # all the notes are played and that the track loops cleanly.
  def self.arp(notes, direction = Arp::Up, spread: 0, extra_octaves: [], pulses: nil, slots: nil, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arpeggiate(notes, direction, spread: spread, extra_octaves: extra_octaves)
    if pulses.nil?
      grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
      new(grid, granularity: granularity, timescale: timescale)
    else
      raise "pulses and slots must both be nil or both be integers" if slots.nil?
      euclid(notes, pulses, slots, full_cycle: true, granularity: granularity, gate: gate, vel: vel, timescale: timescale)
    end
  end

  # Constructs a track that arpeggiates the given degrees of the tonic note in
  # the given scale. Other arguments are as specified in arp.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, spread: 0, extra_octaves: [], granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arp_degrees(tonic, degrees, direction, scale: scale, spread: spread, extra_octaves: extra_octaves)
    grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
    new(grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a mono track that plays the given notes in a Euclidean rhythm.
  # The length of the rhythm is slots, and the number of hits to play over those
  # slots is pulses. notes should be an array of note numbers or symbols, or a
  # single note number or symbol. Unless full_cycle is true (see below), the
  # returned track will have length `slots`.
  # The cycle_notes parameter controls how the notes array is used when placing
  # notes in the track. If it is true, each time there is a hit in the rhythm,
  # the next note from the notes array is used (wrapping around if needed). For
  # example, when spreading [:c3, :d3] over 3 pulses and 4 slots, the result
  # will be a track with the following steps:
  #   :c3, rest, :d3, :c3
  # If cycle_notes is false, when there is a hit in the rhythm, the note at the
  # corresponding index of that hit in the notes array is used (wrapping around
  # as needed). Using the same spread as above with cycle_notes false would
  # result in:
  #   :c3, rest, :c3, :d3
  # The third note is :c3 because the hit index, 2, corresponds :c3 in the notes
  # array (modulo the length of the array).
  # If full_cycle is true, the returned track will repeat the Euclidean pattern
  # (while cycling through the notes) however many times is needed to ensure
  # that all the notes are played and that the track loops cleanly. full_cycle
  # implies cycle_notes. For instance, spreading [:a1, :b1, :c1, :d1] over 3
  # pulses and 4 slots with full_cycle true will result in a track with the
  # following steps (the pipes are only to visually discriminate between groups
  # of the Euclidean pattern):
  #   :a1 rest :b1 :c1 | :d1 rest :a1 :b1 | :c1 rest :d1 :a1 | :b1 rest :c1 :d1
  # Note that each group repeats the same pattern of hits (hit rest hit hit),
  # but the notes cycle across repetitions, so that every given note is played
  # and the overall track is a perfect loop.
  def self.euclid(notes, pulses, slots, invert: false, rotate: 0, cycle_notes: true, full_cycle: false, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    if notes.is_a?(Numeric) || notes.is_a?(Symbol) || notes.is_a?(String)
      notes = [notes]
    end

    hits = $spi.spread(pulses, slots).to_a
    hits.rotate!(rotate) if rotate != 0
    hits.map! { |hit| !hit } if invert

    # If we're doing a full cycle of notes, we may need multiple copies of the
    # Euclidean pattern to complete a perfect loop. If we're spreading n notes
    # over p hits, we need exactly lcm(p, n) hits. And since the pattern
    # contains exactly p hits itself, we need lcm(p, n) / p copies of it.
    if full_cycle
      cycle_notes = true
      needed_groups = pulses.lcm(notes.length) / pulses
    else
      needed_groups = 1
    end

    note_idx = 0
    grid = hits.cycle(needed_groups).map.with_index do |hit, i|
      if hit
        if cycle_notes
          note = notes[note_idx % notes.length]
          note_idx += 1
        else
          note = notes[i % notes.length]
        end

        [Step.new(note, vel: vel, gate: gate)]
      else
        []
      end
    end

    new(grid, granularity: granularity, timescale: timescale)
  end


  ### Properties

  def num_slots
    @grid.length
  end

  def beat_length
    num_slots * @granularity.to_f
  end

  # Returns whether the track consists entirely of rests (i.e., empty slots).
  def empty?
    @grid.all? { |slot| slot.empty? }
  end

  alias all_rests? empty?
  alias rest? empty?

  # Returns whether the track is monophonic (i.e., all slots have <=1 Step).
  def mono?
    @grid.all? { |slot| slot.length <= 1 }
  end

  # Returns whether the track is polyphonic (i.e., any slot has >1 Step).
  def poly?
    @grid.any? { |slot| slot.length > 1 }
  end


  ### Playback support

  # Returns an array of arrays of Steps representing the state of playback at
  # slot i in the given cycle, assuming that the steps in prev_steps were the
  # Steps played in the most recently evaluated slot. The array has the
  # following elements:
  #   [newly triggered Steps, continued (tied) Steps, newly ended Steps]
  # Step probabilities are evaluated, and steps that should not trigger are not
  # returned.
  # Note that the returned array of ended steps does not strictly contain steps
  # that ended exactly at the beginning of this step. It also contains steps
  # that ended between this step and the previous one - i.e. steps with gates
  # less than 1.
  # Wraps the slot index if it exceeds the number of slots in the grid.
  # prev_steps is an array of the Steps that were active in the most recently
  # played slot. prev_steps should be nil or empty when playback is beginning.
  # cycle is the number of times the Track has played in its entirety (used to
  # evaluate Step trigger probabilities).
  # Intended to be called iteratively, incrementing i and the cycle, and feeding
  # back playing and tied steps from the return value as prev_steps.
  def steps_at_slot(i, prev_steps:, cycle:)
    # To support changing the playhead direction and swapping between Tracks,
    # it is important that this code does not assume anything about the order
    # in which slots were or will be played. It must base its logic solely on
    # the contents of slot i and prev_steps. The next steps may not come from
    # slot i+1, and the previous ones may not have come from slot i-1. In fact
    # they may not even be from this Track, if the track is swapped in the
    # Player calling this function.
    new_steps = []
    tied_steps = []
    ended_steps = []

    prev_steps ||= []
    cur_steps = @grid[i % num_slots].filter { |step| step.should_trigger?(cycle, prev_steps) }

    # distinguish between tied notes and newly started ones
    cur_steps.each do |step|
      # were we just playing this note as a tie?
      is_tie = prev_steps.one? { |prev_step| prev_step.tied? && prev_step.note == step.note }
      if is_tie
        tied_steps << step
      else
        new_steps << step
      end
    end

    # find notes from the last slot that have ended.
    prev_steps.each do |prev_step|
      # any note we were playing that is not tied has ended
      note_continues = tied_steps.one? { |tie| tie.note == prev_step.note }
      ended_steps << prev_step if !note_continues
    end

    [new_steps, tied_steps, ended_steps]
  end


  ### Etc.

  def inspect
    res = "Track slots=#{num_slots} granularity=#{granularity} timescale=#{timescale} grid:\n"
    @grid.each_with_index do |slot, i|
      res += "slot #{i} @ t=#{i * granularity.to_f}\n"
      slot.each { |step| res += "  #{step.inspect}\n" }
    end
    res
  end


  ### Mutators

  ## Granularity manipulations

  # Creates a new Track with double the granularity and number of slots. The
  # length of each Step is doubled to keep the Track sounding roughly the same,
  # which may entail turning a single step into multiple tied ones. For example,
  # expanding a 5-slot Track with 8th-note granularity will result in an 10-slot
  # Track with 16th-note granularity. A Step that had a gate of 90% would become
  # two Steps in back-to-back slots, one a tie and the following with 80% gate.
  def expand
    raise "Cannot expand past 64th-note granularity" if @granularity == NoteLength::SixtyFourth

    # Gameplan: each slot in the grid will expand to two slots. Consider each
    # slot individually. Each Step in that slot may expand to either one Step,
    # or two Steps in each of the new slots. Find the "total gate" for each Step
    # by multiplying its current gate by 2. If it is greater than one, the Step
    # becomes two Steps: one a tie, and the other with gate of total_gate - 1.
    # If the total gate is less than 1, the Step remains as one (longer) step in
    # the first of the new slots.

    def expand_step(step)
      step1_prob = step.prob
      total_gate = step.gate * 2.0
      if total_gate > 1  # TODO: tolerance?
        # If we expanded into two steps, only the second gets the probability.
        # (This is just the Oxi's behavior; it only arguably makes sense.)
        step1_prob = nil
        step2 = step.with_gate(total_gate - 1)
        total_gate = 1
      else
        step2 = nil
      end

      step1 = step.mutate(gate: total_gate, prob: step1_prob)

      [step1, step2]
    end

    new_grid = []
    @grid.each do |slot|
      new_slots = [[], []]
      slot.each do |step|
        step1, step2 = expand_step(step)
        new_slots[0] << step1
        new_slots[1] << step2 unless step2.nil?
      end

      new_grid.concat(new_slots)
    end

    mutate(grid: new_grid, granularity: @granularity.halve)
  end

  # Creates a new Track with half the granularity and number of slots. Steps and
  # tied steps have their lengths halved to keep the track sounding roughly the
  # same. For example, condensing a 10-slot Track with 8th-note granularity will
  # result in a 5-slot Track with quarter-note granularity. Say the Track
  # contained two Steps in back-to-back slots for the same note, the first a tie
  # and the second with a gate of 80. That sequence of Steps would become one
  # Step in one slot in the new track, with a gate of 90.
  # Note that this operation is potentially significantly more lossy than
  # expand. Steps with short gates and those starting on off-beats may be
  # completely absent from the result.
  def condense
    raise "Cannot condense past whole-note granularity" if @granularity == NoteLength::Whole

    # Gameplan: each pair of slots in the grid will collapse into one slot in a
    # new grid. In each pair, find the total gate of any given Step by checking
    # if it is tied to a Step with the same note in the following slot. Divide
    # that total gate by 2 and make a new step. Repeat, condensing all the steps
    # from the pair of slots into shorter steps in one slot.

    # Condense two Steps for the same note into one. The Steps are passed in-
    # order as they appear in the Track. One or the other may be nil, but not
    # both. May return nil if the steps condense to nothing.
    def condense_steps(step1, step2)
      # The Oxi seems to discard anything that begins on the second slot when
      # condensing.
      return nil if step1.nil?

      if step2.nil?
        total_gate = step1.gate / 2.0
      else
        total_gate = (step1.gate + step2.gate) / 2.0
      end

      # The probability and velocity of the second step is discarded; the first
      # step wins. (Again, just Oxi behavior.)
      step1.with_gate(total_gate)
    end

    # Condense the Steps from one or two slots into one new slot. The second
    # slot will be nil for the last slot in a Track with an odd number of slots.
    def condense_slots(slot1, slot2 = nil)
      steps_by_note = Hash.new { |h, k| h[k] = [nil, nil] }
      slot1.each { |step| steps_by_note[step.note][0] = step }
      slot2.each { |step| steps_by_note[step.note][1] = step } unless slot2.nil?

      new_slot = []
      steps_by_note.each do |_, steps|
        condensed_step = condense_steps(*steps)
        new_slot << condensed_step unless condensed_step.nil?
      end

      new_slot
    end

    new_grid = []
    @grid.each_slice(2) do |slot_chunk|
      new_grid << condense_slots(*slot_chunk)
    end

    mutate(grid: new_grid, granularity: @granularity.double)
  end

  # Calls expand or condense the appropriate number of times to return a new
  # Track with the given granularity.
  def regranularize(new_granularity)
    new_granularity = NoteLength.normalize(new_granularity)

    return self if @granularity == new_granularity

    # NOTE: this is obviously very silly, but the alternative would be making
    # expand and condense way more complicated, which is not worth it.

    steps = @granularity.steps_to(new_granularity)
    new_track = self
    steps.times do
      new_track = new_granularity < @granularity ? new_track.expand : new_track.condense
    end

    new_track
  end

  alias regrain regranularize
  alias grain regranularize

  # Returns a new track with the given granularity. Does not effect the timing
  # of any Steps; to change granularity while attempting to keep the track
  # sounding roughly the same, use condense, expand, or regranularize.
  def with_granularity(granularity)
    mutate(granularity: granularity)
  end


  ## Grid-level mutations

  # Return a new Track, replacing each slot in this track with the result of the
  # given block. The block must take 1-3 arguments:
  # - The slot
  # - The index of the slot in the Track
  # - The percent through the Track that the slot represents. For instance, the
  #   first slot of the track will have percent 0, the middle slot (in a Track
  #   with an odd number of slots) will have percent 0.5, and the final slot
  #   will have percent 1.0.
  # The block may return:
  # - A slot (an array of Steps), which will replace the slot yielded to the
  #   block
  # - nil, :r, or :rest, which will replace the slot yielded to the block with
  #   an empty slot (i.e. a rest). Note that this is the same as returning an
  #   empty array.
  # - An array of slots, which will all be added in place of the yielded slot
  def mutate_each_slot(&block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    new_grid = []
    @grid.each_with_index do |slot, i|
      if i == 0
        pct = 0.0
      elsif i == @grid.length - 1
        pct = 1.0
      else
        pct = i.to_f / (num_slots - 1)
      end

      new_slot = case block.arity
      when 1
        block.call(slot)
      when 2
        block.call(slot, i)
      when 3
        block.call(slot, i, pct)
      end

      new_grid += Track.slotify(new_slot)
    end
    mutate(grid: new_grid)
  end

  alias mutate_slots mutate_each_slot

  def with_rate(rate)
    mutate(timescale: rate)
  end

  alias rate with_rate

  # Returns a new track with other_track appended to this one. If other_track
  # is not a Track, it is converted to a compatible one using the initializer.
  def append(other_track)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)
    mutate(grid: @grid + other_track.grid)
  end

  alias concat append
  alias add append
  alias + append

  # Create a new Track that merges the Steps in corresponding slots of from this
  # track and other_track. The length of the resulting track is the maximum
  # length of the two tracks. If other_track is not a Track, it is converted to
  # a compatible one using the initializer.
  def merge(other_track)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    if num_slots > other_track.num_slots
      longer_track = self
      shorter_track = other_track
    else
      longer_track = other_track
      shorter_track = self
    end

    new_grid = longer_track.mutable_grid_dup
    shorter_track.grid.each_with_index { |slot, i| new_grid[i].concat(slot) }

    mutate(grid: new_grid)
  end

  alias | merge

  # Creates a new Track by merging each group of n consecutive slots into one
  # slot each. If n does not evenly divide the number of slots in the original
  # track, the final slot will merge the remaining slots. For example, consider
  # a track with slots [:c3, :d3, :e3, :f3, :g3]. Calling grouped_merge(2) on
  # that track would result in a new track with three slots:
  # [[:c3, :d3], [:e3, :f3], [:g3]].
  def grouped_merge(n)
    new_grid = @grid.each_slice(n).map { |slots| slots.flatten }
    mutate(grid: new_grid)
  end

  alias gmerge grouped_merge
  alias group grouped_merge

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. If other_track is not a Track, it is converted to a compatible
  # one using the initializer.
  # cycle controls the behavior if other_track is shorter than this track. When
  # cycle is false, blank slots (rests) will be interleaved once those of
  # other_track are exhausted. If cycle is true, the slots of other_track will
  # be looped as needed. For instance, consider zipping together two sequences
  # with Steps [:a1, :b1, :c1, :d1] and [:e5, :f5].
  # When cycle is false, the resulting Track will contain slots with the
  # following steps:
  #    :a1 :e5 :b1 :f5 :c1 rest :d1 rest
  # When cycle is true, the same operation will result in slots
  #    :a1 :e5 :b1 :f5 :c1 :e5 :d1 :f5
  def zip(other_track, cycle: true)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    other_grid = other_track.grid
    if cycle
      other_grid = other_grid.cycle
    else
      # In the case of a length mismatch, fill in with empty slots.
      repeating_rests = [[]].cycle
      other_grid = other_grid.chain(repeating_rests)
    end

    new_grid = @grid.zip(other_grid).flatten(1)

    mutate(grid: new_grid)
  end

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. If other_track is not a Track, it is converted to a compatible
  # one using the initializer.
  # Unlike zip, this function does not alternate between 1 slot of each track.
  # Instead, group_size many slots of this track appear consecutively, followed
  # by other_group_size slots of other_track, then group_size many slots of this
  # track, and so on. cycle controls the behavior when the other track has fewer
  # groups than this one. It behaves as described in zip. pad_short_groups
  # controls the behavior when a group size does not evenly divide the number of
  # slots in its corresponding track. If it is true, rests are added to the
  # final chunk of slots so that it has the group size.
  # For instance, consider gzipping together a track with slots with the steps
  #     :a1 :b1 :c1 :d1
  # and one with slots with steps
  #     :e2 :f2
  # If group_size is 3 and other_group_size is 1, and pad_short_groups is false,
  # the result will be
  #     :a1 :b1 :c1 :e2 :d1 :f2
  # But if pad_short_groups is true, the second group of slots from the first
  # track will be padded with two rests so that it has a length equal to its
  # group size. The result then would be
  #    :a1 :b1 :c1 :e2 :d1 rest rest :f2
  # Note that pad_short_groups applies to both groups from this track and
  # other_track.
  def grouped_zip(other_track, group_size, other_group_size, cycle: true, pad_short_groups: false)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    a_chunks = @grid.each_slice(group_size).to_a
    b_chunks = other_track.grid.each_slice(other_group_size).to_a

    if pad_short_groups
      if a_chunks.last.length < group_size
        a_chunks[-1] += [[]] * (group_size - a_chunks.last.length)
      end

      if b_chunks.last.length < other_group_size
        b_chunks[-1] += [[]] * (other_group_size - b_chunks.last.length)
      end
    end

    if cycle
      b_chunks = b_chunks.cycle
    else
      # In the case of a length mismatch, fill in with groups of
      # other_group_size many empty slots.
      repeating_empty_chunks = [[[]] * other_group_size].cycle
      b_chunks = b_chunks.chain(repeating_empty_chunks)
    end
    new_grid = a_chunks.zip(b_chunks).flatten(2)

    mutate(grid: new_grid)
  end

  alias gzip grouped_zip

  # Returns a new track that plays each successive overlapped set of n slots.
  # E.g. when called with n=3 on a track with slots :a :b :c :d :e, the
  # resulting track will have slots :a :b :c :b :c :d :c :d :e. If flatten is
  # false, each overlapped set of slots will be grouped into a slot. For
  # example, with n=3 and flatten=false, a track with slots :a :b :c :d will
  # result in a track with three slots: [[:a, :b], [:b, :c], [:c, :d]].
  def each_cons(n, flatten: true)
    new_grid = @grid.each_cons(n).to_a
    if flatten
      new_grid = new_grid.flatten(1)
    else
      new_grid.map!(&:flatten)
    end
    mutate(grid: new_grid)
  end

  # Returns a new track that plays every permutation of n slots. The order of
  # the permutations is indeterminate. If n is nil, permutes all slots.
  def permutation(n = nil)
    mutate(grid: @grid.permutation(n).to_a.flatten(1))
  end

  alias permutations permutation

  # Returns a new track that plays every combination of n slots. The order of
  # the combinations is indeterminate.
  def combination(n)
    mutate(grid: @grid.combination(n).to_a.flatten(1))
  end

  alias combinations combination

  def repeat(n)
    mutate(grid: @grid * n)
  end

  alias * repeat

  # Returns a new track that repeats the slots of this track for n slots. Note
  # that if n does not evenly divide the length of this track, the final
  # repetition in the result will be truncated so that the overall track has n
  # slots.
  def cycle_to_length(n)
    mutate(grid: @grid.cycle.take(n))
  end

  # Returns a new track with all empty slots (rests) removed.
  def compact
    mutate(grid: @grid.reject { |slot| slot.empty? })
  end

  def reverse
    mutate(grid: @grid.reverse)
  end

  alias rev reverse
  alias bw reverse

  # Returns a new Track that will play the grid forwards and then backwards,
  # repeating the slot in the middle.
  def mirror
    mutate(grid: @grid + @grid.reverse)
  end

  # Returns a new Track that will play the grid forwards and then backwards,
  # without repeating the slot in the middle.
  def reflect
    mutate(grid: @grid + @grid.reverse.drop(1))
  end

  alias bnf reflect

  # Returns a new Track with the slots in the grid shuffled.
  def shuffle
    mutate(grid: @grid.shuffle)
  end

  # Returns a new Track with the slots in the grid rotated to the right by the
  # given amount. The track duration is maintained; slots will be wrapped around
  # to the beginning of the grid as needed.
  def rotate(rightward_shift = 1)
    mutate(grid: @grid.rotate(rightward_shift))
  end

  alias right rotate
  alias rshift rotate
  alias shr rotate

  def left(leftward_shift = 1)
    rotate(-leftward_shift)
  end

  alias lshift left
  alias shl left

  # Returns a new Track by adding num_rests many empty slots (rests) to the
  # beginning of the track.
  def left_pad(num_rests = 1)
    mutate(grid: [[]] * num_rests + @grid)
  end

  alias lpad left_pad

  # Returns a new Track by adding num_rests many empty slots (rests) to the end
  # of the track.
  def right_pad(num_rests = 1)
    mutate(grid: @grid + [[]] * num_rests)
  end

  alias rpad right_pad

  # Returns a new Track by adding num_rests many empty slots (rests) after each
  # existing slot.
  def space(num_rests = 1)
    new_grid = []
    @grid.each do |slot|
      new_grid << slot
      new_grid.concat([[]] * num_rests)
    end

    mutate(grid: new_grid)
  end

  # Adds num_rests many empty slots (rests) between each group of group_size
  # slots.
  def space_every(group_size, num_rests = 1)
    new_grid = []
    @grid.each_slice(group_size) do |chunk|
      new_grid += chunk
      new_grid += [[]] * num_rests
    end

    mutate(grid: new_grid)
  end

  # Returns a new Track with the first n slots removed.
  def drop(n = 1)
    mutate(grid: @grid.drop(n))
  end

  # Returns a new Track with the final n slots removed.
  def drop_last(n = 1)
    new_grid = @grid.dup
    new_grid.pop(n)
    mutate(grid: new_grid)
  end

  # Returns a new Track consisting of only the first n slots of this track.
  def take(n)
    mutate(grid: @grid.take(n))
  end

  # Returns a new Track consisting of only the selected slots of this track.
  # Takes the same arguments as Array#slice (aka []): a single integer index, an
  # index and a length, or a range.
  def slice(*args)
    s = @grid.slice(*args)
    s = [s] if s.empty? || !s[0].is_a?(Array)
    mutate(grid: s)
  end

  alias [] slice

  # Returns a new Track consisting of n random slots from this track's grid. The
  # relative order of the chosen slots is not maintained.
  def sample(n)
    # TODO: does this use spi's rng?
    # TODO: more useful if it does maintain order? could sample an array of
    # indexes instead, sort the result, and use those to choose slots.
    mutate(grid: @grid.sample(n))
  end

  # Returns a new Track with all Steps in every nth slot removed. The duration
  # of the Track does not change; the emptied slots simply become rests. Does
  # nothing if n is zero.
  def drop_every(n)
    return self if n == 0

    # e.g., drop every 3:
    # keep  | 0 1 - 3 4 - 6 7 - 9
    # drop  |     2     5     8
    # i % 3 | 0 1 2 0 1 2 0 1 2 0
    new_grid = @grid.map.with_index do |slot, i|
      i % n == n - 1 ? [] : slot
    end

    mutate(grid: new_grid)
  end

  alias dropout drop_every

  # Return a new Track by, with probability p, removing all Steps in any given
  # slot.
  def rand_dropout(p)
    new_grid = @grid.map { |slot| $spi.rand < p ? [] : slot }
    mutate(grid: new_grid)
  end

  alias rdropout rand_dropout

  # Returns a new Track with the steps in slot idx replaced with the given
  # steps.
  def replace_slot(idx, new_steps)
    new_steps = Track.slotify(new_steps)
    new_grid = @grid.dup
    new_grid[idx] = new_steps
    mutate(grid: new_grid)
  end

  alias set_slot replace_slot

  def append_slot(idx, new_steps)
    new_slot = @grid[idx] + Track.slotify(new_steps)
    new_grid = @grid.dup
    new_grid[idx] = new_slot
    mutate(grid: new_grid)
  end

  # Returns two tracks by extracting Steps for which the block returns true.
  # The block must take 1 to 3 arguments:
  # 1. the Step
  # 2. the slot to which the Step belongs
  # 3. the index of the slot to which the Step belongs.
  # If the block returns true, the step will be placed in the second of the two
  # returned tracks. If it returns false, the step will be placed in the first.
  # The returned tracks will have the same length; if the process results in all
  # steps in a slot winding up in only one of the tracks, the slot in the other
  # track will be empty (i.e., a rest).
  # As an example, consider a Track with slots [:c2, :d2, :e2, :f2]. If the
  # block returns true for odd indices, the returned tracks will have slots
  # [:c2, rest, :e2, rest] and [rest, :d2, rest, :f2].
  def extract(&block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    grid1 = []
    grid2 = []

    @grid.each_with_index do |slot, i|
      slot1 = []
      slot2 = []

      slot.each do |step|
        should_extract = case block.arity
        when 1
          block.call(step)
        when 2
          block.call(step, slot)
        when 3
          block.call(step, slot, i)
        end

        if should_extract
          slot2 << step
        else
          slot1 << step
        end
      end

      grid1 << slot1
      grid2 << slot2
    end

    [mutate(grid: grid1), mutate(grid: grid2)]
  end

  # Returns two tracks by extracting the steps in every nth slot. The first
  # returned track will have steps in all the slots that are not every nth, and
  # the second will have steps in every nth slot.
  def extract_every(n)
    extract { |_, _, i| i % n == n - 1 }
  end

  # Returns two tracks by extracting steps that match the given note. The first
  # track contains the non-matching steps, and the second contains the matching
  # ones. See NoteUtils.match? for matching rules.
  def extract_note(note)
    extract { |step| step.matches_note?(note) }
  end

  alias extract_notes extract_note


  ## Step-level mutations

  # Return a new Track, replacing each Step in this track with the result of the
  # given block. The block must take 1-3 arguments:
  # - the Step
  # - the index of the slot to which the Step belongs
  # - the percentage through the Track that the slot the Step belongs to
  #   represents. For instance, Steps in the first slot of the track will have
  #   percent 0, steps in the middle slot (in a Track with an odd number of
  #   slots) will have percent 0.5, and steps in the final slot will have
  #   percent 1.0.
  # The block may return:
  # - A Step, which will replace the step yielded to the block
  # - nil, :r, or :rest, which will remove the step yielded to the block
  # - An array of Steps, which will all be added in place of the yielded step to
  #   the corresponding slot of the yielded step.
  def mutate_each_step(&block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    new_grid = @grid.map.with_index do |slot, i|
      if i == 0
        pct = 0.0
      elsif i == @grid.length - 1
        pct = 1.0
      else
        pct = i.to_f / (num_slots - 1)
      end

      new_slot = []
      slot.each do |step|
        new_step = case block.arity
        when 1
          block.call(step)
        when 2
          block.call(step, i)
        when 3
          block.call(step, i, pct)
        end

        new_slot += Track.slotify(new_step)
      end

      new_slot
    end

    mutate(grid: new_grid)
  end

  alias mutate_steps mutate_each_step

  def with_gate(new_gate)
    mutate_each_step { |step| step.with_gate(new_gate) }
  end

  alias gate with_gate

  def scale_gate(factor)
    mutate_each_step { |step| step.with_gate(step.gate * factor) }
  end

  # Returns a new track where each Step's gate is replaced with the result of
  # curve_func. curve_func must take 1-2 arguments:
  # - the percentage through the track (0.0-1.0) where the slot falls in the
  #   Track
  # - the index of the slot in the Track
  # curve_func should return a floating point value 0-1 that will be used for
  # all Steps in the slot at that percentage/index.
  def with_gate_curve(curve_func)
    raise "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2
    # TODO: implement this with mutate_each_slot instead?
    mutate_each_step do |step, slot_idx, pct|
      gate = case curve_func.arity
      when 1
        curve_func.call(pct)
      when 2
        curve_func.call(pct, slot_idx)
      end

      step.with_gate(gate)
    end
  end

  alias gate_curve with_gate_curve

  def with_vel(new_vel)
    mutate_each_step { |step| step.with_vel(new_vel) }
  end

  alias vel with_vel

  def with_velf(new_velf)
    mutate_each_step { |step| step.with_velf(new_velf) }
  end

  alias velf with_velf

  def scale_vel(factor)
    mutate_each_step { |step| step.with_vel(step.vel * factor) }
  end

  # Returns a new track where each Step's velocity is replaced with the result
  # of curve_func. curve_func must take 1-2 arguments:
  # - the percentage through the track (0.0-1.0) where the slot falls in the
  #   Track
  # - the index of the slot in the Track
  # curve_func should return a velocity to use for all Steps in the slot at that
  # percentage/index. The value returned by curve_func should be either:
  # - If zero_to_one is true, a floating point number 0 - 1 that will be scaled
  #   to a velocity value between 0 and 127, inclusive.
  # - If zero_to_one is false, an integer between 0 and 127, inclusive.
  # with_velf_curve is an alias where zero_to_one is true.
  def with_vel_curve(curve_func, zero_to_one: false)
    raise "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2
    # TODO: implement this with mutate_each_slot instead?
    mutate_each_step do |step, slot_idx, pct|
      vel = case curve_func.arity
      when 1
        curve_func.call(pct)
      when 2
        curve_func.call(pct, slot_idx)
      end

      vel *= 127 if zero_to_one  # with_vel will round & clamp this
      step.with_vel(vel)
    end
  end

  alias vel_curve with_vel_curve

  def with_velf_curve(curve_func)
    with_vel_curve(curve_func, zero_to_one: true)
  end

  alias velf_curve with_velf_curve

  # Returns a new track that fades in linearly, via velocity. min is the
  # starting velocity and max is the final velocity. start specifies at what
  # percentage through the track to begin the fade; all steps before start will
  # have a velocity of min, and ones thereafter will linearly increase to max.
  def fade_in_linear(min = 0.0, max = 1.0, start: 0.0)
    with_velf_curve(Curves.fade_in_linear(min, max, start))
  end

  alias fade_in_lin fade_in_linear
  alias fade_in fade_in_linear
  alias in_lin fade_in_linear

  # Same as fade_in_linear, but quadratically increases velocity.
  def fade_in_quad(min = 0.0, max = 1.0, start: 0.0)
    with_velf_curve(Curves.fade_in_quad(min, max, start))
  end

  alias in_quad fade_in_quad

  # Returns a new track that fades out linearly, via velocity. max is the
  # starting velocity and min is the final velocity. start specifies at what
  # percentage through the track to begin the fade; all steps before start will
  # have a velocity of max, and ones thereafter will linearly decrease to min.
  def fade_out_linear(max = 1.0, min = 0.0, start: 0.0)
    with_velf_curve(Curves.fade_out_linear(max, min, start))
  end

  alias fade_out_lin fade_out_linear
  alias fade_out fade_out_linear
  alias out_lin fade_out_linear

  # Same as fade_in_quad, but quadratically decreases velocity.
  def fade_out_quad(max = 1.0, min = 0.0, start: 0.0)
    with_velf_curve(Curves.fade_out_quad(max, min, start))
  end

  alias out_quad fade_out_quad

  private def taper_slots(taper_final_slot: true, taper_single: false)
    mutate_each_step do |step, slot_idx|
      next step if !step.tied? || slot_idx == 0

      prev_slot = @grid[(slot_idx - 1) % num_slots]
      next_slot = @grid[(slot_idx + 1) % num_slots]

      continuing = prev_slot.any? { |s| s.note == step.note && s.tied? }
      continues = next_slot.any? { |s| s.note == step.note && s.tied? }

      if (taper_single || continuing) && ((taper_final_slot && slot_idx == num_slots - 1) || !continues)
        yield step
      else
        step
      end
    end
  end

  # Sets the gate on the final step of runs of tied steps with the same note.
  # The final step must have a gate of 1 for this method to adjust its gate.
  # If taper_final_slot is true, steps in the final slot of the track will have
  # their gate adjusted even if their note would continue when the track loops
  # to slot 0. If taper_single is true, steps that are not continuations of a
  # tie also have their gate adjusted.
  def taper_gate(trailing_gate = 0.75, taper_final_slot: true, taper_single: false)
    taper_slots(taper_final_slot: taper_final_slot, taper_single: taper_single) { |s| s.with_gate(trailing_gate) }
  end

  # Sets the velocity on the final step of runs of tied steps, in the same
  # manner as taper_gate. If zero_to_one is true, the velocity is a percentage
  # between 0 and 1, rather than a MIDI value from 0 - 127. taper_velf is an
  # alias with zero_to_one set to true.
  def taper_vel(trailing_vel = 64, taper_final_slot: true, taper_single: false, zero_to_one: false)
    trailing_vel *= 127 if zero_to_one
    taper_slots(taper_final_slot: taper_final_slot, taper_single: taper_single) { |s| s.with_vel(trailing_vel) }
  end

  def taper_velf(trailing_vel = 0.5, taper_final_slot: true, taper_single: false)
    taper_vel(trailing_vel, taper_final_slot: taper_final_slot, taper_single: taper_single, zero_to_one: true)
  end

  def with_octave(new_octave)
    mutate_each_step { |step| step.with_octave(new_octave) }
  end

  alias octave with_octave
  alias oct octave

  def shift_octave(shift)
    mutate_each_step { |step| step.shift_octave(shift) }
  end

  def up(octave_shift = 1)
    shift_octave(octave_shift)
  end

  def down(octave_shift = 1)
    shift_octave(-octave_shift)
  end

  # Return a new track that, with probability p, shifts the octave of each Step
  # by a random value in the given range. If range is an integer,
  # [-range, range] is used.
  def rand_octave(range = 1, p: 0.5)
    mutate_each_step do |step|
      next step unless $spi.rand < p

      # We've already decided to shift, so ignore random 0 values. Not using
      # rand_i here since it's exclusive. rand is too, but we're rounding.
      shift = 0
      while shift == 0
        if range.is_a?(Range)
          shift = $spi.rand(range).round
        else
          shift = $spi.rand(-range..range).round
        end
      end

      step.shift_octave(shift)
    end
  end

  alias roct rand_octave

  def shift_tone(shift)
    mutate_each_step { |step| step.shift_tone(shift) }
  end

  alias tone shift_tone
  alias transpose shift_tone

  def semi_up(tone_shift = 1)
    shift_tone(tone_shift)
  end

  alias sup semi_up

  def semi_down(tone_shift = 1)
    shift_tone(-tone_shift)
  end

  alias sdown semi_down

  # Return a new track by, for each Step, adding additional Steps with notes
  # that are the given number of semitones away from the original. offsets
  # should be an array of integer semitones. It defaults to [-12, 12] - i.e.,
  # an octave up and down. The new Steps share the velocity, gate, and
  # probability of the Step from which they were offset. If only is provided,
  # it should be a note (number, string, or symbol) or an array of same. Only
  # steps with notes that match one in only will be harmonized, as determined by
  # NoteUtils.match?.
  def harmonize(*offsets, only: nil)
    only = [only] unless only.nil? || only.is_a?(Array)

    offsets = [-12, 12] if offsets.empty?
    mutate_each_step do |step|
      new_steps = [step]

      if only.nil? || only.any? { |n| step.matches_note?(n) }
        offsets.each { |offset| new_steps << step.shift_tone(offset) }
      end

      new_steps
    end
  end

  # Return a new track in which each Step has its note snapped to the nearest
  # note among the given array, which should consist of MIDI note numbers or
  # symbols.
  def snap_to_notes(notes)
    mutate_each_step { |step| step.with_note(NoteUtils.snap(step.note, notes)) }
  end

  # Return a new track in which each Step has its note snapped to the nearest
  # note in the given scale starting at the given root note. root should be a
  # MIDI note number of symbol, and scale should be one of the scale names known
  # to Sonic Pi.
  def snap_to_scale(root, scale)
    mutate_each_step { |step| step.with_note(NoteUtils.snap_to_scale(step.note, root, scale)) }
  end

  # Returns a new track where each Step with note orig is replaced with a Step
  # that has note repl but is otherwise identical. If orig has an explicit
  # octave (or is a MIDI note number), only Steps with that exact note are
  # effected. If orig does not have an explicit octave, repl must not either. In
  # that case, all Steps with the same pitch class as orig have their notes
  # changed to repl, in the same octave as the original step. For instance,
  # sub_note(:c, :e) on a Track with steps [:c4, :d2, :c3] would result in a
  # track with steps [:e4, :d2, :e3].
  # repl may be nil, :r, or :rest to remove Steps that match orig.
  def sub_note(orig, repl)
    has_octave = NoteUtils.has_octave?(orig)
    repl_is_rest = NoteUtils.rest?(repl)
    if has_octave
      orig = NoteUtils.sym(orig)
    else
      if !repl_is_rest && NoteUtils.has_octave?(repl)
        raise "Replacement notes cannot have an octave if the original note doesn't"
      end
      orig = NoteUtils.pitch_class(orig)
    end

    mutate_each_step do |step|
      if has_octave && step.note == orig
        repl_is_rest ? nil : step.with_note(repl)
      elsif !has_octave && NoteUtils.pitch_class(step.note) == orig
        repl_is_rest ? nil : step.with_note(NoteUtils.sym(repl, octave: step.octave))
      else
        step
      end
    end
  end

  alias sub sub_note


  ### Track construction helpers
  # TODO: philosophically I want these to be private class methods, but you
  # can't call private class methods from instance methods :(. Figure out a way
  # to deal with that, or maybe just give up and make them instance methods.

  # Attempts to convert its argument to a Step. Conversion rules are:
  # - Steps are passed through verbatim.
  # - Notes (symbols, strings and numbers) are converted to Steps using that
  #   note and the default values for the other arguments of Step's initializer.
  # - It is an error to pass a rest (as defined by NoteUtils.rest?) to this
  #   function.
  def self.stepify(x)
    raise "A rest cannot be converted to a Step" if NoteUtils.rest?(x)

    case x
    when Step
      x
    when Symbol, String, Numeric
      Step.new(x)
    else
      raise "Not a valid value for a Step: #{x.inspect}"
    end
  end

  # Given a slot (an array of Steps), returns a new slot with at most one Step
  # with each note. If multiple Steps in the input have the same note, one with
  # the longest gate is chosen.
  def self.dedupe_slot(slot)
    steps_by_note = {}
    yelled = false
    slot.each do |step|
      old_step_with_same_note = steps_by_note[step.note]
      if old_step_with_same_note.nil?
        steps_by_note[step.note] = step
      else
        if !yelled
          $spi.puts("warning: more than one Step with note #{step.note} in the same slot! Picking one with the longest gate!")
          yelled = true
        end
        steps_by_note[step.note] = step if old_step_with_same_note.gate < step.gate
      end
    end

    steps_by_note.values
  end

  private_class_method :dedupe_slot

  # Attempts to convert its argument to a grid slot (i.e. an array of Steps).
  # The returned array will be frozen. Conversion rules:
  # - Rests (see NoteUtils.rest?) become an empty slot ([]).
  # - Single notes (symbols, strings, or numbers) become a slot with a single
  #   Step that is the result of calling `stepify` on the argument.
  # - Single Steps become a slot containing just that step.
  # - Array-like arguments are converted as follows:
  #   1. All rests are removed.
  #   2. All remaining elements are passed through `stepify`.
  #   3. If more than one of the resulting Steps has the same note, a warning is
  #      printed, and only the Step with the longest gate is chosen.
  def self.slotify(x)
    return [].freeze if NoteUtils.rest?(x)

    case x
    when Step
      [x].freeze
    when Symbol, String, Numeric
      [stepify(x)].freeze
    # NOTE: 'Enumerable' resolves to SonicPi::RuntimeMethods::Enumerable in this
    # context, which Array does *not* have as a superclass. So we need to use
    # ::Enumerable to get the built-in class.
    # SPVector is the parent class of RingVector, from e.g. `ring` and `chord`,
    # and potentially other list types in SP. It unfortunately does not derive
    # from (either) Enumerable, so we check for it manually and make sure to use
    # `to_a` before calling Enumerable methods on it.
    when ::Enumerable, SonicPi::Core::SPVector
      raw_slot = x.to_a.reject { |s| NoteUtils.rest?(s) }.map { |s| stepify(s) }
      dedupe_slot(raw_slot).freeze
    else
      raise "Not a valid value for a slot: #{x.inspect}"
    end
  end

  # Attempts to convert its argument to a grid (a 2d array of Steps). The
  # returned array and all of its elements will be frozen. Conversion rules:
  # - A single rest (see NoteUtils.rest?) becomes a grid with one rest ([[]]).
  # - A single note (symbol, string, or number) becomes a grid with one slot
  #   that is the result of calling `slotify` on the argument.
  # - A single Step becomes a grid with one slot containing that step.
  # - Array-like arguments are converted by passing each element through
  #   `slotify`.
  def self.gridify(x)
    return [[].freeze].freeze if NoteUtils.rest?(x)

    case x
    when Step
      [[x].freeze].freeze
    when Symbol, String, Numeric
      [slotify(x)].freeze
    # See note in slotify about these class selections.
    when ::Enumerable, SonicPi::Core::SPVector
      # NOTE: this will convert non-array child elements into individual slots.
      # E.g. gridify([:a1, :b1]) will turn into [[:a1], [:b1]]. I think that's
      # desirable - it's a sort of 'smart' conversion, preferring mono-like
      # behavior unless notes are explicitly grouped into their own array.
      x.to_a.map { |s| slotify(s) }.freeze
    else
      raise "Not a valid value for a grid: #{x.inspect}"
    end
  end


  protected

  # Does a deep dup of the grid, returning a version where the grid itself and
  # each slot is mutable.
  def mutable_grid_dup
    @grid.map { |slot| slot.dup }
  end


  private

  def mutate(**mutations)
    grid = mutations.delete(:grid) || @grid
    [:granularity, :timescale].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Track.new(grid, **mutations)
  end

  def strict_track_merging?
    defaults = $spi.get(:__track_defaults) || {}
    defaults[:strict_track_merging] || false
  end

  def assert_compatible_track(other_track)
    return unless strict_track_merging?

    if @granularity != other_track.granularity
      raise "Granularity mismatch: #{@granularity} != #{other_track.granularity}"
    end

    if @timescale != other_track.timescale
      raise "Timescale mismatch: #{@timescale} != #{other_track.timescale}"
    end
  end

  # Attempts to convert its argument into a Track. If it is already a Track,
  # it is returned as-is. Otherwise, constructs a new Track which will inherit
  # the granularity and timescale from self.
  def compatibly_trackify(x)
    return x if x.is_a?(Track)

    # We can just pass this off to the initializer and let it call gridify.
    mutate(grid: x)
  end
end

def T(*args, **kwargs)
  Track.new(*args, **kwargs)
end
