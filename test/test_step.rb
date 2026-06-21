#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/spiseq/tracks/step"

include SpiSeq::Theory
include SpiSeq::Tracks

class StepTest < Test::Unit::TestCase
  def assert_attrs(step, note, vel, gate, prob = nil)
    assert_instance_of MIDINote, step.note
    assert_equal step.note, note
    assert_equal step.vel, vel
    assert_in_delta step.velf, vel / 127.0, 0.001
    assert_equal step.gate, gate
    assert_equal step.tied?, gate == 1.0  # rubocop:disable Lint/FloatComparison
    if prob.nil?
      assert_nil step.prob
    else
      assert_equal step.prob, prob
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

    assert_attrs S(:c4, prob: 0.1), :c4, 127, 1.0, Prob.chance(0.1)

    custom_prob_lambda = ->{ true }
    assert_attrs S(:c4, prob: custom_prob_lambda), :c4, 127, 1.0, Prob.custom(custom_prob_lambda)
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

    assert_attrs S(:c4, prob: p2).clear_prob, :c4, 127, 1
    assert_attrs S(:c4).clear_prob, :c4, 127, 1
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
      assert_attrs S(:c4).up(n), N(:c4).up(n), 127, 1
      assert_attrs S(:c4).down(n), N(:c4).down(n), 127, 1
    end

    assert_attrs S(:c4).down, :c3, 127, 1
    assert_attrs S(:c4).up, :c5, 127, 1
  end

  def assert_accum(step, delta, min: 0, max: 12, mode: :wrap, prob: nil, target: :note)
    assert_equal step.accum_delta, delta
    assert_equal step.accum_min, min
    assert_equal step.accum_max, max
    assert_equal step.accum_mode, mode
    if prob.nil?
      assert_nil step.accum_prob
    else
      assert_equal step.accum_prob, prob
    end
    assert_equal step.accum_target, target
  end

  def test_accum
    assert_accum S(:c4), 0
    assert_accum S(:c4).accum(1), 1
    assert_accum S(:c4).accum(1, min: -2), 1, min: -2
    assert_accum S(:c4).accum(1, min: -2, max: 5), 1, min: -2, max: 5
    assert_accum S(:c4).accum(1, min: -2, max: 5, mode: :reverse), 1, min: -2, max: 5, mode: :reverse
    assert_accum S(:c4).accum(1, min: -2, max: 5, mode: :reverse, target: :gate), 1, min: -2, max: 5, mode: :reverse, target: :gate
    assert_accum S(:c4).accum(1, min: -2, max: 5, mode: :reverse, target: :vel), 1, min: -2, max: 5, mode: :reverse, target: :vel

    p = Prob.one_in(5)
    assert_accum S(:c4).accum(1, min: -2, max: 5, mode: :reverse, prob: p), 1, min: -2, max: 5, mode: :reverse, prob: p
    assert_accum S(:c4).accum(1, min: -2, max: 5, mode: :reverse, prob: 0.5), 1, min: -2, max: 5, mode: :reverse, prob: Prob.chance(0.5)

    # Subsequent calls to accum reset missing parameters to defaults
    s = S(:c4).accum(1, max: 20)
    s = s.accum(2)
    assert_accum s, 2, max: 12

    # Accum values should persist when steps are mutated with unrelated methods
    s = S(:c4).accum(1, max: 20)
    s = s.with_note(:d5)
    assert_accum s, 1, max: 20

    # without_accum
    s = S(:c4).accum(1, max: 20).without_accum
    assert_accum s, 0

    # Invalid values should raise
    assert_raises { S(:c4).accum(1, mode: :nope) }
    assert_raises { S(:c4).accum(1, mode: nil) }
    assert_raises { S(:c4).accum(1, target: :nope) }
    assert_raises { S(:c4).accum(1, target: :value) }
  end

  def assert_repr(s)
    roundtrip = eval(s.repr)  # rubocop:disable Security/Eval

    assert_attrs roundtrip, s.note, s.vel, s.gate, s.prob
    assert_accum roundtrip, s.accum_delta, min: s.accum_min, max: s.accum_max,
                            mode: s.accum_mode, prob: s.accum_prob, target: s.accum_target

    # A completely default step should just have a note symbol as its short repr
    if s.vel == 127 && s.gate == 1 && s.prob.nil? && s.accum_delta == 0
      roundtrip = eval(s.repr(short: true))  # rubocop:disable Security/Eval
      assert_equal roundtrip, s.note.to_sym
    end
  end

  def test_repr
    assert_repr S(:c4)
    assert_repr S(:c4, gate: 0.5)
    assert_repr S(:c4, gate: 0.25, vel: 50)
    assert_repr S(:c4, gate: 0.25, vel: 50).accum(1)
    assert_repr S(:c4, gate: 0.25, vel: 50).accum(1, min: -5)
    assert_repr S(:c4, gate: 0.25, vel: 50).accum(1, min: -5, max: 22)
    assert_repr S(:c4, gate: 0.25, vel: 50).accum(1, min: -5, max: 22, mode: :freeze)
    assert_repr S(:c4, gate: 0.25, vel: 50).accum(1, min: -5, max: 22, mode: :freeze, target: :gate)
    assert_repr S(:c4, gate: 0.25, vel: 50).accum(1, min: -5, max: 22, mode: :freeze, target: :vel)

    # Prob spot-checks
    assert_repr S(:c4, gate: 0.25, vel: 50, prob: Prob.every_other).accum(1, min: -5, max: 22, mode: :freeze)
    assert_repr S(:c4, gate: 0.25, vel: 50, prob: Prob.x_of_y(2, 5)).accum(1, min: -5, max: 22, mode: :freeze)
    assert_repr S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze)

    # Custom probs
    p = Prob.custom(-> { true })
    s = S(:c4)
    assert_raises(ArgumentError) { s.with_prob(p).repr }
    assert_nothing_raised { s.with_prob(p).repr(safe: true) }
    assert_raises(ArgumentError) { s.accum(1, prob: p).repr }
    assert_nothing_raised { s.accum(1, prob: p).repr(safe: true) }
  end

  def assert_equal_yield
    a = yield
    b = yield
    assert_equal a, b
    assert_equal a.hash, b.hash
  end

  def test_equality
    assert_equal_yield { S(:c4) }
    assert_equal_yield { S(:c4, gate: 0.25) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: Prob.chance(0.25)) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: Prob.pre) }

    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze, target: :gate) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze, target: :vel) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze, target: :vel, prob: Prob.every_other) }
    assert_equal_yield { S(:c4, gate: 0.25, vel: 50, prob: 0.25).accum(1, min: -5, max: 22, mode: :freeze, target: :vel, prob: Prob.every(3)) }

    refute_equal S(:c4),
                 S(:d4)
    refute_equal S(:c4, gate: 0.25),
                 S(:c4, gate: 0.5)
    refute_equal S(:c4, gate: 0.25, vel: 50),
                 S(:c4, gate: 0.25, vel: 127)
    refute_equal S(:c4, gate: 0.25, vel: 50, prob: 0.25),
                 S(:c4, gate: 0.25, vel: 50, prob: 0.75)
    refute_equal S(:c4, gate: 0.25, vel: 50, prob: 0.25),
                 S(:c4, gate: 0.25, vel: 50, prob: Prob.pre)

    refute_equal S(:c4).accum(1),
                 S(:c4).accum(2)
    refute_equal S(:c4).accum(1, min: -5),
                 S(:c4).accum(1, min: -6)
    refute_equal S(:c4).accum(1, min: -5, max: 22),
                 S(:c4).accum(1, min: -5, max: 23)
    refute_equal S(:c4).accum(1, min: -5, max: 22, mode: :freeze),
                 S(:c4).accum(1, min: -5, max: 22, mode: :wrap)
    refute_equal S(:c4).accum(1, min: -5, max: 22, mode: :freeze, target: :gate),
                 S(:c4).accum(1, min: -5, max: 22, mode: :freeze, target: :vel)
    refute_equal S(:c4).accum(1, min: -5, max: 22, mode: :freeze, target: :vel, prob: Prob.every_other),
                 S(:c4).accum(1, min: -5, max: 22, mode: :freeze, target: :vel, prob: Prob.pre)
    refute_equal S(:c4).accum(1, min: -5, max: 22, mode: :freeze, target: :vel, prob: Prob.every(3)),
                 S(:c4).accum(1, min: -5, max: 22, mode: :freeze, target: :vel, prob: Prob.every(2))
  end
end
