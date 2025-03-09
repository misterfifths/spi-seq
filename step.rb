# frozen_string_literal: true

require_relative "midinote"
require_relative "prob"


# An alias for Step.new.
def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


# TODO: legato?
# TODO: microtiming?
class Step
  attr_reader :note, :vel, :gate, :prob

  # note can be a string, symbol, integer MIDI note, or MIDINote instance. The
  # note attribute always contains a MIDINote instance corresponding to the
  # argument.
  # vel is the MIDI velocity for the note, 0 - 127. When played with Sonic Pi's
  # internal synthesis, the velocity will translate into the `amp` value for the
  # note.
  # gate is the percentage of the duration of the step for which the note will
  # be triggered. The note will not be played with a gate of 0, and will be
  # tied to the following step (if any) with a gate of 1.
  # prob is the probability that the step will trigger. It should be either:
  # 1. nil - the Step will always trigger
  # 2. a number between 0 and 1 inclusive that represents the chance that the
  #    Step will trigger
  # 3. a callable predicate lambda/proc that takes the arguments described by
  #    Prob.custom. If the predicate returns true, the step will trigger.
  # 4. an instance of Prob. See that class for some common cases.
  def initialize(note, vel: 127, gate: 1.0, prob: nil)
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

    if prob.nil?
      @prob = nil
    elsif prob.is_a?(Numeric)
      @prob = Prob.chance(prob)
    elsif prob.is_a?(Prob)
      @prob = prob
    else
      @prob = Prob.custom(prob)  # this will raise if this isn't an appropriate predicate
    end
  end

  private def mutate(**mutations)
    note = mutations.delete(:note) || @note
    [:vel, :gate, :prob].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Step.new(note, **mutations)
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

  def with_prob(new_prob)
    mutate(prob: new_prob)
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

  # Returns whether this step should play in the given cycle of playback, with
  # the given set of notes played in the previous slot. This evaluates the
  # step's probability predicate.
  def should_trigger?(cycle, fill, prev_steps)
    return true if @prob.nil?
    @prob.should_trigger?(cycle, fill, self, prev_steps)
  end

  def inspect
    if @prob.nil?
      prob_desc = ""
    else
      prob_desc = " prob=#{@prob}"
    end
    "<Step #{@note}/#{@note.number} vel=#{@vel} gate=#{@gate}#{prob_desc}>"
  end

  def repr
    ctor_args = {}
    ctor_args[:vel] = @vel.to_s unless @vel == 127
    ctor_args[:gate] = @gate.to_s unless tied?
    ctor_args[:prob] = @prob.repr unless @prob.nil?  # prob.repr may throw

    if ctor_args.empty?
      @note.repr
    else
      kwargs = ctor_args.map { |k, v| "#{k}: #{v}" }.join(", ")
      "S(#{@note.repr}, #{kwargs})"
    end
  end
end
