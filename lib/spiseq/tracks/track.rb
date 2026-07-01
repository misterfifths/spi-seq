# frozen_string_literal: true

require_relative "cctrack"
require_relative "prob"
require_relative "step"
require_relative "trackbase"
require_relative "track_recorder"
require_relative "../internal/enumerables"
require_relative "../internal/log"
require_relative "../internal/random"
require_relative "../internal/utils"
require_relative "../math/curves"
require_relative "../theory/arp"
require_relative "../theory/midinote"
require_relative "../theory/notelength"
require_relative "../theory/rest"
require_relative "../theory/scale"

module SpiSeq; module Tracks
  # A Track deals with a grid whose slots contain {Step}s. Step instances
  # represent MIDI notes and properties controlling their expression (e.g.
  # {Step#gate gate} and {Step#vel velocity}). When a Track is played with a
  # {Player} or a {Playback.track_live_loop}, MIDI notes are sent corresponding
  # to the steps. Alternatively, they can be played using Sonic Pi's internal
  # synthesis, though that is not recommended.
  #
  # This class is aliased to `T`.
  #
  # **Tracks are immutable**. The mutation methods provided here, like {#up},
  # return new Tracks that have all the same attributes as the receiver (e.g.
  # {#timescale} and {#granularity}), with just the described change. That
  # includes the steps in its grid, unless the method explicitly modifies those.
  #
  # This class inherits much of its functionality from {TrackBase}, and adds
  # methods that deal explicitly with note-based {Step}s. See the {TrackBase}
  # documentation for the basics of the grid, slots, and mutation methods.
  class Track < TrackBase
    # The {Theory::Scale} to which notes in this track will be
    # {Theory::Scale#snap snapped} when it is played. See {#initialize} for
    # details.
    # @return [Theory::Scale]
    # @see #with_scale
    # @see #snap_to_scale
    attr_reader :scale


    ### @!group Initializers

    # Constructs a Track with the given grid and attributes. `gridish` will be
    # converted into a proper grid, an array of "slots". A slot is itself an
    # array of {Step}s, which all trigger simultaneously for a duration of the
    # `granularity`. A slot may be empty to represent a rest.
    #
    # Track itself is aliased to `T`, and `Track.new` is aliased to `[]`, so you
    # can instantiate a Track with `T[...]`.
    #
    # ### Grid definition
    #
    # The positional arguments may be some mix of:
    # - Single "stepish" values: a {Step}, {Theory::MIDINote}, something
    #   convertible to a MIDINote (a string, symbol, or number; see
    #   {Theory::MIDINote.new}), or a rest (nil, `:r`, `:rest`). Such values
    #   will be converted to a {Step} if needed, using the default gate (1.0)
    #   and velocity (127). The result will be a single-slot track containing
    #   just that step (or a rest). For example:
    #     T[S(:c4, gate: 0.5)]  # grid is [[S(:c4, gate: 0.5)]]
    #     T[N(:c4)]  # grid is [[S(:c4)]]
    #     T[:c4]  # grid is also [[S(:c4)]]; manually calling N is rarely necessary
    #     T[:r]  # grid is [[]]
    # - Arrays of "stepish" values. These are used as the contents of a slot;
    #   the values in an array will be grouped together into a slot in the
    #   track. For example:
    #     T[[:b1, :c1], :a1, :r, :d1]
    #     # grid is [ [S(:b1), S(:c1)], [S(:a1)], [], [S(:d1)] ]
    #
    #     T[[:c5, S(:d5, gate: 0.1)], :c4, :r]
    #     # grid is [ [S(:c5), S(:d5, gate: 0.1)], [S(:c4)], [] ]
    #
    # In the end, the grid conversion should be relatively natural. Non-array
    # value will get their own slot, and values grouped into an array will share
    # a slot. Note-like values will be converted to default {Step}s.
    #
    # It is never necessary to use actual MIDINote instances when constructing a
    # Track - you can just use the symbols, strings, or note numbers directly.
    # Similarly, you only need to manually make {Step}s (probably via {S}) if
    # you need to specify a non-default velocity or gate.
    #
    # Tracks must have at least one slot, though that slot may be empty (a
    # rest). So, `T[]` without any arguments is an error.
    #
    # A single slot cannot contain more than one step with the same {Step#note
    # note}. If that would happen, the step with the highest {Step#gate gate} is
    # is chosen, and the other colliding steps are discarded.
    #
    # ### Scale
    #
    # A Track may have a {#scale} assigned, an instance of {Theory::Scale}
    # (probably one from {Theory::Scale.full_scale}). If one is provided, all
    # the notes in the track are {Theory::Scale#snap quantized to that scale}
    # before they are played. This operation is non-destructive; a Track with a
    # scale can contain {Step}s with notes that are not on the scale, and they
    # will be snapped to the scale just in time for playback. The snapping
    # operation may result in duplicate notes within one slot (e.g. C# and D on
    # a C major scale will both snap to D), which will not be determined until
    # playback. In that case, the step with the longest {Step#gate gate} is
    # played.
    #
    # As an alternative to {#scale}, you can return a new Track with all steps
    # snapped to a scale using the {#snap_to_scale} method.
    #
    # @param gridish [Array<Step, String, Symbol, Integer>, Step, String,
    #   Symbol, Integer, nil, :r, :rest] Defines the grid for the new track; see
    #   above.
    # @param granularity [Theory::NoteLength, Number, Symbol] The {#granularity}
    #   for the new track. Can be a {Theory::NoteLength} or a value understood
    #   by {Theory::NoteLength.new}.
    # @param timescale [Number] The {#timescale} for the new track.
    # @param scale [Theory::Scale, nil] The {#scale} for the new track; see
    #   above.
    def initialize(*gridish, granularity: :eighth, scale: nil, timescale: 1)
      # Track itself does basically nothing with the scale; it's all handled by
      # the Player.
      @scale = scale

      super(*gridish, granularity: granularity, timescale: timescale)
    end

    # Constructs a Track that arpeggiates the given notes. A {Step} will be
    # created for each note with the default gate and velocity (1.0 and 127),
    # and each step will be placed in a slot by itself.
    #
    # The `direction`, `spread`, and `extra_octaves` arguments are the same as
    # those passed to {Theory::Arp.arpeggiate}.
    #
    # Additionally, after arpeggiating the notes, this method can place them in
    # the new track according to a Euclidean rhythm. The `pulses`, `length`,
    # `rotate`, and `full_cycle` arguments are the same as those passed to
    # {.euclid}.
    #
    # @example
    #   Track.arp([:a1, :b1, :c1], :twouptwodown)
    #   # is equivalent to
    #   T[:c1, :c1, :a1, :a1, :b1, :b1, :a1, :a1]
    #
    # @example
    #   Track.arp([:a1, :b1, :c1], :updown, pulses: 4, length: 9)
    #   # is equivalent to
    #   T[:c1, :r, :r, :a1, :r, :b1, :r, :a1, :r]
    #   # The notes from the arpeggiation (:c1, :a1, :b1, :a1) were spread over
    #   # 4 beats in 9 slots, according to a Euclidean rhythm.
    #
    # @param notes [Array<Theory::MIDINote, String, Symbol, Integer>] The notes
    #   to arpeggiate, an array of {Theory::MIDINote}s or any of the values
    #   understood by {Theory::MIDINote.new}.
    # @param direction [Symbol, String] One of the direction names understood by
    #   {Theory::Arp}, e.g. `:pinky` or `:updown`.
    # @param spread [Integer] Adds notes an octave above some number of the
    #   lowest notes in the result. See {Theory::Arp.arpeggiate} for details.
    # @param extra_octaves [Array<Integer>] Adds a copy of the incoming notes
    #   shifted by some number of octaves before arpeggiating. See
    #   {Theory::Arp.arpeggiate} for details.
    # @param pulses [Integer, nil] The number of hits in the Euclidean rhythm,
    #   or nil if no rhythm should be applied. If this is non-nil, `length` must
    #   be as well.
    # @param length [Integer, nil] The length of the Euclidean rhythm, or nil if
    #   no rhythm should be applied. If this is non-nil, `pulses` must be as
    #   well.
    # @param rotate [Integer] Rotates the Euclidean rhythm leftward the given
    #   number of times before using it to construct the track.
    # @param full_cycle [Boolean] If `pulses` and `length` are non-nil and this
    #   parameter is true, the Euclidean rhythm is repeated until all notes are
    #   used and the track loops cleanly. See {.euclid} for examples.
    # @param granularity [Theory::NoteLength, Number, Symbol] The {#granularity
    #   granularity} for the new track. Can be a {Theory::NoteLength} or a value
    #   understood by {Theory::NoteLength.new}.
    # @param timescale [Number] The {#timescale timescale} for the new track.
    # @return [Track]
    # @see Theory::Arp.arpeggiate
    # @see .euclid
    def self.arp(notes, direction = :up, spread: 0, extra_octaves: [], pulses: nil, length: nil, rotate: 0, full_cycle: true, granularity: :eighth, timescale: 1)
      notes = Theory::Arp.arpeggiate(notes, direction, spread: spread, extra_octaves: extra_octaves)
      if pulses.nil?
        grid = notes.map { |n| [Step.new(n)] }
        new(*grid, granularity: granularity, timescale: timescale)
      else
        raise TypeError, "pulses and length must both be nil or both be integers" if length.nil?
        euclid(notes, pulses, length, rotate: rotate, full_cycle: full_cycle, granularity: granularity, timescale: timescale)
      end
    end

    # Construct an [isorhythmic](https://en.wikipedia.org/wiki/Isorhythm) Track.
    # To use classical terms, `gates` defines the talea and `notes` the color.
    #
    # `gates` is an array of numbers which defines the rhythm over which `notes`
    # will be played. The numbers in `gates` will become the gates of the
    # {Step}s in the track. The values in `gates` may also be booleans - true
    # will be interpreted as a gate of 1 and false a gate of 0.
    #
    # Within `gates`, there are "runs". A run is a series of gates that would
    # define a tied sequence of steps (or single untied steps). For instance, a
    # gates array of [1, 0.5, 0.25, 1] defines 3 runs: the first two steps would
    # be tied together, then a standalone step with gate 0.25, and a final step
    # with gate 1. All runs terminate at the end of the array.
    #
    # Each run will be assigned the same note from the `notes` array. The next
    # run will be assigned the next note and so on, wrapping around to the
    # beginning of `notes` as needed. The track continues in this way until all
    # the values in `notes` are used and the track would cycle cleanly.
    #
    # This method has much in common with {.euclid}, except that a "hit" can
    # last more than one slot.
    #
    # @example
    #   Track.isorhythm([:a1, :b2, :c3], [1, 0.5, 0, 0.25])
    #   # is equivalent to
    #   T[:a1, S(:a1, gate: 0.5), :r, S(:b2, gate: 0.25),
    #     :c3, S(:c3, gate: 0.5), :r, S(:a1, gate: 0.25),
    #     :b2, S(:b2, gate: 0.5), :r, S(:c3, gate: 0.25)]
    #   # The gates array represents 2 runs, and each of those runs is assigned
    #   # the same note. The rhythm defined by the gates was repeated 3 times
    #   # while cycling through the notes, so that every note was used and the
    #   # track ends on the final provided note.
    #
    # @param notes [Array<Theory::MIDINote, String, Symbol, Integer>] The notes
    #   to apply to the rhythm in the new track, an array of MIDINotes or any of
    #   the values understood by {Theory::MIDINote.new}.
    # @param gates [Array<Number, Boolean>] The gates that define the rhythm for
    #   the track.
    # @param granularity [Theory::NoteLength, Number, Symbol] The {#granularity}
    #   for the new track. Can be a {Theory::NoteLength} or a value understood
    #   by {Theory::NoteLength.new}.
    # @param timescale [Number] The {#timescale} for the new track.
    # @return [Track]
    # @see .euclid
    # @see #extract_gates
    def self.isorhythm(notes, gates, granularity: :eighth, timescale: 1)
      # Gameplan:
      # This is a variation on `euclid` above, really, with the added
      # complication that a "hit" can last more than one slot.
      # Calculate the number of distinct notes that the `gates` array specifies.
      # That is: find the number of runs, a run being a sequence of tied notes.
      # Ties at the end of `gates` are considered ended even if they would
      # continue in a loop. As with `euclid` above, call that number p.
      # We are spreading n = notes.length notes over those p hits, and we want
      # to cleanly cycle while using all the notes. As per the calculation in
      # `euclid`, that will take exactly lcm(p, n) / p cycles.

      # We're going to leverage the existing run manipulation machinery on Track
      # by building a rhythm track with the proper gates but all C4s. We'll then
      # repeat that track, fixing up the notes as we go along.
      hit_grid = gates.map do |g|
        case g
        when 0, false
          []
        when true
          Step.new(:c4)
        else
          Step.new(:c4, gate: g)
        end
      end
      hit_track = new(*hit_grid, granularity: granularity, timescale: timescale)

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
    class << self; alias iso isorhythm; end


    ### @!group Properties

    # Returns an array of numbers, one per slot in this track, containing the
    # gate for the step in that slot (or 0 if the slot is empty). It is an error
    # to call this method on a track with more than one step in any slot.
    #
    # The resulting array is suitable for use with {.isorhythm}.
    #
    # @example
    #   T[:c4, S(:c4, 0.1), :r].gates
    #   # is equal to
    #   [1, 0.1, 0]
    #
    # @return [Array<Number>]
    # @see .isorhythm
    def extract_gates
      raise ArgumentError, "extract_gates can only be used on a mono track" unless mono?
      @grid.map { |slot| slot.empty? ? 0 : slot[0].gate }
    end
    alias gates extract_gates
    alias extract_rhythm extract_gates
    alias rhythm extract_gates


    ### Mutators

    ## @!group Granularity manipulation

    protected def expand_once
      raise RangeError, "Cannot expand past 64th-note granularity" if @granularity == Theory::NoteLength::SixtyFourth

      # Gameplan: each slot in the grid will expand to two slots. Consider each
      # slot individually. Each Step in that slot may expand to either one Step,
      # or two Steps in each of the new slots. Find the "total gate" for each
      # Step by multiplying its current gate by 2. If it is greater than one,
      # the Step becomes two Steps: one a tie, and the other with gate of
      # total_gate - 1. If the total gate is less than 1, the Step remains as
      # one (longer) step in the first of the new slots.

      expand_step = lambda do |step|
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
          step1, step2 = expand_step.call(step)
          new_slots[0] << step1
          new_slots[1] << step2 unless step2.nil?
        end

        new_grid.concat(new_slots)
      end

      mutate(grid: new_grid, granularity: @granularity.halve)
    end

    # Creates a new Track with double the {#granularity granularity} and number
    # of slots. The length of each {Step} is doubled to keep the Track sounding
    # roughly the same, which may entail turning a single step into two tied
    # ones.
    #
    # This is the opposite of {#condense}.
    #
    # If a step has a {Step#prob probability} and expands into two steps in the
    # new track, only the second will inherit the probability of the original
    # step.
    #
    # It is an error to attempt to expand a track with 64th-note granularity.
    #
    # @example
    #   t = T[S(:a1, gate: 0.25),
    #         S(:b1, gate: 0.5),
    #         S(:c1, gate: 0.75),
    #         :d1, granularity: :eighth]
    #   u = t.expand
    #   # u is equivalent to
    #   T[S(:a1, gate: 0.5), :r,
    #     :b1, :r,
    #     :c1, S(:c1, gate: 0.5),
    #     :d1, :d1, granularity: :sixteenth]
    #   # There are now twice as many slots and the granularity has doubled. But
    #   # to keep things sounding the same, the gates on all steps have also
    #   # doubled, which in some cases resulted a single step expanding to a tie
    #
    # @param times [Integer] The number of times to repeat the expansion.
    # @return [Track]
    # @see #with_granularity
    # @see #condense
    # @see #regrain
    def expand(times = 1)
      t = self
      while times > 0
        t = t.expand_once
        times -= 1
      end

      t
    end

    protected def condense_once
      raise RangeError, "Cannot condense past whole-note granularity" if @granularity == Theory::NoteLength::Whole

      # Gameplan: each pair of slots in the grid will collapse into one slot in
      # a new grid. In each pair, find the total gate of any given Step by
      # checking if it is tied to a Step with the same note in the following
      # slot. Divide that total gate by 2 and make a new step. Repeat,
      # condensing all the steps from the pair of slots into shorter steps in
      # one slot.

      # Condense two Steps for the same note into one. The Steps are passed in-
      # order as they appear in the Track. One or the other may be nil, but not
      # both. May return nil if the steps condense to nothing.
      condense_steps = lambda do |step1, step2|
        # The Oxi seems to discard anything that begins on the second slot when
        # condensing.
        return nil if step1.nil?

        if step2.nil?
          total_gate = step1.gate / 2.0
        else
          total_gate = (step1.gate + step2.gate) / 2.0
        end

        # The probability and velocity of the second step is discarded; the
        # first step wins. (Again, just Oxi behavior.)
        step1.with_gate(total_gate)
      end

      # Condense the Steps from one or two slots into one new slot. The second
      # slot will be nil for the last slot in a Track with an odd number of
      # slots.
      condense_slots = lambda do |slot1, slot2 = nil|
        steps_by_note = Hash.new { |h, k| h[k] = [nil, nil] }
        slot1.each { |step| steps_by_note[step.note][0] = step }
        slot2&.each { |step| steps_by_note[step.note][1] = step }

        new_slot = []
        steps_by_note.each_value do |steps|
          condensed_step = condense_steps.call(*steps)
          new_slot << condensed_step unless condensed_step.nil?
        end

        new_slot
      end

      new_grid = []
      @grid.each_slice(2) do |slot_chunk|
        new_grid << condense_slots.call(*slot_chunk)
      end

      mutate(grid: new_grid, granularity: @granularity.double)
    end

    # Creates a new Track with half the {#granularity granularity} and number of
    # slots. Steps and ties have their lengths halved to keep the track sounding
    # roughly the same.
    #
    # This is the opposite of {#expand}, though this operation is significantly
    # lossier. Steps with short gates and those starting on off-beats may be
    # completely absent from the result.
    #
    # If a tied pair of steps has a {Step#prob probability}, only the
    # probability of the first step will be present in the condensed step.
    #
    # It is an error to attempt to condense a track with whole-note granularity.
    #
    # @example
    #   t = T[S(:a1, gate: 0.5), :r,
    #         :b1, :r,
    #         :c1, S(:c1, gate: 0.5),
    #         :d1, :d1, granularity: :sixteenth]
    #   u = t.condense
    #   # u is equivalent to
    #   T[S(:a1, gate: 0.25),
    #     S(:b1, gate: 0.5),
    #     S(:c1, gate: 0.75),
    #     :d1, granularity: :eighth]
    #   # The number of slots and granularity have both been halved, but so has
    #   # the gate of each step or pair of tied steps. In some cases that
    #   # resulted in two tied steps becoming one.
    #
    # @param times [Integer] The number of times to repeat the condensing
    #   operation.
    # @return [Track]
    # @see #with_granularity
    # @see #expand
    # @see #regrain
    def condense(times = 1)
      t = self
      while times > 0
        t = t.condense_once
        times -= 1
      end

      t
    end

    # {#expand Expands} or {#condense condenses} the appropriate number of times
    # to return a new Track with the given {#granularity granularity}.
    #
    # @example
    #   t = T[:a1, :b1, granularity: :eighth]
    #
    #   t.regrain(:thirtysecond)
    #   # is equivalent to
    #   t.expand.expand
    #
    # @param new_granularity [Theory::NoteLength, Number, Symbol] The
    #   {#granularity granularity} for the new track. Can be a
    #   {Theory::NoteLength} or a value understood by {Theory::NoteLength.new}.
    # @return [Track]
    # @see #with_granularity
    # @see #expand
    # @see #condense
    def regranularize(new_granularity)
      new_granularity = Theory::NoteLength.new(new_granularity)

      return self if @granularity == new_granularity

      steps = @granularity.steps_to(new_granularity)
      (new_granularity < @granularity) ? expand(steps) : condense(steps)
    end
    alias regrain regranularize
    alias grain regranularize


    ## @!group Attribute mutations

    # Returns a new track with the given {#scale}. See {#initialize} for details
    # on this functionality.
    # @param scale [Theory::Scale]
    # @return [Track]
    def with_scale(scale)
      mutate(scale: scale)
    end


    ## @!group Step attribute mutators

    # Return a new Track where each step has the given {Step#gate gate}.
    #
    # @example
    #   T[:c4, S(:d4, gate: 0.5), :r].gate(0.75)
    #   # is equivalent to
    #   T[S(:c5, gate: 0.75), S(:d4, gate: 0.75), :r]
    #
    # @param new_gate [Number]
    # @return [Track]
    # @see #scale_gate
    # @see #gate_curve
    # @see #vel
    def with_gate(new_gate)
      mutate_each_step { |step| step.with_gate(new_gate) }
    end
    alias gate with_gate

    # Return a new Track where each step's {Step#gate gate} is scaled by the
    # given factor.
    #
    # @example
    #   T[:c4, S(:d4, gate: 0.5), :r].scale_gate(0.5)
    #   # is equivalent to
    #   T[S(:c5, gate: 0.5), S(:d4, gate: 0.25), :r]
    #
    # @param factor [Number]
    # @return [Track]
    # @see #gate
    # @see #gate_curve
    def scale_gate(factor)
      mutate_each_step { |step| step.with_gate(step.gate * factor) }
    end

    # Return a new Track where each step has the given {Step#vel velocity},
    # specified in the MIDI range of 0 - 127.
    #
    # @example
    #   T[:c4, S(:d4, vel: 20), :r].vel(63)
    #   # is equivalent to
    #   T[S(:c5, vel: 63), S(:d4, vel: 63), :r]
    #
    # @param new_vel [Number]
    # @return [Track]
    # @see #gate
    # @see #with_velf
    # @see #scale_vel
    # @see #vel_curve
    def with_vel(new_vel)
      mutate_each_step { |step| step.with_vel(new_vel) }
    end
    alias vel with_vel

    # Return a new Track where each step has the given {Step#vel velocity},
    # specified as a value between 0 and 1 inclusive.
    #
    # @example
    #   T[:c4, S(:d4, vel: 20), :r].velf(0.5)
    #   # is equivalent to
    #   T[S(:c5, vel: 63), S(:d4, vel: 63), :r]
    #
    # @param new_velf [Number]
    # @return [Track]
    # @see Step#velf
    # @see #with_vel
    # @see #vel_curve
    def with_velf(new_velf)
      mutate_each_step { |step| step.with_velf(new_velf) }
    end
    alias velf with_velf

    # Return a new Track where each step's {Step#vel velocity} is scaled by the
    # given factor.
    #
    # @example
    #   T[:c4, S(:d4, vel: 20), :r].scale_vel(0.5)
    #   # is equivalent to
    #   T[S(:c5, vel: 63), S(:d4, vel: 10), :r]
    #
    # @param factor [Number]
    # @return [Track]
    # @see #with_vel
    # @see #with_velf
    # @see #vel_curve
    def scale_vel(factor)
      mutate_each_step { |step| step.with_vel(step.vel * factor) }
    end
    alias scale_velf scale_vel

    # Returns a new Track where the octave of each step's {Step#note note} is
    # set to the given value.
    #
    # @example
    #   T[:a1, :b2, :c3].with_octave(5)
    #   # is equivalent to
    #   T[:a5, :b5, :c5]
    #
    # @param new_octave [Integer]
    # @return [Track]
    # @see #shift_octave
    # @see #up
    # @see #down
    # @see #transpose
    def with_octave(new_octave)
      mutate_each_step { |step| step.with_octave(new_octave) }
    end
    alias octave with_octave
    alias oct octave

    # Returns a new Track by shifting the octave of each step's {Step#note note}
    # by the given amount.
    #
    # @example
    #   T[:a1, :b2, :c3].shift_octave(2)
    #   # is equivalent to
    #   T[:a3, :b4, :c5]
    #
    # @param shift [Integer]
    # @return [Track]
    # @see #with_octave
    # @see #up
    # @see #down
    # @see #transpose
    def shift_octave(shift)
      mutate_each_step { |step| step.shift_octave(shift) }
    end

    # Returns a new Track by increasing the octave of each step's {Step#note
    # note} by the given amount. This is equivalent to {#shift_octave}.
    # @param octave_shift [Integer]
    # @return [Track]
    # @see #with_octave
    # @see #shift_octave
    # @see #down
    # @see #transpose
    def up(octave_shift = 1)
      shift_octave(octave_shift)
    end

    # Returns a new Track by decreasing the octave of each Step's note by the
    # given amount. This is equivalent to {#shift_octave} with the negation of
    # its argument.
    # @param octave_shift [Integer]
    # @return [Track]
    # @see #with_octave
    # @see #shift_octave
    # @see #up
    # @see #transpose
    def down(octave_shift = 1)
      shift_octave(-octave_shift)
    end

    # Return a new Track where, with probability `p`, each step's {Step#note
    # note} is shifted by a random value in the given range.
    #
    # @example
    #   T[:a4, :b4, :c4, :d4].rand_octave(-2..1, p: 0.75)
    #   # might return a track equivalent to
    #   T[:a2, :b4, :c5, :d3]
    #
    # @param range [Integer, Range] Defines the range of allowed octave shifts.
    #   If an integer is passed, the range `-range..range` is used.
    # @param p [Number] The probability (0 - 1) that any given step has its
    #   octave shifted.
    # @return [Track]
    # @see #shift_octave
    # @see #up
    # @see #down
    def rand_octave(range = 1, p: 0.5)
      mutate_each_step do |step|
        next step unless Internal::Random.chance(p)

        # We've already decided to shift, so ignore random 0 values. Not using
        # rand_i here since it's exclusive. rand is too, but we're rounding.
        shift = 0
        while shift == 0
          if range.is_a?(Range)
            shift = Internal::Random.rand_f(range).round
          else
            shift = Internal::Random.rand_f(-range..range).round
          end
        end

        step.shift_octave(shift)
      end
    end
    alias roct rand_octave

    # Returns a new Track where each step's {Step#note} is shifted by the given
    # number of semitones.
    #
    # @example
    #   T[:a1, :b1, :r, :c1].transpose(7)
    #   # is equivalent to
    #   T[:e2, :fs2, :r, :g1]
    #
    # @param shift [Integer]
    # @return [Track]
    # @see #semi_up
    # @see #semi_down
    def transpose(shift)
      mutate_each_step { |step| step.transpose(shift) }
    end
    alias tone transpose
    alias shift_tone transpose
    alias t transpose

    # Returns a new Track where each step's {Step#note} is increased by the
    # given number of semitones. This is equivalent to {#transpose}.
    # @param tone_shift [Integer]
    # @return [Track]
    # @see #transpose
    def semi_up(tone_shift = 1)
      transpose(tone_shift)
    end
    alias sup semi_up

    # Returns a new Track where each step's {Step#note} is decreased by the
    # given number of semitones. This is equivalent to {#transpose} with the
    # negation of its argument.
    # @param tone_shift [Integer]
    # @return [Track]
    # @see #transpose
    def semi_down(tone_shift = 1)
      transpose(-tone_shift)
    end
    alias sdown semi_down

    # Return a new Track in which each step has its {Step#note note}
    # {Theory::MIDINote#snap snapped} to the nearest note in the given array.
    #
    # @example
    #   notes = [:c4, :e4, :g4, :b4]
    #   T[:e4, :b3, :gb4, :bs4].snap_to_notes(notes)
    #   # is equivalent to
    #   T[:e4, :c4, :g4, :b4]
    #
    # @param notes [Array<Theory::MIDINote, String, Symbol, Integer>] The notes
    #   which steps will be snapped. Elements can be {Theory::MIDINote}s or
    #   anything understood by {Theory::MIDINote.new}.
    # @return [Track]
    # @see #snap_to_scale
    # @see Theory::MIDINote#snap
    def snap_to_notes(notes)
      mutate_each_step { |step| step.with_note(step.note.snap(notes)) }
    end

    # Return a new Track in which each step has its {Step#note note} snapped to
    # the nearest note in a scale starting on a particular tonic.
    #
    # Unlike providing a global Track {#scale} for quantization in {#initialize}
    # or {#with_scale}, this action is "destructive" in that steps in the new
    # track will have modified notes.
    #
    # @param tonic [String, Symbol] The pitch class for the root note of the
    #   scale, e.g. `:c`.
    # @param scale_name [Symbol, String] The name of the scale to use, one of
    #   the values in {Theory::Scale::SCALE_NAMES}.
    # @return [Track]
    # @see #scale
    # @see Theory::Scale.full_scale
    # @see Theory::Scale#snap
    def snap_to_scale(tonic, scale_name)
      scale = Theory::Scale.full_scale(tonic, scale_name)
      mutate_each_step { |step| step.with_note(scale.snap(step.note)) }
    end


    ## @!group Moving Step attributes along a curve

    # Returns a new Track where each step's {Step#gate gate} is replaced with
    # the result of `curve_func`.
    #
    # `curve_func` must take 1 or 2 arguments, which are, in order:
    # - The percentage through the {#grid grid} (0.0 - 1.0) where the slot
    #   containing the step falls.
    # - The index in the {#grid grid} of the slot containing the step.
    #
    # `curve_func` should return a floating point value 0 - 1 that will be used
    # as the gate for all steps in the corresponding slot.
    #
    # See the {Math::Curves} and {Math::Easings} modules for prebuilt functions
    # that meet these requirements.
    #
    # If `min` or `max` is provided, the curve function will be scaled via
    # {Math::Curves.scale} so that it falls in the given range. If only one of
    # `min` or `max` is provided, the other defaults to the respective endpoint
    # of the range 0 - 1.
    #
    # @param curve_func [#call] A callable defining the curve; see above.
    # @param min [Number, nil] Defines scaling for the curve; see above.
    # @param max [Number, nil] Defines scaling for the curve; see above.
    # @return [Track]
    # @see #gate
    # @see #scale_gate
    # @see #vel_curve
    def with_gate_curve(curve_func, min: nil, max: nil)
      raise TypeError, "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2

      if !min.nil? || !max.nil?
        min = 0 if min.nil?
        max = 1 if max.nil?
        curve_func = Math::Curves.scale(curve_func, min, max)
      end

      mutate_each_step do |step, slot_idx, pct|
        gate = Internal::Utils.call_varargs(curve_func, pct, slot_idx)
        step.with_gate(gate)
      end
    end
    alias gate_curve with_gate_curve

    # Returns a new Track where each step's {Step#vel velocity} is replaced with
    # the result of `curve_func`.
    #
    # `curve_func` must take 1 or 2 arguments, which are, in order:
    # - The percentage through the {#grid grid} (0.0 - 1.0) where the slot
    #   containing the step falls.
    # - The index in the {#grid grid} of the slot containing the step.
    #
    # `curve_func` should return a floating point value that will be used as the
    # velocity for all steps in the corresponding slot. Its range depends on
    # `zero_to_one`:
    # - If `zero_to_one` is true, a floating point number 0 - 1 is expected that
    #   will be scaled to a velocity value between 0 and 127 inclusive.
    # - If `zero_to_one` is false, an integer between 0 and 127 inclusive is
    #   expected, and will be used directly as the velocity.
    #
    # See the {Math::Curves} and {Math::Easings} modules for prebuilt functions
    # that meet these requirements, as long as `zero_to_one` is true.
    #
    # {#with_velf_curve} is an alias where `zero_to_one` is true.
    #
    # If `min` or `max` is provided, the curve function will be scaled via
    # {Math::Curves.scale} so that it falls in the given range. If only one of
    # `min` or `max` is provided, the other defaults to the respective endpoint
    # of the range (0 - 127 if `zero_to_one` is false, otherwise 0 - 1).
    #
    # @param curve_func [#call] A callable defining the curve; see above.
    # @param zero_to_one [Boolean] Defines the range of `curve_func`; see above.
    # @param min [Number, nil] Defines scaling for the curve; see above.
    # @param max [Number, nil] Defines scaling for the curve; see above.
    # @return [Track]
    # @see #vel
    # @see #scale_vel
    # @see #gate_curve
    # @see #with_velf_curve
    # @see #fade_in
    # @see #fade_out
    def with_vel_curve(curve_func, zero_to_one: false, min: nil, max: nil)
      raise TypeError, "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2

      if !min.nil? || !max.nil?
        min = 0 if min.nil?
        max = zero_to_one ? 1 : 127 if max.nil?

        curve_func = Math::Curves.scale(curve_func, min, max, orig_min: 0, orig_max: zero_to_one ? 1 : 127)
      end

      mutate_each_step do |step, slot_idx, pct|
        vel = Internal::Utils.call_varargs(curve_func, pct, slot_idx)
        vel *= 127 if zero_to_one  # with_vel will round & clamp this
        step.with_vel(vel)
      end
    end
    alias vel_curve with_vel_curve

    # An alias for {#with_vel_curve} with `zero_to_one` set to true. See that
    # method for details.
    # @param curve_func [#call] A callable defining the curve, which should
    #   output a value between 0 and 1.
    # @param min [Number, nil] Defines scaling for the curve.
    # @param max [Number, nil] Defines scaling for the curve.
    # @return [Track]
    # @see #with_vel_curve
    def with_velf_curve(curve_func, min: nil, max: nil)
      with_vel_curve(curve_func, zero_to_one: true, min: min, max: max)
    end
    alias velf_curve with_velf_curve

    # Returns a new Track that fades in linearly, via {Step#vel velocity}.
    #
    # @example
    #   T[:a1, :b1, :c1, :d1, :e1, :f1].fade_in(0.1, start: 0.5)
    #   # is equivalent to
    #   T[S(:a1, vel: 12), S(:b1, vel: 12), S(:c1, vel: 12),
    #     S(:d1, vel: 35), S(:e1, vel: 81), :f1]
    #   # Until the halfway point (start = 0.5), steps were given the `min`
    #   # velocity (0.1 * 127 = 12). After that point, velocities increase
    #   # linearly to the `max` (1 by default = 127).
    #
    # @param min [Number] The starting velocity, as the steps begin to fade in.
    # @param max [Number] The velocity for steps in the final slot of the new
    #   track.
    # @param start [Number] Specifies at what percentage through the track to
    #   begin fading; all steps in slots before this percentage will have a
    #   velocity of `min`, and ones thereafter will increase along the curve to
    #   `max`.
    # @return [Track]
    # @see #vel
    # @see #with_vel_curve
    # @see Math::Curves.fade_in_linear
    # @see #fade_in_quad
    # @see #fade_out
    def fade_in_linear(min = 0.0, max = 1.0, start: 0.0)
      with_velf_curve(Math::Curves.fade_in_linear(min, max, start))
    end
    alias fade_in_lin fade_in_linear
    alias fade_in fade_in_linear
    alias in_lin fade_in_linear

    # Returns a new Track that fades in quadratically, via {Step#vel velocity}.
    # This is the same as {#fade_in_linear}, but uses a quadratic curve.
    # @param (see #fade_in_linear)
    # @return [Track]
    # @see #vel
    # @see #with_vel_curve
    # @see Math::Curves.fade_in_quad
    # @see #fade_in
    # @see #fade_out
    def fade_in_quad(min = 0.0, max = 1.0, start: 0.0)
      with_velf_curve(Math::Curves.fade_in_quad(min, max, start))
    end
    alias in_quad fade_in_quad

    # Returns a new Track that fades out linearly, via {Step#vel velocity}.
    #
    # @example
    #   T[:a1, :b1, :c1, :d1, :e1, :f1].fade_out(1, 0.1, start: 0.5)
    #   # is equivalent to
    #   T[:a1, :b1, :c1,
    #     S(:d1, vel: 104), S(:e1, vel: 58), S(:f1, vel: 12)]
    #   # Until the halfway point (start = 0.5), steps were given the `max`
    #   # velocity (1 * 127 = 127). After that point, velocities decrease
    #   # linearly to the `min` (0.1 * 127 = 12).
    #
    # @param max [Number] The starting velocity, as the steps begin to fade out.
    # @param min [Number] The velocity for steps in the last slot of the new
    #   track.
    # @param start [Number] Specifies at what percentage through the track to
    #   begin fading; all steps in slots before this percentage will have a
    #   velocity of `max`, and ones thereafter will decrease along the curve to
    #   `min`.
    # @return [Track]
    # @see #vel
    # @see #with_vel_curve
    # @see Math::Curves.fade_out_linear
    # @see #fade_out_quad
    # @see #fade_in
    def fade_out_linear(max = 1.0, min = 0.0, start: 0.0)
      with_velf_curve(Math::Curves.fade_out_linear(max, min, start))
    end
    alias fade_out_lin fade_out_linear
    alias fade_out fade_out_linear
    alias out_lin fade_out_linear

    # Returns a new Track that fades out quadratically, via {Step#vel velocity}.
    # This is the same as {#fade_out_linear}, but uses a quadratic curve.
    # @param (see #fade_out_linear)
    # @return [Track]
    # @see #vel
    # @see #with_vel_curve
    # @see Math::Curves.fade_out_quad
    # @see #fade_out
    # @see #fade_in
    def fade_out_quad(max = 1.0, min = 0.0, start: 0.0)
      with_velf_curve(Math::Curves.fade_out_quad(max, min, start))
    end
    alias out_quad fade_out_quad

    # Finds runs of tied Steps with the same notes and yields to its block two
    # arguments for each: the index of the slot that begins the run, and the
    # array of Steps that belong to the run. A run is ended by the end of the
    # track, or a Step that is not tied. The final Step in a run is included in
    # the array yielded to the block. Runs that consist of a single Step (i.e.
    # non-tied Steps that are not continuing a note from the previous Step, or
    # Steps at the end of the Track that are not continuing a note) are also
    # yielded to the block.
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

    # Returns a new Track with the Steps in a run of tied Steps with the same
    # note is replaced with another set of Steps.
    #
    # `starting_slot_idx` is the index of the slot where replacement should
    # begin. `orig_steps` is an array of the original steps that are being
    # replaced. ] `new_steps` is an array of steps which should replace those
    # from `orig_steps`.
    #
    # `orig_steps` must be the actual Step instances that are currently in this
    # Track, not copies of them with the same properties. This method is meant
    # to be used in tandem with `each_run`, which returns such an array of
    # steps.
    #
    # This method works by first removing all the steps from `orig_steps` from
    # their corresponding slots, and then adding all the steps from `new_steps`.
    # So, it is valid for new_steps to be a different length than `orig_steps`,
    # as long as `starting_slot_idx + new_steps.length` is not greater than the
    # length of the track.
    protected def set_run(starting_slot_idx, orig_steps, new_steps)
      raise IndexError, "replacement steps are past the end of the track" if starting_slot_idx + new_steps.length > @grid.length

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

    # Returns a new Track with each run of tied Steps replaced with those
    # returned from the block. The block will be given two arguments: the index
    # of the slot where the run begins, and an array of the Steps that
    # constitute the run. The block should return an array of Steps, which will
    # take the place of the run's Steps in the returned track. The array
    # returned from the block may have a different length than the original run,
    # but, when the new Steps are added beginning at the run's starting slot,
    # they must not exceed the length of the Track.
    private def mutate_runs
      new_track = self
      each_run do |starting_slot_idx, orig_steps|
        new_steps = yield starting_slot_idx, orig_steps.dup  # dup'd so the block can mutate it
        new_track = new_track.set_run(starting_slot_idx, orig_steps, new_steps)
      end
      new_track
    end

    # Returns a new track where the final Steps in runs of tied Steps with the
    # same note are replaced with the result of the block. Helper for
    # `taper_vel` and `taper_gate`.
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

    # Returns a new Track replacing the {Step#gate gate} on the final step of
    # runs of tied steps with the same {Step#note note}.
    #
    # @example
    #   T[:c4, :c4, :c4, :r, :d4, S(:d4, gate: 0.5)].taper_gate(0.25)
    #   # is equivalent to
    #   T[:c4, :c4, S(:c4, gate: 0.25), :r, :d4, S(:d4, gate: 0.25)]
    #   # The final step in both runs had its gate set to 0.25.
    #
    # @param trailing_gate [Number] The gate to apply to the final step in a
    #   run.
    # @param taper_final_tie [Boolean] If false, steps in the final slot of the
    #   track will *not* have their gate adjusted if they are ties and are
    #   continued with a step with the same note in the first slot of the track.
    # @param taper_single [Boolean] If true, standalone steps that are not
    #   continuations of a tie also have their gate adjusted.
    # @return [Track]
    # @see #gate
    # @see #gate_curve
    # @see #taper_vel
    def taper_gate(trailing_gate = 0.75, taper_final_tie: false, taper_single: false)
      taper_steps(taper_final_tie: taper_final_tie, taper_single: taper_single) { |s| s.with_gate(trailing_gate) }
    end

    # Returns a new Track replacing the {Step#vel velocity} on the final step of
    # runs of tied steps with the same {Step#note note}.
    #
    # This is the velocity-oriented version of {#taper_gate}; see its
    # documentation for details.
    #
    # @param trailing_vel [Number] The velocity to apply to the final step in a
    #   run. If `zero_to_one` is false, this should be between 0 and 127;
    #   otherwise it should be between 0 and 1.
    # @param taper_final_tie [Boolean] If false, steps in the final slot of the
    #   track will *not* have their velocity adjusted if they are ties and are
    #   continued with a step with the same note in the first slot of the track.
    # @param taper_single [Boolean] If true, standalone steps that are not
    #   continuations of a tie also have their velocity adjusted.
    # @param zero_to_one [Boolean] Defines the range of `trailing_vel`; see
    #   above.
    # @return [Track]
    # @see #vel
    # @see #vel_curve
    # @see #taper_gate
    def taper_vel(trailing_vel = 64, taper_final_tie: false, taper_single: false, zero_to_one: false)
      trailing_vel *= 127 if zero_to_one
      taper_steps(taper_final_tie: taper_final_tie, taper_single: taper_single) { |s| s.with_vel(trailing_vel) }
    end

    # An alias for {#taper_vel} with `zero_to_one` set to true. See that method
    # for details.
    # @param trailing_vel [Number] The velocity to apply to the final step in a
    #   run, as a value between 0 and 1.
    # @param taper_final_tie [Boolean] If false, steps in the final slot of the
    #   track will *not* have their velocity adjusted if they are ties and are
    #   continued with a step with the same note in the first slot of the track.
    # @param taper_single [Boolean] If true, standalone steps that are not
    #   continuations of a tie also have their velocity adjusted.
    # @return [Track]
    # @see #taper_vel
    def taper_velf(trailing_vel = 0.5, taper_final_tie: false, taper_single: false)
      taper_vel(trailing_vel, taper_final_tie: taper_final_tie, taper_single: taper_single, zero_to_one: true)
    end


    ## @!group Partitioning and filtering steps

    # Returns two Tracks by extracting steps that match the given note. Matches
    # are evaluated with {Theory::MIDINote#match?}. The first returned track
    # contains the matching steps, and the second contains the non-matching
    # ones.
    #
    # @example
    #   t = T[[:c1, :c2], :d2, :e2, :f2]
    #   u, v = t.partition_notes(:c)
    #   # u is equivalent to
    #   T[[:c1, :c2], :r, :r, :r]
    #   # and v is
    #   T[:r, :d2, :e2, :f2]
    #
    # @param note [Theory::MIDINote, String, Symbol, Integer] The note or pitch
    #   class to match. See {Theory::MIDINote#match?} for precise rules.
    # @return {Array(Track, Track)}
    # @see Theory::MIDINote#match?
    # @see #partition
    # @see #filter_notes
    def partition_notes(note)
      partition { |step| step.note.match?(note) }
    end
    alias partition_note partition_notes

    # Returns a new track containing only steps that match the given note. The
    # new track will have the same length as this one, but will only contain
    # steps that match. Matches are evaluated with {Theory::MIDINote#match?}.
    #
    # The result is equivalent to the first track returned by
    # {#partition_notes}. The complement of this function is {#reject_notes}.
    #
    # @param (see #partition_notes)
    # @return [Track]
    # @see #partition_notes
    # @see #reject_notes
    # @see #select_steps
    def select_notes(note)
      t, = partition_note(note)
      t
    end
    alias select_note select_notes
    alias filter_notes select_notes
    alias filter_note select_notes

    # Returns a new track containing only steps that do not match the given
    # note. The new track will have the same length as this one, but will only
    # contain steps that do not match. Matches are evaluated with
    # {Theory::MIDINote#match?}.
    #
    # The result is equivalent to the second track returned by
    # {#partition_notes}. The complement of this function is {#select_notes}.
    #
    # @param (see #partition_notes)
    # @return [Track]
    # @see #partition_notes
    # @see #select_notes
    # @see #reject_steps
    def reject_notes(note)
      _, t = partition_note(note)
      t
    end
    alias reject_note reject_notes
    alias drop_notes reject_notes
    alias drop_note reject_notes

    ## @!group Mutating steps

    # Returns a new Track where each step with a matching {Step#note note} is
    # replaced with a step that has note `repl` but is otherwise identical.
    #
    # If `target` is a {Theory::MIDINote}, number, or symbol or string with an
    # octave, only steps with that exact note are effected. If it is a symbol or
    # string without an explicit octave (e.g. `:c`), all steps with that pitch
    # class are effected.
    #
    # If `repl` is a symbol or string without an octave, targeted steps' notes
    # will be in the same octave as the original step but with the pitch class
    # of `repl`. If `repl` is a {Theory::MIDINote}, number, or symbol or string
    # with an octave, it exactly defines the new note for targeted steps.
    #
    # `repl` may be nil, :r, or :rest to remove the targeted steps.
    #
    # @example
    #   t = T[:c4, [:d1, :d2], :c3]
    #
    #   u = t.sub_note(:d2, :f9)
    #   # u is equivalent to
    #   T[:c4, [:d1, :f9], :c3]
    #
    #   v = t.sub_note(:d, :f9)  # changes all Ds
    #   # v is equivalent to
    #   T[:c4, [:f9, :f9], :c3]
    #
    #   w = t.sub_note(:d, :f)  # changes all Ds, but leaves octaves intact
    #   # w is equivalent to
    #   T[:c4, [:f1, :f2], :c3]
    #
    #   x = t.sub_note(:c, :r)  # removes all Cs
    #   # x is equivalent to
    #   T[:r, [:d1, :d2], :r]
    #
    # @param target [Theory::MIDINote, Symbol, String, Integer] Defines the
    #   notes to target; see above.
    # @param repl [Theory::MIDINote, Symbol, String, Integer, nil, :r, :rest]
    #   Defines the replacement note in targeted steps, or a rest value to
    #   remove them; see above.
    # @return [Track]
    def sub_note(target, repl)
      orig_has_octave = Theory::MIDINote.has_octave?(target)
      repl_is_rest = Theory.rest?(repl)
      repl_has_octave = repl_is_rest ? false : Theory::MIDINote.has_octave?(repl)

      target = Theory::MIDINote.new(target)

      mutate_each_step do |step|
        if (orig_has_octave && step.note == target) || (!orig_has_octave && step.note.pitch_class == target.pitch_class)
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
    alias replace_note sub_note
    alias replace sub_note

    # Returns a new Track, applying controlled random mutations to each step.
    # The probability that any given mutation will apply to a Step is given by
    # the `p` parameter. Any given step may have 0 or more independent mutations
    # applied to it.
    #
    # Possible changes:
    # - A transposition. The `tone_shifts` array (which may be nil) provides the
    #   possible semitone offsets that may be applied to a Step; a random value
    #   from it will be chosen if a transposition is to be applied. The
    #   `octave_limit` range describes the valid octaves in which a
    #   transposition can result. If the transposition moves a note outside of
    #   `octave_limit`, the note's octave is clamped to the closest extreme of
    #   `octave_limit`.
    # - A {Step#gate gate} shift. The `gate_delta` float provides the maximum
    #   shift to apply to a step; a random value between 0 and `gate_delta` will
    #   be chosen if a gate shift is to be applied. The `gate_limit` range
    #   restricts the resulting gate value in the same way `octave_limit`
    #   restricts transpositions.
    # - A velocity shift, controlled by `velf_delta` and `velf_limit` in the
    #   same way as a gate shift.
    #
    # @param tone_shifts [Array<Integer>, nil] The possible semitone shifts to
    #   apply to steps, or nil to not transpose notes.
    # @param octave_limit [Range] The range of allowed octaves in the new track;
    #   see above.
    # @param gate_delta [Range, Number] The maximum amount to shift steps'
    #   gates. If this is a number, the range `-gate_delta..gate_delta` is used.
    # @param gate_limit [Range] The range of allowed gates in the new track; see
    #   above.
    # @param velf_delta [Range, Number] The maximum amount to shift steps'
    #   velocities, as a value between 0 and 1. If this is a number, the range
    #   `-velf_delta..velf_delta` is used.
    # @param velf_limit [Range] The range of allowed velocities in the new
    #   track; see above.
    # @param p [Number] The probability that a mutation of any sort will apply
    #   to a step, 0 - 1.
    # @return [Track]
    def evolve(tone_shifts: [-12, 12], octave_limit: 1..6, gate_delta: 0.5, gate_limit: 0.1..1, velf_delta: 0, velf_limit: 0.1..1, p: 0.25)
      gate_delta = -gate_delta..gate_delta unless gate_delta.is_a?(Range)
      velf_delta = -velf_delta..velf_delta unless velf_delta.is_a?(Range)
      tone_shifts = [0] if tone_shifts == 0 || tone_shifts.nil?

      mutate_each_step do |step|
        tone_shift = Internal::Random.chance(p) ? tone_shifts.sample : 0
        gate_shift = Internal::Random.chance(p) ? Internal::Random.rand_f(gate_delta) : 0
        velf_shift = Internal::Random.chance(p) ? Internal::Random.rand_f(velf_delta) : 0

        if tone_shift != 0
          step = step.transpose(tone_shift)

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


    ### @!group CCTrack mapping

    # Return a new {CCTrack} based on the slots of this track.
    #
    # The block will be called with each slot in the {#grid grid} in order. Its
    # return determines the steps in the corresponding slot in a new CCTrack.
    #
    # @example
    #   t = T[:a1, :c2, :c3]
    #   cct = t.to_cc do |slot, slot_idx|
    #     next :r if slot.empty?
    #     slot.first.note.pitch_class == :c ? CC(127, 10 * slot_idx) : nil
    #   end
    #   # cct is equivalent to
    #   CCT[:r, CC(127, 10), CC(127, 20)]
    #
    # @yieldparam slot [Array<Step>] A slot in this track.
    # @yieldparam slot_idx [Integer] (optional) The index of the slot in this
    #   track's grid.
    # @yieldparam percent [Number] The percent through the Track that the slot
    #   represents. For instance, the first slot of the track will have percent
    #   0, the middle slot (in a Track with an odd number of slots) will have
    #   percent 0.5, and the final slot will have percent 1.0.
    # @yieldreturn [CCStep, Array<CCStep>, Array<Array<CCStep>>, nil, :r, :rest]
    #   The contents for the slot(s) in the new {CCTrack}. It may be:
    #   - A single {CCStep} which will be converted to a single-step slot in the
    #     result.
    #   - A slot (an array of {CCStep}s).
    #   - nil, :r, or :rest, which will result in an empty slot (i.e. a rest) in
    #     the result.
    #   - An array of slots, which will all be added to the result in order.
    # @return [CCTrack]
    # @see CCTrack
    # @see CCStep
    # @see #to_simple_cc
    def to_cc(&block)
      raise ArgumentError, "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

      new_grid = []
      @grid.each_with_index do |slot, i|
        if i == 0
          pct = 0.0
        elsif i == @grid.length - 1
          pct = 1.0
        else
          pct = i.to_f / (num_slots - 1)
        end

        replacement = Internal::Utils.call_varargs(block, slot, i, pct)

        # The block may return something convertible to a slot (a CCStep), or a
        # 1d array (which we will take as a slot), or an array that contains
        # some number of other arrays (which we will take as a set of slots).
        # This behavior is in keeping with mutate_slots.
        replacement = if Internal::Enumerables.enumerable?(replacement)
          Internal::Enumerables.arrayify(replacement)  # see note in enumerable?
        else
          [replacement]
        end
        is_gridish = replacement.any? { |e| Internal::Enumerables.enumerable?(e) }

        if is_gridish
          new_grid += CCTrack.gridify(replacement)
        else
          new_grid << replacement  # This will get slotified by the initializer.
        end
      end

      CCTrack.new(*new_grid, granularity: @granularity, timescale: @timescale)
    end
    alias cc to_cc

    # Return a new {CCTrack}, whose steps all share a CC {CCStep#number number},
    # by processing the slots of this track.
    #
    # The block will be called with each slot in the {#grid grid} in order. Its
    # return determines the value for the {CCStep}s in the corresponding slots
    # in a new CCTrack.
    #
    # @example
    #   t = T[:a1, :r, :b1, :c1, :r]
    #   cct = t.to_simple_cc(127) do |slot, _, pct|
    #     next :r if slot.empty?
    #     127 * pct
    #   end
    #   # cct is equivalent to
    #   CCT[CC(127, 0), :r, CC(127, 63), CC(127, 95), :r]
    #
    # @yieldparam slot [Array<Step>] A slot in this track.
    # @yieldparam slot_idx [Integer] (optional) The index of the slot in this
    #   track's grid.
    # @yieldparam percent [Number] The percent through the Track that the slot
    #   represents. For instance, the first slot of the track will have percent
    #   0, the middle slot (in a Track with an odd number of slots) will have
    #   percent 0.5, and the final slot will have percent 1.0.
    # @yieldreturn [Integer, Array<Integer>, nil, :r, :rest]
    #   The contents for the slot(s) in the new {CCTrack}. It may be:
    #   - A single number which will be used together with `cc_number` to make a
    #     one-step slot with a corresponding CCStep.
    #   - An array of numbers, each of which will be converted as above and
    #     added as individual slots in the result.
    #   - nil, :r, or :rest, which will result in an empty slot (i.e. a rest) in
    #     the result.
    # @return [CCTrack]
    # @see CCTrack
    # @see CCStep
    # @see #to_cc
    def to_simple_cc(cc_number, &block)
      raise ArgumentError, "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

      slots = []
      @grid.each_with_index do |slot, i|
        if i == 0
          pct = 0.0
        elsif i == @grid.length - 1
          pct = 1.0
        else
          pct = i.to_f / (num_slots - 1)
        end

        replacement = Internal::Utils.call_varargs(block, slot, i, pct)

        # The block may return a scalar (which we take as a CC value), or an
        # array (which we will take as a definition for a set of slots).
        if Internal::Enumerables.enumerable?(replacement)
          replacement = Internal::Enumerables.arrayify(replacement)  # see note in enumerable?
          if replacement.empty?
            slots << :r
          else
            slots += replacement
          end
        else
          slots << replacement
        end
      end

      CCTrack.simple(cc_number, slots, granularity: @granularity, timescale: @timescale)
    end
    alias simple_cc to_simple_cc

    # @!endgroup


    ### Track construction helpers

    private_class_method def self.step_class
      Step
    end

    # Attempts to convert its non-Step argument to a Step. Possible note-like
    # things (symbols, strings, numbers and MIDINote instances) are converted to
    # Steps using that value as the note and the default values for the other
    # arguments of Step's initializer.
    private_class_method def self.stepify(x)
      case x
      when Symbol, String, Numeric, Theory::MIDINote
        begin
          Step.new(x)
        rescue StandardError
          # Don't want to raise; TrackBase#slotify wants nil on failure
        end
      end
    end

    private_class_method def self.preferred_step(step1, step2)
      # If two steps in a slot share a note, prefer the step with a longer gate.
      (step1.gate >= step2.gate) ? step1 : step2
    end


    protected

    def ctor_kwargs
      kwargs = super
      kwargs[:scale] = nil
      kwargs
    end

    def repr_ctor_method
      "T"
    end
  end


  # @!group Class aliases

  # An alias for the {Track} class. You can easily make a new instance using the
  # {Track.initialize []} method, like `T[:c4, :d4]`.
  T = Track

  # @!endgroup


  # @!group Steps and tracks

  # An alias for {TrackBase.from_grid Track.from_grid}.
  # @return [Track]
  # @see Track#initialize
  module_function module_function def Tg(*args, **kwargs)
    Track.from_grid(*args, **kwargs)
  end

  # @!endgroup
end; end
