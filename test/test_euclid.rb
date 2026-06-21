#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/spiseq/theory/euclid"

include SpiSeq::Theory

class EuclidTest < Test::Unit::TestCase
  def test_args
    assert_raises { euclid("nope", 2) }
    assert_raises { euclid(2, "nope") }
    assert_raises { euclid(2, 3, rotate: "nope") }

    assert_raises { euclid(-1, 2) }
    assert_raises { euclid(2, -1) }
    assert_raises { euclid(2, 3, rotate: -1) }
  end

  def test_length_edge_cases
    assert_equal euclid(0, 0), []
    assert_equal euclid(10, 0), []

    assert_equal euclid(0, 5), [false] * 5
    assert_equal euclid(5, 5), [true] * 5
    assert_equal euclid(10, 5), [true] * 5
  end

  def test_basics
    1.upto(12) do |pulses|
      1.upto(12) do |length|
        0.upto(12) do |rotate|
          res = euclid(pulses, length, rotate: rotate)

          assert_equal res.length, length, "pattern has incorrect length #{res.length}: (#{pulses}, #{length}, #{rotate})"
          assert res.first, "pattern did not start with a hit: (#{pulses}, #{length}, #{rotate})"

          hit_count = res.count { |elem| elem }
          expected_hit_count = [pulses, length].min
          assert_equal hit_count, expected_hit_count, "pattern has incorrect number of hits #{hit_count}: (#{pulses}, #{length}, #{rotate})"
        end
      end
    end
  end

  def test_examples
    # Some spot-checks of particular results
    assert_equal euclid(3, 4), [true, false, true, true]
    assert_equal euclid(3, 4, rotate: 1), [true, true, true, false]
    assert_equal euclid(3, 4, rotate: 2), [true, true, false, true]
    assert_equal euclid(3, 4, rotate: 3), [true, false, true, true]
    assert_equal euclid(3, 4, rotate: 4), [true, true, true, false]

    assert_equal euclid(4, 5), [true, false, true, true, true]
    assert_equal euclid(4, 5, rotate: 1), [true, true, true, true, false]

    assert_equal euclid(5, 8), [true, false, true, false, true, true, false, true]
    assert_equal euclid(5, 8, rotate: 1), [true, false, true, true, false, true, true, false]
  end
end
