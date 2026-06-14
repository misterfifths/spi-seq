# frozen_string_literal: true

require_relative "stepbase"

# @!group Steps and tracks
# An alias for {CCStep#initialize CCStep.new}.
# @return [CCStep]
def CC(*args, **kwargs)
  CCStep.new(*args, **kwargs)
end
# @!endgroup


# A CCStep represents a sequenceable MIDI CC event which can appear in slots in
# the grid of a {CCTrack}. See the {StepBase} documentation for details about
# steps in general, and their probability and accumulation mechanics.
#
# Accumulation on a CCStep applies an offset to the {#value} that will be sent
# for the CC.
#
# **CCSteps are immutable**. The mutation methods provided here, like
# {#with_value}, return new CCSteps that have all the same attributes as the
# receiver, with just the described change.
class CCStep < StepBase
  # The CC number for the event this step represents, 0 - 127 inclusive.
  # @return [Integer]
  attr_reader :cc
  alias cc_number cc
  alias number cc
  alias num cc

  # The value to send for the {#cc} when this step triggers, subject to
  # accumulation. The value is in 0 - 127, inclusive.
  # @return [Integer]
  attr_reader :value
  alias val value


  # Constructs a CCStep.
  #
  # `CCStep.new` is aliased to {CC} for convenience.
  #
  # Accumulation on a CCStep manifests as a shift in the {#value} by the
  # accumulated number.
  #
  # You may find it more convenient to set the accumulation parameters after
  # constructing a step with the {#accum} method.
  #
  # @param (see StepBase#initialize)
  # @param cc [Integer] The CC number for this event; see {#cc}. It is an error
  #   to pass a value outside of 0 - 127 inclusive.
  # @param value [Integer] The value for the CC event (subject to accumulation).
  #   Values outside of 0 - 127 (inclusive) will be clamped to the nearest
  #   extreme.
  def initialize(cc, value, prob: nil,
                 accum_delta: 0, accum_max: 12, accum_min: 0,
                 accum_mode: :wrap, accum_prob: nil, accum_target: nil)
    @cc = cc.to_i
    raise RangeError, "CC numbers must be between 0 and 127, inclusive" if @cc < 0 || @cc > 127

    @value = value.to_i
    if @value < 0
      @value = 0
    elsif @value > 127
      @value = 127
    end

    super(prob: prob, accum_delta: accum_delta, accum_max: accum_max,
          accum_min: accum_min, accum_mode: accum_mode,
          accum_prob: accum_prob, accum_target: accum_target)
  end

  # Returns a new CCStep with the given {#cc CC number}. It is an error to pass
  # a value outside of 0 - 127 inclusive.
  # @param new_cc [Integer]
  # @return [CCStep]
  def with_cc(new_cc)
    mutate(cc: new_cc)
  end
  alias with_cc_number with_cc
  alias with_number with_cc
  alias with_num with_cc

  # Returns a new CCStep with the given {#value}. Values outside of 0 - 127
  # will be clamped.
  # @param new_value [Integer]
  # @return [CCStep]
  def with_value(new_value)
    mutate(value: new_value)
  end
  alias with_val with_value

  # Returns a new CCStep with a value equal to {#value} plus `shift`. If the
  # resulting value is outside of 0 - 127, it will be clamped.
  # @param shift [Integer]
  # @return [CCStep]
  def shift_value(shift)
    mutate(value: @value + shift)
  end
  alias shift_val shift_value

  # @private
  def unique_slot_key
    @cc
  end

  protected

  def ctor_args
    [:cc, :value]
  end

  def default_accum_target
    :value
  end

  def valid_accum_targets
    [:value]
  end

  def repr_ctor_method
    "CC"
  end
end
