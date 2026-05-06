# frozen_string_literal: true

# Prob represents a predicate that determines whether or not a step will trigger
# when its slot in a track is played back (see {StepBase#prob}). Steps can have
# an additional Prob that controls whether their accumulation should apply,
# {StepBase#accum_prob}. Possible probabilities include a {.chance random
# chance}, or many conditions based on the state of playback - e.g.
# {.every_other every other cycle}, or only {.fill if the player is in fill
# mode}. Custom predicates can be created {.custom using a lambda}.
#
# Probs will be evaluated in a number of contexts:
# - For potential playback of a note-based {Step} in a {Track}.
# - For potential triggering of a {CCStep} in a {CCTrack}.
# - To determine whether to apply accumulation for any type of step, via
#   {StepBase#accum_prob}.
#
# In each of those contexts, certain Probs may or may not make sense. For
# instance, {.pre_same_note} is meaningless in CCTracks, where the steps do not
# represent notes. The documentation will call out such cases.
class Prob
  # Make a Prob with a custom trigger probability predicate defined by a lambda
  # or proc. The predicate must take between 0 and 5 arguments inclusive. It
  # will be called with a number of arguments based on that arity:
  #
  # 1. The {PlayerBase#cycle cycle number} of playback in the player.
  # 2. A boolean indicating whether {PlayerBase#fill fill mode} is active in the
  #    player.
  # 3. The step whose probability is being evaluated. The type of the step
  #    varies depending on the track being played: it will be a {Step} for
  #    {Track}s and a {CCStep} for {CCTrack}s.
  # 4. If the step belongs to a {Track} (and is thus an instance of {Step}),
  #    the resolved {MIDINote} that the Step would play if it triggers,
  #    accounting for any accumulation and the track's {Track#scale scale}. If
  #    the step is a CCStep, this argument is nil.
  # 5. If the step belongs to a {Track} (and is thus an instance of {Step}), an
  #    array of {MIDINote}s that were played in the slot immediately prior to
  #    the current one. If the step is a {CCStep}, this argument is an empty
  #    array.
  #
  # The predicate should return true if the step should trigger.
  #
  # @param [#call] callable
  # @return [Prob]
  def self.custom(callable)
    new(callable, "custom", nil)
  end

  # Returns a Prob that will trigger the step with the given probability (0 - 1
  # inclusive).
  # @param [Number] p
  # @return [Prob]
  def self.chance(p)
    new(->{ ExtApi.rand < p }, p.round(2).to_s, "chance(#{p})")
  end

  # Returns a Prob that will trigger the step with a probability of 1 in `n`.
  # @param [Integer] n
  # @return [Prob]
  def self.one_in(n)
    new(->{ ExtApi.one_in(n) }, "one in #{n}", "one_in(#{n})")
  end

  # Returns a Prob that will trigger the step in the `x`th out of each set of
  # `y` {PlayerBase#cycle cycles} of playback. `x` should be <= `y`. For
  # example, `x_of_y(3, 4)` means that the step will trigger on the third of
  # every four cycles.
  # @param [Integer] x
  # @param [Integer] y
  # @return [Prob]
  def self.x_of_y(x, y)
    new(->(cycle) { cycle % y == x - 1 }, "#{x}|#{y}", "x_of_y(#{x}, #{y})")
  end

  # Returns a Prob that will trigger the step every other {PlayerBase#cycle
  # cycle} of playback, beginning with the first. Equivalent to `x_of_y(1, 2)`.
  # @return [Prob]
  # @see .x_of_y
  # @see .every
  def self.every_other
    @every_other_inst ||= x_of_y(1, 2)
  end

  # Returns a Prob that will trigger the step on the first out of each set of
  # `n` {PlayerBase#cycle cycles} of playback. Equivalent to `x_of_y(1, n)`.
  # @param [Integer] n
  # @return [Prob]
  # @see .x_of_y
  # @see .every_other
  def self.every(n)
    x_of_y(1, n)
  end

  # Returns a Prob that will trigger the step on every {PlayerBase#cycle cycle}
  # *except* for the `x`th out of every `y` cycles of playback. This is the
  # inverse of {.x_of_y}.
  # @param [Integer] x
  # @param [Integer] y
  # @return [Prob]
  def self.not_x_of_y(x, y)
    new(->(cycle) { cycle % y != x - 1 }, "!#{x}|#{y}", "not_x_of_y(#{x}, #{y})")
  end

  # Returns a Prob that will trigger the step only on the first
  # {PlayerBase#cycle cycle} of playback.
  # @return [Prob]
  # @see .not_first
  def self.first
    @first_inst ||= new(->(cycle) { cycle == 0 }, "first", "first")
  end

  # Returns a Prob that will trigger the step on every {PlayerBase#cycle cycle}
  # of playback except the first. This is the inverse of {.first}.
  # @return [Prob]
  def self.not_first
    @not_first_inst ||= new(->(cycle) { cycle != 0 }, "!first", "not_first")
  end

  # Returns a Prob that will trigger the step if any step triggered in the
  # previously played slot.
  #
  # Note that this predicate is only applicable to {Step}s in {Track}s; it will
  # always evaluate to false for {CCStep}s in {CCTrack}s.
  #
  # @return [Prob]
  def self.pre
    @pre_inst ||= new(->(_, _, _, _, prev_notes) { !prev_notes.empty? }, "pre", "pre")
  end

  # Returns a Prob that will trigger the step if no step triggered in the
  # previously played slot.
  #
  # Note that this predicate is only applicable to {Step}s in {Track}s; it will
  # always evaluate to true for {CCStep}s in {CCTrack}s.
  #
  # @return [Prob]
  def self.not_pre
    @not_pre_inst ||= new(->(_, _, _, _, prev_notes) { prev_notes.empty? }, "!pre", "not_pre")
  end

  # Returns a Prob that will trigger the step if a step triggered in the
  # previously played slot with the same {Step#note note} as this step.
  #
  # Note that this predicate is only applicable to {Step}s in {Track}s; it will
  # always evaluate to false for {CCStep}s in {CCTrack}s.
  #
  # @return [Prob]
  def self.pre_same_note
    pred = ->(_, _, _, effective_note, prev_notes) { prev_notes.include?(effective_note) }
    @pre_same_note_inst ||= new(pred, "pre same note", "pre_same_note")
  end

  # Returns a Prob that will trigger the step only if none of the steps that
  # triggered in the previously played slot had the same {Step#note note} as
  # this step.
  #
  # Note that this predicate is only applicable to {Step}s in {Track}s; it will
  # always evaluate to true for {CCStep}s in {CCTrack}s.
  #
  # @return [Prob]
  def self.not_pre_same_note
    pred = ->(_, _, _, effective_note, prev_notes) { !prev_notes.include?(effective_note) }
    @not_pre_same_inst ||= new(pred, "!pre same note", "not_pre_same_note")
  end

  # Returns a Prob that will trigger the step if the {PlayerBase#fill fill
  # attribute} of the associated player is true.
  # @return [Prob]
  # @see .not_fill
  def self.fill
    @fill_inst ||= new(->(_, fill) { fill }, "fill", "fill")
  end

  # Returns a Prob that will trigger the step if the {PlayerBase#fill fill
  # attribute} of the associated player is false. This is the inverse of
  # {.fill}.
  # return [Prob]
  def self.not_fill
    @not_fill_inst ||= new(->(_, fill) { !fill }, "!fill", "not_fill")
  end

  # Evaluates the probability predicate, accounting for:
  # - `cycle`: The current cycle of playback of the track
  # - `fill`: The `fill` state of the player
  # - `step`: The step whose probability is being evaluated
  # - `effective_note`: The resolved MIDINote that the step will play, or nil if
  #   the step is not a Step instance.
  # - `prev_notes`: An array of MIDINotes that were triggered in the most recent
  #   slot that was played. If the associated track is not a Track instance,
  #   this should be the empty array.
  # @private
  def should_trigger?(cycle, fill, step, effective_note, prev_notes)
    args = [cycle, fill, step, effective_note, prev_notes].take(@callable.arity)
    @callable.call(*args)
  end

  # Returns a human-readable description of the Prob.
  # @return [String]
  def to_s
    @desc
  end

  # (see #to_s)
  def inspect
    "<Prob #{self}>"
  end

  # Returns a representation of the Prob as Ruby code. Note that this is
  # impossible for Probs made with {.custom}, and will raise an error in that
  # case.
  # @return [String]
  def repr
    raise ArgumentError, "cannot get code representation of probability #{self}" if @repr.nil?
    "Prob.#{@repr}"
  end


  private

  def initialize(callable, desc, repr)
    if callable.respond_to?(:call) && callable.respond_to?(:arity) && callable.arity <= 5
      @callable = callable
    else
      raise ArgumentError, "Invalid probability predicate: must be a callable that takes <= 5 arguments"
    end

    @desc = desc
    @repr = repr
  end
end
