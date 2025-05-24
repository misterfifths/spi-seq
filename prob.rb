# frozen_string_literal: true

# Prob represents a predicate that determines whether or not a step will trigger
# when its slot in a track is played back. Examples of options include a simple
# probability, a condition based on the state of playback (e.g. every other
# cycle), or the `fill` state of the player. Custom predicates can be created
# based on a lambda.
#
# Note that Probs will be evaluated in a number of contexts:
# - For potential playback of a note-based Step in a Track.
# - For potential triggering of a CCStep in a CCTrack.
# - To determine whether to apply accumulation for any type of step, via the
#   `accum_prob` attribute of StepBase.
#
# In each of those contexts, certain Prob types may or may not make sense. Read
# the documentation below for details.
class Prob
  # Use a custom trigger probability predicate. The predicate must respond to
  # `call` and `arity`, and must have an arity between 0 and 3 inclusive. It
  # will be called with a number of arguments based on that arity:
  #
  # 1. The cycle number of playback in the player.
  # 2. A boolean indicating whether `fill` mode is active in the player.
  # 3. The step whose probability is being evaluated, an instance of StepBase.
  # 4. If the step belongs to a Track (and is thus an instance of Step), the
  #    resolved MIDINote that the Step would play if it triggers. If the step
  #    is a CCStep, this argument is nil.
  # 5. If the step belongs to a Track (and is thus an instance of Step), an
  #    array of MIDINotes that were played in the slot immediately prior to
  #    the current one. If the step is a CCStep, this argument is an empty
  #    array.
  #
  # The predicate should return true if the step should trigger.
  def self.custom(callable)
    new(callable, "custom", nil)
  end

  # The step will trigger with the given probability (0 - 1 inclusive).
  def self.chance(p)
    new(->{ ExtApi.rand < p }, p.round(2).to_s, "chance(#{p})")
  end

  # The step will trigger with a probablity of 1 in `n`.
  def self.one_in(n)
    new(->{ ExtApi.one_in(n) }, "one in #{n}", "one_in(#{n})")
  end

  # The step is guaranteed to trigger the `x`th out of each set of `y` cycles of
  # playback. `x` should be <= `y`. For example, `x_of_y(3, 4)` means that the
  # step will trigger on the third of every four cycles.
  def self.x_of_y(x, y)
    new(->(cycle) { cycle % y == x - 1 }, "#{x}|#{y}", "x_of_y(#{x}, #{y})")
  end

  # The step will trigger every other cycle of playback, beginning with the
  # first. Equivalent to `x_of_y(1, 2)`.
  def self.every_other
    @every_other_inst ||= x_of_y(1, 2)
  end

  # The step will trigger on the first out of each set of `n` cycles of
  # playback. Equivalent to `x_of_y(1, n)`.
  def self.every(n)
    x_of_y(1, n)
  end

  # The inverse of `x_of_y` - the step will trigger on every cycle except for
  # the `x`th out of every `y` cycles of playback.
  def self.not_x_of_y(x, y)
    new(->(cycle) { cycle % y != x - 1 }, "!#{x}|#{y}", "not_x_of_y(#{x}, #{y})")
  end

  # The step will trigger only on the first cycle of playback.
  def self.first
    @first_inst ||= new(->(cycle) { cycle == 0 }, "first", "first")
  end

  # The step will trigger on every cycle of playback except the first.
  def self.not_first
    @not_first_inst ||= new(->(cycle) { cycle != 0 }, "!first", "not_first")
  end

  # The step will trigger if any step triggered in the previously played slot.
  #
  # Note that this predicate is only applicable to Steps; it will always
  # evaluate to false for CCSteps in CCTracks.
  def self.pre
    @pre_inst ||= new(->(_, _, _, _, prev_notes) { !prev_notes.empty? }, "pre", "pre")
  end

  # The step will trigger if no step triggered in the previously played slot.
  #
  # Note that this predicate is only applicable to Steps; it will always
  # evaluate to true for CCSteps in CCTracks.
  def self.not_pre
    @not_pre_inst ||= new(->(_, _, _, _, prev_notes) { prev_notes.empty? }, "!pre", "not_pre")
  end

  # The will trigger if a step triggered in the previously played slot with the
  # same note as this step.
  #
  # Note that this predicate is only applicable to Steps; it will always
  # evaluate to false for CCSteps in CCTracks.
  def self.pre_same_note
    pred = ->(_, _, _, effective_note, prev_notes) { prev_notes.include?(effective_note) }
    @pre_same_note_inst ||= new(pred, "pre same note", "pre_same_note")
  end

  # The step will trigger only if none of the steps that triggered in the
  # previously played slot had the same note as this step.
  #
  # Note that this predicate is only applicable to Steps; it will always
  # evaluate to true for CCSteps in CCTracks.
  def self.not_pre_same_note
    pred = ->(_, _, _, effective_note, prev_notes) { !prev_notes.include?(effective_note) }
    @not_pre_same_inst ||= new(pred, "!pre same note", "not_pre_same_note")
  end

  # The step will trigger if the `fill` attribute of the associated player is
  # true.
  def self.fill
    @fill_inst ||= new(->(_, fill) { fill }, "fill", "fill")
  end

  # The step will trigger if the `fill` attribute of the associated player is
  # false.
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
  def should_trigger?(cycle, fill, step, effective_note, prev_notes)
    args = [cycle, fill, step, effective_note, prev_notes].take(@callable.arity)
    @callable.call(*args)
  end

  def to_s
    @desc
  end

  def inspect
    "<Prob #{self}>"
  end

  def repr
    raise "cannot get code representation of probability #{self}" if @repr.nil?
    "Prob.#{@repr}"
  end


  private

  def initialize(callable, desc, repr)
    if callable.respond_to?(:call) && callable.respond_to?(:arity) && callable.arity <= 5
      @callable = callable
    else
      raise "Invalid probability predicate: must be a callable that takes <= 5 arguments"
    end

    @desc = desc
    @repr = repr
  end
end
