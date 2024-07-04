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

  def mutate(mutations)
    mutations = mutations.dup
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
    mutate(vel: (new_velf * 127.0).round)  # this is clamped to 0-127 in the ctor
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
# TODO: make mutable? seems tricky. plus would probably need to make a Grid
# class (or at least a bunch of Track methods) to make manipulation ergonomic.
# TODO: does timescale belong here? really only effects the Player, so it could
# live there, but this feels like a convenient place for it (& to mutate it)
class Track
  attr_reader :granularity, :grid, :timescale


  ### Basic constructors

  # Constructs a track with the given array, each element of which represents
  # a step or a rest. The elements will be played one at a time, in the given
  # order, each for a duration equal to the granularity (in other words, each
  # element of steps defines a slot with a single step). The elements of steps
  # must each be either:
  # - a Step object,
  # - a MIDI note number or symbol, which will be converted to a Step with the
  #   default arguments, or
  # - nil, :r, or :rest to represent a rest.
  def self.mono(steps, granularity: NoteLength::Eighth, timescale: 1)
    grid = steps.map { |s| [s] }
    new(grid: grid, granularity: granularity, timescale: timescale)
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
  def self.poly(grid, granularity: NoteLength::Eighth, timescale: 1)
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs an empty track that rests for the given number of slots.
  def self.rest(num_slots = 1, granularity: NoteLength::Eighth, timescale: 1)
    grid = [[]] * num_slots
    new(grid: grid, granularity: granularity, timescale: timescale)
  end


  ### More interesting constructors

  # Constructs a track that arpeggiates the given notes. extra_octaves is an
  # array of octave shifts. The arpeggiation will include all the notes from the
  # note array in addition to copies of them with the given octave shifts.
  # TODO: incorporate euclidean rhythm
  def self.arp(notes, direction = Arp::Up, spread: 0, extra_octaves: [], granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arpeggiate(notes, direction, spread: spread, extra_octaves: extra_octaves)
    grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a track that arpeggiates the given degrees of the tonic note in
  # the given scale. Other arguments are as specified in arp.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, spread: 0, extra_octaves: [], granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arp_degrees(tonic, degrees, direction, scale: scale, spread: spread, extra_octaves: extra_octaves)
    grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a mono track that plays the given notes in a Euclidean rhythm.
  # The length of the rhythm is slots, and the number of hits to play over those
  # slots is pulses. notes should be an array of note numbers or symbols, or a
  # single note number or symbol.
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
  def self.euclid(notes, pulses, slots, invert: false, rotate: 0, cycle_notes: true, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    if notes.is_a?(Numeric) || notes.is_a?(Symbol) || notes.is_a?(String)
      notes = [notes]
    end

    hits = $spi.spread(pulses, slots).to_a
    hits.rotate!(rotate) if rotate != 0
    hits.map! { |hit| !hit } if invert

    note_idx = 0
    grid = hits.map.with_index do |hit, i|
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

    new(grid: grid, granularity: granularity, timescale: timescale)
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
    @grid.all? { |slot| slot.length == 0 }
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

  ## Grid-level mutations

  def with_rate(rate)
    mutate(timescale: rate)
  end

  alias rate with_rate

  # Returns a new track with the given granularity. Does not effect the timing
  # of any Steps; to change granularity while attempting to keep the track
  # sounding roughly the same, use condense, expand, or regranularize.
  def with_granularity(granularity)
    mutate(granularity: granularity)
  end

  def append(other_track)
    assert_compatible_track(other_track)
    mutate(grid: @grid + other_track.grid)
  end

  alias concat append
  alias add append
  alias + append

  # Create a new Track that merges the Steps in corresponding slots of from this
  # track and other_track. The length of the resulting track is the maximum
  # length of the two tracks.
  def merge(other_track)
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
  # this track. cycle controls the behavior if other_track is shorter than this
  # track. When cycle is false, blank slots (rests) will be interleaved once
  # those of other_track are exhausted. If cycle is true, the slots of
  # other_track will be looped as needed. For instance, consider zipping
  # together two sequences with Steps [:a1, :b1, :c1, :d1] and [:e5, :f5].
  # When cycle is false, the resulting Track will contain slots with the
  # following steps:
  #    :a1 :e5 :b1 :f5 :c1 rest :d1 rest
  # When cycle is true, the same operation will result in slots
  #    :a1 :e5 :b1 :f5 :c1 :e5 :d1 :f5
  def zip(other_track, cycle: true)
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
  # this track. Unlike zip, this function does not alternate between 1 slot of
  # each track. Instead, group_size many slots of this track appear
  # consecutively, followed by other_group_size slots of other_track, then
  # group_size many slots of this track, and so on. cycle controls the behavior
  # when the other track has fewer groups than this one. It behaves as described
  # in zip. pad_short_groups controls the behavior when a group size does not
  # evenly divide the number of slots in its corresponding track. If it is true,
  # rests are added to the final chunk of slots so that it has the group size.
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
  # resulting track will have slots :a :b :c :b :c :d :c :d :e.
  def each_cons(n)
    mutate(grid: @grid.each_cons(n).to_a.flatten(1))
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

  # Returns a new track that repeats the slots of this track for n slots.
  def cycle_to_length(n)
    mutate(grid: @grid.cycle.take(n))
  end

  # Returns a new track with all empty slots (rests) removed.
  def compact
    mutate(grid: @grid.reject { |slot| slot == [] })
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
    s = [s] if s.length == 0 || !s[0].is_a?(Array)
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
    new_grid = @grid.dup
    new_grid[idx] = new_steps
    mutate(grid: new_grid)
  end

  alias set_slot replace_slot

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
        if block.arity == 1
          should_extract = block.call(step)
        elsif block.arity == 2
          should_extract = block.call(step, slot)
        else
          should_extract = block.call(step, slot, i)
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
  # given block. The block may return:
  # - A Step, which will replace the step yielded to the block
  # - nil, :r, or :rest, which will remove the step yielded to the block
  # - An array of Steps, which will all be added in place of the yielded step to
  #   the corresponding slot of the yielded step.
  def mutate_each_step
    mutate_each_step_with_pct { |step, _| yield step }
  end

  # Functionally the same as mutate_each_step, except the block is called with
  # two arguments: the Step, and the percentage through the Track that the slot
  # the Step belongs to represents. For instance, Steps in the first slot of the
  # track will have percent 0, steps in the middle slot (in a Track with an odd
  # number of slots) will have percent 0.5, and steps in the final slot will
  # have percent 1.0.
  def mutate_each_step_with_pct
    new_grid = @grid.map.with_index do |slot, i|
      pct = i.to_f / (num_slots - 1)
      new_slot = []
      slot.each do |step|
        new_step = yield step, pct
        if NoteUtils.rest?(new_step)
          next
        elsif new_step.is_a?(Step)
          new_slot << new_step
        else
          new_slot.concat(new_step)
        end
      end

      new_slot
    end

    mutate(grid: new_grid)
  end

  def with_gate(new_gate)
    mutate_each_step { |step| step.with_gate(new_gate) }
  end

  alias gate with_gate

  def scale_gate(factor)
    mutate_each_step { |step| step.with_gate(step.gate * factor) }
  end

  # Returns a new track where each Step's gate is replaced with the result of
  # curve_func. curve_func will be called with one parameter, a percentage
  # through the track (0-1), and should return a floating point value 0-1 that
  # will be used for all Steps in the slot at that percentage.
  # TODO: add a library of useful curve functions for this
  def with_gate_curve(curve_func)
    raise "Curve function must be a callable that takes one argument" unless curve_func.respond_to?(:call) && curve_func.arity == 1
    mutate_each_step_with_pct { |step, pct| step.with_gate(curve_func.call(pct)) }
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
  # of curve_func. curve_func will be called with one parameter, a percentage
  # through the track (0-1), and should return a velocity to use for all Steps
  # in the slot at that percentage. The value returned by curve_func should be
  # either:
  # - If zero_to_one is true, a floating point number 0 - 1 that will be scaled
  #   to a velocity value between 0 and 127, inclusive.
  # - If zero_to_one is false, an integer between 0 and 127, inclusive.
  # with_velf_curve is an alias where zero_to_one is true.
  def with_vel_curve(curve_func, zero_to_one: false)
    raise "Curve function must be a callable that takes one argument" unless curve_func.respond_to?(:call) && curve_func.arity == 1
    mutate_each_step_with_pct do |step, pct|
      vel = curve_func.call(pct)
      vel *= 127 if zero_to_one
      step.with_vel(vel)
    end
  end

  alias vel_curve with_vel_curve

  def with_velf_curve(curve_func)
    with_vel_curve(curve_func, zero_to_one: true)
  end

  alias velf_curve with_velf_curve

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
  # it should be a note (number, string, or symbol) or an array of notes, and
  # only steps with those notes will be harmonized.
  def harmonize(*offsets, only: nil)
    unless only.nil?
      only = [only] unless only.is_a?(Array)
      only = only.map { |n| NoteUtils.sym(n) }
    end

    offsets = [-12, 12] if offsets.empty?
    mutate_each_step do |step|
      new_steps = [step]
      if only.nil? || only.include?(step.note)
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


  protected

  # Does a deep dup of the grid, returning a version where the grid itself and
  # each slot is mutable.
  def mutable_grid_dup
    @grid.map { |slot| slot.dup }
  end


  private

  def initialize(grid:, granularity:, timescale:)
    # Do a deep frozen clone of grid, while making sure no slot has more than
    # one Step with the same note, and converting nils/rest symbols into empty
    # slots and integers/symbols into Steps. Freeze the whole thing recursively
    # so the version we expose through the attr_reader is immutable.
    @grid = grid.map.with_index do |slot, i|
      steps_by_note = {}
      slot.each do |step|
        next if NoteUtils.rest?(step)
        step = Step.new(step) unless step.is_a?(Step)

        old_step_with_same_note = steps_by_note[step.note]
        if old_step_with_same_note.nil?
          steps_by_note[step.note] = step
        else
          $spi.puts("warning: more than one Step with note #{step.note} in slot #{i}! Picking one with the longest gate!")
          steps_by_note[step.note] = step if old_step_with_same_note.gate < step.gate
        end
      end

      steps_by_note.values.freeze
    end
    @grid.freeze

    @granularity = NoteLength.normalize(granularity)
    @timescale = timescale
  end

  def mutate(mutations)
    mutations = mutations.dup
    [:grid, :granularity, :timescale].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Track.new(**mutations)
  end

  # TODO: do automatic granularity adjustment when possible?
  def assert_compatible_track(other_track)
    if @granularity != other_track.granularity
      raise "Granularity mismatch: #{@granularity} != #{other_track.granularity}"
    end

    if @timescale != other_track.timescale
      raise "Timescale mismatch: #{@timescale} != #{other_track.timescale}"
    end
  end
end
