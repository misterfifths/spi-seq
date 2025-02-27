#!/usr/bin/env ruby

require "test/unit"
require_relative "../step"

class StepTest < Test::Unit::TestCase
  def assert_attrs(step, note, vel, gate, prob = nil)
    assert_instance_of MIDINote, step.note
    assert_equal step.note, note
    assert_equal step.vel, vel
    assert_in_delta step.velf, vel / 127.0, 0.001
    assert_equal step.gate, gate
    assert_equal step.tied?, gate == 1.0
    if prob.nil?
      assert_nil step.prob
    else
      assert_same step.prob, prob
    end
  end

  def test_attrs
    assert_attrs S(:c4), :c4, 127, 1.0
    assert_attrs S(60), :c4, 127, 1.0
    assert_attrs S("c4"), :c4, 127, 1.0
    assert_attrs S("C4"), :c4, 127, 1.0
    assert_attrs S(60.5), 60.5, 127, 1.0

    # We've already tested the hell out of MIDINote, so there's not much point
    # in continuing variations on the type of the note argument.

    assert_attrs S(:c4, vel: 64), :c4, 64, 1.0
    assert_attrs S(:c4, vel: 64.25), :c4, 64, 1.0
    assert_attrs S(:c4, vel: 64.75), :c4, 64, 1.0
    assert_attrs S(:c4, vel: 0), :c4, 0, 1.0
    assert_attrs S(:c4, vel: -10), :c4, 0, 1.0
    assert_attrs S(:c4, vel: 140), :c4, 127, 1.0

    assert_attrs S(:c4, gate: 0), :c4, 127, 0
    assert_attrs S(:c4, gate: 0.5), :c4, 127, 0.5
    assert_attrs S(:c4, gate: 1), :c4, 127, 1
    assert_attrs S(:c4, gate: -2), :c4, 127, 0
    assert_attrs S(:c4, gate: 5), :c4, 127, 1

    assert_attrs S(:c4, vel: 20, gate: 0.5), :c4, 20, 0.5

    p = Prob.one_in(5)
    assert_attrs S(:c4, prob: p), :c4, 127, 1.0, p
  end

  def test_with_mutators
    [:c4, 60, 60.5, "ds5"].each do |n|
      assert_attrs S(:a2).with_note(n), n, 127, 1.0
    end

    assert_attrs S(:c4, vel: 50).with_vel(10), :c4, 10, 1.0
    assert_attrs S(:c4).with_vel(-10), :c4, 0, 1.0
    assert_attrs S(:c4, vel: 0).with_vel(500), :c4, 127, 1.0

    assert_attrs S(:c4, vel: 50).with_velf(1), :c4, 127, 1.0
    assert_attrs S(:c4).with_velf(0), :c4, 0, 1.0
    assert_attrs S(:c4).with_velf(0.5), :c4, 63, 1.0
    assert_attrs S(:c4).with_velf(0.25), :c4, 31, 1.0

    assert_attrs S(:c4).with_gate(0.25), :c4, 127, 0.25
    assert_attrs S(:c4, gate: 0.5).with_gate(1), :c4, 127, 1.0
    assert_attrs S(:c4, gate: 0.5).with_gate(11), :c4, 127, 1.0
    assert_attrs S(:c4).with_gate(-10), :c4, 127, 0

    assert_attrs S(:c4).with_octave(5), :c5, 127, 1
    assert_attrs S(:c4).with_octave(2), :c2, 127, 1
    assert_attrs S(:c4).with_octave(-1), :"c-1", 127, 1

    p1 = Prob.one_in(5)
    p2 = Prob.first
    assert_attrs S(:c4).with_prob(p1), :c4, 127, 1, p1
    assert_attrs S(:c4, prob: p2).with_prob(p1), :c4, 127, 1, p1
  end

  def test_shift_mutators
    (-13..13).each do |n|
      assert_attrs S(:a2).shift_tone(n), N(:a2).shift_tone(n), 127, 1.0
    end

    (-10..10).each do |n|
      assert_attrs S(:c4, vel: 50).shift_vel(n), :c4, 50 + n, 1.0
    end

    (-0.4..0.4).step(0.1) do |n|
      target_vel = ((64.0 / 127 + n) * 127).to_i
      assert_attrs S(:c4, vel: 64).shift_velf(n), :c4, target_vel, 1.0
    end

    (-0.4..0.4).step(0.1) do |n|
      assert_attrs S(:c4, gate: 0.5).shift_gate(n), :c4, 127, 0.5 + n
    end

    (-4..4).each do |n|
      assert_attrs S(:c4).shift_octave(n), N(:c4).shift_octave(n), 127, 1
    end
  end
end
