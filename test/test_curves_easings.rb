#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "../lib/spiseq/math/easings"
require_relative "../lib/spiseq/math/curves"

# The methods on Curves (scale and the fades) are already tested by the Track
# methods that move gate/velocity along a curve, so we'll skip them here. These
# are very simple tests of the expected endpoints and ranges.
class CurvesAndEasingsTest < Test::Unit::TestCase
  include SpiSeq::Math

  TOLERANCE = 0.0001
  MAX_BOUNCE = 0.5  # How far outside of 0 - 1 bouncing easings are allowed to fall

  # Spot checks that f[t] is in range for t in 0..1.
  def assert_unit_range(f, name = nil, bounce: nil)
    0.step(to: 1, by: 0.05) do |t|
      min = [:both, :low].include?(bounce) ? -MAX_BOUNCE : 0
      max = [:both, :high].include?(bounce) ? (1 + MAX_BOUNCE) : 1

      assert (f[t] - min) >= -TOLERANCE, "#{name} @ #{t.round(2)} = #{f[t]} < #{min}"
      assert (f[t] - max) <= TOLERANCE, "#{name} @ #{t.round(2)} = #{f[t]} > #{max}"
    end
  end

  def test_easings
    # Easings that go outside of 0 - 1. Value is :low if they go below 0, :high
    # if they go above 1, and :both if they exceed both 0 and 1.
    bouncing_easings = {
      InBack: :low,
      OutBack: :high,
      InOutBack: :both,
      InElastic: :low,
      OutElastic: :high,
      InOutElastic: :both
    }

    Easings.constants.each do |name|
      f = Easings.const_get(name)

      assert_equal f.arity, 1

      assert_in_delta 0, f[0], TOLERANCE
      assert_in_delta 1, f[1], TOLERANCE

      assert_unit_range f, name, bounce: bouncing_easings[name]
    end
  end

  def test_curves
    # Curves that start at 1; all others are assumed to start at 0
    start_1_curves = [
      :DownLinear,
      :DownUpLinear,
      :DownQuad,
      :DownUpQuad,
      :DownCubic,
      :DownFullCubic,
      :DownSine,
      :DownUpSine,
      :DownUp2Sine,
      :DownUp3Sine
    ]

    # Curves that end at 0; all others are assumed to end at 1
    end_0_curves = [
      :DownLinear,
      :UpDownLinear,
      :DownQuad,
      :UpDownQuad,
      :DownCubic,
      :DownFullCubic,
      :DownSine,
      :UpDownSine,
      :DownUp2Sine,
      :UpDown3Sine
    ]

    Curves.constants.each do |name|
      f = Curves.const_get(name)

      assert_equal f.arity, 1

      expected_start = start_1_curves.include?(name) ? 1 : 0
      expected_end = end_0_curves.include?(name) ? 0 : 1
      assert_in_delta expected_start, f[0], TOLERANCE
      assert_in_delta expected_end, f[1], TOLERANCE

      assert_unit_range f, name
    end
  end
end
