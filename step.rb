# frozen_string_literal: true

require_relative "theory/midinote"
require_relative "prob"


# An alias for Step.new.
def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


# TODO: legato?
# TODO: microtiming?
class Step
  attr_reader :note, :vel, :gate, :prob,
              :accum_delta, :accum_max, :accum_min, :accum_mode, :accum_prob

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
  #
  # Accumulation
  # With the `accum_*` parameters, a Step may be configured so that the note
  # that it actually plays changes by some number of accumulating number of
  # semitones each time it triggers.
  # The parameters are:
  # - accum_delta: The number of semitones to adjust `note` whenever the
  #   accumulation triggers. This value may be negative, but must be between
  #   `accum_min` and `accum_max` (exclusive).
  # - accum_max and accum_min: The acceptable range of the total semitone offset
  #   from `note`, inclusive. The behavior when the total offset exceeds one of
  #   these values is controlled by `accum_mode`.
  # - accum_mode: Controls the behavior when the total semitone offset via
  #   accumulation exceeds `accum_min`..`accum_max` (inclusive). Must be one of
  #   the following values:
  #     - :freeze - The offset will remain "stuck" at `accum_min` or
  #       `accum_max`; further accumulation triggers will have no effect.
  #     - :wrap - The offset will wrap around to the other extreme min or max.
  #       For example, if `accum_max` is 12 and an addition of `accum_delta`
  #       would result in an offset of 14, :wrap mode will convert that into an
  #       offset of `accum_min` + 2.
  #     - :reverse - When an extreme is reached, the value of `accum_delta` is
  #       effectively negated, so that the offset begins moving in the opposite
  #       direction.
  # - accum_prob: A callable lambda/proc that determines whether accumulation
  #   will trigger when the Step does. This has the same possible values as
  #   `prob` described above. Note that accumulation will only potentially
  #   trigger when the Step itself does. That is, the Step `prob` is a
  #   prerequisite for the evaluation of `accum_prob`.
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

    if prob.nil?
      @prob = nil
    elsif prob.is_a?(Numeric)
      @prob = Prob.chance(prob)
    elsif prob.is_a?(Prob)
      @prob = prob
    else
      @prob = Prob.custom(prob)  # this will raise if this isn't an appropriate predicate
    end

    raise ArgumentError, "accum_min must be <= 0" unless accum_min <= 0
    raise ArgumentError, "accum_delta must be between accum_min and accum_max" if accum_delta < accum_min || accum_delta > accum_max
    @accum_delta = accum_delta
    @accum_max = accum_max
    @accum_min = accum_min

    raise ArgumentError, "invalid accum_mode #{accum_mode}" unless %i[wrap reverse freeze].include?(accum_mode)
    @accum_mode = accum_mode

    if accum_prob.nil?
      @accum_prob = nil
    elsif accum_prob.is_a?(Numeric)
      @accum_prob = Prob.chance(accum_prob)
    elsif accum_prob.is_a?(Prob)
      @accum_prob = accum_prob
    else
      @accum_prob = Prob.custom(accum_prob)  # this will raise if this isn't an appropriate predicate
    end
  end

  private def mutate(**mutations)
    note = mutations.delete(:note) || @note
    [:vel, :gate, :prob, :accum_delta, :accum_max, :accum_min, :accum_mode, :accum_prob].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Step.new(note, **mutations)
  end

  # Returns a new Step with the given accumulation parameters set. Note that
  # parameters that are not provided will be set to default values.
  def accum(delta, min: 0, max: 12, mode: :wrap, prob: nil)
    mutate(accum_delta: delta, accum_min: min, accum_max: max, accum_mode: mode, accum_prob: prob)
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

    accum_args = {}
    unless @accum_delta == 0
      accum_args[:max] = @accum_max.to_s unless @accum_max == 12
      accum_args[:min] = @accum_min.to_s unless @accum_min == 0
      accum_args[:mode] = ":#{@accum_mode}" unless @accum_mode == :wrap
      accum_args[:prob] = @accum_prob.repr unless @accum_prob.nil?  # may throw
    end

    return @note.repr if ctor_args.empty? && accum_args.empty?

    res = "S(#{note.repr}"
    unless ctor_args.empty?
      res += ", "
      res += ctor_args.map { |k, v| "#{k}: #{v}" }.join(", ")
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
end
