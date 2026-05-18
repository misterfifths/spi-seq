# frozen_string_literal: true

require_relative "prob"


# TODO: microtiming?


# StepBase represents an event that can be sequenced in a slot inside a
# {TrackBase track}. Do not make instances of StepBase directly; instead use
# one of its subclasses that specialize for a particular sort of event, like
# {Step} for notes in {Track}s, or {CCStep} for MIDI CC events in {CCTrack}s.
#
# A step has a probability ({#prob}), an instance of {Prob}, which determines
# whether it should trigger when its slot is played. It additionally has a
# number of accumulation parameters, which determine changes to be made to the
# step each time it plays. The effect of accumulation varies depending on the
# subclass. For {Step}s, it applies a semitone offset to the {Step#note note};
# for {CCStep}s it applies an offset to the {CCStep#value value} that will be
# sent for the CC.
#
# Note that **steps are immutable**. The mutation methods provided here, like
# {#with_prob}, return new steps that have all the same attributes as the
# receiver, with just the described change.
#
# @abstract Subclasses should override `ctor_args`, `ctor_kwargs`, and
#   `repr_ctor_method` so that {#repr} and `mutate` work as expected.
class StepBase
  # A predicate which determines whether this step will trigger when the slot
  # that contains it is played, or nil if the step should always play.
  # @return [Prob, nil]
  # @see #accum_prob
  attr_reader :prob

  # The amount to add to the accumulation for this step each time it triggers
  # during playback. This value may be negative, but must be between
  # {#accum_min} and {#accum_max} (exclusive). If the delta is 0 (the default),
  # no accumulation occurs.
  #
  # The accumulated value for a step is used in different ways depending on the
  # subclass. For {Step}s, it applies a semitone offset to the {Step#note note};
  # for {CCStep}s it applies an offset to the {CCStep#value value} that will be
  # sent for the CC.
  #
  # @return [Number]
  attr_reader :accum_delta

  # The acceptable range of the total accumulation, inclusive. The behavior when
  # the total exceeds one of these values is controlled by `accum_mode`. The
  # default range is 0 - 12. `accum_min` must be <= 0, and `accum_max` must be
  # greater than `accum_min`.
  # @return [Number]
  attr_reader :accum_max, :accum_min

  # Controls the behavior when the total accumulation exceeds {#accum_min} -
  # {#accum_max} (inclusive). Must be one of the following values:
  # - `:freeze` - The accumulation will remain "stuck" at `accum_min` or
  #   `accum_max`; further accumulation triggers will have no effect.
  # - `:wrap` - The accumulation will wrap around to the other extreme min or
  #   max. For example, if `accum_max` is 12 and an addition of `accum_delta`
  #   would result in an accumulation of 14, `:wrap` mode will convert that into
  #   an accumulation of `accum_min + 1`.
  # - `:reverse` - When an extreme is reached, the value of `accum_delta` is
  #   effectively negated, so that the accumulation begins moving in the
  #   opposite direction. If the accumulation oversteps an extreme, that
  #   overage is accounted for before beginning to reverse. For instance, if
  #   `accum_max` is 12 and `accum_delta` is 3, which would result in an
  #   accumulation of 15, two things happen. First, the delta is internally
  #   negated such that the next accumulation will subtract it instead of add.
  #   Second, the overage of 3 (2 inclusive) is subtracted from `accum_max`,
  #   resulting in a final accumulation of 10. The next time the accumulation
  #   triggers, the result will be 7.
  #
  # The default mode is `:wrap`.
  #
  # @return [:freeze, :wrap, :reverse]
  attr_reader :accum_mode

  # A predicate that determines whether accumulation will trigger when the step
  # does, or nil if it should always trigger. Note that accumulation will only
  # potentially trigger when the step itself does. That is, the overall step
  # {#prob} (if any) is a prerequisite for the evaluation of `accum_prob` and
  # the application of accumulation at all.
  # @see #prob
  # @return [Prob, nil]
  attr_reader :accum_prob

  # Constructs a step.
  #
  # `prob` is the probability that the step will trigger when its slot is
  # played. It will be converted to a {Prob} and should be either:
  # - nil - the step will always trigger
  # - a number between 0 and 1 inclusive that represents the chance that the
  #   step will trigger
  # - a callable predicate lambda/proc that takes the arguments described by
  #   {Prob.custom}. If the predicate returns true, the step will trigger.
  # - an instance of {Prob}. See that class for some common probabilities.
  #
  # With the `accum_*` parameters, a step may be configured so that it varies
  # by some accumulating amount each time it triggers. The actual effect of the
  # accumulation varies by subclass. For {Step}s, it applies a semitone offset
  # to the {Step#note note}; for {CCStep}s it applies an offset to the
  # {CCStep#value value} that will be sent for the CC.
  #
  # You may find it more convenient to set the accumulation parameters after
  # constructing a step with the {#accum} method.
  #
  # @param prob [Prob, Number, #call, nil] The probability that the step will
  #   trigger when its slot is played, or nil if it should always trigger.
  #   Non-{Prob} values will be converted {StepBase#initialize as described}.
  # @param accum_delta [Integer] The amount to add to the accumulation each time
  #   the step triggers during playback; see {#accum_delta}.
  # @param accum_max [Integer] Defines the maximum total accumulation; see
  #   {#accum_max}.
  # @param accum_min [Integer] Defines the minimum total accumulation; see
  #   {#accum_min}.
  # @param accum_mode [:freeze, :wrap, :reverse] Controls the behavior when the
  #   total accumulation exceeds the range defined by `accum_min` and
  #   `accum_max`. See {#accum_mode}.
  # @param accum_prob [Prob, Number, #call, nil] The probability that
  #   accumulation will trigger when the step does, or nil if it should always
  #   trigger. Non-{Prob} values will be converted to {Prob}s as described for
  #   `prob`.
  def initialize(prob: nil,
                 accum_delta: 0, accum_max: 12, accum_min: 0, accum_mode: :wrap, accum_prob: nil)
    @prob = probify(prob)

    raise RangeError, "accum_min must be <= 0" unless accum_min <= 0
    raise RangeError, "accum_delta must be between accum_min and accum_max" if accum_delta < accum_min || accum_delta > accum_max
    @accum_delta = accum_delta
    @accum_max = accum_max
    @accum_min = accum_min

    raise ArgumentError, "invalid accum_mode #{accum_mode}" unless %i[wrap reverse freeze].include?(accum_mode)
    @accum_mode = accum_mode

    @accum_prob = probify(accum_prob)
  end

  # Returns a new step with the given accumulation parameters set. Note that
  # parameters that are not provided will be set to default values.
  # @param delta [Integer] See {#accum_delta}.
  # @param max [Integer] See {#accum_max}.
  # @param min [Integer] See {#accum_min}.
  # @param mode [:freeze, :wrap, :reverse] See {#accum_mode}.
  # @param prob [Prob, Number, #call, nil] See {#accum_prob}. Non-{Prob} values
  #   will be converted to {Prob}s as described by {#initialize}.
  # @return [StepBase]
  def accum(delta, min: 0, max: 12, mode: :wrap, prob: nil)
    mutate(accum_delta: delta, accum_min: min, accum_max: max, accum_mode: mode, accum_prob: prob)
  end

  # Returns a new step with the given {#prob probability}. Non-{Prob} values
  # will be converted to {Prob}s as described by {#initialize}.
  # @param new_prob [Prob, Number, #call, nil]
  # @see #prob
  # @return [StepBase]
  def with_prob(new_prob)
    mutate(prob: new_prob)
  end

  # Returns a new step with the {#prob probability} (if any) removed.
  # @see #prob
  # @return [StepBase]
  def without_prob
    @prob.nil? ? self : with_prob(nil)
  end

  alias clear_prob without_prob

  # Returns whether this step should play in the given cycle of playback, with
  # the given set of notes played in the previous slot. This evaluates the
  # step's probability predicate.
  # @private
  def should_trigger?(cycle, fill, effective_note, prev_notes)
    return true if @prob.nil?
    @prob.should_trigger?(cycle, fill, self, effective_note, prev_notes)
  end

  # Returns whether this step's accumulation should trigger, by evaluating
  # the accum_prob predicate.
  # @private
  def accum_should_trigger?(cycle, fill, effective_note, prev_notes)
    return true if @accum_prob.nil?
    # TODO: should `prev` probability mean "any *accumulation* triggered in the
    # previous slot" in this case?
    @accum_prob.should_trigger?(cycle, fill, self, effective_note, prev_notes)
  end

  # Returns a string representation of the step as Ruby code.
  # @param float_digits [Integer] The number of digits to show after the decimal
  #   point for floating point numbers.
  # @return [String]
  def repr(float_digits: 2)
    stringify = lambda do |val|
      if val.respond_to?(:repr)
        val.repr
      elsif val.is_a?(Symbol)
        ":#{val}"
      elsif val.is_a?(Float)
        if val == val.to_i
          val.to_i.to_s
        else
          format("%.*f", float_digits, val).delete_suffix("0")
        end
      else
        val.to_s
      end
    end

    args = ctor_args.map do |arg_name|
      raw_val = send(arg_name)
      raw_val.respond_to?(:repr) ? raw_val.repr : raw_val.to_s
    end

    kwargs = {}
    ctor_kwargs.each do |kwarg, defval|
      raw_val = send(kwarg)
      next if raw_val == defval
      kwargs[kwarg] = stringify.call(raw_val)
    end

    accum_args = {}
    unless @accum_delta == 0
      accum_kwargs.each do |kwarg, defval|
        raw_val = send(kwarg)
        next if raw_val == defval
        accum_kwarg_name = kwarg.to_s.delete_prefix("accum_").to_sym
        accum_args[accum_kwarg_name] = stringify.call(raw_val)
      end
    end

    # Assume that if the initializer accepts only one positional argument, and
    # that is enough to define the instance, that it is an acceptable shortcut
    # for the step. E.g. `Step.new(:c4)` is representable by just `:c4`.
    return args[0] if args.length == 1 && kwargs.empty? && @accum_delta == 0

    res = "#{repr_ctor_method}("

    res += args.join(", ")

    unless kwargs.empty?
      res += ", " unless args.empty?
      res += kwargs.map { |k, v| "#{k}: #{v}" }.join(", ")
    end

    res += ")"

    unless @accum_delta == 0
      res += ".accum(#{@accum_delta}"
      unless accum_args.empty?
        res += ", "
        res += accum_args.map { |k, v| "#{k}: #{v}" }.join(", ")
      end
      res += ")"
    end

    res
  end

  alias inspect repr


  protected

  # Symbols for additional positional arguments to the initializer, in order as
  # they are passed to it. Subclasses should override this method if they accept
  # such arguments. The symbols are expected to correspond to readable
  # instance attributes. Used to implement `repr` and `mutate`.
  def ctor_args
    []
  end

  # A hash of keyword arguments to the initializer and their default values.
  # Subclasses should override this method to add additional keyword arguments
  # that they accept. The keys are expected to correspond to readable instance
  # attributes. The standard accumulation arguments should *not* appear in this
  # hash. Used to implement `repr` and `mutate`.
  def ctor_kwargs
    {prob: nil}
  end

  # The string representation of the method to call to create a new instance of
  # this step class. Defaults to "<class name>.new"; if there is a shorthand
  # method, subclasses should return it here. Used to implement `repr`.
  def repr_ctor_method
    "#{self.class.name}.new"
  end

  def mutate(**mutations)
    args = ctor_args.map do |arg|
      mutations.delete(arg) || send(arg)
    end

    ctor_kwargs.each_key do |kwarg|
      mutations[kwarg] = send(kwarg) unless mutations.has_key?(kwarg)
    end

    accum_kwargs.each_key do |kwarg|
      mutations[kwarg] = send(kwarg) unless mutations.has_key?(kwarg)
    end

    # This one is not in accum_kwargs.
    mutations[:accum_delta] = @accum_delta unless mutations.has_key?(:accum_delta)

    self.class.new(*args, **mutations)
  end


  private

  # Converts its argument into an instance of Prob, if possible.
  def probify(prob)
    case prob
    when nil
      nil
    when Numeric
      Prob.chance(prob)
    when Prob
      prob
    else
      Prob.custom(prob)  # this will raise if this isn't an appropriate predicate
    end
  end

  # The accumulator-related keyword arguments to the initializer and their
  # default values. It is expected that each key corresponds to a readable
  # instance attribute. It is also expected that deleting the prefix "accum_"
  # from each key will result in a keyword argument to the `accum` method. Used
  # to implement `repr` and `mutate`.
  def accum_kwargs
    {
      accum_max: 12,
      accum_min: 0,
      accum_mode: :wrap,
      accum_prob: nil
    }
  end
end
