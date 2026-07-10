# frozen_string_literal: true

require_relative "../internal/random"
require_relative "../internal/utils"

module SpiSeq; module Tracks
  # Prob represents a predicate that determines whether or not a step will
  # trigger when its slot in a track is played back (see {StepBase#prob}). Steps
  # can have an additional Prob that controls whether their accumulation should
  # apply, {StepBase#accum_prob}. Possible probabilities include a {.chance
  # random chance}, or many conditions based on the state of playback - e.g.
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
  # instance, {.pre_same_note} is meaningless in CCTracks, where the steps do
  # not represent notes. The documentation will call out such cases.
  class Prob
    # Make a Prob with a custom trigger probability predicate defined by a
    # lambda or proc. The predicate may take some number of keyword arguments,
    # described below. None of the arguments are mandatory.
    #
    # - `cycle` (Integer): The {Playback::PlayerBase#cycle cycle number} of
    #   playback in the player.
    # - `fill` (Boolean): Whether {Playback::PlayerBase#fill fill mode} is
    #   active in the player.
    # - `step` ({StepBase}): The step whose probability is being evaluated. The
    #   type of the step varies depending on the track being played: it will be
    #   a {Step} for {Track}s and a {CCStep} for {CCTrack}s.
    # - `note` ({MIDINote}): If the step belongs to a {Track} (and is thus an
    #   instance of {Step}), the resolved note that the Step would play if it
    #   triggers, accounting for any accumulation and the track's {Track#scale
    #   scale}. If the step is a CCStep, this argument is nil.
    # - `prev_notes` (Array<{MIDINote}>): If the step belongs to a {Track} (and
    #   is thus an instance of {Step}), an array of the notes that were played
    #   in the slot immediately prior to the current one. If the step is a
    #   {CCStep}, this argument is an empty array.
    #
    # The predicate should return true if the step should trigger.
    #
    # @param [#call] callable
    # @return [Prob]
    def self.custom(callable) = new(callable, "custom", nil)

    # Returns a Prob that will trigger the step with the given probability
    # (0 - 1 inclusive).
    # @param [Number] p
    # @return [Prob]
    def self.chance(p) = new(->{ Internal::Random.chance(p) }, p.round(2).to_s, "chance(#{p})")

    # Returns a Prob that will trigger the step with a probability of 1 in `n`.
    # `n` must be > 0.
    # @param [Integer] n
    # @return [Prob]
    def self.one_in(n)
      raise ArgumentError, "n must be greater than zero" unless n > 0
      new(->{ Internal::Random.one_in(n) }, "one in #{n}", "one_in(#{n})")
    end

    # Returns a Prob that will trigger the step in the `x`th out of each set of
    # `y` {Playback::PlayerBase#cycle cycles} of playback. `x` should be <= `y`.
    # For example, `x_of_y(3, 4)` means that the step will trigger on the third
    # of every four cycles.
    # @param [Integer] x
    # @param [Integer] y
    # @return [Prob]
    def self.x_of_y(x, y) = new(->(cycle:) { cycle % y == x - 1 }, "#{x}|#{y}", "x_of_y(#{x}, #{y})")

    # Returns a Prob that will trigger the step every other
    # {Playback::PlayerBase#cycle cycle} of playback, beginning with the first.
    # Equivalent to `x_of_y(1, 2)`.
    # @return [Prob]
    # @see .x_of_y
    # @see .every
    def self.every_other = @every_other_inst ||= x_of_y(1, 2)

    # Returns a Prob that will trigger the step on the first out of each set of
    # `n` {Playback::PlayerBase#cycle cycles} of playback. Equivalent to
    # `x_of_y(1, n)`.
    # @param [Integer] n
    # @return [Prob]
    # @see .x_of_y
    # @see .every_other
    def self.every(n) = x_of_y(1, n)

    # Returns a Prob that will trigger the step on every
    # {Playback::PlayerBase#cycle cycle} *except* for the `x`th out of every `y`
    # cycles of playback. This is the inverse of {.x_of_y}.
    # @param [Integer] x
    # @param [Integer] y
    # @return [Prob]
    def self.not_x_of_y(x, y) = new(->(cycle:) { cycle % y != x - 1 }, "!#{x}|#{y}", "not_x_of_y(#{x}, #{y})")

    # Returns a Prob that will trigger the step only on the first
    # {Playback::PlayerBase#cycle cycle} of playback.
    # @return [Prob]
    # @see .not_first
    def self.first = @first_inst ||= new(->(cycle:) { cycle == 0 }, "first", "first")

    # Returns a Prob that will trigger the step on every
    # {Playback::PlayerBase#cycle cycle} of playback except the first. This is
    # the inverse of {.first}.
    # @return [Prob]
    def self.not_first = @not_first_inst ||= new(->(cycle:) { cycle != 0 }, "!first", "not_first")

    # Returns a Prob that will trigger the step if any step triggered in the
    # previously played slot.
    #
    # This predicate is only applicable to {Step}s in {Track}s; it will always
    # evaluate to false for {CCStep}s in {CCTrack}s.
    #
    # @return [Prob]
    def self.pre = @pre_inst ||= new(->(prev_notes:) { !prev_notes.empty? }, "pre", "pre")

    # Returns a Prob that will trigger the step if no step triggered in the
    # previously played slot.
    #
    # This predicate is only applicable to {Step}s in {Track}s; it will always
    # evaluate to true for {CCStep}s in {CCTrack}s.
    #
    # @return [Prob]
    def self.not_pre = @not_pre_inst ||= new(->(prev_notes:) { prev_notes.empty? }, "!pre", "not_pre")

    # Returns a Prob that will trigger the step if a step triggered in the
    # previously played slot with the same {Step#note note} as this step.
    #
    # This predicate is only applicable to {Step}s in {Track}s; it will always
    # evaluate to false for {CCStep}s in {CCTrack}s.
    #
    # Additionally, it is cyclical to use this as an
    # {StepBase#accum_prob accum_prob}, since the note that a Step will play is
    # dependent on the accumulation, which is dependent on the probability,
    # which is dependent on the accumulation, etc.. It will always evaluate to
    # false if used as an `accum_prob`.
    #
    # @return [Prob]
    def self.pre_same_note = @pre_same_note_inst ||= new(->(note:, prev_notes:) { prev_notes.include?(note) }, "pre same note", "pre_same_note")

    # Returns a Prob that will trigger the step only if none of the steps that
    # triggered in the previously played slot had the same {Step#note note} as
    # this step.
    #
    # This predicate is only applicable to {Step}s in {Track}s; it will always
    # evaluate to true for {CCStep}s in {CCTrack}s.
    #
    # Additionally, it is cyclical to use this as an
    # {StepBase#accum_prob accum_prob}, since the note that a Step will play is
    # dependent on the accumulation, which is dependent on the probability,
    # which is dependent on the accumulation, etc.. It will always evaluate to
    # true if used as an `accum_prob`.
    #
    # @return [Prob]
    def self.not_pre_same_note = @not_pre_same_inst ||= new(->(note:, prev_notes:) { !prev_notes.include?(note) }, "!pre same note", "not_pre_same_note")

    # Returns a Prob that will trigger the step if the
    # {Playback::PlayerBase#fill fill attribute} of the associated player is
    # true.
    # @return [Prob]
    # @see .not_fill
    def self.fill = @fill_inst ||= new(->(fill:) { fill }, "fill", "fill")

    # Returns a Prob that will trigger the step if the
    # {Playback::PlayerBase#fill fill attribute} of the associated player is
    # false. This is the inverse of {.fill}.
    # return [Prob]
    def self.not_fill = @not_fill_inst ||= new(->(fill:) { !fill }, "!fill", "not_fill")

    # Evaluates the probability predicate, accounting for:
    # - `cycle`: The current cycle of playback of the track
    # - `fill`: The `fill` state of the player
    # - `step`: The step whose probability is being evaluated
    # - `effective_note`: The resolved MIDINote that the step will play, or nil
    #   if the step is not a Step instance.
    # - `prev_notes`: An array of MIDINotes that were triggered in the most
    #   recent slot that was played. If the associated track is not a Track
    #   instance, this should be the empty array.
    # @private
    def should_trigger?(cycle:, fill:, step:, effective_note: nil, prev_notes: [])
      Internal::Utils.call_varargs(@callable, cycle:, fill:, step:, note: effective_note, prev_notes:)
    end

    # Returns a human-readable description of the Prob.
    # @return [String]
    def to_s = @desc
    alias to_str to_s

    # (see #to_s)
    def inspect = "<Prob #{self}>"

    # Returns a representation of the Prob as Ruby code.
    #
    # This is impossible for Probs made with {.custom}. For such Probs, if
    # `safe` is false, this method will raise. If `safe` is true, this method
    # will return a string that is not valid Ruby.
    #
    # @param safe [Boolean]
    # @return [String]
    def repr(safe: false)
      if @repr.nil?
        if safe
          return "<custom Prob>"
        else
          raise ArgumentError, "cannot get code representation of probability #{self}"
        end
      end

      @repr
    end

    # @private
    def ==(other)
      return true if equal?(other)
      return false unless other.is_a?(Prob)

      # Best we can do for custom probs is identity comparison on the proc.
      return @callable == other.callable if @repr.nil?

      # This isn't exactly ideal but only the tests really need this anyway.
      @repr == other.repr
    end
    alias eql? ==

    # @private
    def hash = @repr.nil? ? @callable.hash : @repr.hash


    protected

    attr_reader :callable


    private

    VALID_KEYWORDS = %i[cycle fill step note prev_notes].freeze
    private_constant :VALID_KEYWORDS

    def initialize(callable, desc, repr)
      req_pos_args, opt_pos_args, req_keywords, = Internal::Utils.describe_args(callable)
      # We could allow optional required arguments, but a Proc's positional
      # arguments are all reported as optional, so let's play it safe.
      raise ArgumentError, "custom predicates cannot have positional arguments" unless req_pos_args == 0 && opt_pos_args == 0
      raise ArgumentError, "predicate requires an invalid keyword argument" if req_keywords.any? { |k| !VALID_KEYWORDS.include?(k) }

      @callable = callable
      @desc = desc
      @repr = repr.nil? ? nil : "Prob.#{repr}"
    end
  end
end; end
