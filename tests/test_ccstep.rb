#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../ccstep"

class CCStepTest < Test::Unit::TestCase
  def assert_attrs(step, cc, val, prob = nil)
    assert_equal step.cc, cc
    assert_equal step.value, val
    if prob.nil?
      assert_nil step.prob
    else
      assert_equal step.prob, prob
    end
  end

  def test_attrs
    assert_attrs CC(0, 0), 0, 0
    assert_attrs CC(1, 0), 1, 0
    assert_attrs CC(1, 1), 1, 1
    assert_attrs CC(127, 0), 127, 0
    assert_attrs CC(127, 127), 127, 127

    assert_attrs CC(1, -2), 1, 0
    assert_attrs CC(1, 128), 1, 127

    assert_raises { CC(-1, 1) }
    assert_raises { CC(128, 1) }

    p = Prob.one_in(5)
    assert_attrs CC(1, 1, prob: p), 1, 1, p

    assert_attrs CC(1, 1, prob: 0.1), 1, 1, Prob.chance(0.1)
  end

  def test_mutators
    assert_attrs CC(1, 127).with_cc(2), 2, 127
    assert_raises { CC(1, 127).with_cc(-1) }
    assert_raises { CC(1, 127).with_cc(128) }

    assert_attrs CC(1, 127).with_val(50), 1, 50
    assert_attrs CC(1, 127).with_val(128), 1, 127
    assert_attrs CC(1, 127).with_val(-10), 1, 0

    (-10..10).each do |n|
      assert_attrs CC(1, 50).shift_val(n), 1, 50 + n
    end

    assert_attrs CC(1, 125).shift_val(10), 1, 127
    assert_attrs CC(1, 2).shift_val(-10), 1, 0
  end

  def assert_accum(step, delta, min: 0, max: 12, mode: :wrap, prob: nil, target: :value)
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
    s = CC(127, 50)

    assert_accum s, 0
    assert_accum s.accum(1), 1
    assert_accum s.accum(1, min: -2), 1, min: -2
    assert_accum s.accum(1, min: -2, max: 5), 1, min: -2, max: 5
    assert_accum s.accum(1, min: -2, max: 5, mode: :reverse), 1, min: -2, max: 5, mode: :reverse
    assert_accum s.accum(1, min: -2, max: 5, mode: :reverse, target: :value), 1, min: -2, max: 5, mode: :reverse, target: :value

    p = Prob.one_in(5)
    assert_accum s.accum(1, min: -2, max: 5, mode: :reverse, prob: p), 1, min: -2, max: 5, mode: :reverse, prob: p
    assert_accum s.accum(1, min: -2, max: 5, mode: :reverse, prob: 0.5), 1, min: -2, max: 5, mode: :reverse, prob: Prob.chance(0.5)

    # Subsequent calls to accum reset missing parameters to defaults
    s = CC(127, 50).accum(1, max: 20)
    s = s.accum(2)
    assert_accum s, 2, max: 12

    # Accum values should persist when steps are mutated with unrelated methods
    s = CC(127, 50).accum(1, max: 20)
    s = s.with_cc(50)
    assert_accum s, 1, max: 20

    # Invalid mode values should raise
    assert_raises { CC(127, 50).accum(1, mode: :nope) }
    assert_raises { CC(127, 50).accum(1, mode: nil) }
    assert_raises { CC(127, 50).accum(1, mode: nil, target: :note) }
  end

  def assert_repr(s)
    roundtrip = eval(s.repr)  # rubocop:disable Security/Eval
    assert_attrs roundtrip, s.cc, s.val, s.prob
    assert_accum roundtrip, s.accum_delta, min: s.accum_min, max: s.accum_max,
                            mode: s.accum_mode, prob: s.accum_prob, target: s.accum_target
  end

  def test_repr
    a = CC(1, 1)

    assert_repr a

    assert_repr a.accum(1)
    assert_repr a.accum(1, min: -5)
    assert_repr a.accum(1, min: -5, max: 22)
    assert_repr a.accum(1, min: -5, max: 22, mode: :freeze)
    assert_repr a.accum(1, min: -5, max: 22, mode: :freeze, target: :value)

    # Prob spot-checks
    assert_repr a.with_prob(Prob.every_other).accum(1, min: -5, max: 22, mode: :freeze)
    assert_repr a.with_prob(Prob.x_of_y(2, 5)).accum(1, min: -5, max: 22, mode: :freeze)
    assert_repr a.with_prob(0.25).accum(1, min: -5, max: 22, mode: :freeze)

    # Custom probs
    p = Prob.custom(-> { true })
    assert_raises(ArgumentError) { a.with_prob(p).repr }
    assert_nothing_raised { a.with_prob(p).repr(safe: true) }
    assert_raises(ArgumentError) { a.accum(1, prob: p).repr }
    assert_nothing_raised { a.accum(1, prob: p).repr(safe: true) }
  end
end
