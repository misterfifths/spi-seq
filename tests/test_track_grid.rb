#!/usr/bin/env ruby
# frozen_string_literal: true

require "test/unit"
require_relative "../track"
require_relative "track_test_helpers"

# TODO: missing permutation & combination tests.

# Test Track's grid manipulation methods.
# Boundary's a little fuzzy here, but this is mostly things that deal with the
# grid as a whole, or that act on slots rather than directly on the steps within
# them.
class TrackGridTest < Test::Unit::TestCase
  include TrackTestHelpers

  def test_append
    assert_merge_strictness :+

    assert_grid T(:c4) + T(:d4), [[:c4], [:d4]]
    assert_grid T(:c4) + :d4, [[:c4], [:d4]]
    assert_grid T(:c4) + Track.rest(2), [[:c4], [], []]
    assert_grid T(:c4) + :r, [[:c4], []]
    assert_grid T(:c4) + [:r, [:d5, :e5]], [[:c4], [], [:d5, :e5]]

    assert_gt T(:c4, granularity: :whole, timescale: 2) + T(:c4, granularity: :whole, timescale: 2), NoteLength::Whole, 2
  end

  def test_merge
    assert_merge_strictness :|

    assert_grid T(:c4) | T(:d4), [[:c4, :d4]]
    assert_grid T(:c4) | :d4, [[:c4, :d4]]
    assert_grid T(:c4) | [:d4], [[:c4, :d4]]
    assert_grid T(:c4) | T(:c4), [[:c4]]  # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
    assert_grid T([:r, :d4]) | T([:c4, :r]), [[:c4], [:d4]]
    assert_grid T([:r, :d4]) | [:c4, :r], [[:c4], [:d4]]
    assert_grid T([[:a1, :b2], [:d4, :e5]]) | T([:c3, :f6]), [[:a1, :b2, :c3], [:d4, :e5, :f6]]

    # Differing lengths: the result should be the length of the longest track.
    assert_grid T(:c4) | T([:d4, :f4]), [[:c4, :d4], [:f4]]
    assert_grid T([:d4, :f4]) | T(:c4), [[:c4, :d4], [:f4]]
    assert_grid T([:d4, :f4]) | :c4, [[:c4, :d4], [:f4]]
    assert_grid T([:d4, :f4]) | [:c4, :g4], [[:c4, :d4], [:f4, :g4]]
    assert_grid T(:c4) | Track.rest(5), [[:c4], [], [], [], []]
  end

  def test_grouped_merge
    t = T([:a1, :b2, :c3, :d4, :e5, :f6])

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

    t = T([:a1, :b2, :c3, :d4])

    assert_grid t.zip(T(:f6)), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.zip(:f6), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.zip([:f6]), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.zip([[:f6]]), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]

    assert_grid t.zip(T(:f6), cycle: false), [[:a1], [:f6], [:b2], [], [:c3], [], [:d4], []]
    assert_grid t.zip(T(:f6), cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:c3], [:d4]]

    assert_grid t.zip(T([:f6, :g6])), [[:a1], [:f6], [:b2], [:g6], [:c3], [:f6], [:d4], [:g6]]
    assert_grid t.zip(T([:f6, :g6]), cycle: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [], [:d4], []]
    assert_grid t.zip(T([:f6, :g6]), cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [:d4]]
  end

  def test_grouped_zip
    assert_merge_strictness :gzip, 1, 1

    t = T([:a1, :b2, :c3, :d4])

    assert_grid t.gzip(T(:f6), 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip(:f6, 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip([:f6], 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip([[:f6]], 1, 1), [[:a1], [:f6], [:b2], [:f6], [:c3], [:f6], [:d4], [:f6]]
    assert_grid t.gzip(T(:f6), 1, 1, cycle: false), [[:a1], [:f6], [:b2], [], [:c3], [], [:d4], []]
    assert_grid t.gzip(T(:f6), 1, 1, cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:c3], [:d4]]

    assert_grid t.gzip(T(:f6), 2, 1), [[:a1], [:b2], [:f6], [:c3], [:d4], [:f6]]
    assert_grid t.gzip(T(:f6), 2, 1, cycle: false), [[:a1], [:b2], [:f6], [:c3], [:d4], []]
    assert_grid t.gzip(T(:f6), 2, 1, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:f6], [:c3], [:d4]]

    assert_grid t.gzip(T(:f6), 3, 1), [[:a1], [:b2], [:c3], [:f6], [:d4], [:a1], [:b2], [:f6]]
    assert_grid t.gzip(T(:f6), 3, 1, cycle: false), [[:a1], [:b2], [:c3], [:f6], [:d4], [], [], []]
    assert_grid t.gzip(T(:f6), 3, 1, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:c3], [:f6], [:d4]]

    assert_grid t.gzip(T(:f6), 4, 1), [[:a1], [:b2], [:c3], [:d4], [:f6]]

    assert_grid t.gzip(T([:f6, :g6]), 1, 1), [[:a1], [:f6], [:b2], [:g6], [:c3], [:f6], [:d4], [:g6]]
    assert_grid t.gzip(T([:f6, :g6]), 1, 1, cycle: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [], [:d4], []]
    assert_grid t.gzip(T([:f6, :g6]), 1, 1, cycle: false, pad_with_rests: false), [[:a1], [:f6], [:b2], [:g6], [:c3], [:d4]]

    assert_grid t.gzip(T([:f6, :g6]), 2, 1), [[:a1], [:b2], [:f6], [:c3], [:d4], [:g6]]

    assert_grid t.gzip(T([:f6, :g6]), 3, 1), [[:a1], [:b2], [:c3], [:f6], [:d4], [:a1], [:b2], [:g6]]
    assert_grid t.gzip(T([:f6, :g6]), 3, 1, cycle: false), [[:a1], [:b2], [:c3], [:f6], [:d4], [], [], [:g6]]

    # Sizes greater than either track
    assert_grid t.gzip(T(:f6), 6, 1), [[:a1], [:b2], [:c3], [:d4], [:a1], [:b2], [:f6]]
    assert_grid t.gzip(T(:f6), 6, 1, cycle: false), [[:a1], [:b2], [:c3], [:d4], [], [], [:f6]]
    assert_grid t.gzip(T(:f6), 6, 1, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:c3], [:d4], [:f6]]

    assert_grid t.gzip(T([:f6, :g6]), 2, 3), [[:a1], [:b2], [:f6], [:g6], [:f6], [:c3], [:d4], [:g6], [:f6], [:g6]]
    assert_grid t.gzip(T([:f6, :g6]), 2, 3, cycle: false), [[:a1], [:b2], [:f6], [:g6], [], [:c3], [:d4], [], [], []]
    assert_grid t.gzip(T([:f6, :g6]), 2, 3, cycle: false, pad_with_rests: false), [[:a1], [:b2], [:f6], [:g6], [:c3], [:d4]]

    # Lil guys
    assert_grid T(:c4).gzip([:d4, :e4], 1, 1), [[:c4], [:d4]]
    assert_grid T(:c4).gzip([:d4, :e4], 1, 2), [[:c4], [:d4], [:e4]]
    assert_grid T(:c4).gzip([:d4, :e4], 2, 1), [[:c4], [:c4], [:d4]]
    assert_grid T(:c4).gzip([:d4, :e4], 2, 1, cycle: false), [[:c4], [], [:d4]]
    assert_grid T(:c4).gzip([:d4, :e4], 2, 1, cycle: false, pad_with_rests: false), [[:c4], [:d4]]
  end

  def test_each_cons
    t = T([:a1, :b2, :c3, :d4])

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

  def test_repeat
    t = T([:a1, :b2])

    assert_raises { t * 0 }
    assert_grid t * 1, t.grid
    assert_grid t * 2, [[:a1], [:b2], [:a1], [:b2]]
    assert_grid t * 3, [[:a1], [:b2], [:a1], [:b2], [:a1], [:b2]]
  end

  def test_cycle_to_length
    t = T([:a1, :b2, :c3])

    assert_raises { t.cycle_to_length(0) }
    assert_grid t.cycle_to_length(1), [[:a1]]
    assert_grid t.cycle_to_length(2), [[:a1], [:b2]]
    assert_grid t.cycle_to_length(3), [[:a1], [:b2], [:c3]]
    assert_grid t.cycle_to_length(4), [[:a1], [:b2], [:c3], [:a1]]
    assert_grid t.cycle_to_length(5), [[:a1], [:b2], [:c3], [:a1], [:b2]]
    assert_grid t.cycle_to_length(6), [[:a1], [:b2], [:c3], [:a1], [:b2], [:c3]]
  end

  def test_compact
    assert_grid T([:r, :r, :a1, :r, :b2, :r, :r, :c3, :r]).compact, [[:a1], [:b2], [:c3]]
    assert_raises { Track.rest.compact }
  end

  def test_reverse
    assert_grid T(:c4).rev, [[:c4]]
    assert_grid T([:a1, :b2]).rev, [[:b2], [:a1]]
    assert_grid T([:a1, :r, :b2]).rev, [[:b2], [], [:a1]]
    assert_grid T([:a1, :r, :b2, :c3]).rev, [[:c3], [:b2], [], [:a1]]
    assert_grid T([:a1, :r, :b2, [:c3, :d4]]).rev, [[:c3, :d4], [:b2], [], [:a1]]
  end

  def test_mirror
    # Repeats the slot in the middle.
    assert_grid T(:c4).mirror, [[:c4], [:c4]]
    assert_grid T([:a1, :b2]).mirror, [[:a1], [:b2], [:b2], [:a1]]
    assert_grid T([:a1, [:b2, :c3]]).mirror, [[:a1], [:b2, :c3], [:b2, :c3], [:a1]]
    assert_grid T([:a1, :r]).mirror, [[:a1], [], [], [:a1]]
    assert_grid T([:a1, :b2, :c3]).mirror, [[:a1], [:b2], [:c3], [:c3], [:b2], [:a1]]
  end

  def test_reflect
    # Does not repeat the slot in the middle.
    assert_grid T(:c4).reflect, [[:c4]]
    assert_grid T([:a1, :b2]).reflect, [[:a1], [:b2], [:a1]]
    assert_grid T([:a1, [:b2, :c3]]).reflect, [[:a1], [:b2, :c3], [:a1]]
    assert_grid T([:a1, :r]).reflect, [[:a1], [], [:a1]]
    assert_grid T([:a1, :b2, :c3]).reflect, [[:a1], [:b2], [:c3], [:b2], [:a1]]
  end

  def test_shuffle
    assert_grid T(:c4).shuffle, [[:c4]]

    srand 1234
    assert_grid T([:a1, :b2, :c3, :d4]).shuffle, [[:a1], [:b2], [:c3], [:d4]]
    assert_grid T([:a1, :b2, :c3, :d4]).shuffle, [[:b2], [:c3], [:d4], [:a1]]
  end

  def test_rotate
    assert_grid T(:c4).shl, [[:c4]]
    assert_grid T(:c4).shl(5), [[:c4]]
    assert_grid T(:c4).shr, [[:c4]]
    assert_grid T(:c4).shr(5), [[:c4]]

    assert_grid T([:a1, :b2]).shl, [[:b2], [:a1]]
    assert_grid T([:a1, :b2]).shl(2), [[:a1], [:b2]]
    assert_grid T([:a1, :b2]).rotate(-2), [[:a1], [:b2]]
    assert_grid T([:a1, :b2]).shl(3), [[:b2], [:a1]]
    assert_grid T([:a1, :b2]).shr, [[:b2], [:a1]]
    assert_grid T([:a1, :b2]).shr(2), [[:a1], [:b2]]
    assert_grid T([:a1, :b2]).rotate(2), [[:a1], [:b2]]
    assert_grid T([:a1, :b2]).shr(3), [[:b2], [:a1]]

    assert_grid T([:a1, :b2, :c3]).shl, [[:b2], [:c3], [:a1]]
    assert_grid T([:a1, :b2, :c3]).shl(2), [[:c3], [:a1], [:b2]]
    assert_grid T([:a1, :b2, :c3]).rotate(-2), [[:c3], [:a1], [:b2]]
    assert_grid T([:a1, :b2, :c3]).shl(3), [[:a1], [:b2], [:c3]]
    assert_grid T([:a1, :b2, :c3]).shl(4), [[:b2], [:c3], [:a1]]
    assert_grid T([:a1, :b2, :c3]).shr, [[:c3], [:a1], [:b2]]
    assert_grid T([:a1, :b2, :c3]).shr(2), [[:b2], [:c3], [:a1]]
    assert_grid T([:a1, :b2, :c3]).rotate(2), [[:b2], [:c3], [:a1]]
    assert_grid T([:a1, :b2, :c3]).shr(3), [[:a1], [:b2], [:c3]]
    assert_grid T([:a1, :b2, :c3]).shr(4), [[:c3], [:a1], [:b2]]
  end

  def test_pad
    assert_grid T(:c4).left_pad, [[], [:c4]]
    assert_grid T(:c4).left_pad(2), [[], [], [:c4]]
    assert_grid T(:c4).right_pad(1), [[:c4], []]
    assert_grid T(:c4).right_pad(2), [[:c4], [], []]

    assert_grid T([:a1, :b2]).left_pad(2), [[], [], [:a1], [:b2]]
    assert_grid T([:a1, :b2]).right_pad(2), [[:a1], [:b2], [], []]
  end

  def test_space
    assert_grid T(:c4).space, [[:c4], []]
    assert_grid T(:c4).space(2), [[:c4], [], []]

    assert_grid T([:a1, :b2]).space, [[:a1], [], [:b2], []]
    assert_grid T([:a1, :b2]).space(2), [[:a1], [], [], [:b2], [], []]
  end

  def test_space_every
    assert_grid T(:c4).space_every(1), [[:c4], []]
    assert_grid T(:c4).space_every(1, 2), [[:c4], [], []]
    assert_grid T(:c4).space_every(2), [[:c4], []]
    assert_grid T(:c4).space_every(2, 2), [[:c4], [], []]

    assert_grid T([:a1, :b2, :c3]).space_every(1), [[:a1], [], [:b2], [], [:c3], []]
    assert_grid T([:a1, :b2, :c3]).space_every(1, 2), [[:a1], [], [], [:b2], [], [], [:c3], [], []]
    assert_grid T([:a1, :b2, :c3]).space_every(2), [[:a1], [:b2], [], [:c3], []]
    assert_grid T([:a1, :b2, :c3]).space_every(3), [[:a1], [:b2], [:c3], []]
    assert_grid T([:a1, :b2, :c3]).space_every(3, 2), [[:a1], [:b2], [:c3], [], []]
    assert_grid T([:a1, :b2, :c3]).space_every(4), [[:a1], [:b2], [:c3], []]
    assert_grid T([:a1, :b2, :c3]).space_every(4, 2), [[:a1], [:b2], [:c3], [], []]
  end

  def test_drop
    assert_raises { T(:c4).drop }
    assert_raises { T([:a1, :a2]).drop(2) }
    assert_raises { T([:a1, :a2]).drop(5) }

    t = T([:a1, :b2, :c3])
    assert_grid t.drop, [[:b2], [:c3]]
    assert_grid t.drop(1), [[:b2], [:c3]]
    assert_grid t.drop(2), [[:c3]]
  end

  def test_drop_last
    assert_raises { T(:c4).drop_last }
    assert_raises { T([:a1, :a2]).drop_last(2) }
    assert_raises { T([:a1, :a2]).drop_last(5) }

    t = T([:a1, :b2, :c3])
    assert_grid t.drop_last, [[:a1], [:b2]]
    assert_grid t.drop_last(1), [[:a1], [:b2]]
    assert_grid t.drop_last(2), [[:a1]]
  end

  def test_take
    assert_raises { T(:c4).take(0) }

    t = T([:a1, :b2, :c3])
    assert_grid t.take(1), [[:a1]]
    assert_grid t.take(2), [[:a1], [:b2]]
    assert_grid t.take(3), [[:a1], [:b2], [:c3]]
    assert_grid t.take(4), [[:a1], [:b2], [:c3]]
  end

  def test_slice
    assert_grid T(:c4)[0], [[:c4]]
    assert_grid T(:c4)[-1], [[:c4]]
    assert_raises { T(:c4)[1] }

    t = T([:a1, :b2, :c3])
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

    assert_grid t[0...1], [[:a1]]
    assert_grid t[0..1], [[:a1], [:b2]]
    assert_grid t[1...3], [[:b2], [:c3]]
    assert_grid t[1..3], [[:b2], [:c3]]
  end

  def test_sample
    assert_raises { T(:c4).sample(0) }
    assert_grid T(:c4).sample(1), [[:c4]]
    assert_grid T(:c4).sample(2), [[:c4]]

    srand 1234
    t = T([:a1, :b2, :c3, :d4])
    assert_grid t.sample(4), [[:d4], [:c3], [:b2], [:a1]]
    assert_grid t.sample(3), [[:a1], [:b2], [:c3]]
    assert_grid t.sample(2), [[:b2], [:c3]]
    assert_grid t.sample(1), [[:d4]]
  end

  def test_drop_every
    assert_grid T(:c4).dropout(0), [[:c4]]
    assert_grid T(:c4).dropout(1), [[]]

    t = T([:a1, :b2, :c3, :d4])
    assert_grid t.dropout(1), [[], [], [], []]
    assert_grid t.dropout(2), [[:a1], [], [:c3], []]
    assert_grid t.dropout(3), [[:a1], [:b2], [], [:d4]]
    assert_grid t.dropout(4), [[:a1], [:b2], [:c3], []]
    assert_grid t.dropout(5), [[:a1], [:b2], [:c3], [:d4]]

    t = T([:a1, :r, :b2, :r, :r, :c3])
    assert_grid t.dropout(1, skip_empty: true), [[], [], [], [], [], []]
    assert_grid t.dropout(2, skip_empty: true), [[:a1], [], [], [], [], [:c3]]
    assert_grid t.dropout(3, skip_empty: true), [[:a1], [], [:b2], [], [], []]
    assert_grid t.dropout(4, skip_empty: true), [[:a1], [], [:b2], [], [], [:c3]]
  end

  def test_rand_dropout
    assert_grid T(:c4).rdropout(1), [[]]
    assert_grid T(:c4).rdropout(0), [[:c4]]

    t = T([:a1, :b2, :c3, :d4])
    assert_grid t.rdropout(1), [[], [], [], []]
    assert_grid t.rdropout(0), [[:a1], [:b2], [:c3], [:d4]]

    srand 1234
    assert_grid t.rdropout, [[], [:b2], [], [:d4]]
  end

  def test_replace_slot
    assert_grid T(:c4).set_slot(0, [:d5, :e5]), [[:d5, :e5]]
    assert_raises { T(:c4).set_slot(2, [:d5]) }

    t = T([:a1, :b2, :c3])
    assert_grid t.set_slot(0, [:f9]), [[:f9], [:b2], [:c3]]
    assert_grid t.set_slot(1, [:f9]), [[:a1], [:f9], [:c3]]
    assert_grid t.set_slot(2, [:f9]), [[:a1], [:b2], [:f9]]

    assert_grid t.set_slot(2, [S(:f9, gate: 0.5), :c5]), [[:a1], [:b2], [S(:f9, gate: 0.5), :c5]]

    [:r, :rest, nil].each do |rest|
      assert_grid t.set_slot(1, rest), [[:a1], [], [:c3]]
    end
  end

  def test_append_slot
    assert_grid T(:c4).append_slot(0, [:d5, :e5]), [[:c4, :d5, :e5]]
    assert_raises { T(:c4).append_slot(2, [:d5]) }

    t = T([:a1, :b2, :c3])
    assert_grid t.append_slot(0, [:f9]), [[:a1, :f9], [:b2], [:c3]]
    assert_grid t.append_slot(1, [:f9]), [[:a1], [:b2, :f9], [:c3]]
    assert_grid t.append_slot(2, [:f9]), [[:a1], [:b2], [:c3, :f9]]

    assert_grid t.append_slot(2, [S(:f9, gate: 0.5), :c5]), [[:a1], [:b2], [:c3, S(:f9, gate: 0.5), :c5]]

    [:r, :rest, nil].each do |rest|
      assert_grid t.append_slot(1, rest), [[:a1], [:b2], [:c3]]
    end
  end

  def assert_extract(track, a_grid, b_grid, method = :extract, *args, &block)
    a, b = track.send(method, *args, &block)
    assert_grid a, a_grid
    assert_grid b, b_grid
  end

  def test_extract
    t = T([:a1, [:b2, :b3], :c3])

    assert_extract(t, [[], [], []], [[:a1], [:b2, :b3], [:c3]]) { |_| true }
    assert_extract(t, [[:a1], [:b2, :b3], [:c3]], [[], [], []]) { |_| false }
    assert_extract(t, [[:a1], [:b2, :b3], [:c3]], [[], [], []]) { |_, _| false }
    assert_extract(t, [[:a1], [:b2, :b3], [:c3]], [[], [], []]) { |_, _, _| false }

    assert_extract(t, [[:a1], [:b3], [:c3]], [[], [:b2], []]) { |step| step.note == :b2 }
    assert_extract(t, [[:a1], [], [:c3]], [[], [:b2, :b3], []]) { |step| step.note.pitch_class == :b }

    assert_extract(t, [[], [:b2, :b3], []], [[:a1], [], [:c3]]) { |_, slot| slot.length == 1 }

    assert_extract(t, [[:a1], [:b2, :b3], []], [[], [], [:c3]]) { |_, _, idx| idx == 2 }
  end

  def assert_extract_every(track, n, a_grid, b_grid)
    assert_extract(track, a_grid, b_grid, :extract_every, n)
  end

  def test_extract_every
    t = T([:a1, [:b2, :b3], :c3])

    assert_raises { t.extract_every(0) }
    assert_extract_every t, 1, [[], [], []], [[:a1], [:b2, :b3], [:c3]]
    assert_extract_every t, 2, [[:a1], [], [:c3]], [[], [:b2, :b3], []]
    assert_extract_every t, 3, [[:a1], [:b2, :b3], []], [[], [], [:c3]]
    assert_extract_every t, 4, [[:a1], [:b2, :b3], [:c3]], [[], [], []]
  end

  def assert_extract_note(track, note, a_grid, b_grid)
    assert_extract(track, a_grid, b_grid, :extract_note, note)
  end

  def test_extract_note
    t = T([:a1, [:b2, :b3], :c3])

    assert_extract_note t, :d, [[:a1], [:b2, :b3], [:c3]], [[], [], []]
    assert_extract_note t, :b, [[:a1], [], [:c3]], [[], [:b2, :b3], []]
    assert_extract_note t, :b2, [[:a1], [:b3], [:c3]], [[], [:b2], []]
    assert_extract_note t, :c, [[:a1], [:b2, :b3], []], [[], [], [:c3]]
    assert_extract_note t, :c3, [[:a1], [:b2, :b3], []], [[], [], [:c3]]
  end
end
