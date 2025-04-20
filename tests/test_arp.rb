#!/usr/bin/env ruby
# frozen_string_literal: true

require "test/unit"
require_relative "../theory/arp"

# TODO: missing degree tests
# TODO: missing spread & extra_octaves tests

class ArpTest < Test::Unit::TestCase
  def assert_arp(notes, order, result)
    assert_equal arp(notes, order), result
  end

  def test_objects
    arp([:c5, 60, "d1"], :up).each { |n| assert_instance_of MIDINote, n }
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
end
