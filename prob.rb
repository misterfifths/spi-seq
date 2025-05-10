# frozen_string_literal: true

class Prob
  # Use a custom trigger probability predicate. The predicate must respond to
  # call and arity, and must have an arity between 0 and 3 inclusive. It will be
  # called with arguments based on its arity:
  # 1. cycle number
  # 2. a boolean indicating whether fill mode is active
  # 3. the Step
  # 4. the resolved MIDINote that the Step would play if it triggers
  # 5. an array of MIDINotes that were played in the slot immediately prior to
  #    the current one
  # The predicate should return true if the Step should trigger.
  def self.custom(callable)
    new(callable, "custom", nil)
  end

  # Step will trigger with the given probability (0-1 inclusive).
  def self.chance(p)
    new(->{ ExtApi.rand < p }, p.round(2).to_s, "chance(#{p})")
  end

  # Step will trigger with a probablity of 1 in n.
  def self.one_in(n)
    new(->{ ExtApi.one_in(n) }, "one in #{n}", "one_in(#{n})")
  end

  # Step is guaranteed to trigger the xth cycle out of each set of y cycles. x
  # should be <= y. For example, x_of_y(3, 4) means that the Step will trigger
  # on the third of every four cycles.
  def self.x_of_y(x, y)
    new(->(cycle) { cycle % y == x - 1 }, "#{x}|#{y}", "x_of_y(#{x}, #{y})")
  end

  # Step will trigger every other cycle, beginning with the first. Equivalent to
  # x_of_y(1, 2);
  def self.every_other
    @every_other_inst ||= x_of_y(1, 2)
  end

  # Step will trigger on the first cycle out of each set of n cycles. Equivalent
  # to x_of_y(1, n).
  def self.every(n)
    x_of_y(1, n)
  end

  # The inverse of x_of_y - the Step will trigger on every cycle except for the
  # xth out of every y cycles.
  def self.not_x_of_y(x, y)
    new(->(cycle) { cycle % y != x - 1 }, "!#{x}|#{y}", "not_x_of_y(#{x}, #{y})")
  end

  # Step will trigger only on the first cycle.
  def self.first
    @first_inst ||= new(->(cycle) { cycle == 0 }, "first", "first")
  end

  # Step will trigger on every cycle except the first.
  def self.not_first
    @not_first_inst ||= new(->(cycle) { cycle != 0 }, "!first", "not_first")
  end

  # Step will trigger if any step triggered in the previously played slot.
  def self.pre
    @pre_inst ||= new(->(_, _, _, _, prev_notes) { !prev_notes.empty? }, "pre", "pre")
  end

  # Step will trigger if no step triggered in the previously played slot.
  def self.not_pre
    @not_pre_inst ||= new(->(_, _, _, _, prev_notes) { prev_notes.empty? }, "!pre", "not_pre")
  end

  # Step will trigger if a step triggered in the previously played slot with the
  # same note as this step.
  def self.pre_same_note
    pred = ->(_, _, _, effective_note, prev_notes) { prev_notes.include?(effective_note) }
    @pre_same_note_inst ||= new(pred, "pre same note", "pre_same_note")
  end

  # Step will trigger only if none of the steps that triggered in the previously
  # played slot had the same note as this step.
  def self.not_pre_same_note
    pred = ->(_, _, _, effective_note, prev_notes) { !prev_notes.include?(effective_note) }
    @not_pre_same_inst ||= new(pred, "!pre same note", "not_pre_same_note")
  end

  def self.fill
    @fill_inst ||= new(->(_, fill) { fill }, "fill", "fill")
  end

  def self.not_fill
    @not_fill_inst ||= new(->(_, fill) { !fill }, "!fill", "not_fill")
  end

  # Evaluates the probability function, accounting for:
  # - cycle: The current cycle of playback of the Track
  # - fill: The fill state of the Player
  # - step: The Step whose probability is being evaluated
  # - effective_note: The resolved MIDINote that the Step will play
  # - prev_notes: An array of MIDINotes that were triggered in the most recent
  #   slot that was played
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
