# frozen_string_literal: true

# cf https://stackoverflow.com/questions/11696736/recreating-css3-transitions-cubic-bezier-curve
# https://github.com/WebKit/WebKit/blob/36e87a1fba92223b5289008516037523be409fba/Source/WebCore/platform/graphics/UnitBezier.h
# @private
class CubicBezier
  SPLINE_SAMPLES = 11
  DEFAULT_EPSILON = 1e-7
  MAX_NEWTON_ITERATIONS = 4

  def initialize(p1x, p1y, p2x, p2y)
    @p1x = p1x.to_f
    @p1y = p1y.to_f
    @p2x = p2x.to_f
    @p2y = p2y.to_f

    # postponing initial sampling until needed
    @inited = false
  end

  def solve(x, epsilon = DEFAULT_EPSILON)
    ensure_inited

    if x < 0
      @start_gradient * x
    elsif x > 1
      1 + @end_gradient * (x - 1.0)
    else
      sample_curve_y(solve_curve_x(x, epsilon))
    end
  end

  alias call solve
  alias [] solve

  def arity
    1
  end

  def sample_curve_x(t)
    ensure_inited
    ((@ax * t + @bx) * t + @cx) * t
  end

  def sample_curve_y(t)
    ensure_inited
    ((@ay * t + @by) * t + @cy) * t
  end

  def sample_curve_derivative_x(t)
    ensure_inited
    (3.0 * @ax * t + 2.0 * @bx) * t + @cx
  end

  def solve_curve_x(x, epsilon = DEFAULT_EPSILON)
    ensure_inited
    t0 = 0.0
    t1 = 0.0
    t2 = x.to_f
    x2 = 0.0
    d2 = 0.0

    # Linear interpolation of spline curve for initial guess.
    delta_t = 1.0 / (SPLINE_SAMPLES - 1)
    (1...SPLINE_SAMPLES).each do |i|
      next if x > @spline_samples[i]

      t1 = delta_t * i
      t0 = t1 - delta_t
      t2 = t0 + (t1 - t0) * (x - @spline_samples[i - 1]) / (@spline_samples[i] - @spline_samples[i - 1])
      break
    end

    # Perform a few iterations of Newton's method -- normally very fast.
    MAX_NEWTON_ITERATIONS.times do
      x2 = sample_curve_x(t2) - x
      return t2 if x2.abs < epsilon

      d2 = sample_curve_derivative_x(t2)
      break if d2.abs < epsilon

      t2 -= x2 / d2
    end

    return t2 if x2.abs < epsilon

    # Fall back to the bisection method for reliability.
    while t0 < t1
      x2 = sample_curve_x(t2)
      return t2 if (x2 - x).abs < epsilon
      if x > x2
        t0 = t2
      else
        t1 = t2
      end

      t2 = (t1 + t0) * 0.5
    end

    # Failure.
    t2
  end

  private

  def ensure_inited
    return if @inited
    @inited = true

    # pre-compute coefficients
    # implicit start & end control points of (0, 0) and (1, 1)
    @cx = 3.0 * @p1x
    @bx = 3.0 * (@p2x - @p1x) - @cx
    @ax = 1.0 - @cx - @bx

    @cy = 3.0 * @p1y
    @by = 3.0 * (@p2y - @p1y) - @cy
    @ay = 1.0 - @cy - @by

    # end-point gradients for stepping outside of [0, 1]
    if @p1x > 0
      @start_gradient = @p1y / @p1x
    elsif @p1y != 0 && @p2x > 0
      @start_gradient = p2y / @p2x
    elsif @p1y != 0 && @p2y != 0
      @start_gradient = 1.0
    else
      @start_gradient = 0.0
    end

    if @p2x < 1
      @end_gradient = (@p2y - 1)/ (@p2x - 1)
    elsif @p2y == 1 && @p1x < 1
      @end_gradient = (@p1y - 1) / (@p1x - 1)
    elsif @p2y == 1 && @p1y == 1
      @end_gradient = 1.0
    else
      @end_gradient = 0.0
    end

    delta_t = 1.0 / (SPLINE_SAMPLES - 1)
    @spline_samples = []
    SPLINE_SAMPLES.times do |i|
      @spline_samples << sample_curve_x(i * delta_t)
    end
  end
end
