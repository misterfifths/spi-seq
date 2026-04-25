# frozen_string_literal: true

require_relative "stepbase"


# An alias for `CCStep.new`.
def CC(*args, **kwargs)
  CCStep.new(*args, **kwargs)
end


# A CCStep represents a sequenceable MIDI CC event which can appear in slots in
# the grid of a CCTrack. See the StepBase documentation for details about steps
# in general, and their probability and accumulation mechanics.
class CCStep < StepBase
  attr_reader :cc, :value
  alias cc_number cc
  alias number cc
  alias num cc
  alias val value


  # Constructs a CCStep.
  #
  # `cc` is the MIDI CC number which will be effected, 0 - 127 inclusive. It is
  # an error to pass a value outside of that range.
  #
  # `value` is the MIDI value to which the CC will be set, 0 - 127 inclusive.
  # Values outside of that range will be clamped to the nearest extreme.
  #
  # Additional parameters are as described in the StepBase initializer.
  #
  # Accumulation on a CCStep manifests as a shift in the CC value by the
  # accumulated value.
  def initialize(cc, value, prob: nil,
                 accum_delta: 0, accum_max: 12, accum_min: 0, accum_mode: :wrap, accum_prob: nil)
    @cc = cc.to_i
    raise RangeError, "CC numbers must be between 0 and 127, inclusive" if @cc < 0 || @cc > 127

    @value = value.to_i
    if @value < 0
      @value = 0
    elsif @value > 127
      @value = 127
    end

    super(prob: prob, accum_delta: accum_delta, accum_max: accum_max,
          accum_min: accum_min, accum_mode: accum_mode, accum_prob: accum_prob)
  end

  def with_cc(new_cc)
    mutate(cc: new_cc)
  end

  alias with_cc_number with_cc
  alias with_number with_cc
  alias with_num with_cc

  def with_value(new_value)
    mutate(value: new_value)
  end

  alias with_val with_value

  def shift_value(offset)
    mutate(value: @value + offset)
  end

  alias shift_val shift_value


  protected

  def ctor_args
    [:cc, :value]
  end

  def repr_ctor_method
    "CC"
  end
end
