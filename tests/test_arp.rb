#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../theory/arp"

# TODO: missing degree tests
# TODO: missing spread & extra_octaves tests

class ArpTest < Test::Unit::TestCase
  def assert_arp(notes, order, result, **kwargs)
    assert_equal arp(notes, order, **kwargs), result
  end

  def test_args
    arp([:c5, 60, "d1"], :up).each { |n| assert_instance_of MIDINote, n }

    assert_raises { arp([:c4], :nope) }
  end

  def test_order
    assert_arp %i[a1 c0 d3 a0], :order, %i[a1 c0 d3 a0]
  end

  def test_up_down
    ns = %i[a1 c0 d3 a0]

    assert_arp ns, :up, %i[c0 a0 a1 d3]
    assert_arp ns, :down, %i[d3 a1 a0 c0]
    assert_arp ns, :updown, %i[c0 a0 a1 d3 a1 a0]
    assert_arp ns, :twouptwodown, %i[c0 c0 a0 a0 a1 a1 d3 d3 a1 a1 a0 a0]
  end

  def test_altern
    ns = %i[a1 c0 d3 a0 c2 e5]

    assert_arp ns, :alternin, %i[c0 e5 a0 d3 a1 c2]
    assert_arp ns.take(5), :alternin, %i[c0 d3 a0 c2 a1]
    assert_arp ns.take(4), :alternin, %i[c0 d3 a0 a1]
    assert_arp ns.take(3), :alternin, %i[c0 d3 a1]
    assert_arp ns.take(2), :alternin, %i[c0 a1]
    assert_arp ns.take(1), :alternin, %i[a1]

    assert_arp ns, :alternout, %i[c2 a1 d3 a0 e5 c0]
    assert_arp ns.take(5), :alternout, %i[a1 a0 c2 c0 d3]
    assert_arp ns.take(4), :alternout, %i[a1 a0 d3 c0]
    assert_arp ns.take(3), :alternout, %i[a1 c0 d3]
    assert_arp ns.take(2), :alternout, %i[a1 c0]
    assert_arp ns.take(1), :alternout, %i[a1]

    assert_arp ns, :alterninout, %i[c0 e5 a0 d3 a1 c2 a1 d3 a0 e5 c0]
    assert_arp ns.take(5), :alterninout, %i[c0 d3 a0 c2 a1 a0 c2 c0 d3]
    assert_arp ns.take(4), :alterninout, %i[c0 d3 a0 a1 a0 d3 c0]
    assert_arp ns.take(3), :alterninout, %i[c0 d3 a1 c0 d3]
    assert_arp ns.take(2), :alterninout, %i[c0 a1 c0]
    assert_arp ns.take(1), :alterninout, %i[a1]
  end

  def test_pinky_thumb
    ns = %i[a1 c0 d3 a0]

    assert_arp ns, :pinky, %i[c0 d3 a0 d3 a1 d3]
    assert_arp ns.take(2), :pinky, %i[c0 a1]

    assert_arp ns, :thumb, %i[a0 c0 a1 c0 d3 c0]
    assert_arp ns.take(2), :thumb, %i[a1 c0]
  end

  def test_peak_valley
    ns = %i[a1 c0 d3 a0 c2 e5]

    assert_arp ns, :peak, %i[c0 a1 d3 e5 c2 a0]
    assert_arp ns.take(5), :peak, %i[c0 a1 d3 c2 a0]
    assert_arp ns.take(4), :peak, %i[c0 a1 d3 a0]
    assert_arp ns.take(3), :peak, %i[c0 d3 a1]
    assert_arp ns.take(2), :peak, %i[c0 a1]
    assert_arp ns.take(1), :peak, %i[a1]

    assert_arp ns, :valley, %i[e5 c2 a0 c0 a1 d3]
    assert_arp ns.take(5), :valley, %i[d3 a1 c0 a0 c2]
    assert_arp ns.take(4), :valley, %i[d3 a0 c0 a1]
    assert_arp ns.take(3), :valley, %i[d3 c0 a1]
    assert_arp ns.take(2), :valley, %i[a1 c0]
    assert_arp ns.take(1), :valley, %i[a1]
  end

  def test_random
    ns = %i[a1 c0 d3 a0]

    unless ExtApi.in_sonic_pi?  # Not testing Sonic Pi's randomness
      srand 1234
      # Inexplicably, Array.shuffle does nothing immediately after an srand?
      assert_arp ns, :random, ns
      assert_arp ns, :random, %i[c0 d3 a0 a1]
      assert_arp ns, :random, %i[a1 d3 a0 c0]
    end
  end

  def test_extra_octaves
    ns = %i[a2 a1 c1 b1]

    assert_arp ns, :up, %i[c1 a1 b1 a2], extra_octaves: [0]  # shouldn't duplicate
    assert_arp ns, :up, %i[c1 a1 b1 c2 a2 b2 a3], extra_octaves: [1]
    assert_arp ns, :up, %i[c0 a0 b0 c1 a1 b1 a2], extra_octaves: [-1]
    assert_arp ns, :up, %i[c0 a0 b0 c1 a1 b1 a2 c3 a3 b3 a4], extra_octaves: [-1, 2]

    # Notes should be added at the end if we're using :order (but there should
    # still be no duplicates)
    assert_arp ns, :order, %i[a2 a1 c1 b1 a3 c2 b2], extra_octaves: [1]
  end

  def test_spread
    ns = %i[a1 b2 a3]

    assert_arp ns, :up, %i[a1 a2 b2 a3], spread: 1
    assert_arp ns, :order, %i[a1 b2 a3 a2 b3], spread: 2

    # spread > length of notes
    assert_arp %i[a1], :order, %i[a1 a2 a3 a4], spread: 3

    # no duplicates, and notes from spread should themselves be eligible for
    # spread, if needed
    assert_arp ns, :order, %i[a1 b2 a3 a2 b3 a4], spread: 3
    assert_arp ns, :order, %i[a1 b2 a3 a2 b3 a4 b4], spread: 4
    assert_arp ns, :order, %i[a1 b2 a3 a2 b3 a4 b4 a5], spread: 5
    assert_arp ns, :up, %i[a1 a2 b2 a3 b3 a4 b4 a5], spread: 5

    # extra_octaves should apply before spread
    assert_arp ns, :order, %i[a1 b2 a3 a2 b3 a4 b4], extra_octaves: [1], spread: 1
    assert_arp ns, :up, %i[a1 a2 b2 a3 b3 a4 b4], extra_octaves: [1], spread: 1

    # notes from spreading are chosen from the next lowest note and added in
    # increasing order, regardless of the order of the original notes
    ns = %i[c5 c3 c1]
    assert_arp ns, :order, %i[c5 c3 c1 c2], spread: 1
    assert_arp ns, :order, %i[c5 c3 c1 c2 c4], spread: 2
    assert_arp ns, :order, %i[c5 c3 c1 c2 c4 c6], spread: 3
  end
end
