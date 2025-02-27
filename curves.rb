# frozen_string_literal: true

module Curves
  # These are all intended to be called with x in [0, 1], and for such values,
  # will return a value in [0, 1]. For values of x outside of that range, the
  # returned values will vary depending on the function; do not expect
  # predictable behavior.
  # To return a new function that scales a given function so that its results
  # fall in a particular range, use the scale method.

  UpLinear = ->(x) { x }
  DownLinear = ->(x) { 1.0 - x }

  DownUpLinear = ->(x) { (2.0 * x - 1.0).abs }
  UpDownLinear = ->(x) { 1.0 - (2.0 * x - 1.0).abs }

  UpQuad = ->(x) { x * x }
  DownQuad = ->(x) { (x - 1.0) ** 2 }

  DownUpQuad = ->(x) { (2.0 * x - 1.0) ** 2 }
  UpDownQuad = ->(x) { 1.0 - (2.0 * x - 1.0) ** 2 }

  # One arm of x^3; no flat part in the middle
  UpCubic = ->(x) { x ** 3 }
  DownCubic = ->(x) { -((x - 1.0) ** 3) }

  # x^3 shifted up and over; flattens in the middle
  UpFullCubic = ->(x) { (Math.cbrt(4.0) * x - Math.cbrt(0.5)) ** 3 + 0.5 }
  DownFullCubic = ->(x) { (Math.cbrt(0.5) - Math.cbrt(4.0) * x) ** 3 + 0.5 }

  DownSine = ->(x) { Math.cos(Math::PI * x) / 2.0 + 0.5 }
  UpSine = ->(x) { -Math.cos(Math::PI * x) / 2.0 + 0.5 }

  DownUpSine = ->(x) { Math.cos(2.0 * Math::PI * x) / 2.0 + 0.5 }
  UpDownSine = ->(x) { -Math.cos(2.0 * Math::PI * x) / 2.0 + 0.5 }

  DownUp2Sine = ->(x) { Math.cos(3.0 * Math::PI * x) / 2.0 + 0.5 }  # 1->0->1->0
  UpDown2Sine = ->(x) { -Math.cos(3.0 * Math::PI * x) / 2.0 + 0.5 }  # 0->1->0->1

  DownUp3Sine = ->(x) { Math.cos(4.0 * Math::PI * x) / 2.0 + 0.5 }  # 1->0->1->0->1
  UpDown3Sine = ->(x) { -Math.cos(4.0 * Math::PI * x) / 2.0 + 0.5 }  # 0->1->0->1->0

  def self.scale(f, min, max)
    ->(x) { min + (max - min) * f.call(x) }
  end

  # Returns a function that increases linearly from min_value to max_value over
  # the range of 0 to 1. ramp_up_start determines at what x value the increase
  # will begin; the function will return min_value for x values below
  # ramp_up_start, and then linearly increasing values between min_value and
  # max_value for those after.
  def self.fade_in_linear(min_value = 0.0, max_value = 1.0, ramp_up_start = 0.0)
    min_value = min_value.to_f
    max_value = max_value.to_f
    ramp_up_start = ramp_up_start.to_f

    lambda do |x|
      return min_value if x < ramp_up_start
      return max_value if x >= 1

      # We're going to go linearly from (ramp_up_start, min_value) to
      # (1, max_value).
      x1 = ramp_up_start
      y1 = min_value
      x2 = 1.0
      y2 = max_value

      (y2 - y1) / (x2 - x1) * (x - x1) + y1
    end
  end

  # Returns a function that decreases linearly from max_value to min_value over
  # the range of 0 to 1. ramp_down_start determines at what x value the decrease
  # will begin; the function will return max_value for x values below
  # ramp_down_start, and then linearly decreasing values between max_value and
  # min_value for those after.
  def self.fade_out_linear(max_value = 1.0, min_value = 0.0, ramp_down_start = 0.0)
    max_value = max_value.to_f
    min_value = min_value.to_f
    ramp_down_start = ramp_down_start.to_f

    lambda do |x|
      return max_value if x < ramp_down_start
      return min_value if x >= 1

      # We're going to go linearly from (ramp_down_start, max_value) to
      # (1, min_value).
      x1 = ramp_down_start
      y1 = max_value
      x2 = 1.0
      y2 = min_value

      (y2 - y1) / (x2 - x1) * (x - x1) + y1
    end
  end

  # Same as fade_in_linear, but quadratically increases values.
  def self.fade_in_quad(min_value = 0.0, max_value = 1.0, ramp_up_start = 0.0)
    min_value = min_value.to_f
    max_value = max_value.to_f
    ramp_up_start = ramp_up_start.to_f

    lambda do |x|
      return min_value if x < ramp_up_start
      return max_value if x >= 1

      # We want a quadratic with its minimum at (ramp_up_start, min_value) which
      # intersects (1, max_value).
      # More precisely, we're after y = (c(x - ramp_up_start))^2 + min_value for
      # some c that makes it hit (1, max_value). Substituting those values and
      # solving for c gives...
      c = Math.sqrt(max_value - min_value) / (1.0 - ramp_up_start)
      (c * (x - ramp_up_start)) ** 2 + min_value
    end
  end

  # Same as fade_out_linear, but quadratically decreases values.
  def self.fade_out_quad(max_value = 1.0, min_value = 0.0, ramp_down_start = 0.0)
    max_value = max_value.to_f
    min_value = min_value.to_f
    ramp_down_start = ramp_down_start.to_f

    lambda do |x|
      return max_value if x < ramp_down_start
      return min_value if x >= 1

      # This is the same quadratic as fade_in_quad, just flipped and moved up
      # so its maximum is at (ramp_down_start, max_value).
      c = Math.sqrt(max_value - min_value) / (1.0 - ramp_down_start)
      max_value - (c * (x - ramp_down_start)) ** 2
    end
  end
end
