#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../track"
require_relative "track_test_helpers"

# Test Track's grid manipulation methods.
# Boundary's a little fuzzy here, but this is mostly things that deal with the
# grid as a whole, or that act on slots rather than directly on the steps within
# them.
class TrackGridTest < Test::Unit::TestCase
  include TrackTestHelpers

  def assert_mutate_slots(track, grid, &block)
    t = track.mutate_each_slot(&block)
    assert_grid t, grid
  end

  def test_mutate_each_slot
    t = T[:a1, [:b2, :b3], :c3]

    assert_mutate_slots(t, [[:f9], [:f9], [:f9]]) { |_| :f9 }
    assert_mutate_slots(t, [[:f9], [:f9], [:f9]]) { |_, _| :f9 }
    assert_mutate_slots(t, [[:f9], [:f9], [:f9]]) { |_, _, _| :f9 }

    [[], nil, :r, :rest].each do |rest|
      assert_mutate_slots(t, [[], [], []]) { |_| rest }
    end

    assert_mutate_slots(t, [[:a1], [:b2, :b3], [:c3]]) { |slot| slot }
    assert_mutate_slots(t, [[:a1], [:f9], [:c3]]) { |slot| (slot.length == 2) ? [:f9] : slot }
    assert_mutate_slots(t, [[:f8, :f9], [:b2, :b3], [:f8, :f9]]) { |slot| (slot.length == 2) ? slot : [:f8, :f9] }

    assert_mutate_slots(t, [[:a1], [:f9], [:c3]]) { |slot, idx| (idx == 1) ? [:f9] : slot }

    # rubocop:disable Lint/FloatComparison
    assert_mutate_slots(t, [[:f9], [:b2, :b3], [:c3]]) { |slot, _, pct| (pct == 0) ? [:f9] : slot }
    assert_mutate_slots(t, [[:a1], [:f9], [:c3]]) { |slot, _, pct| (pct == 0.5) ? [:f9] : slot }
    assert_mutate_slots(t, [[:a1], [:b2, :b3], [:f9]]) { |slot, _, pct| (pct == 1) ? [:f9] : slot }
    # rubocop:enable Lint/FloatComparison

    # Returning something gridish from the block.
    assert_mutate_slots(t, [[:a1], [:f8], [:f9], [:c3]]) { |slot, idx| (idx == 1) ? [[:f8], [:f9]] : slot }
    assert_mutate_slots(t, [[:c3, :c4], [:f8], [:f9], [:g7], [:g8], [:a2, :a3]]) do |_, idx|
      if idx == 1
        [[:f8], [:f9]]
      elsif idx == 2
        [:g7, :g8, [:a2, :a3]]  # Interpreted as a grid, since it contains an array
      else
        [:c3, :c4]  # Interpreted as a slot
      end
    end
  end

  def test_append
    assert_merge_strictness :+

    assert_grid T[:c4] + T[:d4], [[:c4], [:d4]]
    assert_grid T[:c4] + :d4, [[:c4], [:d4]]
    assert_grid T[:c4] + Track.rest(2), [[:c4], [], []]
    assert_grid T[:c4] + :r, [[:c4], []]
    assert_grid T[:c4] + [:r, [:d5, :e5]], [[:c4], [], [:d5, :e5]]

    assert_gt T[:c4, granularity: :whole, timescale: 2] + T[:c4, granularity: :whole, timescale: 2], NoteLength::Whole, 2
  end

  def test_merge
    assert_merge_strictness :|

    assert_grid T[:c4] | T[:d4], [[:c4, :d4]]
    assert_grid T[:c4] | :d4, [[:c4, :d4]]
    assert_grid T[:c4] | [:d4], [[:c4, :d4]]
    assert_grid T[:c4] | T[:c4], [[:c4]]  # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
    assert_grid T[:r, :d4] | T[:c4, :r], [[:c4], [:d4]]
    assert_grid T[:r, :d4] | [:c4, :r], [[:c4], [:d4]]
    assert_grid T[[:a1, :b2], [:d4, :e5]] | T[:c3, :f6], [[:a1, :b2, :c3], [:d4, :e5, :f6]]

    # Differing lengths: the result should be the length of the longest track.
    assert_grid T[:c4] | T[:d4, :f4], [[:c4, :d4], [:f4]]
    assert_grid T[:d4, :f4] | T[:c4], [[:c4, :d4], [:f4]]
    assert_grid T[:d4, :f4] | :c4, [[:c4, :d4], [:f4]]
    assert_grid T[:d4, :f4] | [:c4, :g4], [[:c4, :d4], [:f4, :g4]]
    assert_grid T[:c4] | Track.rest(5), [[:c4], [], [], [], []]
  end

  def test_grouped_merge
    t = T[:a1, :b2, :c3, :d4, :e5, :f6]

    # Even division
    assert_grid t.group(1), [[:a1], [:b2], [:c3], [:d4], [:e5], [:f6]]
    assert_grid t.group(2), [[:a1, :b2], [:c3, :d4], [:e5, :f6]]
    assert_grid t.group(3), [[:a1, :b2, :c3], [:d4, :e5, :f6]]
    assert_grid t.group(6), [[:a1, :b2, :c3, :d4, :e5, :f6]]

    # Uneven division
    assert_grid t.group(4), [[:a1, :b2, :c3, :d4], [:e5, :f6]]
    assert_grid t.group(5), [[:a1, :b2, :c3, :d4, :e5], [:f6]]

    # Group size > track length
    assert_grid t.group(7), [[:a1, :b2, :c3, :d4, :e5, :f6]]
    assert_grid t.group(20), [[:a1, :b2, :c3, :d4, :e5, :f6]]
  end

  def test_zip
    assert_merge_strictness :zip

    t = T[:a1, :b2, :c3, :d4]

    assert_grid t.zip(T[:f6]), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.zip(:f6), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.zip([:f6]), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.zip([[:f6]]), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]

    assert_grid t.zip(T[:f6], cycle: false), [[:a1], [:f6], [:b2], [], [:c3], [], [:d4], []]
    assert_grid t.zip(T[:f6], cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:c3], [:d4]]

    assert_grid t.zip(T[:f6, :g6]), [[:a1], [:f6], [:b2], [:g6], [:c3], [:f6], [:d4], [:g6]]
    assert_grid t.zip(T[:f6, :g6], cycle: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [], [:d4], []]
    assert_grid t.zip(T[:f6, :g6], cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [:d4]]
  end

  def test_grouped_zip
    assert_merge_strictness :gzip, 1, 1

    t = T[:a1, :b2, :c3, :d4]

    assert_grid t.gzip(T[:f6], 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip(:f6, 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip([:f6], 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip([[:f6]], 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip(T[:f6], 1, 1, cycle: false), [[:a1], [:f6], [:b2], [], [:c3], [], [:d4], []]
    assert_grid t.gzip(T[:f6], 1, 1, cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:c3], [:d4]]

    assert_grid t.gzip(T[:f6], 2, 1), [[:a1], [:b2], [:f6], [:c3], [:d4], [:f6]]
    assert_grid t.gzip(T[:f6], 2, 1, cycle: false), [[:a1], [:b2], [:f6], [:c3], [:d4], []]
    assert_grid t.gzip(T[:f6], 2, 1, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:f6], [:c3], [:d4]]

    assert_grid t.gzip(T[:f6], 3, 1), [[:a1], [:b2], [:c3], [:f6], [:d4], [:a1], [:b2], [:f6]]
    assert_grid t.gzip(T[:f6], 3, 1, cycle: false), [[:a1], [:b2], [:c3], [:f6], [:d4], [], [], []]
    assert_grid t.gzip(T[:f6], 3, 1, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:c3], [:f6], [:d4]]

    assert_grid t.gzip(T[:f6], 4, 1), [[:a1], [:b2], [:c3], [:d4], [:f6]]

    assert_grid t.gzip(T[:f6, :g6], 1, 1), [[:a1], [:f6], [:b2], [:g6], [:c3], [:f6], [:d4], [:g6]]
    assert_grid t.gzip(T[:f6, :g6], 1, 1, cycle: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [], [:d4], []]
    assert_grid t.gzip(T[:f6, :g6], 1, 1, cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [:d4]]

    assert_grid t.gzip(T[:f6, :g6], 2, 1), [[:a1], [:b2], [:f6], [:c3], [:d4], [:g6]]

    assert_grid t.gzip(T[:f6, :g6], 3, 1), [[:a1], [:b2], [:c3], [:f6], [:d4], [:a1], [:b2], [:g6]]
    assert_grid t.gzip(T[:f6, :g6], 3, 1, cycle: false), [[:a1], [:b2], [:c3], [:f6], [:d4], [], [], [:g6]]

    # Sizes greater than either track
    assert_grid t.gzip(T[:f6], 6, 1), [[:a1], [:b2], [:c3], [:d4], [:a1], [:b2], [:f6]]
    assert_grid t.gzip(T[:f6], 6, 1, cycle: false), [[:a1], [:b2], [:c3], [:d4], [], [], [:f6]]
    assert_grid t.gzip(T[:f6], 6, 1, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:c3], [:d4], [:f6]]

    assert_grid t.gzip(T[:f6, :g6], 2, 3), [[:a1], [:b2], [:f6], [:g6], [:f6], [:c3], [:d4], [:g6], [:f6], [:g6]]
    assert_grid t.gzip(T[:f6, :g6], 2, 3, cycle: false), [[:a1], [:b2], [:f6], [:g6], [], [:c3], [:d4], [], [], []]
    assert_grid t.gzip(T[:f6, :g6], 2, 3, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:f6], [:g6], [:c3], [:d4]]

    # Lil guys
    assert_grid T[:c4].gzip([:d4, :e4], 1, 1), [[:c4], [:d4]]
    assert_grid T[:c4].gzip([:d4, :e4], 1, 2), [[:c4], [:d4], [:e4]]
    assert_grid T[:c4].gzip([:d4, :e4], 2, 1), [[:c4], [:c4], [:d4]]
    assert_grid T[:c4].gzip([:d4, :e4], 2, 1, cycle: false), [[:c4], [], [:d4]]
    assert_grid T[:c4].gzip([:d4, :e4], 2, 1, cycle: false, pad_with_rests: false), [[:c4], [:d4]]
  end

  def test_each_cons
    t = T[:a1, :b2, :c3, :d4]

    assert_grid t.each_cons(1), [[:a1], [:b2], [:c3], [:d4]]
    assert_grid t.each_cons(1, flatten: false), [[:a1], [:b2], [:c3], [:d4]]
    assert_grid t.each_cons(2), [[:a1], [:b2], [:b2], [:c3], [:c3], [:d4]]
    assert_grid t.each_cons(2, flatten: false), [[:a1, :b2], [:b2, :c3], [:c3, :d4]]
    assert_grid t.each_cons(3), [[:a1], [:b2], [:c3], [:b2], [:c3], [:d4]]
    assert_grid t.each_cons(3, flatten: false), [[:a1, :b2, :c3], [:b2, :c3, :d4]]
    assert_grid t.each_cons(4), [[:a1], [:b2], [:c3], [:d4]]
    assert_grid t.each_cons(4, flatten: false), [[:a1, :b2, :c3, :d4]]

    assert_raises { t.each_cons(5) }
  end

  def test_permutation_combination
    # Order on these is indeterminate, so this is questionable test. Safe to
    # assume it'll match the methods on Array though.
    grid = [[:c1], [:c2, :c3], [:c4, :c5, :c6], [:a1]]
    assert_grid T.from_grid(grid).permutation, grid.permutation.to_a.flatten(1)

    1.upto(grid.length) do |n|
      assert_grid T.from_grid(grid).permutation(n), grid.permutation(n).to_a.flatten(1)
      assert_grid T.from_grid(grid).combination(n), grid.combination(n).to_a.flatten(1)
    end
  end

  def test_repeat
    t = T[:a1, :b2]

    assert_raises { t * 0 }
    assert_grid t * 1, t.grid
    assert_grid t * 2, [[:a1], [:b2], [:a1], [:b2]]
    assert_grid t * 3, [[:a1], [:b2], [:a1], [:b2], [:a1], [:b2]]
  end

  def test_cycle_to_length
    t = T[:a1, :b2, :c3]

    assert_raises { t.cycle_to_length(0) }
    assert_grid t.cycle_to_length(1), [[:a1]]
    assert_grid t.cycle_to_length(2), [[:a1], [:b2]]
    assert_grid t.cycle_to_length(3), [[:a1], [:b2], [:c3]]
    assert_grid t.cycle_to_length(4), [[:a1], [:b2], [:c3], [:a1]]
    assert_grid t.cycle_to_length(5), [[:a1], [:b2], [:c3], [:a1], [:b2]]
    assert_grid t.cycle_to_length(6), [[:a1], [:b2], [:c3], [:a1], [:b2], [:c3]]
  end

  def test_repeat_slots
    t = T[:a1, :r, [:b1, :c1]]

    assert_raises(ArgumentError) { t.repeat_slots(0) }
    assert_raises(ArgumentError) { t.repeat_slots(0.5) }
    assert_grid t.repeat_slots(1), t.grid
    assert_grid t.repeat_slots, [[:a1], [:a1], [], [], [:b1, :c1], [:b1, :c1]]
    assert_grid t.repeat_slots(2), t.repeat_slots.grid
    assert_grid t.repeat_slots(3), [[:a1], [:a1], [:a1],
                                    [], [], [],
                                    [:b1, :c1], [:b1, :c1], [:b1, :c1]]
  end

  def test_compact
    assert_grid T[:r, :r, :a1, :r, :b2, :r, :r, :c3, :r].compact, [[:a1], [:b2], [:c3]]
    assert_raises { Track.rest.compact }
  end

  def test_trim
    t = T[:r, :r, :a1, :b2, :r, :c3, :r, :r, :r]

    assert_grid t.ltrim, [[:a1], [:b2], [], [:c3], [], [], []]
    assert_grid t.rtrim, [[], [], [:a1], [:b2], [], [:c3]]
    assert_grid t.trim, [[:a1], [:b2], [], [:c3]]

    assert_raises { Track.rest(2).ltrim }
    assert_raises { Track.rest(2).rtrim }
    assert_raises { Track.rest(2).trim }
  end

  def test_reverse
    assert_grid T[:c4].rev, [[:c4]]
    assert_grid T[:a1, :b2].rev, [[:b2], [:a1]]
    assert_grid T[:a1, :r, :b2].rev, [[:b2], [], [:a1]]
    assert_grid T[:a1, :r, :b2, :c3].rev, [[:c3], [:b2], [], [:a1]]
    assert_grid T[:a1, :r, :b2, [:c3, :d4]].rev, [[:c3, :d4], [:b2], [], [:a1]]
  end

  def test_mirror
    # Repeats the slot in the middle.
    assert_grid T[:c4].mirror, [[:c4], [:c4]]
    assert_grid T[:a1, :b2].mirror, [[:a1], [:b2], [:b2], [:a1]]
    assert_grid T[:a1, [:b2, :c3]].mirror, [[:a1], [:b2, :c3], [:b2, :c3], [:a1]]
    assert_grid T[:a1, :r].mirror, [[:a1], [], [], [:a1]]
    assert_grid T[:a1, :b2, :c3].mirror, [[:a1], [:b2], [:c3], [:c3], [:b2], [:a1]]
  end

  def test_reflect
    # Does not repeat the slot in the middle.
    assert_grid T[:c4].reflect, [[:c4]]
    assert_grid T[:a1, :b2].reflect, [[:a1], [:b2], [:a1]]
    assert_grid T[:a1, [:b2, :c3]].reflect, [[:a1], [:b2, :c3], [:a1]]
    assert_grid T[:a1, :r].reflect, [[:a1], [], [:a1]]
    assert_grid T[:a1, :b2, :c3].reflect, [[:a1], [:b2], [:c3], [:b2], [:a1]]
  end

  def test_shuffle
    assert_grid T[:c4].shuffle, [[:c4]]

    unless ExtApi.in_sonic_pi?  # Not testing Sonic Pi's randomness
      srand 1234
      # Inexplicably, Array.shuffle does nothing immediately after an srand?
      assert_grid T[:a1, :b2, :c3, :d4].shuffle, [[:a1], [:b2], [:c3], [:d4]]
      assert_grid T[:a1, :b2, :c3, :d4].shuffle, [[:b2], [:c3], [:d4], [:a1]]
    end
  end

  def test_shuffle_filled_slots
    assert_grid T[:c4].shuffle_filled, [[:c4]]
    assert_grid T[:c4, :r].shuffle_filled, [[:c4], []]
    assert_grid Track.rest(2).shuffle_filled, [[], []]

    t = T[:a1, :r, :r, :b2, [:c3, :d4]]
    unless ExtApi.in_sonic_pi?  # Not testing Sonic Pi's randomness
      srand 1234
      # Inexplicably, Array.shuffle does nothing immediately after an srand?
      assert_grid t.shuffle_filled, [[:a1], [], [], [:b2], [:c3, :d4]]
      assert_grid t.shuffle_filled, [[:b2], [], [], [:c3, :d4], [:a1]]
      assert_grid t.shuffle_filled, [[:c3, :d4], [], [], [:b2], [:a1]]
    end
  end

  def test_rotate
    assert_grid T[:c4].shl, [[:c4]]
    assert_grid T[:c4].shl(5), [[:c4]]
    assert_grid T[:c4].shr, [[:c4]]
    assert_grid T[:c4].shr(5), [[:c4]]

    assert_grid T[:a1, :b2].shl, [[:b2], [:a1]]
    assert_grid T[:a1, :b2].shl(2), [[:a1], [:b2]]
    assert_grid T[:a1, :b2].rotate(2), [[:a1], [:b2]]
    assert_grid T[:a1, :b2].shl(3), [[:b2], [:a1]]
    assert_grid T[:a1, :b2].shr, [[:b2], [:a1]]
    assert_grid T[:a1, :b2].shr(2), [[:a1], [:b2]]
    assert_grid T[:a1, :b2].rotate(-2), [[:a1], [:b2]]
    assert_grid T[:a1, :b2].shr(3), [[:b2], [:a1]]

    assert_grid T[:a1, :b2, :c3].shl, [[:b2], [:c3], [:a1]]
    assert_grid T[:a1, :b2, :c3].shl(2), [[:c3], [:a1], [:b2]]
    assert_grid T[:a1, :b2, :c3].rotate(2), [[:c3], [:a1], [:b2]]
    assert_grid T[:a1, :b2, :c3].shl(3), [[:a1], [:b2], [:c3]]
    assert_grid T[:a1, :b2, :c3].shl(4), [[:b2], [:c3], [:a1]]
    assert_grid T[:a1, :b2, :c3].shr, [[:c3], [:a1], [:b2]]
    assert_grid T[:a1, :b2, :c3].shr(2), [[:b2], [:c3], [:a1]]
    assert_grid T[:a1, :b2, :c3].rotate(-2), [[:b2], [:c3], [:a1]]
    assert_grid T[:a1, :b2, :c3].shr(3), [[:a1], [:b2], [:c3]]
    assert_grid T[:a1, :b2, :c3].shr(4), [[:c3], [:a1], [:b2]]
  end

  def test_pad
    assert_grid T[:c4].left_pad, [[], [:c4]]
    assert_grid T[:c4].left_pad(2), [[], [], [:c4]]
    assert_grid T[:c4].right_pad(1), [[:c4], []]
    assert_grid T[:c4].right_pad(2), [[:c4], [], []]

    assert_grid T[:a1, :b2].left_pad(2), [[], [], [:a1], [:b2]]
    assert_grid T[:a1, :b2].right_pad(2), [[:a1], [:b2], [], []]
  end

  def test_space
    assert_grid T[:c4].space, [[:c4], []]
    assert_grid T[:c4].space(2), [[:c4], [], []]

    assert_grid T[:a1, :b2].space, [[:a1], [], [:b2], []]
    assert_grid T[:a1, :b2].space(2), [[:a1], [], [], [:b2], [], []]
  end

  def test_space_every
    assert_grid T[:c4].space_every(1), [[:c4], []]
    assert_grid T[:c4].space_every(1, 2), [[:c4], [], []]
    assert_grid T[:c4].space_every(2), [[:c4], []]
    assert_grid T[:c4].space_every(2, 2), [[:c4], [], []]

    assert_grid T[:a1, :b2, :c3].space_every(1), [[:a1], [], [:b2], [], [:c3], []]
    assert_grid T[:a1, :b2, :c3].space_every(1, 2), [[:a1], [], [], [:b2], [], [], [:c3], [], []]
    assert_grid T[:a1, :b2, :c3].space_every(2), [[:a1], [:b2], [], [:c3], []]
    assert_grid T[:a1, :b2, :c3].space_every(3), [[:a1], [:b2], [:c3], []]
    assert_grid T[:a1, :b2, :c3].space_every(3, 2), [[:a1], [:b2], [:c3], [], []]
    assert_grid T[:a1, :b2, :c3].space_every(4), [[:a1], [:b2], [:c3], []]
    assert_grid T[:a1, :b2, :c3].space_every(4, 2), [[:a1], [:b2], [:c3], [], []]
  end

  def test_drop
    assert_raises { T[:c4].drop }
    assert_raises { T[:a1, :a2].drop(2) }
    assert_raises { T[:a1, :a2].drop(5) }

    t = T[:a1, :b2, :c3]
    assert_grid t.drop(0), t.grid
    assert_grid t.drop, [[:b2], [:c3]]
    assert_grid t.drop(1), [[:b2], [:c3]]
    assert_grid t.drop(2), [[:c3]]

    assert_raises { T[:c4].drop_last }
    assert_raises { T[:a1, :a2].drop_last(2) }
    assert_raises { T[:a1, :a2].drop_last(5) }

    t = T[:a1, :b2, :c3]
    assert_grid t.drop_last(0), t.grid
    assert_grid t.drop_last, [[:a1], [:b2]]
    assert_grid t.drop_last(1), [[:a1], [:b2]]
    assert_grid t.drop(-1), [[:a1], [:b2]]
    assert_grid t.drop_last(2), [[:a1]]
    assert_grid t.drop(-2), [[:a1]]
  end

  def test_take
    assert_raises { T[:c4].take(0) }

    t = T[:a1, :b2, :c3]
    assert_grid t.take(1), [[:a1]]
    assert_grid t.take(2), [[:a1], [:b2]]
    assert_grid t.take(3), [[:a1], [:b2], [:c3]]
    assert_grid t.take(4), [[:a1], [:b2], [:c3]]

    assert_grid t.take(-1), [[:c3]]
    assert_grid t.take_last, [[:c3]]
    assert_grid t.take_last(1), [[:c3]]
    assert_grid t.take(-2), [[:b2], [:c3]]
    assert_grid t.take_last(2), [[:b2], [:c3]]
    assert_grid t.take(-3), [[:a1], [:b2], [:c3]]
    assert_grid t.take_last(3), [[:a1], [:b2], [:c3]]
  end

  def test_slice
    assert_grid T[:c4][0], [[:c4]]
    assert_grid T[:c4][-1], [[:c4]]
    assert_raises(IndexError) { T[:c4][1] }

    t = T[:a1, :b2, :c3]
    assert_grid t[0], [[:a1]]
    assert_grid t[1], [[:b2]]
    assert_grid t[2], [[:c3]]
    assert_grid t[-1], [[:c3]]
    assert_grid t[-2], [[:b2]]
    assert_grid t[-3], [[:a1]]

    assert_grid t[0, 1], [[:a1]]
    assert_grid t[0, 2], [[:a1], [:b2]]
    assert_grid t[1, 2], [[:b2], [:c3]]
    assert_grid t[1, 3], [[:b2], [:c3]]
    assert_grid t[-2, 2], [[:b2], [:c3]]
    assert_grid t[-3, 1], [[:a1]]

    assert_grid t[0...1], [[:a1]]
    assert_grid t[0..1], [[:a1], [:b2]]
    assert_grid t[1...3], [[:b2], [:c3]]
    assert_grid t[1..3], [[:b2], [:c3]]
    assert_grid t[-3..-2], [[:a1], [:b2]]
  end

  def test_sample
    assert_raises { T[:c4].sample(0) }
    assert_grid T[:c4].sample(1), [[:c4]]
    assert_grid T[:c4].sample(2), [[:c4]]

    unless ExtApi.in_sonic_pi?  # Not testing Sonic Pi's randomness
      srand 1234
      t = T[:a1, :b2, :r, :c3, :d4]
      assert_grid t.sample(5), [[:a1], [:b2], [], [:c3], [:d4]]
      assert_grid t.sample(4), [[:a1], [:b2], [], [:c3]]
      assert_grid t.sample(3), [[:a1], [], [:d4]]
      assert_grid t.sample(2), [[:b2], [:d4]]
      assert_grid t.sample(1), [[:b2]]

      srand 789
      assert_grid t.sample_filled(5), [[:a1], [:b2], [:c3], [:d4]]
      assert_grid t.sample_filled(4), [[:a1], [:b2], [:c3], [:d4]]
      assert_grid t.sample_filled(3), [[:a1], [:b2], [:d4]]
      assert_grid t.sample_filled(2), [[:b2], [:c3]]
      assert_grid t.sample_filled(1), [[:c3]]
    end
  end

  def test_drop_every
    assert_raises { T[:c4].dropout }
    assert_raises { T[:c4].dropout(0) }
    assert_raises { T[:c4].dropout(-1) }
    assert_raises { T[:c4].dropout(1, 0) }
    assert_raises { T[:c4].dropout("nope") }

    assert_grid T[:c4].dropout(1), [[]]

    t = T[:a1, :b2, :c3, :d4]
    assert_grid t.dropout(1), [[], [], [], []]
    assert_grid t.dropout(2), [[:a1], [], [:c3], []]
    assert_grid t.dropout(3), [[:a1], [:b2], [], [:d4]]
    assert_grid t.dropout(4), [[:a1], [:b2], [:c3], []]
    assert_grid t.dropout(5), [[:a1], [:b2], [:c3], [:d4]]
    assert_grid t.dropout(10), [[:a1], [:b2], [:c3], [:d4]]

    t = T[:a1, :r, :b2, :r, :r, :c3]
    assert_grid t.dropout(1, skip_empty: true), [[], [], [], [], [], []]
    assert_grid t.dropout(2, skip_empty: true), [[:a1], [], [], [], [], [:c3]]
    assert_grid t.dropout(3, skip_empty: true), [[:a1], [], [:b2], [], [], []]
    assert_grid t.dropout(4, skip_empty: true), [[:a1], [], [:b2], [], [], [:c3]]

    # Multiple gaps
    t = T[*[:a1] * 12]
    assert_grid t.dropout(1, 3), [[], [:a1], [:a1], [], [], [:a1], [:a1], [], [], [:a1], [:a1], []]
    assert_grid t.dropout(2, 4), [[:a1], [], [:a1], [:a1], [:a1], [], [:a1], [], [:a1], [:a1], [:a1], []]
    assert_grid t.dropout(2, 3, 4), [[:a1], [], [:a1], [:a1], [], [:a1], [:a1], [:a1], [], [:a1], [], [:a1]]

    t = T[*[:a1, :r] * 6]
    assert_grid t.dropout(1, 3, skip_empty: true),
      [
        [], [],    # drop (1), rest
        [:a1], [], # keep (3), rest
        [:a1], [], # keep (3), rest
        [], [],    # drop (3), rest
        [], [],    # drop (1), rest
        [:a1], []  # keep (3), rest
      ]
  end

  def test_drop_x_of_y
    t = T[*[:a1] * 12]

    assert_raises { t.gdrop(1, 0) }
    assert_raises { t.gdrop(0, 1) }
    assert_raises { t.gdrop(-1, 2) }
    assert_raises { t.gdrop(5, 3) }
    assert_raises { t.gdrop(0.25, 1) }

    assert_grid t.gdrop(1, 3), [[], [:a1], [:a1]] * 4
    assert_grid t.gdrop(2, 3), [[:a1], [], [:a1]] * 4
    assert_grid t.gdrop(3, 3), [[:a1], [:a1], []] * 4

    assert_grid t.gdrop(1, 5), [[], [:a1], [:a1], [:a1], [:a1]] * 2 + [[], [:a1]]
    assert_grid t.gdrop(3, 5), [[:a1], [:a1], [], [:a1], [:a1]] * 2 + [[:a1], [:a1]]

    assert_grid t.gdrop(2, 15), [[:a1], []] + [[:a1]] * 10

    # this is useless but shouldn't be an error
    assert_grid t.gdrop(1, 1), [[]] * 12

    t = T[*[:a1, :r] * 6]
    assert_grid t.gdrop(2, 3, skip_empty: true),
      [
        [:a1], [],
        [], [],
        [:a1], []
      ] * 2
  end

  def test_rand_dropout
    assert_grid T[:c4].rdropout(1), [[]]
    assert_grid T[:c4].rdropout(0), [[:c4]]

    t = T[:a1, :b2, :c3, :d4]
    assert_grid t.rdropout(1), [[], [], [], []]
    assert_grid t.rdropout(0), [[:a1], [:b2], [:c3], [:d4]]

    unless ExtApi.in_sonic_pi?  # Not testing Sonic Pi's randomness
      srand 1234
      assert_grid t.rdropout, [[], [:b2], [], [:d4]]
    end
  end

  def test_replace_slot
    assert_grid T[:c4].set_slot(0, [:d5, :e5]), [[:d5, :e5]]
    assert_raises { T[:c4].set_slot(2, [:d5]) }

    t = T[:a1, :b2, :c3]
    assert_grid t.set_slot(0, [:f9]), [[:f9], [:b2], [:c3]]
    assert_grid t.set_slot(1, [:f9]), [[:a1], [:f9], [:c3]]
    assert_grid t.set_slot(2, [:f9]), [[:a1], [:b2], [:f9]]

    assert_grid t.set_slot(2, [S(:f9, gate: 0.5), :c5]), [[:a1], [:b2], [S(:f9, gate: 0.5), :c5]]

    [:r, :rest, nil].each do |rest|
      assert_grid t.set_slot(1, rest), [[:a1], [], [:c3]]
    end

    # Negative indexes
    assert_grid t.set_slot(-1, [:f9]), [[:a1], [:b2], [:f9]]
    assert_grid t.set_slot(-2, [:f9]), [[:a1], [:f9], [:c3]]
    assert_grid t.set_slot(-3, [:f9]), [[:f9], [:b2], [:c3]]
  end

  def test_clear_slot
    t = T[:a1, [:b2, :c3], :r]
    assert_grid t.clear_slot(0), [[], [:b2, :c3], []]
    assert_grid t.clear_slot(1), [[:a1], [], []]
    assert_grid t.clear_slot(2), [[:a1], [:b2, :c3], []]
    assert_grid t.clear_slot(3), t.grid  # does nothing

    t = T[:a1, :b1, :c1, :d1, :e1]
    assert_grid t.clear_slot(0, 5), [[], [], [], [], []]
    assert_grid t.clear_slot(0, 6), [[], [], [], [], []]  # the step outside the range was ignored
    assert_grid t.clear_slot(1, 3), [[:a1], [], [], [], [:e1]]
    assert_grid t.clear_slot(2, 2), [[:a1], [:b1], [], [], [:e1]]
    assert_grid t.clear_slot(2, 3), [[:a1], [:b1], [], [], []]
    assert_grid t.clear_slot(5, -9), t.grid  # the range is effectively empty; does nothing

    assert_grid t.clear_slot(0..5), [[], [], [], [], []]
    assert_grid t.clear_slot(0..10), [[], [], [], [], []]  # the step outside the range was ignored
    assert_grid t.clear_slot(1..3), [[:a1], [], [], [], [:e1]]
    assert_grid t.clear_slot(2..3), [[:a1], [:b1], [], [], [:e1]]
    assert_grid t.clear_slot(2..4), [[:a1], [:b1], [], [], []]

    assert_raises(TypeError) { t.clear_slot(:nope) }
    assert_raises(TypeError) { t.clear_slot(5, :nope) }
    assert_raises(TypeError) { t.clear_slot(0..1, 3) }

    # Open ranges
    assert_grid t.clear_slot(..2), [[], [], [], [:d1], [:e1]]
    assert_grid t.clear_slot(2..), [[:a1], [:b1], [], [], []]

    # Negative indexes
    t = T[:a1, :b1, :c1, :d1]
    assert_grid t.clear_slot(-1), [[:a1], [:b1], [:c1], []]
    assert_grid t.clear_slot(-2), [[:a1], [:b1], [], [:d1]]
    assert_grid t.clear_slot(-3, 2), [[:a1], [], [], [:d1]]
    assert_grid t.clear_slot(-4..-2), [[], [], [], [:d1]]
    assert_grid t.clear_slot(-3..), [[:a1], [], [], []]
    assert_grid t.clear_slot(..-3), [[], [], [:c1], [:d1]]
  end

  def test_clear_filled_slot
    t = T[:a1, :b1, :r, :c1]
    assert_grid t.clear_filled_slot(0), [[], [:b1], [], [:c1]]
    assert_grid t.clear_filled_slot(1), [[:a1], [], [], [:c1]]
    assert_grid t.clear_filled_slot(2), [[:a1], [:b1], [], []]
    assert_grid t.clear_filled_slot(3), [[:a1], [:b1], [], [:c1]]  # does nothing
    assert_grid t.clear_filled_slot(-1), [[:a1], [:b1], [], []]
    assert_grid t.clear_filled_slot(-2), [[:a1], [], [], [:c1]]
    assert_grid t.clear_filled_slot(-3), [[], [:b1], [], [:c1]]
    assert_grid t.clear_filled_slot(-4), [[:a1], [:b1], [], [:c1]]  # does nothing

    assert_grid t.clear_filled_slot(0, 2), [[], [], [], [:c1]]
    assert_grid t.clear_filled_slot(0, 3), [[], [], [], []]
    assert_grid t.clear_filled_slot(1, 2), [[:a1], [], [], []]
    assert_grid t.clear_filled_slot(1, 10), [[:a1], [], [], []]

    assert_grid t.clear_filled_slot(0..1), [[], [], [], [:c1]]
    assert_grid t.clear_filled_slot(0..2), [[], [], [], []]
    assert_grid t.clear_filled_slot(1..2), [[:a1], [], [], []]
    assert_grid t.clear_filled_slot(1..10), [[:a1], [], [], []]

    assert_grid t.clear_filled_slot(1..), [[:a1], [], [], []]
    assert_grid t.clear_filled_slot(2..), [[:a1], [:b1], [], []]
    assert_grid t.clear_filled_slot(..-2), [[], [], [], [:c1]]
  end

  def test_clear_last_slots_clear_last_filled_slots
    t = T[:a1, :b1, :r, :c1]
    assert_grid t.clear_last_filled_slot, [[:a1], [:b1], [], []]
    assert_grid t.clear_last_filled_slots(1), [[:a1], [:b1], [], []]
    assert_grid t.clear_last_filled_slots(2), [[:a1], [], [], []]
    assert_grid t.clear_last_filled_slots(3), [[], [], [], []]
    assert_grid t.clear_last_filled_slots(10), [[], [], [], []]
    assert_grid t.clear_last_filled_slots(0), [[:a1], [:b1], [], [:c1]]  # does nothing

    assert_grid t.clear_last_slot, [[:a1], [:b1], [], []]
    assert_grid t.clear_last_slots(1), [[:a1], [:b1], [], []]
    assert_grid t.clear_last_slots(2), [[:a1], [:b1], [], []]
    assert_grid t.clear_last_slots(3), [[:a1], [], [], []]
    assert_grid t.clear_last_slots(4), [[], [], [], []]
    assert_grid t.clear_last_slots(10), [[], [], [], []]
    assert_grid t.clear_last_slots(0), [[:a1], [:b1], [], [:c1]]  # does nothing
  end

  def test_append_slot
    assert_grid T[:c4].append_slot(0, [:d5, :e5]), [[:c4, :d5, :e5]]
    assert_raises { T[:c4].append_slot(2, [:d5]) }

    t = T[:a1, :b2, :c3]
    assert_grid t.append_slot(0, [:f9]), [[:a1, :f9], [:b2], [:c3]]
    assert_grid t.append_slot(1, [:f9]), [[:a1], [:b2, :f9], [:c3]]
    assert_grid t.append_slot(2, [:f9]), [[:a1], [:b2], [:c3, :f9]]

    assert_grid t.append_slot(2, [S(:f9, gate: 0.5), :c5]), [[:a1], [:b2], [:c3, S(:f9, gate: 0.5), :c5]]

    [:r, :rest, nil].each do |rest|
      assert_grid t.append_slot(1, rest), [[:a1], [:b2], [:c3]]
    end

    # Negative indexes
    t = T[:a1, :b2, :c3]
    assert_grid t.append_slot(-1, [:f9]), [[:a1], [:b2], [:c3, :f9]]
    assert_grid t.append_slot(-2, [:f9]), [[:a1], [:b2, :f9], [:c3]]
  end

  def assert_partition(track, a_grid, b_grid, method = :partition, *args, **kwargs, &block)
    a, b = track.send(method, *args, **kwargs, &block)
    assert_grid a, a_grid
    assert_grid b, b_grid

    # Test the corresponding filter method too, if there is one.
    filter_method = {
      partition: :filter,
      partition_slots: :filter_slots,
      partition_note: :filter_note
    }[method]

    assert_grid track.send(filter_method, *args, **kwargs, &block), a_grid unless filter_method.nil?
  end

  def test_partition
    t = T[:a1, [:b2, :b3], :c3]

    assert_partition(t, [[:a1], [:b2, :b3], [:c3]], [[], [], []]) { |_| true }
    assert_partition(t, [[], [], []], [[:a1], [:b2, :b3], [:c3]]) { |_| false }
    assert_partition(t, [[], [], []], [[:a1], [:b2, :b3], [:c3]]) { |_, _| false }
    assert_partition(t, [[], [], []], [[:a1], [:b2, :b3], [:c3]]) { |_, _, _| false }

    assert_partition(t, [[], [:b2], []], [[:a1], [:b3], [:c3]]) { |step| step.note == :b2 }
    assert_partition(t, [[], [:b2, :b3], []], [[:a1], [], [:c3]]) { |step| step.note.pitch_class == :b }

    assert_partition(t, [[:a1], [], [:c3]], [[], [:b2, :b3], []]) { |_, slot| slot.length == 1 }

    assert_partition(t, [[], [], [:c3]], [[:a1], [:b2, :b3], []]) { |_, _, idx| idx == 2 }
  end

  def assert_partition_slots(track, a_grid, b_grid, &block)
    assert_partition(track, a_grid, b_grid, :partition_slots, &block)
  end

  def test_partition_slots
    t = T[:a1, [:b2, :b3], :c3]

    assert_partition_slots(t, [[:a1], [:b2, :b3], [:c3]], [[], [], []]) { |_| true }
    assert_partition_slots(t, [[], [], []], [[:a1], [:b2, :b3], [:c3]]) { |_| false }
    assert_partition_slots(t, [[], [], []], [[:a1], [:b2, :b3], [:c3]]) { |_, _| false }

    assert_partition_slots(t, [[:a1], [], [:c3]], [[], [:b2, :b3], []]) { |slot| slot.length == 1 }
    assert_partition_slots(t, [[], [], [:c3]], [[:a1], [:b2, :b3], []]) { |_, idx| idx == 2 }
  end

  def assert_partition_every(track, ns, a_grid, b_grid, skip_empty: false)
    ns = [ns] unless ns.is_a?(Enumerable)
    assert_partition(track, a_grid, b_grid, :partition_every, *ns, skip_empty: skip_empty)
  end

  def test_partition_every
    t = T[:a1, [:b2, :b3], :c3]

    assert_raises { t.partition_every(0) }
    assert_partition_every t, 1, [[:a1], [:b2, :b3], [:c3]], [[], [], []]
    assert_partition_every t, 2, [[], [:b2, :b3], []], [[:a1], [], [:c3]]
    assert_partition_every t, 3, [[], [], [:c3]], [[:a1], [:b2, :b3], []]
    assert_partition_every t, 4, [[], [], []], [[:a1], [:b2, :b3], [:c3]]

    # Multiple gaps
    t = T[*[:a1] * 12]
    assert_partition_every t, [1, 3],
      [[:a1], [], [], [:a1], [:a1], [], [], [:a1], [:a1], [], [], [:a1]],
      [[], [:a1], [:a1], [], [], [:a1], [:a1], [], [], [:a1], [:a1], []]
    assert_partition_every t, [2, 4],
      [[], [:a1], [], [], [], [:a1], [], [:a1], [], [], [], [:a1]],
      [[:a1], [], [:a1], [:a1], [:a1], [], [:a1], [], [:a1], [:a1], [:a1], []]
    assert_partition_every t, [2, 3, 4],
      [[], [:a1], [], [], [:a1], [], [], [], [:a1], [], [:a1], []],
      [[:a1], [], [:a1], [:a1], [], [:a1], [:a1], [:a1], [], [:a1], [], [:a1]]

    t = T[*[:a1, :r] * 6]
    assert_partition_every t, [1, 3],
      [
        [:a1], [],
        [], [],
        [], [],
        [:a1], [],
        [:a1], [],
        [], []
      ],
      [
        [], [],    # drop (1), rest
        [:a1], [], # keep (3), rest
        [:a1], [], # keep (3), rest
        [], [],    # drop (3), rest
        [], [],    # drop (1), rest
        [:a1], []  # keep (3), rest
      ], skip_empty: true
  end

  def assert_gpartition(t, x, y, grid1, grid2, skip_empty: false)
    t1, t2 = t.gpartition(x, y, skip_empty: skip_empty)
    assert_grid t1, grid1
    assert_grid t2, grid2
  end

  def test_partition_x_of_y
    t = T[*[:a1] * 12]

    assert_raises { t.gpartition(1, 0) }
    assert_raises { t.gpartition(0, 1) }
    assert_raises { t.gpartition(-1, 2) }
    assert_raises { t.gpartition(5, 3) }
    assert_raises { t.gpartition(0.25, 1) }

    assert_gpartition t, 1, 3,
                      [[:a1], [], []] * 4,
                      [[], [:a1], [:a1]] * 4
    assert_gpartition t, 2, 3,
                      [[], [:a1], []] * 4,
                      [[:a1], [], [:a1]] * 4
    assert_gpartition t, 3, 3,
                      [[], [], [:a1]] * 4,
                      [[:a1], [:a1], []] * 4

    assert_gpartition t, 1, 5,
                      [[:a1], [], [], [], []] * 2 + [[:a1], []],
                      [[], [:a1], [:a1], [:a1], [:a1]] * 2 + [[], [:a1]]
    assert_gpartition t, 3, 5,
                      [[], [], [:a1], [], []] * 2 + [[], []],
                      [[:a1], [:a1], [], [:a1], [:a1]] * 2 + [[:a1], [:a1]]

    assert_gpartition t, 2, 15,
                      [[], [:a1]] + [[]] * 10,
                      [[:a1], []] + [[:a1]] * 10

    t = T[*[:a1, :r] * 6]
    assert_gpartition t, 2, 3,
      [
        [], [],
        [:a1], [],
        [], []
      ] * 2,
      [
        [:a1], [],
        [], [],
        [:a1], []
      ] * 2, skip_empty: true
  end

  def assert_partition_note(track, note, a_grid, b_grid)
    assert_partition(track, a_grid, b_grid, :partition_note, note)
  end

  def test_partition_note
    t = T[:a1, [:b2, :b3], :c3]

    assert_partition_note t, :d, [[], [], []], [[:a1], [:b2, :b3], [:c3]]
    assert_partition_note t, :b, [[], [:b2, :b3], []], [[:a1], [], [:c3]]
    assert_partition_note t, :b2, [[], [:b2], []], [[:a1], [:b3], [:c3]]
    assert_partition_note t, :c, [[], [], [:c3]], [[:a1], [:b2, :b3], []]
    assert_partition_note t, :c3, [[], [], [:c3]], [[:a1], [:b2, :b3], []]
  end

  def test_extract_gates
    assert_equal Track.rest.gates, [0]
    assert_equal Track.rest(4).gates, [0, 0, 0, 0]
    assert_equal T[:c4].gates, [1]
    assert_equal T[:r, :c4].gates, [0, 1]
    assert_equal T[:c4, :c4].gates, [1, 1]
    assert_equal T[:r, :c4, :c4, :r].gates, [0, 1, 1, 0]
    assert_equal T[:r, :c4, :r, :c4].gates, [0, 1, 0, 1]
    assert_equal T[S(:c4, gate: 0.5)].gates, [0.5]
    assert_equal T[:c4, S(:c4, gate: 0.5)].gates, [1, 0.5]
    assert_equal T[S(:c4, gate: 0.25), S(:c4, gate: 0.5)].gates, [0.25, 0.5]
    assert_equal T[:c4, S(:c4, gate: 0.25), S(:c4, gate: 0.5)].gates, [1, 0.25, 0.5]
    assert_equal T[S(:c4, gate: 0.25), :r, S(:c4, gate: 0.5)].gates, [0.25, 0, 0.5]

    assert_equal T[:c4, :d4].gates, [1, 1]
    assert_equal T[:c4, S(:d4, gate: 0.1)].gates, [1, 0.1]

    assert_raises { T[[:c4, :d4]].gates }
  end
end
