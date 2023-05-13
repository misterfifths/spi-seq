# cf https://stackoverflow.com/questions/11696736/recreating-css3-transitions-cubic-bezier-curve
# https://github.com/WebKit/WebKit/blob/36e87a1fba92223b5289008516037523be409fba/Source/WebCore/platform/graphics/UnitBezier.h
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

  alias [] solve

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
      if x <= @spline_samples[i]
        t1 = delta_t * i
        t0 = t1 - delta_t
        t2 = t0 + (t1 - t0) * (x - @spline_samples[i - 1]) / (@spline_samples[i] - @spline_samples[i - 1])
        break
      end
    end

    # Perform a few iterations of Newton's method -- normally very fast.
    MAX_NEWTON_ITERATIONS.times do
      x2 = sample_curve_x(t2) - x
      return t2 if x2.abs < epsilon

      d2 = sample_curve_derivative_x(t2)
      break if d2.abs < epsilon

      t2 = t2 - x2 / d2
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


module Easings
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


# cf https://physics.stackexchange.com/a/333436
class Bounce
  DT = 0.001

  def initialize(coeff_restitution: 0.75,
                 contact_time: 0.1,
                 h0: 5,
                 v0: 0,
                 g: 10,
                 h_stop: 0.01)
    @h0 = h0.to_f
    @v0 = v0.to_f
    @g = g.to_f
    @rho = coeff_restitution.to_f
    @tau = contact_time.to_f
    @h_stop = h_stop.to_f

    @inited = false
  end

  def time_to_settle
    ensure_inited
    @times.last
  end

  def sample(t)
    ensure_inited

    idx = idx_for_time(t)
    return @h0 if idx <= 0
    return @samples.last if idx >= @samples.length - 1

    # value is between @samples[idx - 1] and @samples[idx]
    # lerp based on the percent between the times at those indices
    t0 = @times[idx - 1]
    t1 = @times[idx]
    s0 = @samples[idx - 1]
    s1 = @samples[idx]
    Underscore.remap(t, t0, t1, s0, s1)
  end

  alias [] sample

  # TODO: clean this up and figure out its purpose exactly
  # def each_sample(factor: 1, &block)
  #   ensure_inited

  #   steps = (@samples.length / factor.to_f).ceil
  #   printf("will do %d steps\n", steps)
  #   steps.times do |i|
  #     i *= factor
  #     prev_i = i - factor
  #     next_i = i + factor
  #     prev_i = 0 if prev_i < 0
  #     i = @samples.length - 1 if i > @samples.length - 1
  #     next_i = @samples.length - 1 if next_i > @samples.length - 1

  #     s = @samples[i]
  #     t = @times[i]
  #     if i < @samples.length - 1
  #       # dt = @times[i + 1] - @times[i]
  #       # dt = @times[next_i] - @times[i]
  #       dt = @times[i] - @times[prev_i]
  #     else
  #       dt = nil
  #     end

  #     # bounce_start = i > 0 && @samples[i] == 0 && @samples[prev_i] > 0
  #     bounce_start = i > 0 && @samples[i] <= @samples[prev_i] && @samples[i] <= @samples[next_i]

  #     if block.arity == 2
  #       block[t, s]
  #     elsif block.arity == 3
  #       block[t, s, dt]
  #     else
  #       block[t, s, dt, bounce_start]
  #     end
  #   end
  # end

  def samples
    ensure_inited
    @times.zip(@samples)
  end

  def contact_times
    ensure_inited
    @contact_times
  end

  private

  def idx_for_time(t)
    ensure_inited

    return 0 if t <= 0
    return @times.length - 1 if t >= @times.last

    idx = @times.bsearch_index { |x| x >= t }

    # shouldn't happen but can't hurt
    return @times.length - 1 if idx.nil?
    idx

    # printf("t=%.3f -> idx=%d @times[idx]=%.3f\n", t.to_f, idx, @times[idx])
  end

  def strip_zeroes
    return if @samples.empty? || @samples.length == 1

    for i in 1..@samples.length
      break if @samples[-i] != 0
    end

    # leave behind one final zero
    # if i == 1, we didn't find any (@samples[-1] != 0)
    # if i == 2, we only found one
    if i > 2 then
      @samples.pop(i - 2)
      @times.pop(i - 2)
    end
  end

  def ensure_inited
    return if @inited
    @inited = true

    v = @v0
    h = hmax = @h0
    t = 0.0
    freefall = true

    t_last = -Math.sqrt(2.0 * h / @g)
    vmax = Math.sqrt(2.0 * hmax * @g)

    @samples = []
    @times = []
    @contact_times = []

    while hmax > @h_stop
      # printf("t=%.3f h=%.3f hmax=%.3f\n", t, h, hmax)
      if freefall then
        hnew = h + v * DT - 0.5 * @g * DT * DT
        if hnew < 0 then
          @contact_times << t
          t = t_last + 2.0 * Math.sqrt(2.0 * hmax / @g)
          freefall = false
          t_last = t + @tau
          h = 0
          # printf("contact: t->%.3f hnew=%.3f\n", t, hnew)
        else
          t += DT
          v -= @g * DT
          h = hnew
          # printf("freefall: t->%.3f hnew=%.3f v=%.3f\n", t, hnew, v)
        end
      else
        t += @tau
        vmax *= @rho
        v = vmax
        freefall = true
        h = 0
        # printf("bounce: t->%.3f v=%.3f\n", t, v)
      end

      hmax = 0.5 * vmax * vmax / @g
      @samples << h
      @times << t
    end

    # printf("stopped bouncing after %d samples, t=%.3f, h=%.3f\n", @samples.length, t, h)

    strip_zeroes

    # printf("after stripping, have %d samples, max t=%.3f, h=%.8f\n", @samples.length, @times.last, @samples.last)
  end
