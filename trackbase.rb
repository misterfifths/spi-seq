# frozen_string_literal: true

require_relative "extapi"
require_relative "prob"
require_relative "step"
require_relative "theory/euclid"
require_relative "theory/notelength"

# @!group Steps and tracks

# Set global track-related behaviors.
# @param strict_track_merging [Boolean] If true, tracks with mismatched
#   {TrackBase#granularity granularities}, {TrackBase#timescale timescales},
#   or (for {Track}s) {Track#scale scales} cannot interact with one another.
#   That is, an exception will be raised if you attempt to {TrackBase#merge
#   merge}, {TrackBase#append join}, {TrackBase#zip zip}, or otherwise commingle
#   such tracks. If false, generally speaking, the track on which a method is
#   called is the one that will determine the attributes of the result. E.g., in
#   `t1.zip(t2)`, the result will have the granularity, timescale, and (if these
#   are Tracks) scale of `t1`. Strict track merging is off by default.
# @return [void]
# @see current_track_defaults
def use_track_defaults(strict_track_merging:)
  ExtApi.set(:__track_defaults, { strict_track_merging: strict_track_merging })
end

# Returns the current track defaults as set by {use_track_defaults}, or an
# empty hash if no defaults have been set.
# @return [Hash{Symbol => Object}]
def current_track_defaults
  ExtApi.get(:__track_defaults) || {}
end

# @!endgroup


