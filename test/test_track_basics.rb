#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/track_helpers"
require_relative "../lib/spiseq/theory/scale"
require_relative "../lib/spiseq/tracks/track"

include SpiSeq::Tracks
include SpiSeq::Theory

# Test basic Track methods - simple methods, direct attr mutators, etc.
class TrackBasicTest < Test::Unit::TestCase
  include TrackHelpers

  def test_basic_methods
    assert_equal T[:c4].num_slots, 1
    assert_equal T[:c4, :d4].num_slots, 2

    assert_equal T[:c4].beat_length, 0.5
    assert_equal T[:c4, :d4].beat_length, 1
    assert_equal T[:c4, :d4, granularity: :whole].beat_length, 8

    assert T[:r].empty?
    assert T[:r, :r].empty?
    refute T[:c4].empty?

    assert T[:r].mono?
    assert T[:c4].mono?
    assert T[:c4, :d4].mono?
    refute T[:c4, [:d4, :e4]].mono?

    refute T[:r].poly?
    refute T[:c4].poly?
    refute T[:c4, :d4].poly?
    assert T[:c4, [:d4, :e4]].poly?
  end

  def test_attr_mutators
    assert_gt T[:c4].with_granularity(:whole), :whole, 1
    assert_gt T[:c4, granularity: :half].with_granularity(:sixteenth), :sixteenth, 1

    assert_gt T[:c4].with_rate(2), :eighth, 2
    assert_gt T[:c4, timescale: 5].with_rate(0.5), :eighth, 0.5

    c_maj = Scale.full_scale(:c, :major)
    c_min = Scale.full_scale(:c, :minor)
    assert_gt T[:c4].with_scale(c_maj), :eighth, 1, scale: c_maj
    assert_gt T[:c4, scale: c_min].with_scale(c_maj), :eighth, 1, scale: c_maj
    assert_gt T[:c4, scale: c_min].with_scale(nil), :eighth, 1
  end

  def test_filled_slots
    assert_empty Track.rest(3).indexes_of_filled_slots
    assert_raises { Track.rest(3).nth_filled_slot(0) }

    t = T[:a1, [:b2, :b3], :r, :c3, :r]
    assert_equal t.indexes_of_filled_slots, [0, 1, 3]

    s = t.nth_filled_slot(0)
    assert_equal s.length, 1
    assert_equal s[0].note, :a1

    s = t.nth_filled_slot(1)
    assert_equal s.length, 2
    assert(s.one? { |slot| slot.note == :b2 })
    assert(s.one? { |slot| slot.note == :b3 })

    s = t.nth_filled_slot(2)
    assert_equal s.length, 1
    assert_equal s[0].note, :c3

    # Negative indexes
    s = t.nth_filled_slot(-1)
    assert_equal s.length, 1
    assert_equal s[0].note, :c3

    s = t.nth_filled_slot(-2)
    assert_equal s.length, 2
    assert(s.one? { |slot| slot.note == :b2 })
    assert(s.one? { |slot| slot.note == :b3 })
  end

  def test_repr
    assert_repr T[:r]
    assert_repr T[:c4]
    assert_repr T[:c4, :d4]
    assert_repr T[:c4, :r, :d4]
    assert_repr T[[:c4, :e4], :r, :d4]

    assert_repr T[S(:c4, gate: 0.5)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50).accum(1)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50).accum(1, min: -5)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50).accum(1, min: -5, max: 22)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50).accum(1, min: -5, max: 22, mode: :freeze)]

    # Prob spot-checks
    assert_repr T[S(:c4, gate: 0.25, vel: 50, prob: Prob.every_other).accum(1, min: -5, max: 22, mode: :freeze)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50, prob: Prob.x_of_y(2, 5)).accum(1, min: -5, max: 22, mode: :freeze)]
    assert_repr T[S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze)]

    assert_repr T[:c4, granularity: :whole]
    assert_repr T[:c4, granularity: :whole, timescale: 2]
    assert_repr T[:c4, granularity: :whole, timescale: 2, scale: Scale.full_scale(:c, :major)]

    # Custom probs
    p = Prob.custom(-> { true })
    s = S(:c4)
    assert_raises(ArgumentError) { T[s.with_prob(p)].repr }
    assert_nothing_raised { T[s.with_prob(p)].repr(safe: true) }
    assert_raises(ArgumentError) { T[s.accum(1, prob: p)].repr }
    assert_nothing_raised { T[s.accum(1, prob: p)].repr(safe: true) }
  end

  def assert_eql_with_hash(a, b)
    assert_equal a, b
    assert_equal a.hash, b.hash
  end

  def assert_eql_yield
    assert_eql_with_hash yield, yield
  end

  def test_equality
    assert_eql_yield { T.rest }
    assert_eql_yield { T.rest(4) }
    assert_eql_yield { T[:c4] }
    assert_eql_yield { T[:c4, :d4] }
    assert_eql_yield { T[:c4, :d4, scale: Scale.full_scale(:c, :major)] }
    assert_eql_yield { T[:c4, :d4, scale: Scale.new(:c4, :major)] }
    assert_eql_yield { T[:c4, :d4, granularity: :eighth] }
    assert_eql_yield { T[:c4, :d4, granularity: :whole, timescale: 2] }
    assert_eql_yield { T[[:c4, :d4], [:e4, :f4]] }
    assert_eql_yield { T[[S(:c4, gate: 0.5), :c4]] }

    assert_eql_with_hash T[:c4], T[S(:c4, gate: 1)]
    assert_eql_with_hash T[:c4].gate(0.5), T[S(:c4, gate: 0.5)]

    # Order of steps in a slot as passed to the ctor is insignificant
    assert_eql_with_hash T[[:c4, :d4]], T[[:d4, :c4]]

    # Step deduplication
    assert_eql_with_hash T[[S(:c4, gate: 0.5), :c4]], T[:c4]

    # All attrs matter
    refute_equal T[:c4, granularity: :eighth],
                 T[:c4, granularity: :whole]
    refute_equal T[:c4, granularity: :whole, timescale: 2],
                 T[:c4, granularity: :whole, timescale: 3]
    refute_equal T[:c4, granularity: :whole, timescale: 3, scale: Scale.new(:c4, :major)],
                 T[:c4, granularity: :whole, timescale: 3, scale: Scale.new(:c4, :minor)]
  end
end
