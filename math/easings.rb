# frozen_string_literal: true

require_relative "bezier"

# Collects a number of curves suitable for smoothly transitioning a value
# between a minimum and maximum along a curve. These may be useful for functions
# like {CCTrack#add_curve} or {Track#with_vel_curve}.
#
# All of the constants on this module share the following behaviors:
# - Each can be called with a single numeric argument using `call` (like a Proc
#   or lambda).
# - For each constant `f`, `f.call(0) == 0` and `f.call(1) == 1`.
# - For `t` in 0 - 1 inclusive, `f.call(t)` is roughly in the range of 0 - 1
#   inclusive. If it is outside of that range, it represents some "bouncing".
#   Curves that return values outside of 0 - 1 are documented as such, and if
#   used for transitioning a value, results may be outside of the specified
#   range.
# - For `t` outside of 0 - 1, `f.call(t)` is not an error but should be
#   considered undefined.
#
# These curves differ from those in the {Curves} module in that their results
# always begin at 0 and end at 1.
module Easings
  # @!group Named CSS easings

  # The identity function; linearly moves between 0 and 1.
  Linear = ->(t) { t }

  # The default CSS cubic Bézier easing curve ("ease" in CSS).
  # @see https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/easing-function#ease
  Default = CubicBezier.new(0.25, 0.1, 0.25, 1.0)

  # The "ease-in" CSS cubic Bézier easing curve.
  # @see https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/easing-function#ease-in
  In = CubicBezier.new(0.42, 0.0, 1.0, 1.0)

  # The "ease-out" CSS cubic Bézier easing curve.
  # @see https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/easing-function#ease-out
  Out = CubicBezier.new(0.0, 0.0, 0.58, 1.0)

  # The "ease-in-out" CSS cubic Bézier easing curve.
  # @see https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/easing-function#ease-in-out
  InOut = CubicBezier.new(0.42, 0.0, 0.58, 1.0)


  # @!group Other easings
  # See https://github.com/ai/easings.net/blob/master/src/easings.yml

  # A cubic Bézier curve as described. See https://easings.net for a graphical
  # representation of the curve.
  InSine = CubicBezier.new(0.12, 0, 0.39, 0)
  # (see InSine)
  OutSine = CubicBezier.new(0.61, 1, 0.88, 1)
  # (see InSine)
  InOutSine = CubicBezier.new(0.37, 0, 0.63, 1)
  # (see InSine)
  InQuad = CubicBezier.new(0.11, 0, 0.5, 0)
  # (see InSine)
  OutQuad = CubicBezier.new(0.5, 1, 0.89, 1)
  # (see InSine)
  InOutQuad = CubicBezier.new(0.45, 0, 0.55, 1)
  # (see InSine)
  InCubic = CubicBezier.new(0.32, 0, 0.67, 0)
  # (see InSine)
  OutCubic = CubicBezier.new(0.33, 1, 0.68, 1)
  # (see InSine)
  InOutCubic = CubicBezier.new(0.65, 0, 0.35, 1)
  # (see InSine)
  InQuart = CubicBezier.new(0.5, 0, 0.75, 0)
  # (see InSine)
  OutQuart = CubicBezier.new(0.25, 1, 0.5, 1)
  # (see InSine)
  InOutQuart = CubicBezier.new(0.76, 0, 0.24, 1)
  # (see InSine)
  InQuint = CubicBezier.new(0.64, 0, 0.78, 0)
  # (see InSine)
  OutQuint = CubicBezier.new(0.22, 1, 0.36, 1)
  # (see InSine)
  InOutQuint = CubicBezier.new(0.83, 0, 0.17, 1)
  # (see InSine)
  InExpo = CubicBezier.new(0.7, 0, 0.84, 0)
  # (see InSine)
  OutExpo = CubicBezier.new(0.16, 1, 0.3, 1)
  # (see InSine)
  InOutExpo = CubicBezier.new(0.87, 0, 0.13, 1)
  # (see InSine)
  InCirc = CubicBezier.new(0.55, 0, 1, 0.45)
  # (see InSine)
  OutCirc = CubicBezier.new(0, 0.55, 0.45, 1)
  # (see InSine)
  InOutCirc = CubicBezier.new(0.85, 0, 0.15, 1)

  # (see InSine)
  #
  # Note that this curve's output exceeds the range 0 - 1.
  InBack = CubicBezier.new(0.36, 0, 0.66, -0.56)
  # (see InBack)
  OutBack = CubicBezier.new(0.34, 1.56, 0.64, 1)
  # (see InBack)
  InOutBack = CubicBezier.new(0.68, -0.6, 0.32, 1.6)

  # The following are not expressible with beziers

  # (see InBack)
  InElastic = lambda do |t|
    return 0 if t <= 0
    return 1 if t >= 1
    c4 = (2 * Math::PI) / 3
    -(2.0 ** (10 * t - 10)) * Math.sin((t * 10 - 10.75) * c4)
  end

  # (see InBack)
  OutElastic = lambda do |t|
    return 0 if t <= 0
    return 1 if t >= 1
    c4 = (2 * Math::PI) / 3
    (2 ** (-10 * t)) * Math.sin((t * 10 - 0.75) * c4) + 1
  end

  # (see InBack)
  InOutElastic = lambda do |t|
    return 0 if t <= 0
    return 1 if t >= 1
    c5 = (2 * Math::PI) / 4.5
    if t < 0.5
      -((2 ** (20 * t - 10)) * Math.sin((20 * t - 11.125) * c5)) / 2.0
    else
      ((2 ** (-20 * t + 10)) * Math.sin((20 * t - 11.125) * c5)) / 2.0 + 1
    end
  end

  # (see InSine)
  InBounce = lambda do |t|
    1 - OutBounce[1 - t]
  end

  # (see InSine)
  OutBounce = lambda do |t|
    n1 = 7.5625
    d1 = 2.75

    if t < 1 / d1
      n1 * t * t
    elsif t < 2 / d1
      t -= 1.5 / d1
      n1 * t * t + 0.75
    elsif t < 2.5 / d1
      t -= 2.25 / d1
      n1 * t * t + 0.9375
    else
      t -= 2.625 / d1
      n1 * t * t + 0.984375
    end
  end

  # (see InSine)
  InOutBounce = lambda do |t|
    if t < 0.5
      (1 - OutBounce[1 - 2 * t]) / 2.0
    else
      (1 + OutBounce[2 * t - 1]) / 2.0
    end
  end
end
