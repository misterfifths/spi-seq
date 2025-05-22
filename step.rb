# frozen_string_literal: true

require_relative "stepbase"
require_relative "theory/midinote"


# An alias for Step.new.
def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


# TODO: legato?


# A Step represents a sequenceable MIDI note event which can appear in slots in
# the grid of a Track. See the documentation for StepBase for details about
# steps in general, and their probability and accumulation mechanics.
class Step < StepBase
  attr_reader :note, :vel, :gate

  # Constructs a Step.
  #
  # `note` can be a string, symbol, integer MIDI note, or MIDINote instance. The
  # `note` attribute always contains a MIDINote instance corresponding to the
  # argument.
  #
  # `vel` is the MIDI velocity for the note, 0 - 127. When played with Sonic
  # Pi's internal synthesis, the velocity will translate into the `amp` value
  # for the note.
  #
  # `gate` is the percentage of the duration of its slot for which the note will
  # be triggered. The note will not be played with a gate of 0. With a gate of
  # 1, the note is "tied". That is, it will continue without interruption if
  # there is a Step in the next played slot with the same note.
  #
  # Additional parameters are as described in the StepBase initializer.
  #
  # Accumulation on a Step manifests as a shift in the Step's note by the
  # accumulated number of semitones.
  def initialize(note, vel: 127, gate: 1.0, prob: nil,
                 accum_delta: 0, accum_max: 12, accum_min: 0, accum_mode: :wrap, accum_prob: nil)
    @note = MIDINote.new(note)

    @vel = vel.to_i
    if @vel < 0
      @vel = 0
    elsif @vel > 127
      @vel = 127
    end

    # TODO: quantize this?
    @gate = gate.to_f
    if @gate < 0.0
      @gate = 0.0
    elsif @gate > 1.0
      @gate = 1.0
    end

    super(prob: prob, accum_delta: accum_delta, accum_max: accum_max,
          accum_min: accum_min, accum_mode: accum_mode, accum_prob: accum_prob)
  end

  def with_note(new_note)
    mutate(note: new_note)
  end

  def with_vel(new_vel)
    mutate(vel: new_vel)
  end

  def shift_vel(shift)
    with_vel(@vel + shift)
  end

  def with_velf(new_velf)
    mutate(vel: new_velf * 127)  # this is clamped to 0-127 in the ctor
  end

  def shift_velf(shift)
    with_velf(velf + shift)
  end

  def with_gate(new_gate)
    mutate(gate: new_gate)
  end

  def shift_gate(shift)
    with_gate(@gate + shift)
  end

  def with_octave(new_octave)
    with_note(@note.with_octave(new_octave))
  end

  def shift_octave(shift)
    with_note(@note.shift_octave(shift))
  end

  # Adjusts the note by the given number of semitones.
  def shift_tone(shift)
    with_note(@note.shift_tone(shift))
  end

  alias transpose shift_tone

  def velf
    @vel / 127.0
  end

  def tied?
    @gate == 1.0  # rubocop:disable Lint/FloatComparison
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

  def repr_ctor_method
    "S"
  end
end
