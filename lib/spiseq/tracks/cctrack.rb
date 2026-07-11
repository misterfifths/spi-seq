# frozen_string_literal: true

require_relative "ccstep"
require_relative "trackbase"
require_relative "../internal/enumerables"
require_relative "../internal/log"
require_relative "../theory/notelength"
require_relative "../theory/rest"

module SpiSeq; module Tracks
  # A CCTrack deals with a grid whose slots contain {CCStep}s. CCStep instances
  # represent MIDI CC events, consisting of a {CCStep#number CC number} and a
  # {CCStep#value value}. When a CCTrack is played with a {CCPlayer} or a
  # {Playback.track_live_loop}, MIDI CC messages are sent corresponding to the
  # steps.
  #
  # This class is aliased to `CCT`.
  #
  # **Tracks are immutable**. The mutation methods provided here, like
  # {#add_curve}, return new CCTracks that have all the same attributes as the
  # receiver (e.g. {#timescale} and {#granularity}), with just the described
  # change. That includes the steps in its grid, unless the method explicitly
  # modifies those.
  #
  # This class inherits much of its functionality from {TrackBase}. See its
  # documentation for the basics of the grid, slots, and mutation methods.
  class CCTrack < TrackBase
    ### Initializers

    # Constructs a CCTrack with the given grid and attributes. `gridish` will be
    # converted into a proper grid, an array of "slots". A slot is itself an
    # array of {CCStep}s, which all trigger simultaneously for a duration of the
    # `granularity`. A slot may be empty to represent a rest.
    #
    # CCTrack itself is aliased to `CCT`, and `CCTrack.new` is aliased to `[]`,
    # so you can instantiate a CCTrack with `CCT[...]`.
    #
    # The positional arguments may be some mix of:
    # - "Stepish" values: a {CCStep} or a rest (nil, `:r`, `:rest`). Such values
    #   will be converted to a single slot containing that step (or a rest). For
    #   example:
    #     CCT[CC(127, 5)]  # grid is [[CC(127, 5)]]
    #     CCT[CC(127, 5), CC(127, 20)]  # grid is [[CC(127, 5)], [CC(127, 20)]]
    #     CCT[CC(127, 5), :r]  # grid is [[CC(127, 5)], []]
    #     CCT[:r]  # grid is [[]]
    # - Arrays of "stepish" values. These are used as the contents of a slot;
    #   the values in an array will be grouped together into a slot in the
    #   track. For example:
    #     CCT[[CC(127, 10), CC(5, 6)], :r, CC(127, 5)]
    #     # grid is [ [CC(127, 10), CC(5, 6)], [], [CC(127, 5)] ]
    #
    # In the end, the grid conversion should be relatively natural. Non-array
    # values will get their own slot, and values grouped into an array will
    # share a slot.
    #
    # Tracks must have at least one slot, though that slot may be empty (a
    # rest). So, `CCT[]` with no arguments is an error.
    #
    # A single slot cannot contain more than one step with the same
    # {CCStep#number number}. If that would happen, the step with the highest
    # {CCStep#value value} is chosen, and the other colliding steps are
    # discarded.
    #
    # @param gridish [Array<CCStep>, CCStep, nil, :r, :rest>] Defines the grid
    #   for the new track; see above.
    # @param granularity [Theory::NoteLength, Number, Symbol] The {#granularity}
    #   for the new track. Can be a {Theory::NoteLength} or a value understood
    #   by {Theory::NoteLength.new}.
    # @param timescale [Number] The {#timescale} for the new track.
    def initialize(*gridish, granularity: :eighth, timescale: 1)
      # Overridden purely to provide documentation.
      super
    end

    # Creates a new CCTrack where all steps target one CC number, `cc_number`.
    #
    # `slots` is an array which specifies how to construct the {CCStep}s in the
    # resulting track; each element of `slots` will correspond to a step in its
    # own slot. Each element of `slots` can be:
    # - An integer, which is used as the {CCStep#value value} in a {CCStep} with
    #   {CCStep#number number} `cc_number`.
    # - A {CCStep} instance, which will be passed through verbatim.
    # - A rest (see {Theory.rest?}), which will result in an empty slot.
    #
    # @example
    #   CCTrack.simple(56, [1, 2, :r, CC(100, 5), 3])
    #   # is equivalent to
    #   CCTrack.new([CC(56, 1), CC(56, 2), :r, CC(100, 5), CC(56, 3)])
    #
    # @param cc_number [Integer] The CC number that all slots in the resulting
    #   track will target.
    # @param slots [Array<Integer, CCStep, Symbol, nil>] Defines the contents
    #   of the slots in the resulting track. See above.
    # @param granularity [Theory::NoteLength, Number, Symbol] The {#granularity
    #   granularity} for the new track.
    # @param timescale [Number] The {#timescale timescale} for the new track.
    # @return [CCTrack]
    def self.simple(cc_number, slots, granularity: :eighth, timescale: 1)
      slots = slots.map do |slot|
        next :r if Theory.rest?(slot)

        case slot
        when CCStep
          slot
        when Numeric
          CCStep.new(cc_number, slot)
        else
          raise TypeError, "slots must be numbers, CCSteps, or rests"
        end
      end

      new(*slots, granularity:, timescale:)
    end

    # Creates a track containing {CCStep}s for the given number whose value
    # varies along a curve.
    #
    # This is a helper that makes a new track and adds steps to it using
    # {#add_curve}.
    #
    # @example
    #   CCTrack.curve(127, 50, 80, Curves::UpLinear, 8)
    #   # is equivalent to
    #   CCT[CC(127, 50), CC(127, 54), CC(127, 58), CC(127, 62),
    #       CC(127, 67), CC(127, 71), CC(127, 75), CC(127, 80)]
    #
    # @param cc_number [Integer] The {CCStep#number number} for the new CCSteps.
    # @param start_val [Integer] The starting {CCStep#value value} for the new
    #   steps. This can be greater than `end_val` if the values should decrease
    #   over time.
    # @param end_val [Integer] The ending {CCStep#value value} for the new
    #   steps. This can be less than `start_val` if the values should decrease
    #   over time.
    # @param curve [#call] A lambda or proc that defines the curve. It will be
    #   called with a single floating point value between 0 - 1 (the percent
    #   through the curve) and should return a value between 0 - 1. For this
    #   function to act as expected, it should return 0 for an input of 0, and 1
    #   for an input of 1. See the {Curves} and {Easings} modules for a number
    #   of prebuilt options.
    # @param length [Integer] The length of the new track. Steps along the curve
    #   will be added to every step in the track.
    # @return [CCTrack]
    # @see Curves
    # @see Easings
    # @see #add_curve
    def self.curve(cc_number, start_val, end_val, curve, length)
      t = CCTrack.rest(length)
      t.add_curve(cc_number, start_val, end_val, curve, 0, length - 1)
    end


    ### Mutators

    # Returns a new track, adding {CCStep}s whose value varies along a curve.
    #
    # @example
    #   t = CCTrack.rest(8)
    #   t = t.add_curve(10, 0, 50, Curves::UpLinear, 1, 6)
    #   # t is now equivalent to
    #   CCTrack.new([:r, CC(10, 0), CC(10, 10), CC(10, 20),
    #                CC(10, 30), CC(10, 40), CC(10, 50), :r])
    #
    # @param cc_number [Integer] The {CCStep#number number} for the new CCSteps.
    # @param start_val [Integer] The starting {CCStep#value value} for the new
    #   steps. This can be greater than `end_val` if the values should decrease
    #   over time.
    # @param end_val [Integer] The ending {CCStep#value value} for the new steps.
    #   This can be less than `start_val` if the values should decrease over
    #   time.
    # @param curve [#call] A lambda or proc that defines the curve. It will be
    #   called with a single floating point value between 0 - 1 (the percent
    #   through the curve) and should return a value between 0 - 1. For this
    #   function to act as expected, it should return 0 for an input of 0, and 1
    #   for an input of 1. See the {Curves} and {Easings} modules for a number
    #   of prebuilt options.
    # @param slot_start_idx [Integer] The index of the first slot where a step
    #   will be added. This must be a valid index for the track's {#grid grid},
    #   and must be < `slot_end_idx`.
    # @param slot_end_idx [Integer] The index of the final slot where a step
    #   will be added. This must be a valid index for the track's {#grid grid},
    #   and must be > `slot_start_idx`.
    # @return [CCTrack]
    # @see Curves
    # @see Easings
    # @see .curve
    def add_curve(cc_number, start_val, end_val, curve, slot_start_idx, slot_end_idx)
      raise IndexError, "slot start is >= slot end" if slot_start_idx >= slot_end_idx
      raise IndexError, "slot range is beyond the grid" if slot_start_idx < 0 || slot_end_idx >= @grid.length

      new_grid = mutable_grid_dup

      (slot_start_idx..slot_end_idx).each do |i|
        pct = if i == slot_start_idx
          0.0
        elsif i == slot_end_idx
          1.0
        else
          (i - slot_start_idx).to_f / (slot_end_idx - slot_start_idx)
        end

        val = start_val + curve.call(pct) * (end_val - start_val)
        new_grid[i] << CCStep.new(cc_number, val)
      end

      mutate(grid: new_grid)
    end


    ### Track construction helpers

    private_class_method def self.step_class = CCStep

    private_class_method def self.preferred_step(step1, step2)
      # If two steps in a slot share a CC number, prefer the step with a higher
      # value.
      (step1.value >= step2.value) ? step1 : step2
    end


    private

    def repr_ctor_method = "CCT"
  end


  # @!group Class aliases

  # An alias for the {CCTrack} class. You can easily make a new instance using
  # the {CCTrack.initialize []} method, like `CCT[CC(127, 64), CC(127, 0)]`.
  CCT = CCTrack

  # @!endgroup


  # @!group Steps and tracks

  # An alias for {TrackBase.from_grid CCTrack.from_grid}.
  # @return [CCTrack]
  # @see CCTrack#initialize
  module_function def CCTg(...) = CCTrack.from_grid(...)

  # @!endgroup
end; end