# TrackBase represents an abstract "grid" of steps. Do not make instances of
# TrackBase directly; instead use one of its subclasses that specialize for the
# type of step, like {Track} or {CCTrack}.
#
# A track's {#grid} is a 2d array, each element of which is a "slot". A slot
# contains 0 or more steps. A step represents some sort of event (a MIDI note,
# in the case of {Step}, for example) that will trigger when that slot is
# played. During playback, all the steps in a slot will trigger simultaneously.
# The order of steps within a slot is not significant.
#
# Each slot lasts for a timespan equal to the track's {#granularity}, which is
# some fraction of a beat (e.g. 1/4 for sixteenth note granularity). An empty
# slot represents a rest of the same duration. Thus the length of a track in
# beats is the granularity multiplied by the number of slots in the grid.
#
# Tracks also have a {#timescale}, which is the speed at which the track will
# play relative to the current Sonic Pi BPM. A timescale of 2 means that the
# track will play at twice the BPM, e.g., and 0.5 means half-speed.
#
# Subclasses of TrackBase deal with different types of steps. For example, the
# {Track} class has slots that contain {Step}s, which represent MIDI notes and
# their related properties (e.g. {Step#gate gate} and {Step#vel velocity}).
# The TrackBase class contains functionality that is agnostic to the type of
# steps in the grid. The subclasses add behavior specific to the steps they
# contain.
#
# Note that **tracks are immutable**. The provided mutation methods make the
# described changes and return new tracks that are otherwise identical to the
# track on which they were called. For example, {#with_timescale} returns a new
# track that only differs from the track on which was called in its
# {#timescale}; its {#grid}, {#granularity}, and other properties are unchanged.
# Many methods do change the grid, like {#concat}, but unless otherwise stated
# they will leave `timescale`, `granularity`, and all other properties alone.
#
# Methods in this class that are documented as returning TrackBase instances
# will actually return an instance of whatever class they are called on; e.g.
# `Track.new(:c4).left_pad(3)` will return a {Track}. Likewise, anything
# documented as having type {StepBase} will actually be the type of step
# belonging to the track subclass you're using.
#
# Most of the examples below use {Track}s, but all of the methods on this class
# are also available for use with {CCTrack}s.
#
# @abstract Subclasses of TrackBase must provide the following methods:
#   - `gridify`, `slotify`, `stepify` - class methods to convert values to
#     grids, slots, and steps.
#   - `ctor_kwargs` - optional, used to implement `mutate` and {#repr}, and to
#     test for track compatibility. Implement this if your subclass takes
#     additional keyword arguments to its initializer.
class TrackBase
  # The duration of slots in the track, represented as a fraction of a beat. For
  # instance, a granularity of {NoteLength::Eighth} means that each slot lasts
  # for half a beat.
  # @return [NoteLength]
  # @see #with_granularity
  # @see Track#condense
  # @see Track#expand
  # @see Track#regranularize
  attr_reader :granularity

  # The speed that this track will play relative to the BPM. A timescale of 2
  # means that this track will play at twice the BPM, e.g., and 0.5 means
  # half-speed.
  # @return [Number]
  # @see #with_timescale
  attr_reader :timescale

  # The track's grid - that is, its array of slots. Each slot is itself an array
  # of steps. The type of steps in the grid is determined by the TrackBase
  # subclass. {Track}s have grids containing slots with {Step}s, and {CCTrack}s
  # have {CCStep}s.
  #
  # The grid itself and all of the slot arrays within it are frozen.
  #
  # @return [Array<Array<StepBase>>]
  attr_reader :grid
  alias slots grid


  ### @!group Initializers

  # Constructs a track with the given grid and attributes. `gridish` will be
  # converted into a proper grid, an array of "slots". A slot is itself an
  # array of steps, which all trigger simultaneously for a duration of the
  # `granularity`. A slot may be empty to represent a rest.
  #
  # `gridish` is converted to a grid using rules specific to subclasses; see
  # those for details. In general, non-array arguments will be placed in a slot
  # by themselves, and arrays are used as a slot.
  #
  # Tracks must have at least one slot, though that slot may be empty (a rest).
  #
  # @param gridish [Array<StepBase>, StepBase, nil, :r, :rest] (and other types
  #   on a per-subclass basis) Defines the grid for the track; see subclass
  #   initializers for details.
  # @param granularity [NoteLength, Number, Symbol] The {#granularity} for the
  #   new track. Can be a {NoteLength} or a value understood by
  #   {NoteLength.new}.
  # @param timescale [Number] The {#timescale} for the new track.
  def initialize(*gridish, granularity: NoteLength::Eighth, timescale: 1)
    @grid = self.class.gridify(gridish)
    raise ArgumentError, "A Track's grid must have at least one slot" if @grid.empty?
    @granularity = NoteLength.new(granularity)

    raise RangeError, "Timescale must be a number greater than 0" unless timescale.is_a?(Numeric) && timescale > 0
    @timescale = timescale
  end

  class << self
    alias [] new
  end

  # Constructs a track with the given grid and attributes. This is equivalent
  # to {#initialize} except that the grid definition `gridish` is passed as an
  # array rather than `*args`. That makes it easier to do things like this:
  #   Track.from_grid([:a1, :b2] + [:c4] * 5)
  #   # equivalent to
  #   T[:a1, :b1, :c4, :c4, :c4, :c4, :c4]
  #
  # The equivalent initializer call is a little awkward:
  #   T[:a1, :b2, *[:c4] * 5]
  #
  # This method also accepts single step values:
  #   Track.from_grid(:c4)
  #   # is equivalent to
  #   T[:c4]
  #
  # @param gridish [Array<Array<StepBase>, StepBase, nil, :r, :rest>,
  #   Array<StepBase>, StepBase, nil, :r, :rest] (and other types on a per-
  #   subclass basis) Defines the grid for the track. If this is an array, it
  #   is passed a splat to {#initialize}. If it is a single element it is passed
  #   as such to the initializer. See subclass initializers for acceptable
  #   values and conversion rules.
  # @param granularity [NoteLength, Number, Symbol] The {#granularity} for the
  #   new track. Can be a {NoteLength} or a value understood by
  #   {NoteLength.new}.
  # @param timescale [Number] The {#timescale} for the new track.
  # @return [TrackBase]
  # @see #initialize
  def self.from_grid(gridish, granularity: NoteLength::Eighth, timescale: 1)
    if ExtApi.enumerable?(gridish) && !gridish.empty?
      new(*gridish, granularity: granularity, timescale: timescale)
    else
      new(gridish, granularity: granularity, timescale: timescale)
    end
  end

  # Constructs a track with the given number of slots, each of which is empty
  # (i.e. a rest).
  # @param num_slots [Integer] The length of the new track in slots.
  # @param granularity [NoteLength, Number, Symbol] The {#granularity} for the
  #   new track. Can be a {NoteLength} or a value understood by
  #   {NoteLength.new}.
  # @param timescale [Number] The {#timescale} for the new track.
  # @return [TrackBase]
  def self.rest(num_slots = 1, granularity: NoteLength::Eighth, timescale: 1)
    grid = [[]] * num_slots
    new(*grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a track that plays the slots of `gridish` in a Euclidean rhythm.
  # The length of the rhythm is `length`, and the number of hits to play over
  # that length is `pulses`. `gridish` specifies a grid and is handled in the
  # same manner as a `gridish` passed to {#initialize}.
  #
  # Unless `full_cycle` is true (see below), the returned track will have the
  # given length. The `cycle` parameter controls how gridish is used when
  # placing slots in the track. If it is true, each time there is a hit in the
  # rhythm, the next slot from `gridish` is used (wrapping around if needed).
  # But if `cycle` is false, when there is a hit in the rhythm, the note at the
  # corresponding index of that hit in `gridish` is used (wrapping around as
  # needed). For example:
  #   Track.euclid([:c3, :d3], 3, 4)
  #   # is equivalent to
  #   T[:c3, :r, :d3, :c4]
  #
  #   Track.euclid([:c3, :d3, :e3], 3, 4, cycle: false)
  #   # is equivalent to
  #   T[:c3, :r, :e3, :c3]
  #   # The final two slots contain :e3 and :c3 because those are the
  #   # corresponding notes at those slot indices in `gridish` passed to euclid
  #   # (modulo its length).
  #
  # If `full_cycle` is true, the returned track will repeat the Euclidean
  # pattern (while cycling through `gridish`) however many times is needed to
  # ensure that all the slots are played and that the track loops cleanly.
  # `full_cycle` implies `cycle`. For instance:
  #   Track.euclid([:a1, :b1, :c1, :d1], 3, 4, full_cycle: true)
  #   # is equivalent to
  #   T[:a1, :r, :b1, :c1,
  #     :d1, :r, :a1, :b1,
  #     :c1, :r, :d1, :a1,
  #     :b1, :r, :c1, :d1]
  #
  # Note that each group of 4 slots in the result repeats the same pattern of
  # hits (hit rest hit hit), but the steps chosen from the input cycle across
  # repetitions, so that every given slot in `gridish` is played and the overall
  # track is a perfect loop.
  #
  # @param gridish [StepBase, Array<StepBase, Array<StepBase>>] (or other
  #   subclass-specific types) Defines the the slots to cycle through according
  #   to the rhythm. See the sublass initializer for potential values.
  # @param pulses [Integer] The number of hits in the Euclidean rhythm.
  # @param length [Integer] The length of the Euclidean rhythm.
  # @param invert [Boolean] If true, the hit pattern in the rhythm is inverted;
  #   slots that would have been rests will now be filled and vice-versa.
  # @param rotate [Integer] Rotates the Euclidean rhythm leftward the given
  #   number of times before using it to construct the track.
  # @param cycle [Boolean] Controls how to step through the slots in `gridish`;
  #   see above.
  # @param full_cycle [Boolean] If true, the rhythm is repeated until all slots
  #   in `gridish` are used and the track loops cleanly. Implies `cycle`.
  # @param granularity [NoteLength, Number, Symbol] The {#granularity} for the
  #   new track. Can be a {NoteLength} or a value understood by
  #   {NoteLength.new}.
  # @param timescale [Number] The {#timescale} for the new track.
  # @return [TrackBase]
  # @see euclid
  def self.euclid(gridish, pulses, length, invert: false, rotate: 0, cycle: true, full_cycle: false, granularity: NoteLength::Eighth, timescale: 1)
    hits = Object.send(:euclid, pulses, length)
    # TODO: this is a different notion of rotation than that of ::euclid. Should
    # we standardize it?
    hits.rotate!(rotate) if rotate != 0
    hits.map! { |hit| !hit } if invert

    gridish = gridify(gridish)
    raise ArgumentError, "you must provide at least one slot" if gridish.empty?

    # Can't do a full cycle when there are no hits...
    full_cycle = false if pulses == 0

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

    new(*grid, granularity: granularity, timescale: timescale)
  end


  ### @!group Properties

  # The number of slots in the track; i.e., the length of the {#grid}.
  # @return [Integer]
  def num_slots
    @grid.length
  end

  alias length num_slots

  # The duration of the track in beats. That is, the length of the {#grid}
  # multiplied by the {#granularity}.
  # @return [Number]
  def beat_length
    num_slots * @granularity.to_f
  end

  # Returns whether the track consists entirely of rests (i.e., empty slots).
  # @return [Boolean]
  # @see #mono?
  # @see #poly?
  def empty?
    @grid.all? { |slot| slot.empty? }
  end

  alias all_rests? empty?
  alias rest? empty?

  # Returns whether the track is monophonic (i.e., all slots have <= 1 step).
  # @return [Boolean]
  # @see #poly?
  # @see #empty?
  def mono?
    @grid.all? { |slot| slot.length <= 1 }
  end

  # Returns whether the track is polyphonic (i.e., any slot has > 1 step).
  # @return [Boolean]
  # @see #mono?
  # @see #empty?
  def poly?
    @grid.any? { |slot| slot.length > 1 }
  end

  # Returns the indexes of all non-empty slots in the {#grid}.
  # @return [Array<Integer>]
  def indexes_of_filled_slots
    idxs = []
    @grid.each_with_index { |slot, i| idxs << i unless slot.empty? }
    idxs
  end

  # Returns the `n`th non-empty slot in the {#grid}.
  # @param n [Integer]
  # @return [Array<StepBase>]
  def nth_filled_slot(n)
    @grid[indexes_of_filled_slots[n]]
  end

  alias filled_slot nth_filled_slot


  ### @!group String representations

  # Returns a string representation of the track as Ruby code.
  # @param group [Integer, nil] The number of slots of the track to group
  #   together on a single line before adding a line break, or nil to keep all
  #   slots on the same line.
  # @return [String]
  # @see #inspect
  def repr(group: 8)
    ctor_invocation = "#{repr_ctor_method}["
    slot_line_indent = " " * ctor_invocation.length

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

    total_slot_repr = grouped_slot_reprs.map { |chunk| chunk.join(", ") }.join(",\n#{slot_line_indent}")

    ctor_args = {}
    ctor_kwargs.each do |kwarg, defval|
      raw_val = send(kwarg)
      next if raw_val == defval
      ctor_args[kwarg] = raw_val.respond_to?(:repr) ? raw_val.repr : raw_val.to_s
    end

    if ctor_args.empty?
      kwargs = ""
    else
      kwargs = ", " + ctor_args.map { |k, v| "#{k}: #{v}" }.join(", ")  # rubocop:disable Style/StringConcatenation
    end

    "#{ctor_invocation}#{total_slot_repr}#{kwargs}]"
  end

  # Copies the {#repr} of this track to the clipboard.
  # @param (see #repr)
  # @return [void]
  def copy_repr(group: 8)
    Clipboard.copy(repr(group: group))
  end

  # Returns a friendly string representation of the track.
  # @return [String]
  # @see #repr
  def inspect
    res = "#{self.class.name} slots=#{num_slots} granularity=#{granularity} timescale=#{timescale} grid:\n"
    @grid.each_with_index do |slot, i|
      res += "slot #{i} @ t=#{i * granularity.to_f}\n"
      slot.each { |step| res += "  #{step.repr}\n" }
    end
    res
  end


  ### Mutators

  ## @!group Attribute mutations

  # Returns a new track with the given {#granularity}. Does not effect the
  # timing of any steps, so the track's duration (in terms of beat length) will
  # change. To change the granularity of a {Track} while attempting to keep it
  # sounding roughly the same, use {Track#condense}, {Track#expand}, or
  # {Track#regranularize}.
  # @param granularity [NoteLength, Number, Symbol] The new track granularity.
  #   Can be a {NoteLength} or a value understood by {NoteLength.new}.
  # @return [TrackBase]
  def with_granularity(granularity)
    mutate(granularity: granularity)
  end

  # Returns a new track with the given {#timescale}.
  # @param scale [Number]
  # @return [TrackBase]
  def with_timescale(scale)
    mutate(timescale: scale)
  end

  alias with_rate with_timescale
  alias rate with_rate


  ## @!group Integrating with other tracks

  # Returns a new track with `other_track` appended to this one. If
  # `other_track` is not a track, it is converted to one using the initializer.
  #
  # @example
  #   T[:a1, :b2] + T[:c3, :r]
  #   # is equivalent to
  #   T[:a1, :b2, :c3, :r]
  #
  # @example
  #   T[:a1, :b2] + [:c4] * 4  # The array will be converted to a track
  #   # is equivalent to
  #   T[:a1, :b2, :c4, :c4, :c4, :c4]
  #
  # @param other_track [TrackBase, StepBase, Array<StepBase, Array<StepBase>>]
  #   The track to append, or a value that is convertible to a track. See the
  #   subclass initializer for details.
  # @return [TrackBase]
  # @see #append_slot
  def append(other_track)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)
    mutate(grid: @grid + other_track.grid)
  end

  alias concat append
  alias add append
  alias + append

  # Create a new track that merges the steps in corresponding slots of this
  # track and `other_track`. The length of the resulting track is the maximum
  # length of the two tracks. If `other_track` is not a track, it is converted
  # to a compatible one using the initializer.
  #
  # @example
  #   t = T[:c1, :r, :c3]
  #   u = T[:r, :c2, :c4, :c5]
  #   v = t | u
  #   # v is equivalent to
  #   T[:c1, :c2, [:c3, :c4], :c5]
  #
  # @param other_track [TrackBase, StepBase, Array<StepBase, Array<StepBase>>]
  #   The track to merge with this one, or a value that is convertible to a
  #   track. See the subclass initializer for details.
  # @return [TrackBase]
  # @see #append
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

  # Creates a new track that interleaves the slots of `other_track` with those
  # of this track. If `other_track` is not a track, it is converted to a
  # compatible one using the initializer.
  #
  # `cycle` and `pad_with_rests` control the behavior if `other_track` is
  # shorter than this track. If `cycle` is true (the default), the slots of
  # `other_track` will be looped as needed.
  #
  # If `cycle` is false, the behavior depends on `pad_with_rests`. If it is true
  # (the default), when `other_track`'s slots are exhausted, empty slots (rests)
  # are inserted in place of the missing slots. If it is false, the remaining
  # slots of this track appear consecutively once `other_track` is exhausted.
  # pad_with_rests is only relevant when cycle is false.
  #
  # @example
  #   t = T[:a1, :b1, :c1, :d1]
  #   u = T[:e5, :f5]
  #
  #   v = t.zip(u)
  #   # v is equivalent to
  #   T[:a1, :e5, :b1, :f5, :c1, :e5, :d1, :f5]
  #
  #   x = t.zip(u, cycle: false)
  #   # x is equivalent to
  #   T[:a1, :e5, :b1, :f5, :c1, :r, :d1, :r]
  #
  #   y = t.zip(u, cycle: false, pad_with_rests: false)
  #   # y is equivalent to
  #   T[:a1, :e5, :b1, :f5, :c1, :d1]
  #
  # @param other_track [TrackBase, StepBase, Array<StepBase, Array<StepBase>>]
  #   The track to zip with this one, or a value that is convertible to a track.
  #   See the subclass initializer for details.
  # @param cycle [Boolean] Controls the behavior when `other_track` is shorter
  #   than this one. See above.
  # @param pad_with_rests [Boolean] If `cycle` is false, controls the behavior
  #   when `other_track`'s slots are exhausted. See above.
  # @return [TrackBase]
  # @see #grouped_zip
  # @see #space
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

  # Creates a new track that inserts the slots of `other_track` after some
  # number of slots from this track. If `other_track` is not a track, it is
  # converted to a compatible one using the initializer.
  #
  # Unlike {#zip}, this function does not alternate between 1 slot of each
  # track. Instead, `group_size` many slots of this track appear consecutively,
  # followed by `other_group_size` slots of `other_track`, then `group_size`
  # many slots of this track, and so on.
  #
  # `cycle` controls the behavior when either track does not have enough
  # remaining slots to fill a group. If it is true, the group is filled by
  # returning to the beginning of the short track and using slots from there.
  # If it is true, when one track is exhausted, no more groups from it are
  # added to the resulting track.
  #
  # `pad_with_rests` only takes effect when `cycle` is false. If it is true,
  # when either track is exhausted, empty slots (rests) are added to the
  # resulting track in place of the missing slots.
  #
  # @example
  #   t = T[:a1, :b1, :c1, :d1]
  #   u = T[:e2, :f2]
  #
  #   v = t.gzip(u, 3, 1)
  #   # v is equivalent to
  #   T[:a1, :b1, :c1, :e2, :d1, :a1, :b1, :f2]
  #   # Note that when the slots in t were exhausted (after the :d1), the
  #   # remaining slots in that group came from wrapping around to the beginning
  #   # of the track - hence the :a1 and :b1.
  #
  #   w = t.gzip(u, 3, 1, cycle: false)
  #   # w is equivalent to
  #   T[:a1, :b1, :c1, :e2, :d1, :r, :r, :f2]
  #   # No wrap-around happened here, so the short group was filled with rests.
  #
  #   x = t.gzip(u, 3, 1, cycle: false, pad_with_rests: false)
  #   # x is equivalent to
  #   T[:a1, :b1, :c1, :e2, :d1, :f2]
  #   # Same as above, but the short group was not filled out with rests.
  #
  # @param other_track [TrackBase, StepBase, Array<StepBase, Array<StepBase>>]
  #   The track to zip with this one, or a value that is convertible to a track.
  #   See the subclass initializer for details.
  # @param group_size [Integer] The number of slots from this track that will
  #   appear before slots from `other_track`.
  # @param other_group_size [Integer] The number of slots from `other_track`
  #   that will appear after slots from this one.
  # @param cycle [Boolean] Controls the behavior when `other_track` is shorter
  #   than this one. See above.
  # @param pad_with_rests [Boolean] If `cycle` is false, controls the behavior
  #   when `other_track`'s slots are exhausted. See above.
  # @return [TrackBase]
  # @see #zip
  # @see #space
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


  ## @!group Managing rests

  # Returns a new track with all empty slots (rests) removed from this one.
  # Raises an exception if this would result in an empty track.
  # @return [TrackBase]
  # @see #ltrim
  # @see #rtrim
  # @see #trim
  def compact
    mutate(grid: @grid.reject { |slot| slot.empty? })
  end

  # Returns a new track with the same length as this one, but with all slots
  # cleared (i.e., rests).
  # @return [TrackBase]
  # @see .rest
  def clear
    mutate(grid: [[]] * @grid.length)
  end

  # Returns a new track with all empty slots (rests) removed from the beginning
  # of this track. Raises an exception if this would result in an empty track.
  # @return [TrackBase]
  # @see #compact
  # @see #rtrim
  # @see #trim
  # @see #lpad
  # @see #rpad
  def ltrim
    mutate(grid: @grid.drop_while { |slot| slot.empty? })
  end

  # Returns a new track with all empty slots (rests) removed from the end of
  # this track. Raises an exception if this would result in an empty track.
  # @return [TrackBase]
  # @see #compact
  # @see #ltrim
  # @see #trim
  # @see #lpad
  # @see #rpad
  def rtrim
    # We could obviously be more clever about this but I'm feeling lazy.
    new_grid = @grid.reverse.drop_while { |slot| slot.empty? }.reverse!
    mutate(grid: new_grid)
  end

  # Returns a new track with all empty slots (rests) removed from the beginning
  # and the end of this track. Raises an exception if this would result in an
  # empty track.
  # @return [TrackBase]
  # @see #compact
  # @see #ltrim
  # @see #rtrim
  # @see #lpad
  # @see #rpad
  def trim
    ltrim.rtrim
  end

  # Returns a new track by adding `num_rests` many empty slots (rests) to the
  # beginning of the track.
  # @param num_rests [Integer]
  # @return [TrackBase]
  # @see #rpad
  # @see #ltrim
  # @see #rtrim
  # @see #trim
  def left_pad(num_rests = 1)
    mutate(grid: [[]] * num_rests + @grid)
  end

  alias lpad left_pad

  # Returns a new track by adding `num_rests` many empty slots (rests) to the
  # end of the track.
  # @param num_rests [Integer]
  # @return [TrackBase]
  # @see #lpad
  # @see #rtrim
  # @see #ltrim
  # @see #trim
  def right_pad(num_rests = 1)
    mutate(grid: @grid + [[]] * num_rests)
  end

  alias rpad right_pad

  # Returns a new track by adding `num_rests` many empty slots (rests) after
  # each slot in this track.
  #
  # @example
  #   T[:a1, :b1, :c1].space(2)
  #   # is equivalent to
  #   T[:a1, :r, :r, :b1, :r, :r, :c1, :r, :r]
  #
  # @param num_rests [Integer]
  # @return [TrackBase]
  # @see #space_every
  def space(num_rests = 1)
    new_grid = []
    @grid.each do |slot|
      new_grid << slot
      new_grid.concat([[]] * num_rests)
    end

    mutate(grid: new_grid)
  end

  # Returns a new track by adding `num_rests` many empty slots (rests) between
  # each group of `group_size` slots from this track.
  #
  # @example
  #   T[:a1, :b1, :c1, :d1, :e1, :f1].space_every(3, 2)
  #   # is equivalent to
  #   T[:a1, :b1, :c1, :r, :r, :d1, :e1, :f1, :r, :r]
  #
  # @param group_size [Integer]
  # @param num_rests [Integer]
  # @return [TrackBase]
  # @see #space
  def space_every(group_size, num_rests = 1)
    new_grid = []
    @grid.each_slice(group_size) do |chunk|
      new_grid += chunk
      new_grid += [[]] * num_rests
    end

    mutate(grid: new_grid)
  end

  ## @!group Reordering slots

  # Returns a new track with the slots of this track in reverse order.
  #
  # @example
  #   T[[:a1, :a2], :b1, :r].reverse
  #   # is equivalent to
  #   T[:r, :b1, [:a1, :a2]]
  #
  # @return [TrackBase]
  # @see #mirror
  # @see #reflect
  def reverse
    mutate(grid: @grid.reverse)
  end

  alias rev reverse
  alias bw reverse

  # Returns a new track with the slots of this track in order and then reversed,
  # repeating the slot in the middle.
  #
  # @example
  #   T[:a1, :b1, :c1].mirror
  #   # is equivalent to
  #   T[:a1, :b1, :c1, :c1, :b1, :a1]
  #
  # @return [TrackBase]
  # @see #reverse
  # @see #reflect
  def mirror
    mutate(grid: @grid + @grid.reverse)
  end

  # Returns a new track with the slots of this track in order and then reversed,
  # without repeating the slot in the middle.
  #
  # @example
  #   T[:a1, :b1, :c1].reflect
  #   # is equivalent to
  #   T[:a1, :b1, :c1, :b1, :a1]
  #
  # @return [TrackBase]
  # @see #reverse
  # @see #mirror
  def reflect
    mutate(grid: @grid + @grid.reverse.drop(1))
  end

  alias bnf reflect

  # Returns a new track with the slots of this track in a random order.
  # @return [TrackBase]
  # @see #shuffle_filled_slots
  def shuffle
    mutate(grid: @grid.shuffle)
  end

  # Returns a new track by randomly swapping the filled slots in this track. Any
  # slots that were rests remain so; only the contents of filled slots is
  # effected.
  # @return [TrackBase]
  # @see #shuffle
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

  # Returns a new track with the slots in this track rotated to the left by the
  # given amount. The track duration is maintained; slots will be wrapped around
  # to the end of the grid as needed.
  #
  # @example
  #   T[:a1, :b1, :c1, :d1, :e1].rotate(2)
  #   # is equivalent to
  #   T[:c1, :d1, :e1, :a1, :b1]
  #
  # @param leftward_shift [Integer]
  # @return [TrackBase]
  # @see #shr
  def rotate(leftward_shift = 1)
    mutate(grid: @grid.rotate(leftward_shift))
  end

  alias left rotate
  alias lshift rotate
  alias shl rotate

  # Returns a new track with the slots in the grid rotated to the right by the
  # given amount. The track duration is maintained; slots will be wrapped around
  # to the end of the grid as needed.
  # @param rightward_shift [Integer]
  # @return [TrackBase]
  # @see #left
  def right(rightward_shift = 1)
    rotate(-rightward_shift)
  end

  alias rshift right
  alias shr right


  # @!group Mutating slots

  # Return a new track, replacing each slot in this track with the result of the
  # given block.
  #
  # The block may return:
  # - A single step or something convertible to one (as defined by the track
  #   subclass), which will be converted to a one-step slot and replace the slot
  #   yielded to the block.
  # - A slot (an array of steps), which will replace the slot yielded to the
  #   block.
  # - `nil`, `:r`, or `:rest`, which will replace the slot yielded to the block
  #   with an empty slot (i.e. a rest). Note that this is the same as returning
  #   an empty array.
  # - An array of slots, which will all be added in place of the yielded slot
  #
  # @example
  #   t = T[[:f8, :f9], :b2, [:f8, :f9]]
  #   u = t.mutate_each_slot { |slot| slot.length == 1 ? [:c4] : slot }
  #   # u is equivalent to
  #   T[[:f8, :f9], [:c4], [:f8, :f9]]
  #
  # @example
  #   t = T[[:a1, :a2], :b1, :r, :d1]
  #   u = t.mutate_each_slot { |slot, idx| idx > 1 ? slot : [:c4] }
  #   # u is equivalent to
  #   T[:c4, :c4, :r, :d1]
  #
  # @yieldparam slot [Array<StepBase>] The slot to mutate.
  # @yieldparam index [Integer] (optional) The index of the slot in the track.
  # @yieldparam percent [Number] (optional) The percent through the track that
  #   the slot falls. For instance, the first slot of the track will have
  #   percent 0, the middle slot (in a track with an odd number of slots) will
  #   have percent 0.5, and the final slot will have percent 1.0.
  # @yieldreturn [StepBase, Array<StepBase, Array<StepBase>>, nil, :r, :rest]
  #   (or other subclass-defined types) Determines the value to use in place of
  #   the slot in the resulting track; see above.
  # @return [TrackBase]
  # @see #mutate_each_step
  # @see #mutate_slot
  # @see #mutate_filled_slot
  def mutate_each_slot(&block)
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

      args = [slot, i, pct].take(block.arity)
      replacement = block.call(*args)

      # The block may return something convertible to a slot (step/note/etc.),
      # or a 1d array (which we will take as a slot), or an array that contains
      # some number of other arrays (which we will take as a set of slots). This
      # behavior is pretty odd. But, it's somewhat in keeping with set_slot, and
      # having the ability to expand one slot into multiple here is nice...
      replacement = [replacement] unless ExtApi.enumerable?(replacement)
      is_gridish = replacement.any? { |e| ExtApi.enumerable?(e) }

      if is_gridish
        new_grid += self.class.gridify(replacement)
      else
        new_grid << replacement  # This will get slotified by the initializer.
      end
    end
    mutate(grid: new_grid)
  end

  alias mutate_slots mutate_each_slot

  # Returns a new track with the steps in slot `idx` replaced with the given
  # steps.
  #
  # @example
  #   T[:a1, :b1, :r, :d1].replace_slot(2, [:c2, :c3])
  #   # is equivalent to
  #   T[:a1, :b1, [:c2, :c3], :d1]
  #
  # @param idx [Integer] The index of the slot to replace. Must be a valid index
  #   for the {#grid}.
  # @param new_steps [StepBase, Array<StepBase>, nil, :r, :rest] (or other types
  #   depending on the subclass) The new contents of the slot. May be an array
  #   of the subclass-appropriate step type (e.g. {Step} for {Track}s), a single
  #   such step (which will be converted to a single-step slot), or a value
  #   convertible to a step (e.g. a {MIDINote} for {Track}s). If this value is
  #   a {MIDINote.rest? rest}, the slot is cleared.
  # @return [TrackBase]
  # @see #clear_slot
  # @see #append_slot
  # @see #set_filled_slot
  def replace_slot(idx, new_steps)
    raise IndexError, "Index #{idx} is beyond the length of the track (#{@grid.length})" if idx >= @grid.length
    new_grid = @grid.dup
    new_grid[idx] = new_steps  # This will get slotified by the initializer.
    mutate(grid: new_grid)
  end

  alias set_slot replace_slot

  # Return a new track, replacing the steps in the `n`th non-empty slot with the
  # given steps. This is equivalent to {#set_slot} with the index of the `n`th
  # non-empty slot; see that method for details.
  # @param n [Integer] The `n`th non-empty slot will be mutated.
  # @param new_steps [StepBase, Array<StepBase>, nil, :r, :rest] (or other types
  #   depending on the subclass) The new contents of the slot. May be an array
  #   of the subclass-appropriate step type (e.g. {Step} for {Track}s), a single
  #   such step (which will be converted to a single-step slot), or a value
  #   convertible to a step (e.g. a {MIDINote} for {Track}s). If this value is
  #   a {MIDINote.rest? rest}, the slot is cleared.
  # @return [TrackBase]
  # @see #set_slot
  # @see #indexes_of_filled_slots
  # @see #filled_slot
  def replace_filled_slot(n, new_steps)
    idx = indexes_of_filled_slots[n]
    set_slot(idx, new_steps)
  end

  alias set_filled_slot replace_filled_slot

  # Returns a new track with all steps in slot `idx` removed. That is, the slot
  # is turned into a rest.
  #
  # @example
  #   T[:a1, [:b1, :b2], :c3].clear_slot(1)
  #   # is equivalent to
  #   T[:a1, :r, :c3]
  #
  # @param idx [Integer] The index of the slot to replace. Must be a valid index
  #   for the {#grid}.
  # @return [TrackBase]
  # @see set_slot
  def clear_slot(idx)
    replace_slot(idx, [])
  end

  # Returns a new track with the given steps appended to the slot at the given
  # index.
  #
  # @example
  #   T[:a1, :b1, :c1].append_slot(1, [:b2, :b3])
  #   # is equivalent to
  #   T[:a1, [:b1, :b2, :b3], :c1]
  #
  # @param idx [Integer] The index of the slot to replace. Must be a valid index
  #   for the {#grid}.
  # @param new_steps [StepBase, Array<StepBase>, nil, :r, :rest] (or other types
  #   depending on the subclass) - The step or steps to add to the slot. May be
  #   an array of the subclass-appropriate step type (e.g. {Step} for {Track}s),
  #   a single such step, or a value convertible to a step (e.g. a {MIDINote}
  #   for {Track}s).
  # @return [TrackBase]
  # @see #append
  # @see #set_slot
  def append_slot(idx, new_steps)
    raise IndexError, "index #{idx} is past the end of the grid" if idx >= @grid.length

    new_slot = @grid[idx] + self.class.slotify(new_steps)
    new_grid = @grid.dup
    new_grid[idx] = new_slot
    mutate(grid: new_grid)
  end


  ## @!group Adding, removing, and filtering slots

  # Returns a new track that repeats the slots of this track `n` times.
  #
  # @example
  #   T[:a1, :b2] * 4
  #   # is equivalent to
  #   T[:a1, :b2, :a1, :b2, :a1, :b2, :a1, :b2]
  #
  # @param n [Integer]
  # @return [TrackBase]
  # @see #cycle_to_length
  def repeat(n)
    mutate(grid: @grid * n)
  end

  alias * repeat

  # Returns a new track that repeats the slots of this track for `n` slots. Note
  # that if `n` does not evenly divide the length of this track, the final
  # repetition in the result will be truncated so that the overall track has `n`
  # slots.
  #
  # @example
  #   T[:a1, :b1, :c1].cycle_to_length(5)
  #   # is equivalent to
  #   T[:a1, :b1, :c1, :a1, :b1]
  #
  # @param n [Integer] The number of slots in the new track.
  # @return [TrackBase]
  # @see #repeat
  def cycle_to_length(n)
    mutate(grid: @grid.cycle.take(n))
  end

  # Returns a new track with the first `n` slots removed from this one.
  #
  # @example
  #   T[:a1, :b1, :c1, :d1].drop(2)
  #   # is equivalent to
  #   T[:c1, :d1]
  #
  # @param n [Integer]
  # @return [TrackBase]
  # @see #ltrim
  # @see #drop_last
  # @see #take
  def drop(n = 1)
    mutate(grid: @grid.drop(n))
  end

  # Returns a new track with the final `n` slots removed from this one.
  #
  # @example
  #   T[:a1, :b1, :c1, :d1].drop_last(2)
  #   # is equivalent to
  #   T[:a1, :b1]
  #
  # @param n [Integer]
  # @return [TrackBase]
  # @see #rtrim
  # @see #drop
  def drop_last(n = 1)
    new_grid = @grid.dup
    new_grid.pop(n)
    mutate(grid: new_grid)
  end

  # Returns a new track consisting of only the first `n` slots of this track.
  #
  # @example
  #   T[:a1, :b1, :c1, :d1].take(3)
  #   # is equivalent to
  #   T[:a1, :b1, :c1]
  #
  # @param n [Integer]
  # @return [TrackBase]
  # @see #drop
  def take(n)
    mutate(grid: @grid.take(n))
  end

  # Returns a new track consisting of only the selected slots of this track.
  # Takes the same arguments as Array#slice (aka `[]`): a single integer index,
  # an index and a length, or a range.
  # @return [TrackBase]
  def slice(*args)
    s = @grid.slice(*args)
    s = [s] if s.empty? || !s[0].is_a?(Array)
    mutate(grid: s)
  end

  alias [] slice

  private def sample_enum(e, n)
    # Sonic Pi overrides Array.sample with a version that returns a single
    # value, not an array. Reimplement it.
    e.to_a.shuffle.take(n)
  end

  # Returns a new track consisting of `n` random slots from this track's grid.
  # The relative order of the selected slots is maintained.
  #
  # @example
  #   T[:a1, :b1, :r, :d1, :e1].sample(2)
  #   # might result in
  #   T[:b1, :e1]
  #   # or, if the rest is selected
  #   T[:r, :d1]
  #
  # @param n [Intger] The number of slots to select.
  # @return [TrackBase]
  # @see #sample_filled_slots
  def sample(n)
    idxs = sample_enum(0...@grid.length, n).sort
    mutate(grid: @grid.values_at(*idxs))
  end

  # Returns a new track consisting of `n` random non-rest slots from this
  # track's grid. Unlike {#sample}, only picks from slots with steps. The
  # relative order of the slots is maintained.
  # @param n [Integer] The number of slots to select.
  # @return [TrackBase]
  # @see #sample
  def sample_filled_slots(n)
    idxs = sample_enum(indexes_of_filled_slots, n).sort
    mutate(grid: @grid.values_at(*idxs))
  end

  alias sample_filled sample_filled_slots

  # Returns a new track by removing all steps in slots that are certain
  # distances apart. The duration of the track does not change; the emptied
  # slots simply become rests.
  #
  # The arguments specify which slots to clear. They must all be integers > 0.
  # This method will walk through the track and clear every nth slot, where n
  # is the next number in the arguments. The function will cycle through the
  # arguments if there are enough slots to warrant it.
  #
  # @example
  #   t = T[:c4] * 9
  #
  #   u = t.dropout(3)
  #   # u is equivalent to
  #   T[:c4, :c4, :r,
  #     :c4, :c4, :r,
  #     :c4, :c4, :r]
  #
  #   v = t.dropout(2, 3)
  #   # v is equivalent to
  #   T[:c4, :r,
  #     :c4, :c4, :r,
  #     :c4, :r,
  #     :c4, :c4]
  #
  # @example
  #   t = T[:c4, :c4, :r, :c4, :r, :c4, :c4]
  #
  #   u = t.dropout(2)
  #   # u is equivalent to
  #   T[:c4, :r,
  #     :r, :r,
  #     :r, :r,
  #     :c4]
  #
  #   v = t.dropout(2, skip_empty: true)
  #   # v is equivalent to
  #   T[:c4, :r,
  #     :r, :c4, :r, :r,
  #     :c4]
  #   # The slots containing rests were ignored.
  #
  # @param gaps [Integer] Specifies the slots to clear; see above. You must pass
  #   at least one value.
  # @param skip_empty [Boolean] If true, empty slots (rests) are not considered
  #   when counting slots.
  # @return [TrackBase]
  # @see #extract_every
  # @see #drop_x_of_y
  # @see #rand_dropout
  def drop_every(*gaps, skip_empty: false)
    t, = extract_every(*gaps, skip_empty: skip_empty)
    t
  end

  alias dropout drop_every

  # Considers the track in groups of `y` slots, and clears every `x`th slot
  # within each group. The length of the track is not changed; cleared slots
  # become rests.
  #
  # @example
  #   T[:a1, :a2, :a3, :a4, :a5, :a6, :a7].drop_x_of_y(2, 3)
  #   # is equivalent to
  #   T[:a1, :r, :a3,
  #     :a4, :r, :a6,
  #     :a7]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   turn into a rest. Must be greater than 0 and <= `y`.
  # @param y [Integer] The size of the groups of slots to consider. Must be
  #   greater than 0 and >= `x`.
  # @param skip_empty [Boolean] If true, empty slots (rests) are not considered
  #   when counting slots.
  # @return [TrackBase]
  # @see #extract_x_of_y
  # @see #dropout
  # @see #rand_dropout
  def drop_x_of_y(x, y, skip_empty: false)
    t, = extract_x_of_y(x, y, skip_empty: skip_empty)
    t
  end

  alias grouped_drop drop_x_of_y
  alias grouped_droput drop_x_of_y
  alias gdropout drop_x_of_y
  alias gdrop drop_x_of_y

  # Return a new track by, with probability `p`, removing all steps in any given
  # slot. The length of the track is not changed; cleared slots become rests.
  # @param p [Number] The probability that any given slot will be cleared, 0 - 1
  #   inclusive.
  # @return [TrackBase]
  # @see #dropout
  # @see #drop_x_of_y
  def rand_dropout(p = 0.5)
    new_grid = @grid.map { |slot| (ExtApi.rand < p) ? [] : slot }
    mutate(grid: new_grid)
  end

  alias rdropout rand_dropout

  # Returns two tracks by extracting slots for which a block returns true. This
  # is the slot equivalent of {#extract_steps}; the first returned track
  # contains slots for which the block returns false, and the second ones for
  # which the block returns true. Both tracks will have the same length; slots
  # that are not selected into a particular track will be rests.
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   u, v = t.extract_slots { |slot| slot.length == 2 }
  #   # u is equivalent to
  #   T[:r, :d2, :e2, :f2]
  #   # and v is
  #   T[[:c1, :c2], :r, :r, :r]
  #
  #   x, y = t.extract_slots { |_, i| i % 2 == 0 }
  #   # x is equivalent to
  #   T[:r, :d2, :r, :f2]
  #   # and y is
  #   T[[:c1, :c2], :r, :e2, :r]
  #
  # @yieldparam slot [Array<StepBase>] The slot under consideration.
  # @yieldparam slot_idx [Integer] (optional) The index in the {#grid} of the
  #   slot.
  # @yieldreturn [Boolean] If true, the slot will be placed in the second of
  #   the two returned tracks. If false, it will be placed in the first.
  #
  # @return [Array(TrackBase, TrackBase)]
  # @see #extract_steps
  # @see #extract_x_of_y
  # @see #extract_every
  def extract_slots(&block)
    raise ArgumentError, "block must take <= 2 arguments" unless block.arity <= 2

    grid1 = []
    grid2 = []

    @grid.each_with_index do |slot, i|
      args = [slot, i].take(block.arity)
      if block.call(*args)
        grid1 << []
        grid2 << slot
      else
        grid1 << slot
        grid2 << []
      end
    end

    [mutate(grid: grid1), mutate(grid: grid2)]
  end

  # Returns a new track containing only slots for which a block returns true.
  # The new track will have the same length as this one, but will only contain
  # contain steps in the selected slots; others will be rests.
  #
  # The result is equivalent to the second returned track of {#extract_slots},
  # and the block is exactly as described on that method.
  #
  # @yieldparam (see #extract_slots)
  # @yieldreturn [Boolean] If true, the slot will be present in the returned
  #   track. If false, the corresponding slot in the new track will be empty
  #   (i.e. a rest).
  #
  # @return [Track]
  # @see #extract_slots
  # @see #filter_steps
  def filter_slots(&block)
    _, t = extract_slots(&block)
    t
  end

  alias select_slots filter_slots

  # Returns two tracks by selecting steps in slots that are certain distances
  # apart. This is an expanded version of {#drop_every}. The first track it
  # returns is exactly equal to the result of `drop_every`, and the second is
  # its complement. That is, slots that are empty in the first track will be
  # filled in the second.
  #
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1, :f1]
  #
  #   u, v = t.extract_every(3)
  #   # u is equivalent to
  #   T[:a1, :b1, :r, :d1, :e1, :r]
  #   # and v is
  #   T[:r, :r, :c4, :r, :r, :f1]
  #
  # @param (see #drop_every)
  # @return [TrackBase]
  # @see #drop_every
  # @see #extract_x_of_y
  def extract_every(*gaps, skip_empty: false)
    raise ArgumentError, "you must pass at least one argument" if gaps.empty?
    gaps.map! { |n| Integer.try_convert(n) }
    raise TypeError, "all arguments must be convertible to integers" if gaps.any? { |n| n.nil? }
    raise RangeError, "all arguments must be > 0" if gaps.any? { |n| n <= 0 }

    # e.g., drop every 3:
    # keep  | 0 1 - 3 4 - 6 7 - 9
    # drop  |     2     5     8
    # i % 3 | 0 1 2 0 1 2 0 1 2 0

    gap_idx = 0
    kept_slots = 0
    extract_slots do |slot|
      next false if skip_empty && slot.empty?

      gap = gaps[gap_idx % gaps.length]
      if kept_slots % gap == gap - 1
        # We're extracting this slot; move on to the next gap and reset count
        kept_slots = 0
        gap_idx += 1
        true
      else
        kept_slots += 1
        false
      end
    end
  end

  # Returns two tracks by selecting the `x`th slot in each group of `y`. This is
  # an expanded version of {#drop_x_of_y}. The first track it returns is exactly
  # equal to the result of `drop_x_of_y`, and the second is its complement. That
  # is, slots that are empty in the first track will be filled in the second.
  #
  # @example
  #   u, v = T[:a1, :a2, :a3, :a4, :a5, :a6, :a7].extract_x_of_y(2, 3)
  #   # u is equivalent to
  #   T[:a1, :r, :a3,
  #     :a4, :r, :a6,
  #     :a7]
  #   # and v is
  #   T[:r, :a2, :r,
  #     :r, :a5, :r,
  #     :r]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   place in the first returned track; other slots will be in the second. Must
  #   be greater than 0 and <= `y`.
  # @param y [Integer] The size of the groups of slots to consider. Must be
  #   greater than 0 and >= `x`.
  # @param skip_empty [Boolean] If true, empty slots (rests) are not considered
  #   when counting slots.
  # @return [TrackBase]
  # @see #extract_every
  # @see #drop_x_of_y
  def extract_x_of_y(x, y, skip_empty: false)
    raise TypeError, "x and y must be integers" unless x.is_a?(Integer) && y.is_a?(Integer)
    raise RangeError, "x and y must be > 0" unless x > 0 && y > 0
    raise RangeError, "x must be <= y" unless x <= y

    i = 0
    extract_slots do |slot|
      next false if skip_empty && slot.empty?

      extract_this = i % y == x - 1
      i += 1
      extract_this
    end
  end

  alias grouped_extract extract_x_of_y
  alias gextract extract_x_of_y


  ## @!group Combining and permuting slots

  # Creates a new track by merging each group of `n` consecutive slots into one
  # slot each. If `n` does not evenly divide the number of slots in the original
  # track, the final slot will merge the remaining slots.
  #
  # @example
  #   T[:c3, :d3, :e3, :f3, :g3].gmerge(2)
  #   # is equivalent to
  #   T[[:c3, :d3], [:e3, :f3], [:g3]]
  #
  # @param n [Integer] The size of each group of slots to merge.
  # @return [TrackBase]
  # @see #each_cons
  def grouped_merge(n)
    new_grid = @grid.each_slice(n).map { |slots| slots.flatten }
    mutate(grid: new_grid)
  end

  alias gmerge grouped_merge
  alias group grouped_merge

  # Returns a new track that plays each successive overlapped set of `n` slots.
  # If `flatten` is false, each overlapped set of slots will be grouped into a
  # new slot.
  #
  # @example
  #   T[:a1, :b1, [:c1, :c2], :d1, :e1].each_cons(3)
  #   # is equivalent to
  #   T[:a1, :b1, [:c1, :c2],
  #     :b1, [:c1, :c2], :d1,
  #     [:c1, :c2], :d1, :e1]
  #
  # @example
  #   T[:a1, :b1, [:c1, :c2], :d1, :e1].each_cons(3, flatten: false)
  #   # is equivalent to
  #   T[[:a1, :b1, :c1, :c2],
  #     [:b1, :c1, :c2, :d1],
  #     [:c1, :c2, :d1, :e1]]
  #
  # @param n [Integer] The number of slots to consider in groups. It is an error
  #   to pass a value greater than the length of the track.
  # @param flatten [Boolean] Whether the grouped slots should be merged together
  #   into single slots.
  # @return [TrackBase]
  # @see #gmerge
  def each_cons(n, flatten: true)
    raise IndexError, "n=#{n} is greater than the length of the track (#{@grid.length})" if n > @grid.length

    new_grid = @grid.each_cons(n).to_a
    if flatten
      new_grid = new_grid.flatten(1)
    else
      new_grid.map!(&:flatten)
    end
    mutate(grid: new_grid)
  end

  # Returns a new track that contains every permutation of `n` slots. The order
  # of the permutations is indeterminate. If `n` is nil, permutes all slots.
  # @param n [Integer, nil]
  # @return [TrackBase]
  # @see #combination
  def permutation(n = nil)
    mutate(grid: @grid.permutation(n).to_a.flatten(1))
  end

  alias permutations permutation

  # Returns a new track that contains every combination of `n` slots. The order
  # of the combinations is indeterminate.
  # @param n [Integer]
  # @return [TrackBase]
  # @see #permutation
  def combination(n)
    mutate(grid: @grid.combination(n).to_a.flatten(1))
  end

  alias combinations combination


  ## @!group Adding, removing, and filtering steps

  # Returns two tracks by extracting steps for which a block returns true.
  #
  # If the block returns true, the step will be placed in the second of the two
  # returned tracks. If it returns false, the step will be placed in the first.
  # The returned tracks will have the same length; if the process results in all
  # steps in a slot winding up in only one of the tracks, the slot in the other
  # track will be empty (i.e., a rest).
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   u, v = t.extract_steps { |step| step.note.match?(:c) }
  #   # u is equivalent to
  #   T[:r, :d2, :e2, :f2]
  #   # and v is
  #   T[[:c1, :c2], :r, :r, :r]
  #
  #   x, y = t.extract_steps { |step| step.note.octave == 2 }
  #   # x is equivalent to
  #   T[:c1, :r, :r, :r]
  #   # and y is
  #   T[:c2, :d2, :e2, :f2]
  #
  # @yieldparam step [StepBase] The step under consideration.
  # @yieldparam slot [Array<StepBase>] (optional) The slot to which the step
  #   belongs.
  # @yieldparam slot_idx [Integer] (optional) The index in the {#grid} of the
  #   slot the step belongs to.
  # @yieldreturn [Boolean] If true, the step will be placed in the second of
  #   the two returned tracks. If false, it will be placed in the first.
  #
  # @return [Array(TrackBase, TrackBase)]
  # @see #filter_steps
  # @see #extract_slots
  # @see #extract_x_of_y
  # @see #extract_every
  def extract_steps(&block)
    raise ArgumentError, "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

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

  alias extract extract_steps

  # Returns a new track containing only steps for which a block returns true.
  # The new track will have the same length as this one, but will only contain
  # the selected steps.
  #
  # The result is equivalent to the second returned track of {#extract_steps},
  # and the block is exactly as described on that method.
  #
  # @yieldparam (see #extract_steps)
  # @yieldreturn [Boolean] If true, the step will be present in the returned
  #   track.
  #
  # @return [Track]
  # @see #extract_steps
  # @see #filter_slots
  def filter_steps(&block)
    _, t = extract_steps(&block)
    t
  end

  alias filter filter_steps
  alias select_steps filter_steps
  alias select filter_steps




  ## @!group Mutating steps

  # Return a new track, replacing each step in this track with the result of the
  # given block.
  # 
  # The block may return:
  # - A step, which will replace the step yielded to the block.
  # - nil, :r, or :rest, which will remove the step yielded to the block.
  # - An array of steps, which will all be added in place of the yielded step to
  #   the corresponding slot of the yielded step.
  # 
  # @example
  #   t = T[[:f8, :f9], :c2, [:c8, :d9]]
  #   u = t.mutate_each_step do |step|
  #     step.with_gate(step.note.octave > 8 ? 0.25 : 1)
  #   end
  #   # u is equivalent to
  #   T[[:f8, S(:f9, gate: 0.25)],
  #     :c2,
  #     [:c8, S(:d9, gate: 0.25)]]
  #
  #   v = t.mutate_each_step { |step| step.note.pitch_class == :c ? :r : step  }
  #   # v is equivalent to
  #   T[[:f8, :f9], :r, :d9]
  # 
  # @yieldparam step [StepBase] The step to mutate.
  # @yieldparam slot_idx [Integer] (optional) The index in the {#grid} of the
  #   slot to which the step belongs.
  # @yieldparam percent [Number] (optional) The percent through the track that
  #   the slot falls. For instance, the first slot of the track will have
  #   percent 0, the middle slot (in a track with an odd number of slots) will
  #   have percent 0.5, and the final slot will have percent 1.0.
  # @yieldreturn [StepBase, Array<StepBase>, nil, :r, :rest] (or other subclass-
  #   defined types) Determines the value to use in place of the step in the
  #   resulting track; see above.
  #
  # @return [TrackBase]
  # @see #mutate_each_slot
  def mutate_each_step(&block)
    raise ArgumentError, "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

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

        new_slot += self.class.slotify(new_step)
      end

      new_slot
    end

    mutate(grid: new_grid)
  end

  alias mutate_steps mutate_each_step

  # Returns a new track by replacing the steps in the given slot with the result
  # of the given block. The block will be called once with each step in the
  # slot. The result of the block will replace the step it is called with.
  #
  # The block should return:
  # - A single step, which will replace the given step in the slot.
  # - An array of steps, which will all be added to the slot in place of the
  #   given step.
  # - An empty array or a rest, which will remove the given step from the slot.
  # - Equivalents of any of the above (see `slotify`).
  #
  # Note that if the slot at the given index is empty, the block will not be
  # called and no changes will be made.
  #
  # @example
  #   t = T[[:f8, :f9], :c2, [:c8, :d9]]
  #   u = t.mutate_steps_in_slot(2) { |step| step.shift_octave(-2) }
  #   # u is equivalent to
  #   T[[:f8, :f9], :c2, [:c6, :d7]]
  #
  # @yieldparam step [StepBase] The step to mutate.
  # @yieldreturn [StepBase, Array<StepBase>, nil, :r, :rest] (or other subclass-
  #   defined types) Determines the value to use in place of the step in the
  #   resulting track; see above.
  #
  # @param idx [Integer] The index in the {#grid} of the slot to mutate.
  # @return [TrackBase]
  # @see #mutate_each_step
  # @see #mutate_each_slot
  # @see #set_slot
  def mutate_steps_in_slot(idx, &block)
    raise ArgumentError, "Block must take 1 argument" if block.arity != 1

    new_slot = @grid[idx].map { |step| block.call(step) }.flatten
    set_slot(idx, new_slot)
  end

  alias mutate_slot_steps mutate_steps_in_slot
  alias mutate_slot mutate_steps_in_slot

  # Return a new track, replacing the steps in the `n`th non-empty slot with the
  # result of the given block. This is equivalent to {#mutate_steps_in_slot}
  # with the index of the `n`th non-empty slot; see that method for details.
  # @yieldparam (see #mutate_steps_in_slot)
  # @yieldreturn (see #mutate_steps_in_slot)
  # @param n [Integer] The `n`th non-empty slot will be mutated.
  # @return (see #mutate_steps_in_slot)
  # @see #mutate_steps_in_slot
  # @see #indexes_of_filled_slots
  # @see #filled_slot
  def mutate_filled_slot(n, &block)
    idx = indexes_of_filled_slots[n]
    mutate_steps_in_slot(idx, &block)
  end


  ## @!group Step attribute mutators

  # Returns a new track where every step has the given {StepBase#prob
  # probability}.
  #
  # @param p [Prob, Number, #call, nil] The probability to set on the steps in
  #   the new track, or nil to clear any probability. Non-{Prob} values will be
  #   converted as described in {StepBase#initialize}.
  # @param overwrite [Boolean] If false, steps that already have a probability
  #   are left unchanged.
  # @return [TrackBase]
  # @see #without_prob
  # @see StepBase#prob
  # @see Prob
  def with_prob(p, overwrite: true)
    mutate_each_step do |step|
      if step.prob.nil? || overwrite
        step.with_prob(p)
      else
        step
      end
    end
  end

  alias prob with_prob

  # Returns a new track with the {StepBase#prob probability} removed from each
  # step. That is, the steps in the resulting track will always trigger.
  # @return [TrackBase]
  # @see #with_prob
  # @see StepBase#prob
  # @see Prob
  def without_prob
    mutate_each_step { |step| step.without_prob }
  end

  alias clear_prob without_prob

  # Returns a new track where every step has the {Prob.fill fill probability}.
  # Or, if the argument is false, all steps with the `fill` probability in this
  # track will have their probability cleared in the result (steps with other
  # probabilities are left unchanged).
  # @param fill [Boolean] Whether to set or unset the `fill` probability.
  # @return [TrackBase]
  # @see #with_prob
  # @see #clear_prob
  # @see Prob.fill
  # @see PlayerBase#fill
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

  # @!endgroup


  ### Track construction helpers
  # TODO: philosophically I want these to be private class methods, but you
  # can't call private class methods from instance methods :(. Figure out a way
  # to deal with that, or maybe just give up and make them instance methods.

  # Attempts to convert its argument to a Step.
  #
  # Subclasses must implement this method and may do whatever conversion is
  # convenient for users. E.g. symbols or strings may be converted to MIDI note
  # Steps.
  #
  # @private
  def self.stepify(_)
    raise RuntimeError, "subclasses must implement stepify"
  end

  # Attempts to convert its argument to a grid slot (i.e. an array of steps).
  #
  # Subclasses must implement this method, presumably by using `stepify` to
  # convert applicable step-like things (step instances or scalars) into a
  # single-element slot with that step, and doing the same for each element of
  # an enumerable. Rests should be removed from the result entirely.
  #
  # The result must be frozen.
  #
  # @private
  def self.slotify(_)
    raise RuntimeError, "subclasses must implement slotify"
  end

  # Attempts to convert its argument to a grid (a 2d array of steps).
  #
  # Subclasses must implement this method, presumably based on the result of
  # `slotify`.
  #
  # The result must be frozen.
  #
  # @private
  def self.gridify(_)
    raise RuntimeError, "subclasses must implement gridify"
  end


  protected

  # Does a deep dup of the grid, returning a version where the grid itself and
  # each slot is mutable.
  def mutable_grid_dup
    @grid.map { |slot| slot.dup }
  end

  # Returns a hash of the keyword arguments to the initializer and their default
  # values. The keys of the hash are assumed to also be readable attributes of
  # the class. This hash is used to implement `mutate`, `repr`, and
  # `assert_compatible_track`. Subclasses should override this method to add any
  # additional arguments their initializer accepts.
  def ctor_kwargs
    {
      granularity: NoteLength::Eighth,
      timescale: 1
    }
  end

  # The string representation of the method to call to create a new instance of
  # this track subclass. Defaults to the name of the class; if there is a
  # shorthand method, subclasses should return it here. Used to implement
  # `repr`, which will call it with square brackets, not parentheses.
  def repr_ctor_method
    self.class.name
  end

  # Returns a new track by applying the given mutations to this track. That is,
  # calls the track initializer, substituting the given keyword arguments and
  # passing the current values for any that are not provided. The special
  # keyword argument `grid` is used to change the grid itself.
  def mutate(**mutations)
    grid = mutations.delete(:grid) || @grid
    ctor_kwargs.each_key do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    self.class.new(*grid, **mutations)
  end

  def strict_track_merging?
    current_track_defaults[:strict_track_merging] || false
  end

  def assert_compatible_track(other_track)
    return unless strict_track_merging?

    ctor_kwargs.each_key do |kwarg|
      us = send(kwarg)
      them = other_track.send(kwarg)
      raise ArgumentError, "incompatible tracks: #{kwarg} #{us} != #{them}" unless us == them
    end
  end

  # Attempts to convert its argument into a track. If it is already a track,
  # it is returned as-is. Otherwise, constructs a new track which will inherit
  # the granularity and timescale from self.
  def compatibly_trackify(x)
    return x if x.is_a?(self.class)

    # We can just pass this off to the initializer and let it call gridify.
    mutate(grid: x)
  end
end
