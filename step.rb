# frozen_string_literal: true

require_relative "stepbase"
require_relative "theory/midinote"

# @!group Steps and tracks
# An alias for {Step#initialize Step.new}.
# @return [Step]
def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end
# @!endgroup


# TODO: legato?


# A Step represents a sequenceable MIDI note event which can appear in slots in
# the grid of a {Track}. See the documentation for {StepBase} for details about
# steps in general, and their probability and accumulation mechanics.
#
# Accumulation on a Step applies a semitone offset to the {#note} by default,
# but can also target the {#gate} or {#vel}.
#
# **Steps are immutable**. The mutation methods provided here, like
# {#with_note}, return new Steps that have all the same attributes as the
# receiver, with just the described change.
class Step < StepBase
  # The note that this step will play when triggered during playback.
  # @return [MIDINote]
  attr_reader :note

  # The velocity to use when playing this step over MIDI, 0 - 127 inclusive.
  #
  # When played with Sonic Pi's internal synthesis, the velocity will translate
  # into an `amp` value passed to `play`.
  #
  # @return [Integer]
  attr_reader :vel

  # The gate for this step as a percentage 0.0 - 1.0. This is the percentage of
  # the duration of a slot for which the step will trigger its note. For
  # instance, a value of 0.5 means the note will last half the duration of the
  # slot in the {Track} that contains it.
  #
  # The note will not be played with a gate of 0. With a gate of 1, the note is
  # "tied". That is, it will continue without interruption if there is a Step in
  # the next played slot with the same note.
  #
  # @return [Number]
  attr_reader :gate

  # Constructs a Step.
  #
  # `Step.new` is aliased to {S} for convenience.
  #
  # By default, accumulation on a Step manifests as a shift in the {#note} by
  # the accumulated number of semitones. It can also target the {#gate} or
  # {#vel} with the `accum_target` parameter.
  #
  # You may find it more convenient to set the accumulation parameters after
  # constructing a step with the {#accum} method.
  #
  # @param (see StepBase#initialize)
  # @param note [MIDINote, String, Symbol, Integer] The note this step will
  #   play when triggered. May be any value understood by {MIDINote.new}.
  # @param vel [Integer] The velocity to use when triggering a MIDI not event
  #   for the step. Values outside of 0 - 127 (inclusive) will be clamped to
  #   the nearest extreme. See {#vel}.
  # @param gate [Number] The gate for the note event, as a fraction of the
  #   duration of its slot. Values outside of 0.0 - 1.0 will be clamped to the
  #   nearest extreme. See {#gate}.
  def initialize(note, vel: 127, gate: 1.0, prob: nil,
                 accum_delta: 0, accum_max: 12, accum_min: 0,
                 accum_mode: :wrap, accum_prob: nil, accum_target: nil)
    @note = MIDINote.new(note)

    @vel = vel.to_i
    if @vel < 0
      @vel = 0
    elsif @vel > 127
      @vel = 127
    end

    @gate = gate.to_f
    if @gate < 0.0
      @gate = 0.0
    elsif @gate > 1.0
      @gate = 1.0
    end

    super(prob: prob, accum_delta: accum_delta, accum_max: accum_max,
          accum_min: accum_min, accum_mode: accum_mode,
          accum_prob: accum_prob, accum_target: accum_target)
  end

  # Returns a new Step with the given {#note}.
  # @param new_note [MIDINote, String, Symbol, Integer] A MIDINote or any value
  #   understood by {MIDINote.new}.
  # @return [Step]
  def with_note(new_note)
    mutate(note: new_note)
  end

  # Returns a new Step with the given {#vel velocity}. Values outside of 0 - 127
  # will be clamped.
  # @param new_vel [Integer] The new velocity; see {#vel}.
  # @return [Step]
  def with_vel(new_vel)
    mutate(vel: new_vel)
  end

  # Returns a new Step with a velocity equal to {#vel} plus `shift`. If the
  # resulting velocity is outside of 0 - 127, it will be clamped.
  # @param shift [Integer]
  # @return [Step]
  def shift_vel(shift)
    with_vel(@vel + shift)
  end

  # Returns a new Step with the given {#velf velocity}, expressed as a fraction
  # between 0 and 1. Values outside of that range will be clamped.
  # @param new_velf [Number]
  # @see #velf
  # @return [Step]
  def with_velf(new_velf)
    mutate(vel: new_velf * 127)  # this is clamped to 0-127 in the ctor
  end

  # Returns a new Step a velocity equal to the current {#velf} plus `shift`. If
  # the resulting velocity is outside of 0 - 127, it will be clamped.
  # @param shift [Number]
  # @return [Step]
  def shift_velf(shift)
    with_velf(velf + shift)
  end

  # Returns a new Step with the given {#gate}. If the value is outside of 0 - 1,
  # it will be clamped.
  # @param new_gate [Integer]
  # @return [Step]
  def with_gate(new_gate)
    mutate(gate: new_gate)
  end

  # Returns a new Step with a gate equal to {#gate} + shift. If the result is
  # outside of 0 - 1, it will be clamped.
  # @param shift [Integer]
  # @return [Step]
  def shift_gate(shift)
    with_gate(@gate + shift)
  end

  # Returns a new Step with a note that has the same pitch class as {#note} but
  # is in the given octave. For instance, `S(:c1).with_octave(5)` will return
  # a step with a note of C5.
  # @param new_octave [Integer]
  # @return [Step]
  def with_octave(new_octave)
    with_note(@note.with_octave(new_octave))
  end

  # Returns a new Step with a note that has the same pitch class as {#note} but
  # an octave offset by `shift`. For instance, `S(:c1).shift_octave(3)` will
  # return a step with a note of C4.
  # @param shift [Integer]
  # @return [Step]
  def shift_octave(shift)
    with_note(@note.shift_octave(shift))
  end

  # Returns a new Step with the same pitch class as {#note} but with its octave
  # shifted up by the given amount. This is equivalent to {#shift_octave}.
  # @param shift [Integer]
  # @return [Step]
  def up(shift = 1)
    shift_octave(shift)
  end

  # Returns a new Step with the same pitch class as {#note} but with its octave
  # shifted down by the given amount. This is equivalent to {#shift_octave} with
  # the negation of its argument.
  # @param shift [Integer]
  # @return [Step]
  def down(shift = 1)
    shift_octave(-shift)
  end

  # Returns a new Step with {#note} offset by the given number of semitones.
  # @param shift [Integer]
  # @return [Step]
  def transpose(shift)
    with_note(@note.transpose(shift))
  end

  alias shift_tone transpose
  alias t transpose

  # The velocity of this step, as a fraction between 0 and 1.
  # @return [Number]
  # @see #vel
  def velf
    @vel / 127.0
  end

  # Returns true if this step is tied; that is, its {#gate} is 1.
  # @return [Boolean]
  def tied?
    @gate == 1.0  # rubocop:disable Lint/FloatComparison
  end

  # @private
  def unique_slot_key
    @note.to_sym
  end


  protected

  def ctor_args
    [:note]
  end

  def ctor_kwargs
    kwargs = super
    kwargs[:vel] = 127
    kwargs[:gate] = 1
    kwargs
  end

  def default_accum_target
    :note
  end

  def valid_accum_targets
    %i[note gate vel]
  end

  def repr_ctor_method
    "S"
  end
end
