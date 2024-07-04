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
    return ->(x) { min + (max - min) * f.call(x) }
  end
end
