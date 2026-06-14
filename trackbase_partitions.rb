# frozen_string_literal: true

require_relative "trackbase"
require_relative "utils/internal_utils"

# The slot partition methods and their select/reject/clear/inverse clear
# variants. There's really very little code in here, but there is a shocking
# amount of documentation.
#-
class TrackBase
  # @!macro [new] drop_desc
  #   If `drop` is false, both tracks will have the same length; slots that are
  #   selected into one track will have a corresponding rest in the other. If
  #   `drop` is true, that is not the case: the first track will contain only
  #   the selected slots and the second the remaining ones. If that operation
  #   would result in a track with no slots, nil is returned for that track.
  #   <!-- forcing a newline -->

  # @!macro [new] drop_param
  #   @param drop [Boolean] Controls whether slots are removed or filled with
  #     rests; see above.

  # @!macro [new] partition_return
  #   @return [Array<TrackBase, nil>] A two-element array containing first a
  #     track with the selected slots and second one with all remaining slots.
  #     If `drop` is true, either track may be nil if no slots were chosen for
  #     it.

  # @!macro [new] skip_empty_param
  #   @param skip_empty [Boolean] If true, empty slots (rests) are not
  #     considered when counting slots.
  
  # @!macro [new] group_y_param
  #   @param y [Integer] The size of the groups of slots to consider. Must be
  #     greater than 0 and >= `x`.
  
  
  # @!group Partitioning and filtering slots

  ### partition_slots family
  
  # Returns two tracks, the first containing all the steps for block returns
  # true and the second those for which it returns false. This is the slot
  # equivalent of {#partition_steps}, except that by default the returned tracks
  # may not have the same length as this track.
  #
  # @macro drop_desc
  #
  # There is a family of methods providing functionality based on this one. To
  # select or reject slots matching a block, see {#select_slots} and
  # {#reject_slots}. To clear select slots, rather than removing them entirely,
  # see {#clear_slots} and {#clear_slots_except}.
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   x, y = t.partition_slots { |_, i| i % 2 == 0 }
  #   # x is equivalent to
  #   T[[:c1, :c2], :e2]
  #   # and y is
  #   T[:d2, :f2]
  #
  #   u, v = t.partition_slots(drop: false) { |slot| slot.length == 2 }
  #   # u is equivalent to
  #   T[[:c1, :c2], :r, :r, :r]
  #   # and v is
  #   T[:r, :d2, :e2, :f2]
  #
  # @yieldparam slot [Array<StepBase>] The slot under consideration.
  # @yieldparam slot_idx [Integer] (optional) The index in the {#grid} of the
  #   slot.
  # @yieldreturn [Boolean] If true, the slot will be placed in the first of the
  #   two returned tracks. If false, it will be placed in the second.
  #
  # @macro drop_param
  # @macro partition_return
  # @see #partition_steps
  # @see #partition_x_of_y
  # @see #partition_every
  # @see #partition_rand
  # @see #select_slots
  # @see #reject_slots
  # @see #clear_slots
  # @see #clear_slots_except
  def partition_slots(drop: true, &block)
    raise ArgumentError, "block must take <= 2 arguments" unless block.arity <= 2

    grid1 = []
    grid2 = []

    @grid.each_with_index do |slot, i|
      if SpiSeq::Utils.call_varargs(block, slot, i)
        grid1 << slot
        grid2 << [] unless drop
      else
        grid1 << [] unless drop
        grid2 << slot
      end
    end

    [grid1.empty? ? nil : mutate(grid: grid1),
     grid2.empty? ? nil : mutate(grid: grid2)]
  end

  # Returns a new track containing only select slots from this one.
  #
  # You may select slots in two different ways:
  #
  # 1. By providing index(es) in the {#grid} via an index, an index and a
  #    length, or a range, in the same manner as `Array#slice`. Selecting slots
  #    this way is equivalent to using {#slice}.
  # 2. By providing a block as described in {#partition_slots}. The new track
  #    will contain only slots for which the block returns true.
  #
  # The second variant returns exactly the first track from a call to
  # {#partition_slots}. This method's complement is {#reject_slots}. To convert
  # unselected slots to rests, rather than removing them entirely, use
  # {#clear_slots_except}. To clear slots this method would select, use
  # {#clear_slots}.
  #
  # If no slots are selected, returns nil.
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   t.select_slots(0, 2)
  #   # is equivalent to
  #   T[[:c1, :c2], :d2]
  #
  #   t.select_slots { |slot| slot.length == 1 }
  #   # is equivalent to
  #   T[:d2, :e2, :f2]
  #
  # @yieldparam (see #partition_slots)
  # @yieldreturn [Boolean] If true, the slot will be present in the returned
  #   track.
  #
  # @param idx_or_range [Integer, Range] The index of the first slot to select,
  #   or a range of indexes to select. Invalid indexes are ignored. It is an
  #   error to provide this value if a block is also provided.
  # @param length [Integer, nil] If `idx_or_range` is an integer, the number of
  #   slots after that index to select (nil will select just that slot). It is
  #   an error to provide a value for this parameter if the first argument is a
  #   range or nil.
  # @return [TrackBase, nil]
  # @see #slice
  # @see #partition_slots
  # @see #reject_slots
  # @see #clear_slots_except
  # @see #clear_slots
  # @see #select_every
  # @see #select_x_of_y
  # @see #select_rand
  # @see #select_steps
  def select_slots(idx_or_range = nil, length = nil, &block)
    if !idx_or_range.nil?
      raise ArgumentError, "a block cannot be provided if an index or range is" unless block.nil?
      length.nil? ? slice(idx_or_range) : slice(idx_or_range, length)
    elsif !length.nil?
      raise ArgumentError, "a starting index must be provided if a length is" unless length.nil?
    elsif block.nil?
      raise ArgumentError, "a block must be provided if no index or range is"
    else
      t, = partition_slots(&block)
      t
    end
  end
  alias filter_slots select_slots

  # Returns a new track excluding certain slots from this one.
  #
  # This is the complement of {#select_slots} and behaves exactly like it except
  # that the criteria for selecting slots is inverted. If given a block, it
  # returns exactly the second track from a call to {#partition_slots}. To
  # convert unselected slots to rests, rather than removing them entirely,
  # use {#clear_slots}.
  #
  # If all slots are rejected, returns nil.
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   t.reject_slots(0, 2)
  #   # is equivalent to
  #   T[:e2, :f2]
  #
  #   t.reject_slots { |slot| slot.length == 1 }
  #   # is equivalent to
  #   T[[:c1, :c2]]
  #
  # @yieldparam (see #partition_slots)
  # @yieldreturn [Boolean] If false, the slot will be present in the returned
  #   track.
  #
  # @param idx_or_range [Integer, Range] The index of the first slot to reject,
  #   or a range of indexes to reject. Invalid indexes are ignored. It is an
  #   error to provide this value if a block is also provided.
  # @param length [Integer, nil] If `idx_or_range` is an integer, the number of
  #   slots after that index to reject (nil will reject just that slot). It is
  #   an error to provide a value for this parameter if the first argument is a
  #   range or nil.
  # @return [TrackBase, nil]
  # @see #partition_slots
  # @see #select_slots
  # @see #clear_slots
  # @see #reject_every
  # @see #reject_x_of_y
  # @see #reject_rand
  # @see #reject_steps
  def reject_slots(idx_or_range = nil, length = nil, &block)
    if !idx_or_range.nil?
      raise ArgumentError, "a block cannot be provided if an index or range is" unless block.nil?

      indexes = resolve_slice_idxs(@grid.length, idx_or_range, length)
      new_grid = []
      @grid.each_with_index do |slot, i|
        next if indexes.include?(i)
        new_grid << slot
      end
      new_grid.empty? ? nil : mutate(grid: new_grid)
    elsif !length.nil?
      raise ArgumentError, "a starting index must be provided if a length is" unless length.nil?
    elsif block.nil?
      raise ArgumentError, "a block must be provided if no index or range is"
    else
      _, t = partition_slots(&block)
      t
    end
  end
  alias drop_slots reject_slots

  # Returns a new track clearing select slots from this one.
  #
  # This method behaves exactly like {#reject_slots} except that the length of
  # this track is maintained; selected slots are not removed, they are instead
  # replaced with rests.
  #
  # This method's complement is {#clear_slots_except}. If given a block, it
  # returns exactly the second track from a call to {#partition_slots} with
  # `drop` set to false. To remove slots rather than convert them to rests, use
  # {#reject_slots}.
  #
  # If neither arguments nor a block is passed, all slots are cleared in the new
  # track.
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   t.clear_slots
  #   # is equivalent to
  #   T[:r, :r, :r, :r]
  #
  #   t.clear_slots(0, 2)
  #   # is equivalent to
  #   T[:r, :r, :e2, :f2]
  #
  #   t.clear_slots { |slot| slot.length == 1 }
  #   # is equivalent to
  #   T[[:c1, :c2], :r, :r, :r]
  #
  # @yieldparam (see #partition_slots)
  # @yieldreturn [Boolean] If true, the corresponding slot will be a rest in the
  #   returned track. If false, the new track will contain the slot as-is.
  #
  # @param idx_or_range [Integer, Range] The index of the first slot to clear,
  #   or a range of indexes to clear. Invalid indexes are ignored. It is an
  #   error to provide this value if a block is also provided.
  # @param length [Integer, nil] If `idx_or_range` is an integer, the number of
  #   slots after that index to clear (nil will clear just that slot). It is
  #   an error to provide a value for this parameter if the first argument is a
  #   range or nil.
  # @return [TrackBase]
  # @see #partition_slots
  # @see #reject_slots
  # @see #clear_slots_except
  # @see #clear_every
  # @see #clear_x_of_y
  # @see #clear_rand
  # @see #reject_steps
  def clear_slots(idx_or_range = nil, length = nil, &block)
    if !idx_or_range.nil?
      raise ArgumentError, "a block cannot be provided if an index or range is" unless block.nil?

      indexes = resolve_slice_idxs(@grid.length, idx_or_range, length)
      new_grid = mutable_grid_dup
      indexes.each do |i|
        slot = new_grid[i]
        next if slot.nil?  # invalid index
        slot.clear
      end
      mutate(grid: new_grid)
    elsif !length.nil?
      raise ArgumentError, "a starting index must be provided if a length is" unless length.nil?
    elsif block.nil?
      mutate(grid: [[]] * @grid.length)
    else
      _, t = partition_slots(drop: false, &block)
      t
    end
  end
  alias clear_slot clear_slots
  alias clear clear_slots

  # Returns a new track clearing slots except the given ones.
  #
  # This is the complement of {#clear_slots} and behaves exactly like it except
  # that the criteria for selecting slots is inverted. If given a block, it
  # returns exactly the first track from a call to {#partition_slots} with
  # `drop` set to false. To remove slots except for certain ones, rather than
  # convert them to rests, use {#select_slots}.
  #
  # @example
  #   t = T[[:c1, :c2], :d2, :e2, :f2]
  #
  #   t.clear_slots_except(0, 2)
  #   # is equivalent to
  #   T[[:c1, :c2], :d2, :r, :r]
  #
  #   t.clear_slots_except { |slot| slot.length == 1 }
  #   # is equivalent to
  #   T[:r, :d2, :e2, :f2]
  #
  # @yieldparam (see #partition_slots)
  # @yieldreturn [Boolean] If true, the slot will be present in the returned
  #   track. If false, the corresponding slot in the new track will be a rest.
  #
  # @param idx_or_range [Integer, Range] The index of the first slot to
  #   maintain, or a range of indexes to maintain. Invalid indexes are ignored.
  #   It is an error to provide this value if a block is also provided.
  # @param length [Integer, nil] If `idx_or_range` is an integer, the number of
  #   slots after that index to maintain (nil will maintain just that slot). It
  #   is an error to provide a value for this parameter if the first argument is
  #   a range or nil.
  # @return [TrackBase]
  # @see #partition_slots
  # @see #select_slots
  # @see #clear_slots
  # @see #clear_every_except
  # @see #clear_except_x_of_y
  # @see #clear_except_rand
  # @see #reject_steps
  def clear_slots_except(idx_or_range = nil, length = nil, &block)
    if !idx_or_range.nil?
      raise ArgumentError, "a block cannot be provided if an index or range is" unless block.nil?

      indexes = resolve_slice_idxs(@grid.length, idx_or_range, length)
      new_grid = mutable_grid_dup
      new_grid.each_with_index do |slot, i|
        slot.clear unless indexes.include?(i)
      end
      mutate(grid: new_grid)
    elsif !length.nil?
      raise ArgumentError, "a starting index must be provided if a length is" unless length.nil?
    elsif block.nil?
      raise ArgumentError, "a block must be provided if no index or range is"
    else
      t, = partition_slots(drop: false, &block)
      t
    end
  end
  alias clear_except clear_slots_except
  alias clear_slots_unless clear_slots_except
  alias clear_unless clear_slots_except


  ### partition_every family

  # Returns two tracks, the first containing slots that are a certain distance
  # apart, and the second the remaining slots.
  #
  # The arguments specify which slots to clear. They must all be integers > 0.
  # This method will walk through the track and place every nth slot in the
  # first returned track, where n is the next number in the arguments. Other
  # slots are placed in the second track. The function will cycle through the
  # arguments if there are enough slots to warrant it.
  # 
  # @macro drop_desc
  #
  # There is a family of methods providing functionality based on this one. To
  # select or reject slots at intervals, see {#select_every} and
  # {#reject_every}. To clear select slots, rather than removing them entirely,
  # see {#clear_every} and {#clear_every_except}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1, :f1]
  #   u, v = t.partition_every(3)
  #   # u is equivalent to
  #   T[:c4, :f1]
  #   # and v is
  #   T[:a1, :b1, :d1, :e1]
  #
  # @example
  #   t = T[:c4] * 9
  #   u, v = t.partition_every(2, 3, drop: false)
  #   # u is equivalent to
  #   T[:r, :c4, :r,
  #     :r, :c4,
  #     :r, :c4, :r,
  #     :r]
  #   # and v is the complement:
  #   T[:c4, :r, :c4,
  #     :c4, :r,
  #     :c4, :r, :c4,
  #     :c4]
  #
  # @example
  #   t = T[:c4, :c4, :r, :c4, :r, :c4, :c4]
  #
  #   # rests are counted by default
  #   u, v = t.partition_every(2, skip_empty: true, drop: false)
  #   # u is equivalent to
  #   T[:r, :c4,
  #     :r, :r,
  #     :r, :c4,
  #     :r]
  #   # and v is the complement:
  #   T[:c4, :r,
  #     :r, :c4,
  #     :r, :r,
  #     :c4]
  #
  #   # but you can ignore them for counting with `skip_empty`:
  #   x, y = t.partition_every(2, skip_empty: true, drop: false)
  #   # x is equivalent to
  #   T[:r, :c4,
  #     :r,  # rest is skipped in counting
  #     :r,
  #     :r,  # another skipped rest
  #     :c4, :r]
  #   # and y is the complement:
  #   T[:c4, :r,
  #     :r,
  #     :c4,
  #     :r,
  #     :r, :c4]
  #
  # @param gaps [Integer] Specifies the slots to clear; see above. You must pass
  #   at least one value.
  # @macro drop_param
  # @macro skip_empty_param
  # @macro partition_return
  # @see partition_slots
  # @see partition_x_of_y
  # @see partition_every
  # @see rand_partition
  # @see select_every
  # @see reject_every
  # @see clear_every
  # @see clear_every_except
  def partition_every(*gaps, drop: true, skip_empty: false)
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
    partition_slots(drop: drop) do |slot|
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

  # Returns a new track containing only slots that are certain distances apart.
  # 
  # If no slots are selected, returns nil.
  #
  # This returns exactly the first track from a call to {#partition_every}. This
  # method's complement is {#reject_every}. To convert unselected slots to
  # rests, rather than removing them entirely, use {#clear_every_except}. To
  # clear slots this one would select, use {#clear_every}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1, :f1, :g1]
  #
  #   t.select_every(2)
  #   # is equivalent to
  #   T[:b2, :d1, :f1]
  #
  #   t.select_every(2, 3)
  #   # is equivalent to
  #   T[:b2, :e1, :g1]
  #
  # @param gaps [Integer] Specifies the slots to select; see {#partition_every}.
  #   You must pass at least one value.
  # @macro skip_empty_param
  # @return [TrackBase, nil]
  # @see #partition_every
  # @see #reject_every
  # @see #clear_every_except
  # @see #clear_every
  # @see #select_slots
  # @see #select_x_of_y
  # @see #select_rand
  # @see #select_steps
  def select_every(*gaps, skip_empty: false)
    t, = partition_every(*gaps, skip_empty: skip_empty)
    t
  end
  alias filter_every select_every

  # Returns a new track excluding steps that are certain distances apart.
  # 
  # If all slots are rejected, returns nil.
  #
  # This returns exactly the second track from a call to {#partition_every}.
  # This method's complement is {#select_every}. To convert selected slots to
  # rests, rather than removing them entirely, use {#clear_every}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1, :f1, :g1]
  #
  #   t.reject_every(2)
  #   # is equivalent to
  #   T[:a1, :c1, :e1, :g1]
  #
  #   t.reject_every(2, 3)
  #   # is equivalent to
  #   T[:a1, :c1, :d1, :f1]
  #
  # @param gaps [Integer] Specifies the slots to reject; see {#partition_every}.
  #   You must pass at least one value.
  # @macro skip_empty_param
  # @return [TrackBase, nil]
  # @see #partition_every
  # @see #select_every
  # @see #clear_every
  # @see #reject_slots
  # @see #reject_x_of_y
  # @see #reject_rand
  # @see #reject_steps
  def reject_every(*gaps, skip_empty: false)
    _, t = partition_every(*gaps, skip_empty: skip_empty)
    t
  end
  alias drop_every reject_every

  # Returns a new track clearing slots that are certain distances apart.
  # 
  # This method behaves exactly like {#reject_every} except that the length of
  # this track is maintained; selected slots are not removed, they are instead
  # replaced with rests.
  # 
  # This returns exactly the second track from a call to {#partition_every} with
  # `drop` set to false. This method's complement is {#clear_every_except}. To
  # remove slots rather than converting them to rests, use {#reject_every}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1, :f1, :g1]
  #
  #   t.clear_every(2)
  #   # is equivalent to
  #   T[:a1, :r, :c1, :r, :e1, :r, :g1]
  #
  #   t.clear_every(2, 3)
  #   # is equivalent to
  #   T[:a1, :r, :c1, :d1, :r, :f1, :r]
  #
  # @param gaps [Integer] Specifies the slots to clear; see {#partition_every}.
  #   You must pass at least one value.
  # @macro skip_empty_param
  # @return [TrackBase]
  # @see #partition_every
  # @see #reject_every
  # @see #clear_every_except
  # @see #clear_slots
  # @see #clear_x_of_y
  # @see #clear_rand
  # @see #reject_steps
  def clear_every(*gaps, skip_empty: false)
    _, t = partition_every(*gaps, drop: false, skip_empty: skip_empty)
    t
  end
  alias dropout clear_every

  # Returns a new track clearing slots except those are certain distances apart.
  # 
  # This is the complement of {#clear_every} and behaves exactly like it except
  # that the criteria for selecting slots is inverted. It returns exactly the
  # first track from a call to {#partition_every} with `drop` set to false. To
  # remove the slots that this method converts to rests, use {#select_every}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1, :f1, :g1]
  #
  #   t.clear_every_except(2)
  #   # is equivalent to
  #   T[:r, :b1, :r, :d1, :r, :f1, :r]
  #
  #   t.clear_every_except(2, 3)
  #   # is equivalent to
  #   T[:r, :b1, :r, :r, :e1, :r, :g1]
  #
  # @param gaps [Integer] Specifies the slots to maintain; see
  #   {#partition_every}. You must pass at least one value.
  # @macro skip_empty_param
  # @return [TrackBase]
  # @see #partition_every
  # @see #select_every
  # @see #clear_every
  # @see #clear_slots_except
  # @see #clear_except_x_of_y
  # @see #clear_except_rand
  # @see #reject_steps
  def clear_every_except(*gaps, skip_empty: false)
    t, = partition_every(*gaps, drop: false, skip_empty: skip_empty)
    t
  end


  ### partition_x_of_y family

  # Returns two tracks, the first containing those in the `x`th slot of each
  # group of `y` and the second the others.
  #
  # @macro drop_desc
  # 
  # There is a family of methods providing functionality based on this one. To
  # select or reject slots based on how they fall in groups, see
  # {#select_x_of_y} and {#reject_x_of_y}. To clear slots, rather than removing
  # them entirely, see {#clear_x_of_y} and {#clear_except_x_of_y}.
  #
  # @example
  #   t = T[:a1, :b1, :c1,
  #         :d1, :e1, :f1]
  #
  #   u, v = t.partition_x_of_y(2, 3)
  #   # u is equivalent to
  #   T[:b1, :e1]  # there are two groups of three, and these are the second slots in each
  #   # and v is
  #   T[:a1, :c1, :d1, :f1]
  #
  #   x, y = t.partition_x_of_y(2, 3, drop: false)
  #   # x is equivalent to
  #   T[:r, :b1, :r,
  #     :r, :e1, :r]
  #   # and y is the complement:
  #   T[:a1, :r, :c1,
  #     :d1, :r, :f1]
  #
  # @example
  #   t = T[:a4, :b4, :r,
  #         :c4, :r, :d4,
  #         :e4]
  #
  #   # rests are counted by default
  #   u, v = t.partition_x_of_y(1, 3)
  #   # u is equivalent to
  #   T[:a4, :c4, :e4]
  #   # and v is everything else:
  #   T[:b4, :r, :r, :c4]
  #
  #   # but you can ignore them for selecting slots with `skip_empty`
  #   x, y = t.partition_x_of_y(1, 3, skip_empty: true)
  #   # x is equivalent to
  #   T[:a4, :d4]  # two groups were formed - [:a4, :b4, :c4] and [:d4, :e4]
  #   # all other slots and the rests are in y:
  #   T[:b4, :r, :c4, :r, :e4]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   place in the first track. Must be greater than 0 and <= `y`.
  # @macro group_y_param
  # @macro drop_param
  # @macro skip_empty_param
  # @macro partition_return
  # @see #partition_steps
  # @see #partition_slots
  # @see #partition_every
  # @see #partition_rand
  # @see #select_x_of_y
  # @see #reject_x_of_y
  # @see #clear_x_of_y
  # @see #clear_except_x_of_y
  def partition_x_of_y(x, y, drop: true, skip_empty: false)
    raise TypeError, "x and y must be integers" unless x.is_a?(Integer) && y.is_a?(Integer)
    raise RangeError, "x and y must be > 0" unless x > 0 && y > 0
    raise RangeError, "x must be <= y" unless x <= y

    i = 0
    partition_slots(drop: drop) do |slot|
      next false if skip_empty && slot.empty?

      extract_this = i % y == x - 1
      i += 1
      extract_this
    end
  end
  alias grouped_partition partition_x_of_y
  alias gpartition partition_x_of_y

  # Returns a new track containing only slots in the `x`th slot of each group of
  # `y`.
  # 
  # If no slots are selected, returns nil.
  #
  # This returns exactly the first track from a call to {#partition_x_of_y}.
  # This method's complement is {#reject_x_of_y}. To convert unselected slots to
  # rests, rather than removing them entirely, use {#clear_except_x_of_y}. To
  # clear slots this method would select, use {#clear_x_of_y}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1,
  #         :d1, :e1, :f1]
  #
  #   t.select_x_of_y(2, 3)
  #   # is equivalent to
  #   T[:b1, :e1]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   select into the returned track. Must be greater than 0 and <= `y`.
  # @macro group_y_param
  # @macro skip_empty_param
  # @return [TrackBase, nil]
  # @see #partition_x_of_y
  # @see #reject_x_of_y
  # @see #clear_except_x_of_y
  # @see #clear_x_of_y
  # @see #select_slots
  # @see #select_every
  # @see #select_rand
  # @see #select_steps
  def select_x_of_y(x, y, skip_empty: false)
    t, = partition_x_of_y(x, y, skip_empty: skip_empty)
    t
  end
  alias grouped_select select_x_of_y
  alias gselect select_x_of_y
  alias filter_x_of_y select_x_of_y
  alias grouped_filter select_x_of_y
  alias gfilter select_x_of_y

  # Returns a new track excluding slots in the `x`th slot of each group of `y`.
  # 
  # If all slots are rejected, returns nil.
  #
  # This returns exactly the second track from a call to {#partition_x_of_y}.
  # This method's complement is {#select_x_of_y}. To convert selected slots to
  # rests, rather than removing them entirely, use {#clear_x_of_y}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1,
  #         :d1, :e1, :f1]
  #
  #   t.reject_x_of_y(2, 3)
  #   # is equivalent to
  #   T[:a1, :c1,
  #     :d1, :f1]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   reject. Must be greater than 0 and <= `y`.
  # @macro group_y_param
  # @macro skip_empty_param
  # @return [TrackBase, nil]
  # @see #partition_x_of_y
  # @see #select_x_of_y
  # @see #clear_x_of_y
  # @see #reject_slots
  # @see #reject_every
  # @see #reject_rand
  # @see #reject_steps
  def reject_x_of_y(x, y, skip_empty: false)
    _, t = partition_x_of_y(x, y, skip_empty: skip_empty)
    t
  end
  alias grouped_reject reject_x_of_y
  alias greject reject_x_of_y
  alias drop_x_of_y reject_x_of_y
  alias grouped_drop reject_x_of_y
  alias gdrop reject_x_of_y

  # Returns a new track clearing the `x`th slot in each group of `y`.
  # 
  # This method behaves exactly like {#reject_x_of_y} except that the length of
  # the track is maintained; selected slots are not removed, they are instead
  # replaced with rests.
  # 
  # This returns exactly the second track from a call to {#partition_x_of_y}
  # with `drop` set to false. This method's complement is
  # {#clear_except_x_of_y}. To remove slots rather than converting them to
  # rests, use {#reject_x_of_y}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1,
  #         :d1, :e1, :f1]
  #
  #   t.clear_x_of_y(2, 3)
  #   # is equivalent to
  #   T[:a1, :r, :c1,
  #     :d1, :r, :f1]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   clear. Must be greater than 0 and <= `y`.
  # @macro group_y_param
  # @macro skip_empty_param
  # @return [TrackBase]
  # @see #partition_x_of_y
  # @see #reject_x_of_y
  # @see #clear_except_x_of_y
  # @see #clear_slots
  # @see #clear_every
  # @see #clear_rand
  # @see #reject_steps
  def clear_x_of_y(x, y, skip_empty: false)
    _, t = partition_x_of_y(x, y, drop: false, skip_empty: skip_empty)
    t
  end
  alias grouped_clear clear_x_of_y
  alias gclear clear_x_of_y
  alias grouped_droput reject_x_of_y
  alias gdropout reject_x_of_y

  # Returns a new track clearing slots except the `x`th in each group of `y`
  # slots.
  # 
  # This is the complement of {#clear_x_of_y} and behaves exactly like it except
  # that the criteria for selecting slots is inverted. It returns exactly the
  # first track from a call to {#partition_x_of_y} with `drop` set to false. To
  # remove slots that this method converts to rests, use {#select_x_of_y}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1,
  #         :d1, :e1, :f1]
  #
  #   t.clear_except_x_of_y(2, 3)
  #   # is equivalent to
  #   T[:r, :b1, :r,
  #     :r, :e1, :r]
  #
  # @param x [Integer] Specifies the slot within each group of `y` slots to
  #   maintain. Must be greater than 0 and <= `y`.
  # @macro group_y_param
  # @macro skip_empty_param
  # @return [TrackBase]
  # @see #partition_x_of_y
  # @see #select_x_of_y
  # @see #clear_x_of_y
  # @see #clear_slots_except
  # @see #clear_every_except
  # @see #clear_except_rand
  # @see #reject_steps
  def clear_except_x_of_y(x, y, skip_empty: false)
    t, = partition_x_of_y(x, y, drop: false, skip_empty: skip_empty)
    t
  end


  ### partition_rand family

  # Returns two tracks, the first containing any given slot with probability
  # `p`, and the other the remaining slots.
  # 
  # @macro drop_desc
  # 
  # There is a family of methods providing functionality based on this one. To
  # select or reject slots with a given probability, see {#select_rand} and
  # {#reject_rand}. To clear slots, rather than removing them entirely, see
  # {#clear_rand} and {#clear_except_rand}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1]
  #
  #   u, v = t.partition_rand(0.25)
  #   # u might be equivalent to
  #   T[:a1, :c1]
  #   # and v would be the complement:
  #   T[:b1, :d1, :e1]
  #
  #   x, y = t.partition_rand(0)
  #   # x will be nil and y will be equivalent to t
  #
  #   p, r = t.partition_rand(1)
  #   # p will be equivalent to t and r will be nil
  #
  # @param p [Number] The probability that any given slot will be present in
  #   the first track, 0 - 1 inclusive.
  # @macro drop_param
  # @macro partition_return
  # @see #partition_steps
  # @see #partition_slots
  # @see #partition_every
  # @see #partition_x_of_y
  # @see #select_rand
  # @see #reject_rand
  # @see #clear_rand
  # @see #clear_except_rand
  def partition_rand(p = 0.5, drop: true)
    partition_slots(drop: drop) { SpiSeq::Random.chance(p) }
  end
  alias rand_partition partition_rand

  # Returns a new track containing slots from this one with probability `p`.
  # 
  # If no slots are selected, returns nil.
  #
  # This returns exactly the first track from a call to {#partition_rand}. This
  # method's complement is {#reject_rand}. To convert unselected slots to rests,
  # rather than removing them entirely, use {#clear_except_rand}. To clear
  # slots this method would select, use {#clear_rand}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1]
  #
  #   t.select_rand(0.75)
  #   # might be equivalent to
  #   T[:a1, :c1, :d1, :e1]
  #
  #   t.select_rand(1)  # always equivalent to t
  #   t.select_rand(0)  # always nil
  #
  # @param p [Number] The probability that any given slot will be present in
  #   the result, 0 - 1 inclusive.
  # @return [TrackBase, nil]
  # @see #partition_rand
  # @see #reject_rand
  # @see #clear_except_rand
  # @see #clear_rand
  # @see #select_slots
  # @see #select_every
  # @see #select_x_of_y
  # @see #select_steps
  # @see #sample
  def select_rand(p = 0.5)
    t, = rand_partition(p)
    t
  end
  alias rand_select select_rand
  alias rselect select_rand
  alias rand_filter select_rand
  alias filter_rand select_rand
  alias rfilter select_rand

  # Returns a new track excluding slots from this one with probability `p`.
  # 
  # If all slots are rejeted, returns nil.
  #
  # This returns exactly the second track from a call to {#partition_rand}. This
  # method's complement is {#select_rand}. To convert selected slots to rests,
  # rather than removing them entirely, use {#clear_rand}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1]
  #
  #   t.reject_rand(0.75)
  #   # might be equivalent to
  #   T[:a1, :e1]
  #
  #   t.reject_rand(0)  # always equivalent to t
  #   t.reject_rand(1)  # always nil
  #
  # @param p [Number] The probability that any given slot will be removed from
  #   the result, 0 - 1 inclusive.
  # @return [TrackBase, nil]
  # @see #partition_rand
  # @see #select_rand
  # @see #clear_rand
  # @see #reject_slots
  # @see #reject_every
  # @see #reject_x_of_y
  # @see #reject_steps
  def reject_rand(p = 0.5)
    _, t = rand_partition(p)
    t
  end
  alias rand_reject reject_rand
  alias rreject reject_rand
  alias rand_drop reject_rand
  alias drop_rand reject_rand
  alias rdrop reject_rand

  # Returns a new track by clearing slots with probability `p`.
  # 
  # This method behaves exactly like {#reject_rand} except that the length of
  # the track is maintained; selected slots are not removed, they are instead
  # replaced with rests.
  # 
  # This returns exactly the second track from a call to {#partition_rand} with
  # `drop` set to false. This method's complement is {#clear_except_rand}. To
  # remove slots rather than converting them to rests, use {#reject_rand}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1]
  #
  #   t.clear_rand(0.75)
  #   # might be equivalent to
  #   T[:a1, :r, :r, :d1, :r]
  #
  #   t.clear_rand(0)  # always equivalent to t
  #   t.clear_rand(1)  # always entirely rests
  #
  # @param p [Number] The probability that any given slot will be cleared in
  #   the result, 0 - 1 inclusive.
  # @return [TrackBase]
  # @see #partition_rand
  # @see #reject_rand
  # @see #clear_except_rand
  # @see #clear_slots
  # @see #clear_every
  # @see #clear_x_of_y
  # @see #reject_steps
  def clear_rand(p = 0.5)
    _, t = rand_partition(p, drop: false)
    t
  end
  alias rand_clear clear_rand
  alias rclear clear_rand
  alias rand_dropout clear_rand
  alias rdropout clear_rand

  # Returns a new track clearing slots with probability `1 - p`.
  # 
  # This is the complement of {#clear_rand} and behaves exactly like it except
  # that the criteria for selecting slots is inverted. It returns exactly the
  # first track from a call to {#partition_rand} with `drop` set to false. To
  # remove slots that this method converts to rests, use {#select_rand}.
  # 
  # @example
  #   t = T[:a1, :b1, :c1, :d1, :e1]
  #
  #   t.clear_rand_except(0.75)
  #   # might be equivalent to
  #   T[:r, :b1, :c1, :d1, :r]
  #
  #   t.clear_rand_except(1)  # always equivalent to t
  #   t.clear_rand_except(0)  # always entirely resets
  #
  # @param p [Number] The probability that any given slot will not be cleared in
  #   the result, 0 - 1 inclusive.
  # @return [TrackBase]
  # @see #partition_rand
  # @see #select_rand
  # @see #clear_rand
  # @see #clear_slots_except
  # @see #clear_every_except
  # @see #clear_except_x_of_y
  # @see #reject_steps
  def clear_except_rand(p = 0.5)
    t, = rand_partition(p, drop: false)
    t
  end
  alias clear_rand_except clear_except_rand
  alias rand_clear_except clear_except_rand
end