end

# TODO: don't quite understand how to get a sane set of SonicPi functions in
# here... e.g., the standalone ring() function is missing, but Object#ring
# isn't? And note() is not around unless we include this or WesternTheory...
begin
  include SonicPi::Lang::Core
rescue NameError
  puts "not in SonicPi; some things probably won't work"
end

module Underscore
  def self._floatify1(x)
    return x if x.is_a? Float
    return x.to_f if x.is_a? Numeric
    note(x).to_f
  end

  def self._floatify(*args)
    return _floatify1(args.first) if args.length == 1
    args.map { |x| _floatify1(x) }
  end

  def self.clamp(val, min = 0, max = 1)
    val, min, max = _floatify(val, min, max)

    return min if val < min
    return max if val > max
    val
  end

  def self.lerp(min, max, pct, clamp: false)
    min, max, pct = _floatify(min, max, pct)

    res = min + (max - min) * pct
    return clamp(res, min, max) if clamp
    res
  end

  def self.ease(min, max, pct, curve, clamp: false)
    lerp(min, max, curve[pct], clamp: clamp)
  end

  def self.norm(val, min, max, clamp: false)
    val, min, max = _floatify(val, min, max)
    res = (val - min) / (max - min)
    return clamp(res) if clamp
    res
  end

  def self.remap(val, orig_min, orig_max, target_min, target_max, clamp: false)
    pct = norm(val, orig_min, orig_max)
    lerp(target_min, target_max, pct, clamp: clamp)
  end

  def self.alerp(vals, pct)
    # lerp through an array, such that the value at index i happens
    # exactly at pct=i/(vals.length - 1) and in-between pcts are
    # lerped between adjacent values. pct is always clamped to [0, 1].
    # For example, if vals=[1, 5, 9, 10] then...
    # pct   alerp(vals, pct) (approx.)
    # 0     1
    # 0.1   1.4  (i.e., 10% between 1 and 5)
    # 0.33  5
    # 0.5   7 (~halfway between 5 and 9)
    # 0.66  9
    # 0.8   9.4 (~40% between 9 and 10)
    # 1     10
    pct_per_idx = 1.0 / (vals.length - 1)
    start_idx = (pct / pct_per_idx).floor

    return vals[0] if start_idx <= 0
    return vals.last if start_idx >= vals.length - 1

    # how far are we between the value at start_idx and the next?
    pct_to_next = (pct - pct_per_idx * start_idx) / pct_per_idx
    lerp(vals[start_idx], vals[start_idx + 1], pct_to_next, clamp: true)
  end

  def self.curve_samples(curve, count)
    vals = []
    count.times do |i|
      t = i.to_f / (count - 1)
      vals << curve[t]
    end

    vals
  end

  def self.cring(curve, count)
    # the standalone ring() function is weird from in here
    # but doing it like this is fine
    curve_samples(curve, count).ring
  end

  def self.cramp(curve, count)
    ramp(*curve_samples(curve, count))
  end

  # TODO?
  # quantise arguments throughout?
end


module Enumerable
  def each_with_pct
    return to_enum(:each_with_pct) unless block_given?

    len = self.count
    self.each_with_index do |e, i|
      pct = i.to_f / (len - 1)
      yield e, pct, i
    end
  end

  def each_with_next(skip_last: false)
    return to_enum(:each_with_next, skip_last: skip_last) unless block_given?

    len = self.count
    last_idx = len - 1
    last_idx -= 1 if skip_last

    if self.is_a? Array then
      vals = self
    else
      vals = self.to_a
    end

    for i in 0..last_idx
      val = vals[i]
      next_val = vals[i + 1]

      yield val, next_val, i
    end
  end
end


class Integer
  def times_with_pct
    return to_enum(:times_with_pct) unless block_given?

    for i in 0...self
      pct = i.to_f / (self - 1)
      yield i, pct
    end
  end
end
