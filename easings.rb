# require_relative "bezier.rb"

module Easings
  # everything in here has some things in common:
  # 1. each can be called with a single argument t using [] (like a Proc)
  # 2. f[0] == 0 and f[1] == 1
  # 3. f[t] for t in (0, 1) is roughly in the range of [0, 1].
  #    if f[t] is outside of [0, 1] it represents some "bouncing" and will
  #    probably translate to values going outside of the intended range.
  # 4. f[t] for t outside of [0, 1] is not an error but is pretty inconsistent.
  #    it may stick at 0 or 1, or interpolate based on the slope of the function
  #    at the endpoints. probably don't rely on it.

  Linear = ->(t) { t }

  # named CSS easings
  # see https://developer.mozilla.org/en-US/docs/Web/CSS/easing-function
  Default = CubicBezier.new(0.25, 0.1, 0.25, 1.0)
  In = CubicBezier.new(0.42, 0.0, 1.0, 1.0)
  Out = CubicBezier.new(0.0, 0.0, 0.58, 1.0)
  InOut = CubicBezier.new(0.42, 0.0, 0.58, 1.0)

  # these are from https://easings.net
  # and in particular https://github.com/ai/easings.net/blob/master/src/easings.yml
  InSine = CubicBezier.new(0.12, 0, 0.39, 0)
  OutSine = CubicBezier.new(0.61, 1, 0.88, 1)
  InOutSine = CubicBezier.new(0.37, 0, 0.63, 1)
  InQuad = CubicBezier.new(0.11, 0, 0.5, 0)
  OutQuad = CubicBezier.new(0.5, 1, 0.89, 1)
  InOutQuad = CubicBezier.new(0.45, 0, 0.55, 1)
  InCubic = CubicBezier.new(0.32, 0, 0.67, 0)
  OutCubic = CubicBezier.new(0.33, 1, 0.68, 1)
  InOutCubic = CubicBezier.new(0.65, 0, 0.35, 1)
  InQuart = CubicBezier.new(0.5, 0, 0.75, 0)
  OutQuart = CubicBezier.new(0.25, 1, 0.5, 1)
  InOutQuart = CubicBezier.new(0.76, 0, 0.24, 1)
  InQuint = CubicBezier.new(0.64, 0, 0.78, 0)
  OutQuint = CubicBezier.new(0.22, 1, 0.36, 1)
  InOutQuint = CubicBezier.new(0.83, 0, 0.17, 1)
  InExpo = CubicBezier.new(0.7, 0, 0.84, 0)
  OutExpo = CubicBezier.new(0.16, 1, 0.3, 1)
  InOutExpo = CubicBezier.new(0.87, 0, 0.13, 1)
  InCirc = CubicBezier.new(0.55, 0, 1, 0.45)
  OutCirc = CubicBezier.new(0, 0.55, 0.45, 1)
  InOutCirc = CubicBezier.new(0.85, 0, 0.15, 1)
  InBack = CubicBezier.new(0.36, 0, 0.66, -0.56)
  OutBack = CubicBezier.new(0.34, 1.56, 0.64, 1)
  InOutBack = CubicBezier.new(0.68, -0.6, 0.32, 1.6)

  # the following are not expressible with beziers

  InElastic = lambda do |t|
    return 0 if t <= 0
    return 1 if t >= 1
    c4 = (2 * Math::PI) / 3
    -(2.0 ** (10 * t - 10)) * Math.sin((t * 10 - 10.75) * c4)
  end

  OutElastic = lambda do |t|
    return 0 if t <= 0
    return 1 if t >= 1
    c4 = (2 * Math::PI) / 3
    (2 ** (-10 * t)) * Math.sin((t * 10 - 0.75) * c4) + 1
  end

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

  InBounce = lambda do |t|
    1 - OutBounce[1 - t]
  end

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

  InOutBounce = lambda do |t|
    if t < 0.5
      (1 - OutBounce[1 - 2 * t]) / 2.0
    else
      (1 + OutBounce[2 * t - 1]) / 2.0
    end
  end
end
