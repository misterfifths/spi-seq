# frozen_string_literal: true

require_relative "extapi"
require_relative "step"
require_relative "midinote"
require_relative "notelength"
require_relative "prob"
require_relative "arp"
require_relative "curves"
require_relative "easings"


# An alias for Track.new.
def T(*args, **kwargs)
  Track.new(*args, **kwargs)
end


# Set global Track behaviors.
# strict_track_merging: If true, Tracks with mismatched granularities or
# timescales cannot interact with one another. That is, they cannot be merged,
# joined, zipped, or otherwise commingle. If false, generally speaking, the
# track on which a method is being called is the one that will determine the
# granularity and timescale of the result. E.g., in t1.zip(t2), the result will
# have the properties of t1. Default: false.
def use_track_defaults(strict_track_merging:)
  ExtApi.set(:__track_defaults, { strict_track_merging: strict_track_merging })
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
  # - A single rest (see MIDINote.rest?) becomes a grid with one empty slot.
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
    @granularity = NoteLength.new(granularity)

    raise "Timescale must be a number greater than 0" unless timescale.is_a?(Numeric) && timescale > 0
    @timescale = timescale
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
  # If pulses and length are given, the arpeggiated notes are spread in a
  # Euclidean rhythm. The track will repeat the Euclidean pattern (while cycling
  # through the arpeggiated notes) however many times is needed to ensure that
  # all the notes are played and that the track loops cleanly, unless full_cycle
  # is false. The rotate parameter controls rotation of the Euclidean pattern.
  def self.arp(notes, direction = Arp::Up, spread: 0, extra_octaves: [], pulses: nil, length: nil, rotate: 0, full_cycle: true, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arpeggiate(notes, direction, spread: spread, extra_octaves: extra_octaves)
    if pulses.nil?
      grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
      new(grid, granularity: granularity, timescale: timescale)
    else
      raise "pulses and length must both be nil or both be integers" if length.nil?
      euclid(notes, pulses, length, rotate: rotate, full_cycle: full_cycle, granularity: granularity, gate: gate, vel: vel, timescale: timescale)
    end
  end

  # Constructs a track that arpeggiates the given degrees of the tonic note in
  # the given scale. Other arguments are as specified in arp.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, spread: 0, extra_octaves: [], pulses: nil, length: nil, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arp_degrees(tonic, degrees, direction, scale: scale, spread: spread, extra_octaves: extra_octaves)
    if pulses.nil?
      grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
      new(grid, granularity: granularity, timescale: timescale)
    else
      raise "pulses and length must both be nil or both be integers" if length.nil?
      euclid(notes, pulses, length, full_cycle: true, granularity: granularity, gate: gate, vel: vel, timescale: timescale)
    end
  end

  # Constructs a track that plays the slots of gridish in a Euclidean rhythm.
  # The length of the rhythm is length, and the number of hits to play over
  # that length is pulses. gridish should be an array of notes or Steps or
  # arrays thereof, or a single note/Step. The elements (or the single element)
  # will be passed through gridify; see it for conversion rules. Any elements
  # of gridish that need to be converted to Steps will use the given gate and
  # vel. They are ignored for elements that are already Steps.
  # Unless full_cycle is true (see below), the returned track will the given
  # length. The cycle parameter controls how gridish is used when placing slots
  # in the track. If it is true, each time there is a hit in the rhythm, the
  # next slot from gridish is used (wrapping around if needed). For example,
  # when spreading [:c3, :d3] over 3 pulses and length 4, the result will be a
  # track with the following slots:
  #   :c3, rest, :d3, :c3
  # If cycle is false, when there is a hit in the rhythm, the note at the
  # corresponding index of that hit in gridish is used (wrapping around as
  # needed). Using the same spread as above with cycle false would result in:
  #   :c3, rest, :c3, :d3
  # The third note is :c3 because the hit index, 2, corresponds :c3 in gridish
  # (modulo its length).
  # If full_cycle is true, the returned track will repeat the Euclidean pattern
  # (while cycling through gridish) however many times is needed to ensure
  # that all the slots are played and that the track loops cleanly. full_cycle
  # implies cycle. For instance, spreading [:a1, :b1, :c1, :d1] over 3 pulses
  # and 4 length with full_cycle true will result in a track with the following
  # slots (the pipes are only to visually discriminate between groups of the
  # the Euclidean pattern):
  #   :a1 rest :b1 :c1 | :d1 rest :a1 :b1 | :c1 rest :d1 :a1 | :b1 rest :c1 :d1
  # Note that each group repeats the same pattern of hits (hit rest hit hit),
  # but the slots cycle across repetitions, so that every given slot is played
  # and the overall track is a perfect loop.
  def self.euclid(gridish, pulses, length, invert: false, rotate: 0, cycle: true, full_cycle: false, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    hits = ExtApi.spread(pulses, length).to_a
    hits.rotate!(rotate) if rotate != 0
    hits.map! { |hit| !hit } if invert

    gridish = Track.gridify(gridish, def_gate: gate, def_vel: vel)

    # If we're doing a full cycle, we may need multiple copies of the Euclidean
    # pattern to complete a perfect loop. If we're spreading n slots over p
    # hits, we need exactly lcm(p, n) hits. And since the pattern contains
    # exactly p hits itself, we need lcm(p, n) / p copies of it.
    if full_cycle
      cycle = true
      needed_groups = pulses.lcm(gridish.length) / pulses
    else
      needed_groups = 1
    end

    slot_idx = 0
    grid = hits.cycle(needed_groups).map.with_index do |hit, i|
      if hit
        if cycle
          slot = gridish[slot_idx % gridish.length]
          slot_idx += 1
        else
          slot = gridish[i % gridish.length]
        end

        slot
      else
        []
      end
    end

    new(grid, granularity: granularity, timescale: timescale)
  end

  # Construct an isorhythmic track. See https://en.wikipedia.org/wiki/Isorhythm.
  # To use classical terms, `gates` defines the talea and `notes` the color.
  #
  # `gates` is an array of numbers which defines the rhythm over which `notes`
  # will be played. The numbers in `gates` will become the gates of the Steps in
  # the track.
  #
  # Within `gates`, there are "runs". A run is a series of gates that would
  # define a tied sequence of steps (or single untied steps). For instance, a
  # gates array of [1, 0.5, 0.25, 1] defines 3 runs: the first two steps would
  # be tied together, then a standalone step with gate 0.5, and a final step
  # with gate 1. (Note that trailing tied steps are considered to end at the end
  # end of the array.)
  #
  # Each run in `gates` will be assigned the same note from the `notes` array.
  # Subsequent runs will be assigned the next note, cycling as needed if the
  # number of runs outnumbers the number of notes.
  #
  # The entire pattern of notes over the rhythm defined by `gates` will be
  # repeated as many times as needed so that the resulting track uses all the
  # elements of `notes` and cycles cleanly.
  #
  # This method has much in common with `euclid`, except that a "hit" can last
  # more than one slot.
  #
  # For example:
  # isorhythm([:a1, :b2, :c3], [1, 0.5, 0, 0.25]) would result in a track with
  # slots
  #   [:a1, S(:a1, gate: 0.5), :r, S(:b2, gate: 0.25),
  #    :c3, S(:c3, gate: 0.5), :r, S(:a1, gate: 0.25),
  #    :b2, S(:b2, gate: 0.5), :r, S(:c3, gate: 0.25)]
  # The `gates` array represents 2 runs, and you can see that each of those runs
  # was assigned the same note from `notes`. In the final track, the rhythm
  # defined by `gates` was repeated three times while cycling through `notes`,
  # so that every note was used and the track ends on the final note of `notes`.
  def self.isorhythm(notes, gates, granularity: NoteLength::Eighth, vel: 127, timescale: 1)
    # Gameplan:
    # This is a variation on `euclid` above, really, with the added complication
    # that a "hit" can last more than one slot.
    # Calculate the number of distinct notes that the `gates` array specifies.
    # That is: find the number of runs, a run being a sequence of tied notes.
    # Ties at the end of `gates` are considered ended even if they would
    # continue in a loop. As with `euclid` above, call that number p.
    # We are spreading n = notes.length notes over those p hits, and we want to
    # cleanly cycle while using all the notes. As per the calculation in
    # `euclid`, that will take exactly lcm(p, n) / p cycles.

    # We're going to leverage the existing run manipulation machinery on Track
    # by building a rhythm track with the proper gates but all C4s. We'll then
    # repeat that track, fixing up the notes as we go along.
    hit_grid = gates.map { |g| g == 0 ? [] : Step.new(:c4, gate: g, vel: vel) }
    hit_track = Track.new(hit_grid, granularity: granularity, timescale: timescale)

    # TODO: make these methods public so we don't have to call them with send.
    run_count = 0
    hit_track.send(:each_run) { |_, _| run_count += 1 }

    needed_cycles = run_count.lcm(notes.length) / run_count

    # Now build up the track by mutating hit_track, needed_cycle times.
    track = nil
    note_idx = 0
    needed_cycles.times do
      this_track = hit_track.send(:mutate_runs) do |_, orig_steps|
        # Replace each note in the run with the proper note at note_idx. Aside
        # from the note, the Steps in hit_track already have the correct
        # properties.
        new_steps = orig_steps.map do |step|
          step.with_note(notes[note_idx])
        end

        note_idx = (note_idx + 1) % notes.length

        new_steps
      end

      if track.nil?
        track = this_track
      else
        track += this_track
      end
    end

    track
  end

  def self.iso(*args, **kwargs)
    isorhythm(*args, **kwargs)
  end


  ### Properties

  def num_slots
    @grid.length
  end

  alias length num_slots

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
  # If fill is true, steps with the 'fill' probability will be triggered.
  # Intended to be called iteratively, incrementing i and the cycle, and feeding
  # back playing and tied steps from the return value as prev_steps.
  def steps_at_slot(i, prev_steps:, cycle:, fill:)
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
    cur_steps = @grid[i % num_slots].filter { |step| step.should_trigger?(cycle, fill, prev_steps) }

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
      ended_steps << prev_step unless note_continues
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

  def repr(group: 8)
    slot_line_indent = "    "  # to align with 'T([  '

    slot_reprs = @grid.map do |slot|
      if slot.empty?
        ":r"
      elsif slot.length == 1
        slot[0].repr
      else
        "[" + slot.map { |step| step.repr }.join(", ") + "]"  # rubocop:disable Style/StringConcatenation
      end
    end

    if group.nil?
      grouped_slot_reprs = [slot_reprs]
    else
      grouped_slot_reprs = slot_reprs.each_slice(group).to_a
    end

    slot_repr_lines = grouped_slot_reprs.length
    total_slot_repr = grouped_slot_reprs.map { |chunk| chunk.join(", ") }.join(",\n#{slot_line_indent}")

    ctor_args = {}
    ctor_args[:granularity] = @granularity.repr unless @granularity == NoteLength::Eighth
    ctor_args[:timescale] = @timescale unless @timescale == 1

    if ctor_args.empty?
      kwargs = ""
    else
      kwargs = ", " + ctor_args.map { |k, v| "#{k}: #{v}" }.join(", ")  # rubocop:disable Style/StringConcatenation
    end

    if slot_repr_lines > 1
      "T([\n#{slot_line_indent}#{total_slot_repr}\n]#{kwargs})"
    else
      "T([#{total_slot_repr}]#{kwargs})"
    end
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

      step1 = step.with_gate(total_gate).with_prob(step1_prob)

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
      slot2&.each { |step| steps_by_note[step.note][1] = step }

      new_slot = []
      steps_by_note.each_value do |steps|
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
    new_granularity = NoteLength.new(new_granularity)

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

      args = [slot, i, pct].take(block.arity)
      replacement = block.call(*args)

      # The block may return something convertible to a slot (step/note/etc.),
      # or a 1d array (which we will take as a slot), or an array that contains
      # some number of other arrays (which we will take as a set of slots). This
      # behavior is pretty odd. But, it's somewhat in keeping with set_slot, and
      # having the ability to expand one slot into multiple here is nice...
      replacement = [replacement] unless replacement.is_a?(::Enumerable) || replacement.is_a?(SonicPi::Core::SPVector)
      is_gridish = replacement.any? { |e| e.is_a?(::Enumerable) || e.is_a?(SonicPi::Core::SPVector) }

      if is_gridish
        new_grid += Track.gridify(replacement)
      else
        new_grid << replacement  # This will get slotified by the initializer.
      end
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
  # cycle and pad_with_rests control the behavior if other_track is shorter than
  # this track. If cycle is true (the default), the slots of other_track will be
  # looped as needed.
  # If cycle is false, the behavior depends on pad_with_rests. If it is true
  # (the default), when other_track's slots are exhausted, empty slots (rests)
  # are inserted in place of the missing slots. If it is false, the remaining
  # slots of this track appear consecutively once other_track is exhausted.
  # pad_with_rests is only relevant when cycle is false.
  # For example, consider zipping together two sequences with Steps
  # [:a1, :b1, :c1, :d1] and [:e5, :f5].
  # When cycle is true (the default), the resulting Track will contain slots
  # with the following steps:
  #    :a1 :e5 :b1 :f5 :c1 :e5 :d1 :f5
  # When cycle is false and pad_with_rests is true (the default), the resulting
  # Track will contain slots with the following steps:
  #    :a1 :e5 :b1 :f5 :c1 rest :d1 rest
  # If cycle is false and pad_with_rests is also false, the result is
  #    :a1 :e5 :b1 :f5 :c1 :d1
  def zip(other_track, cycle: true, pad_with_rests: true)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    new_grid = []
    b_idx = 0
    @grid.each do |slot|
      new_grid << slot
      b_idx %= other_track.length if cycle
      if b_idx < other_track.length
        new_grid << other_track.grid[b_idx]
      elsif pad_with_rests
        new_grid << []
      end

      b_idx += 1
    end

    mutate(grid: new_grid)
  end

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. If other_track is not a Track, it is converted to a compatible
  # one using the initializer.
  # Unlike zip, this function does not alternate between 1 slot of each track.
  # Instead, group_size many slots of this track appear consecutively, followed
  # by other_group_size slots of other_track, then group_size many slots of this
  # track, and so on.
  # `cycle` controls the behavior when either track does not have enough
  # remaining  slots to fill a group. If it is true, the group is filled by
  # returning to the beginning of the short track and using slots from there.
  # If it is true, when one track is exhausted, no more groups from it are
  # added to the resulting track.
  # `pad_with_rests` only takes effect when `cycle` is false. If it is true,
  # when either track is exhausted, empty slots (rests) are added to the
  # resulting track in place of the missing slots.
  # For instance, consider gzipping together a track with slots with the steps
  #     :a1 :b1 :c1 :d1
  # and one with slots with steps
  #     :e2 :f2
  # If group_size is 3, other_group_size is 1, and cycle is true, you'll get
  #     :a1 :b1 :c1 :e2 :d1 :a1 :b1 :f2
  # Note that when the tracks in the first slot were exhausted (after the :d1),
  # the remaining slots in that group came from wrapping around to the beginning
  # of the track - hence the :a1 and :b1.
  # If cycle were false in that example, the result would be
  #     :a1 :b1 :c1 :e2 :d1 :f2
  # No wrap-around occurred here, and the group beginning with :d1 is just cut
  # short. If cycle were false and pad_with_rests were true, the result would be
  #     :a1 :b1 :c1 :e2 :d1 rest rest :f2
  # In this case, the shortfall from the first track was replace with rests, so
  # that the group beginning with :d1 was ensured to have group_size many slots.
  def grouped_zip(other_track, group_size, other_group_size, cycle: true, pad_with_rests: true)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    new_grid = []

    # Append n elements to new_grid from grid, starting at idx, wrapping around
    # if we're cycling or adding empty slots if we're padding. Returns the index
    # from which we should begin adding on the next iteration.
    add_group = lambda do |n, grid, idx|
      n.times do
        idx %= grid.length if cycle
        if idx < grid.length
          new_grid << grid[idx]
        elsif pad_with_rests
          new_grid << []
        end

        idx += 1
      end

      idx
    end

    a_idx = 0
    b_idx = 0
    num_groups = (@grid.length / group_size.to_f).ceil
    num_groups.times do
      a_idx = add_group.call(group_size, @grid, a_idx)
      b_idx = add_group.call(other_group_size, other_track.grid, b_idx)
    end

    mutate(grid: new_grid)
  end

  alias gzip grouped_zip

  # Returns a new track that plays each successive overlapped set of n slots.
  # E.g. when called with n=3 on a track with slots :a :b :c :d :e, the
  # resulting track will have slots :a :b :c :b :c :d :c :d :e. If flatten is
  # false, each overlapped set of slots will be grouped into a slot. For
  # example, with n=2 and flatten=false, a track with slots :a :b :c :d will
  # result in a track with three slots: [[:a, :b], [:b, :c], [:c, :d]].
  # Raises an error if n is greater than the length of the track.
  def each_cons(n, flatten: true)
    raise "n=#{n} is greater than the length of the track (#{@grid.length})" if n > @grid.length

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

  # Returns a new Track by shuffling the filled slots in the grid. Any slots
  # that were rests remain so; only the contents of filled slots is effected.
  def shuffle_filled_slots
    shuffled_idxs = indexes_of_filled_slots.shuffle

    shuffled_idxs_cursor = 0
    mutate_each_slot do |slot|
      next [] if slot.empty?
      ret = @grid[shuffled_idxs[shuffled_idxs_cursor]]
      shuffled_idxs_cursor += 1
      ret
    end
  end

  alias shuffle_filled shuffle_filled_slots

  # Returns a new Track with the slots in the grid rotated to the right by the
  # given amount. The track duration is maintained; slots will be wrapped around
  # to the beginning of the grid as needed.
  def rotate(rightward_shift = 1)
    mutate(grid: @grid.rotate(-rightward_shift))
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
  # relative order of the slots is maintained.
  def sample(n)
    # TODO: does this use spi's rng?
    idxs = (0...@grid.length).to_a.sample(n).sort
    mutate(grid: @grid.values_at(*idxs))
  end

  # Returns a new Track consisting of n random slots from this track's grid.
  # Only picks from filled slots; rests are not considered. The relative order
  # of the slots is maintained.
  def sample_filled_slots(n)
    idxs = indexes_of_filled_slots.sample(n).sort
    mutate(grid: @grid.values_at(*idxs))
  end

  alias sample_filled sample_filled_slots

  # Returns a new Track with all Steps in every nth slot removed. The duration
  # of the Track does not change; the emptied slots simply become rests. Does
  # nothing if n is zero.
  def drop_every(n, skip_empty: false)
    return self if n == 0

    # e.g., drop every 3:
    # keep  | 0 1 - 3 4 - 6 7 - 9
    # drop  |     2     5     8
    # i % 3 | 0 1 2 0 1 2 0 1 2 0
    i = 0
    new_grid = @grid.map do |slot|
      if skip_empty && slot.empty?
        []
      else
        i += 1
        (i - 1) % n == n - 1 ? [] : slot
      end
    end

    mutate(grid: new_grid)
  end

  alias dropout drop_every

  # Return a new Track by, with probability p, removing all Steps in any given
  # slot.
  def rand_dropout(p = 0.5)
    new_grid = @grid.map { |slot| ExtApi.rand < p ? [] : slot }
    mutate(grid: new_grid)
  end

  alias rdropout rand_dropout

  # Returns a new Track with the steps in slot idx replaced with the given
  # steps.
  def replace_slot(idx, new_steps)
    raise "Index #{idx} is beyond the length of the track (#{@grid.length})" if idx >= @grid.length
    new_grid = @grid.dup
    new_grid[idx] = new_steps  # This will get slotified by the initializer.
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
        args = [step, slot, i].take(block.arity)
        should_extract = block.call(*args)

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
  # ones. See MIDINote.match? for matching rules.
  def extract_note(note)
    extract { |step| step.note.match?(note) }
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
        args = [step, i, pct].take(block.arity)
        new_step = block.call(*args)

        new_slot += Track.slotify(new_step)
      end

      new_slot
    end

    mutate(grid: new_grid)
  end

  alias mutate_steps mutate_each_step

  # Return a new track, replacing the Steps in the given slot with the result of
  # the given block. The block must take 1 argument, and will be called for each
  # Step in the slot. The result of the block will replace the Step it is called
  # with. The block should return:
  # - A single Step, which will replace the given Step in the slot.
  # - An array of Steps, which will all be added to the slot in place of the
  #   given Step.
  # - An empty array or a rest, which will remove the given Step from the slot.
  # - Equivalents of any of the above (see slotify).
  # Note that if the slot at the given index is empty, the block will not be
  # called and no changes will be made.
  def mutate_steps_in_slot(idx, &block)
    raise "Block must take 1 argument" if block.arity != 1

    new_slot = @grid[idx].map { |step| block.call(step) }.flatten
    set_slot(idx, new_slot)
  end

  alias mutate_slot_steps mutate_steps_in_slot
  alias mutate_slot mutate_steps_in_slot

  # Return a new track, replacing the Steps in the nth non-empty slot with the
  # result of the given block. This is equivalent to a call to
  # mutate_steps_in_slot with the index of the nth non-empty slot; see that
  # method for details.
  def mutate_filled_slot(n, &block)
    idx = indexes_of_filled_slots[n]
    mutate_steps_in_slot(idx, &block)
  end

  # Return a new track, replacing the Steps in the nth non-empty slot with the
  # given steps.
  def replace_filled_slot(n, new_steps)
    idx = indexes_of_filled_slots[n]
    set_slot(idx, new_steps)
  end

  alias set_filled_slot replace_filled_slot

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
  # If min or max is provided, the curve function will be scaled via
  # Curves.scale so that it falls in the given range. If only one of min or max
  # is provided, the other defaults to the respective endpoint of the range 0-1.
  def with_gate_curve(curve_func, min: nil, max: nil)
    raise "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2

    if !min.nil? || !max.nil?
      min = 0 if min.nil?
      max = 1 if max.nil?
      curve_func = Curves.scale(curve_func, min, max)
    end

    mutate_each_step do |step, slot_idx, pct|
      args = [pct, slot_idx].take(curve_func.arity)
      gate = curve_func.call(*args)

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

  alias scale_velf scale_vel

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
  # If min or max is provided, the curve function will be scaled via
  # Curves.scale so that it falls in the given range. If only one of min or max
  # is provided, the other defaults to the respective endpoint of the range of
  # the curve function (0-127 if zero_to_one is false, otherwise 0-1).
  def with_vel_curve(curve_func, zero_to_one: false, min: nil, max: nil)
    raise "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2

    if !min.nil? || !max.nil?
      min = 0 if min.nil?
      max = zero_to_one ? 1 : 127 if max.nil?

      curve_func = Curves.scale(curve_func, min, max, orig_min: 0, orig_max: zero_to_one ? 1 : 127)
    end

    mutate_each_step do |step, slot_idx, pct|
      args = [pct, slot_idx].take(curve_func.arity)
      vel = curve_func.call(*args)

      vel *= 127 if zero_to_one  # with_vel will round & clamp this
      step.with_vel(vel)
    end
  end

  alias vel_curve with_vel_curve

  def with_velf_curve(curve_func, min: nil, max: nil)
    with_vel_curve(curve_func, zero_to_one: true, min: min, max: max)
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

  # Returns a new track where every step has the 'fill' probability. Or, if the
  # argument is false, a new track where all steps with the 'fill' probability
  # have their probability cleared (steps with other probabilities are
  # unchanged).
  def fill(fill = true)
    mutate_each_step do |step|
      if fill
        step.with_prob(Prob.fill)
      elsif step.prob.equal?(Prob.fill)
        step.with_prob(nil)
      else
        step
      end
    end
  end

  # Finds runs of tied steps with the same notes and yields to its block two
  # arguments for each: the index of the slot that begins the run, and the array
  # of steps that belong to the run. A run is ended by the end of the track, or
  # a step that is not tied. The final step in a run is included in the array
  # yielded to the block. Runs that consist of a single step (i.e. non-tied
  # steps that are not continuing a note from the previous step, or steps at the
  # end of the track that are not continuing a note) are also yielded to the
  # block.
  private def each_run
    ended_runs = []
    active_runs_by_note = {}  # notes -> { starting_slot_idx:, steps: }

    @grid.each_with_index do |slot, slot_idx|
      # Find what's new and what continues in this slot.
      slot.each do |step|
        run_info = active_runs_by_note[step.note]
        if run_info.nil?
          # A new run.
          run_info = { starting_slot_idx: slot_idx, steps: [step] }

          # If it's not tied it ends immediately.
          if step.tied?
            active_runs_by_note[step.note] = run_info
          else
            ended_runs << run_info
          end
        else
          # If the step is tied, the run continues. Otherwise it ends here.
          run_info[:steps] << step
          unless step.tied?
            ended_runs << run_info
            active_runs_by_note.delete(step.note)
          end
        end
      end

      # Now look for ended runs, which are missing in this slot.
      ended_notes = []
      active_runs_by_note.each do |note, run_info|
        next if slot.any? { |step| step.note == note }

        # This is an ended run.
        ended_runs << run_info
        ended_notes << note
      end

      ended_notes.each { |note| active_runs_by_note.delete(note) }
    end

    # Collect runs that lasted the whole track, and sort.
    ended_runs += active_runs_by_note.values
    ended_runs.sort_by! { |run_info| run_info[:starting_slot_idx] }

    ended_runs.each do |run_info|
      yield run_info[:starting_slot_idx], run_info[:steps]
    end
  end

  # Replaces steps in a run of tied steps with the same note. starting_slot_idx
  # is the index of the slot where replacement should begin. orig_steps is an
  # array of the original steps that are being replaced. new_steps is an array
  # of steps which should replace those from orig_steps.
  # orig_steps must be the actual Step instances that are currently in this
  # track, not copies of them with the same properties. This method is meant to
  # be used in tandem with each_run, which returns such an array of steps.
  # This method works by first removing all the steps from orig_steps from their
  # corresponding slots, and then adding all the steps from new_steps. So, it is
  # valid for new_steps to be a different length than orig_steps, as long as
  # starting_slot_idx + new_steps.length is not greater than the length of the
  # track.
  protected def set_run(starting_slot_idx, orig_steps, new_steps)
    raise "replacement steps are past the end of the track" if starting_slot_idx + new_steps.length > @grid.length

    new_grid = mutable_grid_dup

    orig_steps.each_with_index do |orig_step, i|
      new_grid[starting_slot_idx + i].delete orig_step
    end

    # TODO: gridify new_steps?
    new_steps.each_with_index do |new_step, i|
      new_grid[starting_slot_idx + i] << new_step
    end

    mutate(grid: new_grid)
  end

  # Returns a new track with each run of tied steps replaced with those returned
  # from the block. The block will be given two arguments: the index of the slot
  # where the run begins, and an array of the steps that constitute the run. The
  # block should return an array of steps, which will take the place of the
  # run's step in the returned track. The array returned from the block may have
  # a different length than the original run, but, when the new steps are added
  # beginning at the run's starting slot, they must not exceed the length of the
  # track.
  private def mutate_runs
    new_track = self
    each_run do |starting_slot_idx, orig_steps|
      new_steps = yield starting_slot_idx, orig_steps.dup
      new_track = new_track.set_run(starting_slot_idx, orig_steps, new_steps)
    end
    new_track
  end

  # Returns a new track where the final steps in runs of tied steps with the
  # same note are replaced with the result of the block. Helper for taper_vel
  # and taper_gate.
  private def taper_steps(taper_final_tie: false, taper_single: false)
    mutate_runs do |starting_slot_idx, steps|
      run_loops = false

      if (starting_slot_idx + steps.length) == @grid.length && steps[-1].tied?
        run_loops = @grid[0].any? { |slot_0_step| slot_0_step.note == steps[-1].note }
        next steps if run_loops && !taper_final_tie
      end

      next steps if steps.length == 1 && !run_loops && !taper_single

      steps[-1] = yield steps[-1]
      steps
    end
  end

  # Sets the gate on the final step of runs of tied steps with the same note.
  # The final step does not have to be tied for this method to adjust its gate;
  # such a step's gate will be set to trailing_gate.
  # If taper_final_tie is false (the default), steps in the final slot of the
  # track will not have their gate adjusted if they are tied and are continued
  # with a step with the same note in the first slot of the track.
  # If taper_single is true, standalone steps that are not continuations of a
  # tie also have their gate adjusted. Note that steps in the final slot of the
  # track that are tied and continue in the first slot of the track are not
  # effected by taper_single.
  def taper_gate(trailing_gate = 0.75, taper_final_tie: false, taper_single: false)
    taper_steps(taper_final_tie: taper_final_tie, taper_single: taper_single) { |s| s.with_gate(trailing_gate) }
  end

  # Sets the velocity on the final step of runs of tied steps, in the same
  # manner as taper_gate. If zero_to_one is true, the velocity is a percentage
  # between 0 and 1, rather than a MIDI value from 0 - 127. taper_velf is an
  # alias with zero_to_one set to true.
  def taper_vel(trailing_vel = 64, taper_final_tie: false, taper_single: false, zero_to_one: false)
    trailing_vel *= 127 if zero_to_one
    taper_steps(taper_final_tie: taper_final_tie, taper_single: taper_single) { |s| s.with_vel(trailing_vel) }
  end

  def taper_velf(trailing_vel = 0.5, taper_final_tie: false, taper_single: false)
    taper_vel(trailing_vel, taper_final_tie: taper_final_tie, taper_single: taper_single, zero_to_one: true)
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
      next step unless ExtApi.rand < p

      # We've already decided to shift, so ignore random 0 values. Not using
      # rand_i here since it's exclusive. rand is too, but we're rounding.
      shift = 0
      while shift == 0
        if range.is_a?(Range)
          shift = ExtApi.rand(range).round
        else
          shift = ExtApi.rand(-range..range).round
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

  # For each slot, yields to its block a two-element array of:
  # - the step in the slot being harmonized, or nil if the slot is empty
  # - an array of notes that harmonize with the note in the step, as given by
  #   MIDINote.harmonize. The note from the step itself is not included.
  #   If the note is not in the given scale, or if the slot is empty, this array
  #   is empty.
  private def iter_harmonized_slots(tonic, scale_name, position:, voices: nil)
    # This is an artificial but pretty sensible limitation.
    raise 'Only a mono track can be harmonized' unless mono?

    raise "position must be 0, 1, 2, or :rand" unless position == :rand || (position >= 0 && position < 3)
    if voices.is_a?(Numeric)
      raise "If voices is an integer, it must be 1, 2, or 3" unless [1, 2, 3].contain?(voices)
    elsif voices.is_a?(Array)
      raise "If voices is an array, all of its elements must be 1, 2, or 3" unless voices.all? { |v| [1, 2, 3].contain?(v) }
    elsif !voices.nil?
      raise "voices must be an integer or an array"
    end

    random_pos = position == :rand
    position = ExtApi.rand_i(3) if random_pos

    # Massage the voice argument indices if needed
    if voices.is_a?(Array)
      voices = voices.map { |i| 3 - i }
    end

    @grid.each do |slot|
      if slot.empty?
        # Note that this early exit means position does not get incremented/
        # randomized for rests.
        yield [nil, []]
        next
      end

      s = slot[0]

      notes = s.note.harmonize(tonic, scale_name, position: position)
      notes.pop  # Remove the step note itself (which may leave the array empty)

      if voices.is_a?(Numeric)
        # Take the final voices-many notes (they're lowest->highest)
        notes = notes.pop(voices)
      elsif voices.is_a?(Array)
        notes = notes.values_at(*voices)
      end

      yield [s, notes]

      if random_pos
        position = case position
        when 0
          ExtApi.choose([1, 2])
        when 1
          ExtApi.choose([0, 2])
        when 2
          ExtApi.choose([0, 1])
        end
      else
        position = (position + 1) % 3
      end
    end
  end

  # Return a new track where each slot has new steps added to it for notes that
  # harmonize with the existing step in that slot. Can only be called on mono
  # tracks. Arguments are as described in MIDINote.harmonize.
  # position is the starting position to use when harmonizing. It may be 0, 1,
  # 2, or :rand. If it is an integer, the position will increment for each step.
  # If it is :rand, random, non-repeating positions will be used.
  # voices represents which voices of the harmony to include in the results. If
  # it is an integer, it represents the number of voices to include (from high
  # to low). If it is an array, it represents individual voices to include
  # (from high to low; bass is 3 and soprano is 1).
  # The gate and vel arguments are used when creating new steps for the added
  # notes.
  # If a note in the track is not in the given scale, no additional notes will
  # be added in that slot.
  def harmonize(tonic, scale_name, position: 0, voices: nil, gate: 1, vel: 127)
    new_grid = []
    iter_harmonized_slots(tonic, scale_name, position: position, voices: voices) do |step, notes|
      if step.nil?
        new_grid << []
      else
        new_slot = notes.map { |n| Step.new(n, gate: gate, vel: vel) }
        new_slot.unshift(step)
        new_grid << new_slot
      end
    end

    mutate(grid: new_grid)
  end

  # Returns an array of three new Tracks, each representing a voice harmonized
  # with the note in the corresponding slot in this track. Can only be called
  # on mono tracks. The tracks are returned from lowest (bass) to highest
  # (soprano). Arguments are as described in harmonize.
  # If a note in the track is not in the given scale, there will be a rest in
  # the corresponding slots in the returned tracks.
  def split_harmonize(tonic, scale_name, position: 0, gate: 1, vel: 127)
    new_grids = [[], [], []]
    iter_harmonized_slots(tonic, scale_name, position: position) do |step, notes|
      if step.nil? || notes.empty?
        new_grids.each { |g| g << [] }
      else
        notes.each_with_index do |n, i|
          new_grids[i] << [Step.new(n, gate: gate, vel:vel)]
        end
      end
    end

    new_grids.map { |g| mutate(grid: g) }
  end

  # Return a new track in which each Step has its note snapped to the nearest
  # note among the given array, which should consist of MIDI note numbers or
  # symbols.
  def snap_to_notes(notes)
    mutate_each_step { |step| step.with_note(step.note.snap(notes)) }
  end

  # Return a new track in which each Step has its note snapped to the nearest
  # note in the given scale starting at the given root note. root should be a
  # MIDI note number of symbol, and scale should be one of the scale names known
  # to Sonic Pi.
  def snap_to_scale(root, scale)
    mutate_each_step { |step| step.with_note(step.note.snap_to_scale(root, scale)) }
  end

  # Returns a new track where each Step with note orig is replaced with a Step
  # that has note repl but is otherwise identical. If orig has an explicit
  # octave (or is a MIDI note number), only Steps with that exact note are
  # effected. If orig does not have an explicit octave, all Steps with the same
  # pitch class as orig have their notes changed to repl. If repl also does not
  # have an octave, the replacements are in the same octave as the original
  # step. For instance, consider a track with steps
  #     :c4, [:d1, :d2], :c3
  # sub_note(:c, :e) on that track would result in a track with the steps
  #     :e4, [:d1, :d2], :e3
  # And sub_note(:c, :f9) would result in
  #     :f9, [:d1, :d2], :f9
  # But sub_note(:d2, :f9) would only match the D2:
  #     :c4, [:d1, :f9], :c3
  # repl may be nil, :r, or :rest to remove Steps that match orig.
  def sub_note(orig, repl)
    orig_has_octave = MIDINote.has_octave?(orig)
    repl_is_rest = MIDINote.rest?(repl)
    repl_has_octave = repl_is_rest ? false : MIDINote.has_octave?(repl)

    orig = MIDINote.new(orig)

    mutate_each_step do |step|
      if (orig_has_octave && step.note == orig) || (!orig_has_octave && step.note.pitch_class == orig.pitch_class)
        if repl_is_rest
          nil
        elsif repl_has_octave
          step.with_note(repl)
        else
          step.with_note(step.note.with_pitch_class(repl))
        end
      else
        step
      end
    end
  end

  alias sub sub_note

  # Returns a new track, applying controlled random mutations to each Step. The
  # probability that any given mutation will apply to a Step is given by the p
  # parameter. Any given step may have 0 or more independent mutations applied
  # to it.
  # Possible changes:
  # - A transposition. The tone_shifts array (which may be nil) provides the
  #   possible semitone offsets that may be applied to a Step; a random value
  #   from it will be chosen if a transposition is to be applied. The
  #   octave_limit range describes the valid octaves in which a transposition
  #   can result. If the transposition moves a note outside of octave_limit,
  #   the note's octave is clamped to the closest extreme of octave_limit.
  # - A gate shift. The gate_delta float provides the maximum shift to apply to
  #   a Step; a random value between 0 and gate_delta will be chosen if a gate
  #   shift is to be applied. The gate_limit range restricts the resulting gate
  #   value in the same way octave_limit restricts transpositions.
  # - A velocity shift, controlled by velf_delta and velf_limit in the same way
  #   as a gate shift.
  def evolve(tone_shifts: [-12, 12], octave_limit: 1..6, gate_delta: 0.5, gate_limit: 0.1..1, velf_delta: 0, velf_limit: 0.1..1, p: 0.25)
    gate_delta = -gate_delta..gate_delta unless gate_delta.is_a?(Range)
    velf_delta = -velf_delta..velf_delta unless velf_delta.is_a?(Range)
    tone_shifts = [0] if tone_shifts == 0 || tone_shifts.nil?

    mutate_each_step do |step|
      tone_shift = (ExtApi.rand < p) ? ExtApi.choose(tone_shifts) : 0
      gate_shift = (ExtApi.rand < p) ? ExtApi.rand(gate_delta) : 0
      velf_shift = (ExtApi.rand < p) ? ExtApi.rand(velf_delta) : 0

      if tone_shift != 0
        step = step.shift_tone(tone_shift)

        new_octave = step.note.octave
        new_octave = octave_limit.min if new_octave < octave_limit.min
        new_octave = octave_limit.max if new_octave > octave_limit.max

        step = step.with_octave(new_octave)
      end

      if gate_shift != 0
        new_gate = step.gate + gate_shift
        new_gate = gate_limit.min if new_gate < gate_limit.min
        new_gate = gate_limit.max if new_gate > gate_limit.max

        step = step.with_gate(new_gate)
      end

      if velf_shift != 0
        new_velf = step.velf + velf_shift
        new_velf = velf_limit.min if new_velf < velf_limit.min
        new_velf = velf_limit.max if new_velf > velf_limit.max

        step = step.with_velf(new_velf)
      end

      step
    end
  end


  ### Getters

  # Returns the indexes of all non-empty slots in the grid.
  def indexes_of_filled_slots
    idxs = []
    @grid.each_with_index { |slot, i| idxs << i unless slot.empty? }
    idxs
  end

  # Returns the nth non-empty slot in the grid.
  def nth_filled_slot(n)
    @grid[indexes_of_filled_slots[n]]
  end

  alias filled_slot nth_filled_slot


  ### Track construction helpers
  # TODO: philosophically I want these to be private class methods, but you
  # can't call private class methods from instance methods :(. Figure out a way
  # to deal with that, or maybe just give up and make them instance methods.

  # Attempts to convert its argument to a Step. Conversion rules are:
  # - Steps are passed through verbatim.
  # - Notes (symbols, strings and numbers) are converted to Steps using that
  #   note and the default values for the other arguments of Step's initializer.
  # - It is an error to pass a rest (as defined by MIDINote.rest?) to this
  #   function.
  # def_gate and def_vel will be used for any Steps that need to be constructed.
  def self.stepify(x, def_gate: 1.0, def_vel: 127)
    raise "A rest cannot be converted to a Step" if MIDINote.rest?(x)

    case x
    when Step
      x
    when Symbol, String, Numeric, MIDINote
      Step.new(x, gate: def_gate, vel: def_vel)
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
        unless yelled
          ExtApi.puts("warning: more than one Step with note #{step.note} in the same slot! Picking one with the longest gate!")
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
  # - Rests (see MIDINote.rest?) become an empty slot ([]).
  # - Single notes (symbols, strings, or numbers) become a slot with a single
  #   Step that is the result of calling `stepify` on the argument.
  # - Single Steps become a slot containing just that step.
  # - Array-like arguments are converted as follows:
  #   1. All rests are removed.
  #   2. All remaining elements are passed through `stepify`.
  #   3. If more than one of the resulting Steps has the same note, a warning is
  #      printed, and only the Step with the longest gate is chosen.
  # def_gate and def_vel will be used for any Steps that need to be constructed.
  def self.slotify(x, def_gate: 1.0, def_vel: 127)
    return [].freeze if MIDINote.rest?(x)

    case x
    when Step
      [x].freeze
    when Symbol, String, Numeric, MIDINote
      [stepify(x, def_gate: def_gate, def_vel: def_vel)].freeze
    # NOTE: 'Enumerable' resolves to SonicPi::RuntimeMethods::Enumerable in this
    # context, which Array does *not* have as a superclass. So we need to use
    # ::Enumerable to get the built-in class.
    # SPVector is the parent class of RingVector, from e.g. `ring` and `chord`,
    # and potentially other list types in SP. It unfortunately does not derive
    # from (either) Enumerable, so we check for it manually and make sure to use
    # `to_a` before calling Enumerable methods on it.
    # Also note that in-place mutation methods (`reject!`, `map!`, e.g.) seem
    # to be broken on Chord objects, and should be avoided. See Arp.arpeggiate
    # for some notes.
    when ::Enumerable, SonicPi::Core::SPVector
      raw_slot = x.to_a.reject { |s| MIDINote.rest?(s) }.map { |s| stepify(s, def_gate: def_gate, def_vel: def_vel) }
      dedupe_slot(raw_slot).freeze
    else
      raise "Not a valid value for a slot: #{x.inspect}"
    end
  end

  # Attempts to convert its argument to a grid (a 2d array of Steps). The
  # returned array and all of its elements will be frozen. Conversion rules:
  # - A single rest (see MIDINote.rest?) becomes a grid with one rest ([[]]).
  # - A single note (symbol, string, or number) becomes a grid with one slot
  #   that is the result of calling `slotify` on the argument.
  # - A single Step becomes a grid with one slot containing that step.
  # - Array-like arguments are converted by passing each element through
  #   `slotify`.
  # def_gate and def_vel will be used for any Steps that need to be constructed.
  def self.gridify(x, def_gate: 1.0, def_vel: 127)
    return [[].freeze].freeze if MIDINote.rest?(x)

    case x
    when Step
      [[x].freeze].freeze
    when Symbol, String, Numeric, MIDINote
      [slotify(x, def_gate: def_gate, def_vel: def_vel)].freeze
    # See note in slotify about these class selections.
    when ::Enumerable, SonicPi::Core::SPVector
      # NOTE: this will convert non-array child elements into individual slots.
      # E.g. gridify([:a1, :b1]) will turn into [[:a1], [:b1]]. I think that's
      # desirable - it's a sort of 'smart' conversion, preferring mono-like
      # behavior unless notes are explicitly grouped into their own array.
      x.to_a.map { |s| slotify(s, def_gate: def_gate, def_vel: def_vel) }.freeze
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
    defaults = ExtApi.get(:__track_defaults) || {}
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
