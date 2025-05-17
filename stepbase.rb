# frozen_string_literal: true

require_relative "prob"


# TODO: microtiming?
# TODO: split accumulation stuff into a subclass? AccumulatingStep < StepBase?


# StepBase represents an event that can be sequenced in a slot inside a track.
# Do not make instances of StepBase directly; instead use one of its subclasses
# that specialize for a particular sort of event, like Step, which represents
# a MIDI note.
#
# A step has a probability (`prob`), an instance of Prob, which determines
# whether it should trigger when its slot is played back. It additionally has
# a variety of accumulation parameters, which determine changes to be made to
# the note each time it plays back. The effect of accumulation varies depending
# on the subclass. For example, for Steps, it applies a semitone offset to the
# note.
class StepBase
  attr_reader :prob,
              :accum_delta, :accum_max, :accum_min, :accum_mode, :accum_prob

  # Constructs a step.
  #
  # `prob` is the probability that the step will trigger. It should be either:
  # 1. nil - the step will always trigger
  # 2. a number between 0 and 1 inclusive that represents the chance that the
  #    step will trigger
  # 3. a callable predicate lambda/proc that takes the arguments described by
  #    `Prob.custom`. If the predicate returns true, the step will trigger.
  # 4. an instance of Prob. See that class for some common cases.
  #
  # Accumulation
  # With the `accum_*` parameters, a step may be configured so that it varies
  # by some accumulating amount each time it triggers. The actual effect of the
  # accumulation varies by subclass. For example, for Steps, it applies a
  # semitone offset to the Step's note.
  #
  # The accumulation parameters are:
  # - `accum_delta`: The amount to adjust the accumulation whenever it triggers.
  #   This value may be negative, but must be between `accum_min` and
  #   `accum_max` (exclusive).
  # - `accum_max` and `accum_min`: The acceptable range of the total
  #   accumulation, inclusive. The behavior when the total exceeds one of these
  #   values is controlled by `accum_mode`.
  # - `accum_mode`: Controls the behavior when the total accumulation exceeds
  #   `accum_min`..`accum_max` (inclusive). Must be one of the following values:
  #     - :freeze - The accumulation will remain "stuck" at `accum_min` or
  #       `accum_max`; further accumulation triggers will have no effect.
  #     - :wrap - The accumulation will wrap around to the other extreme min or
  #       max. For example, if `accum_max` is 12 and an addition of
  #       `accum_delta` would result in an accumulation of 14, :wrap mode will
  #       convert that into an accumulation of `accum_min` + 2.
  #     - :reverse - When an extreme is reached, the value of `accum_delta` is
  #       effectively negated, so that the accumulation begins moving in the
  #       opposite direction.
  # - `accum_prob`: A callable lambda/proc that determines whether accumulation
  #   will trigger when the Step does. This has the same possible values as
  #   `prob` described above. Note that accumulation will only potentially
  #   trigger when the step itself does. That is, the step `prob` is a
  #   prerequisite for the evaluation of `accum_prob`.
  def initialize(prob: nil,
                 accum_delta: 0, accum_max: 12, accum_min: 0, accum_mode: :wrap, accum_prob: nil)
    @prob = probify(prob)

    raise ArgumentError, "accum_min must be <= 0" unless accum_min <= 0
    raise ArgumentError, "accum_delta must be between accum_min and accum_max" if accum_delta < accum_min || accum_delta > accum_max
    @accum_delta = accum_delta
    @accum_max = accum_max
    @accum_min = accum_min

    raise ArgumentError, "invalid accum_mode #{accum_mode}" unless %i[wrap reverse freeze].include?(accum_mode)
    @accum_mode = accum_mode

    @accum_prob = probify(accum_prob)
  end

  # Returns a new step with the given accumulation parameters set. Note that
  # parameters that are not provided will be set to default values.
  def accum(delta, min: 0, max: 12, mode: :wrap, prob: nil)
    mutate(accum_delta: delta, accum_min: min, accum_max: max, accum_mode: mode, accum_prob: prob)
  end

  # Returns a new step with the given probability.
  def with_prob(new_prob)
    mutate(prob: new_prob)
  end

  # Returns whether this step should play in the given cycle of playback, with
  # the given set of notes played in the previous slot. This evaluates the
  # step's probability predicate.
  def should_trigger?(cycle, fill, effective_note, prev_notes)
    return true if @prob.nil?
    @prob.should_trigger?(cycle, fill, self, effective_note, prev_notes)
  end

  # Returns whether this step's accumulation should trigger, by evaluating
  # the accum_prob predicate.
  def accum_should_trigger?(cycle, fill, effective_note, prev_notes)
    return true if @accum_prob.nil?
    # TODO: should `prev` probability mean "any *accumulation* triggered in the
    # previous slot" in this case?
    @accum_prob.should_trigger?(cycle, fill, self, effective_note, prev_notes)
  end

  def repr
    args = ctor_args.map do |arg_name|
      raw_val = send(arg_name)
      raw_val.respond_to?(:repr) ? raw_val.repr : raw_val.to_s
    end

    kwargs = {}
    ctor_kwargs.each do |kwarg, defval|
      raw_val = send(kwarg)
      next if raw_val == defval
      kwargs[kwarg] = raw_val.respond_to?(:repr) ? raw_val.repr : raw_val.to_s
    end

    accum_args = {}
    unless @accum_delta == 0
      accum_kwargs.each do |kwarg, defval|
        raw_val = send(kwarg)
        next if raw_val == defval

        if raw_val.respond_to?(:repr)
          repr_val = raw_val.repr
        elsif raw_val.is_a?(Symbol)
          repr_val = ":#{raw_val}"
        else
          repr_val = raw_val.to_s
        end

        accum_kwarg_name = kwarg.to_s.delete_prefix("accum_").to_sym
        accum_args[accum_kwarg_name] = repr_val
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
