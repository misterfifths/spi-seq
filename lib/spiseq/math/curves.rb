# frozen_string_literal: true

module SpiSeq; module Math
  # Collects a number of curves suitable for changing a value over time. These
  # may be useful for functions like {Tracks::Track#with_vel_curve}.
  #
  # All of the constants on this module share the following behaviors:
  # - Each can be called with a single numeric argument using `call` (like a
  #   Proc or lambda).
  # - For `t` in 0 - 1 inclusive, for each constant `f`, `f.call(t)` is in the
  #   range of 0 - 1 inclusive.
  # - For `t` outside of 0 - 1, `f.call(t)` is not an error but should be
  #   considered undefined.
  #
  # These curves differ from those in the {Easings} module in that their results
  # do not always begin at 0 or end at 1. Some do the exact opposite, like
  # {.DownQuad}. Others reach 1 in the middle and return to 0 at the end, like
  # {.UpDownSine}. Still others follow different trajectories.
  #
  # To scale a curve so that its output covers a certain range, use {.scale}.
  module Curves
    # The identity function; linearly moves between 0 and 1.
    UpLinear = ->(x) { x }
    # A curve that linearly moves from 1 to 0.
    DownLinear = ->(x) { 1.0 - x }

    # A curve that moves from 1 to 0 at the halfway point, then back to 1.
    DownUpLinear = ->(x) { (2.0 * x - 1.0).abs }
    # A curve that moves from 0 to 1 at the halfway point, then back to 0.
    UpDownLinear = ->(x) { 1.0 - (2.0 * x - 1.0).abs }

    # A curve that moves quadratically from 0 to 1.
    UpQuad = ->(x) { x * x }
    # A curve that moves quadratically from 1 to 0.
    DownQuad = ->(x) { (x - 1.0) ** 2 }

    # A curve that moves quadratically from 1 to 0 at the halfway point, then
    # back to 1.
    DownUpQuad = ->(x) { (2.0 * x - 1.0) ** 2 }
    # A curve that moves quadratically from 0 to 1 at the halfway point, then
    # back to 0.
    UpDownQuad = ->(x) { 1.0 - (2.0 * x - 1.0) ** 2 }

    # A curve that moves cubically from 0 to 1. This is one arm of `x^3`; there
    # is no leveling out in the middle.
    UpCubic = ->(x) { x ** 3 }
    # A curve that moves cubically from 1 to 0. This is one arm of `x^3`; there
    # is no leveling out in the middle.
    DownCubic = ->(x) { -((x - 1.0) ** 3) }

    # A curve that moves cubically from 0 to 1. This is the full cubic curve,
    # and has a leveling in the middle.
    UpFullCubic = ->(x) { (::Math.cbrt(4.0) * x - ::Math.cbrt(0.5)) ** 3 + 0.5 }
    # A curve that moves cubically from 1 to 0. This is the full cubic curve,
    # and has a leveling in the middle.
    DownFullCubic = ->(x) { (::Math.cbrt(0.5) - ::Math.cbrt(4.0) * x) ** 3 + 0.5 }

    # A curve that moves from 1 to 0 along a sine.
    DownSine = ->(x) { ::Math.cos(::Math::PI * x) / 2.0 + 0.5 }
    # A curve that moves from 0 to 1 along a sine.
    UpSine = ->(x) { -::Math.cos(::Math::PI * x) / 2.0 + 0.5 }

    # A curve that moves along a sine from 1 to 0 at the halfway point, then
    # back to 1.
    DownUpSine = ->(x) { ::Math.cos(2.0 * ::Math::PI * x) / 2.0 + 0.5 }
    # A curve that moves along a sine from 0 to 1 at the halfway point, then
    # back to 0.
    UpDownSine = ->(x) { -::Math.cos(2.0 * ::Math::PI * x) / 2.0 + 0.5 }

    # A curve that moves along a sine from 1 -> 0 -> 1 -> 0.
    DownUp2Sine = ->(x) { ::Math.cos(3.0 * ::Math::PI * x) / 2.0 + 0.5 }
    # A curve that moves along a sine from 0 -> 1 -> 0 -> 1.
    UpDown2Sine = ->(x) { -::Math.cos(3.0 * ::Math::PI * x) / 2.0 + 0.5 }

    # A curve that moves along a sine from 1 -> 0 -> 1 -> 0 -> 1.
    DownUp3Sine = ->(x) { ::Math.cos(4.0 * ::Math::PI * x) / 2.0 + 0.5 }
    # A curve that moves along a sine from 0 -> 1 -> 0 -> 1 -> 0.
    UpDown3Sine = ->(x) { -::Math.cos(4.0 * ::Math::PI * x) / 2.0 + 0.5 }

    # Returns a curve that is the result of scaling another curve so that its
    # values fall within a given range.
    #
    # @param f [#call] The curve to scale, which should be callable with a
    #   single floating point argument.
    # @param min [Number] The desired minimum for the scaled curve.
    # @param max [Number] The desired maximum for the scaled curve.
    # @param orig_min [Number] The minimum output of `f`, before scaling.
    # @param orig_max [Number] The maximum output of `f`, before scaling.
    # @return [#call] A lambda that will call `f` and scale its output so that
    #   it falls between `min` and `max` inclusive.
    module_function def scale(f, min, max, orig_min: 0, orig_max: 1)
      ->(x) { min + (max - min) * ((f.call(x) - orig_min) / (orig_max - orig_min)) }
    end

    # Returns a lambda that increases linearly from `min_value` to `max_value`
    # over the range of 0 to 1. `ramp_up_start` determines at what input value
    # the increase will begin; the function will return `min_value` for inputs
    # below `ramp_up_start`, and then linearly increasing values between
    # `min_value` and `max_value` for those after.
    # @param min_value [Number]
    # @param max_value [Number]
    # @param ramp_up_start [Number]
    # @return [#call]
    module_function def fade_in_linear(min_value = 0.0, max_value = 1.0, ramp_up_start = 0.0)
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

    # Returns a function that decreases linearly from `max_value` to `min_value`
    # over the range of 0 to 1. `ramp_down_start` determines at what input value
    # the decrease will begin; the function will return `max_value` for inputs
    # below `ramp_down_start`, and then linearly decreasing values between
    # `max_value` and `min_value` for those after.
    # @param min_value [Number]
    # @param max_value [Number]
    # @param ramp_down_start [Number]
    # @return [#call]
    module_function def fade_out_linear(max_value = 1.0, min_value = 0.0, ramp_down_start = 0.0)
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

    # The same as {fade_in_linear}, but quadratically increases values.
    # @param (see fade_in_linear)
    # @return [#call]
    module_function def fade_in_quad(min_value = 0.0, max_value = 1.0, ramp_up_start = 0.0)
      min_value = min_value.to_f
      max_value = max_value.to_f
      ramp_up_start = ramp_up_start.to_f

      lambda do |x|
        return min_value if x < ramp_up_start
        return max_value if x >= 1

        # We want a quadratic with its minimum at (ramp_up_start, min_value)
        # which intersects (1, max_value).
        # More precisely, we're after y = (c(x - ramp_up_start))^2 + min_value
        # for some c that makes it hit (1, max_value). Substituting those values
        # and solving for c gives...
        c = ::Math.sqrt(max_value - min_value) / (1.0 - ramp_up_start)
        (c * (x - ramp_up_start)) ** 2 + min_value
      end
    end

    # The same as {fade_out_linear}, but quadratically decreases values.
    # @param (see fade_out_linear)
    # @return [#call]
    module_function def fade_out_quad(max_value = 1.0, min_value = 0.0, ramp_down_start = 0.0)
      max_value = max_value.to_f
      min_value = min_value.to_f
      ramp_down_start = ramp_down_start.to_f

      lambda do |x|
        return max_value if x < ramp_down_start
        return min_value if x >= 1

        # This is the same quadratic as fade_in_quad, just flipped and moved up
        # so its maximum is at (ramp_down_start, max_value).
        c = ::Math.sqrt(max_value - min_value) / (1.0 - ramp_down_start)
        max_value - (c * (x - ramp_down_start)) ** 2
      end
    end
  end
end; end
