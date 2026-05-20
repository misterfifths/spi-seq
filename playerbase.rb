# frozen_string_literal: true

require_relative "extapi"
require_relative "trackbase"


# TODO: playhead direction - mostly just a matter of how we move the slot index
# in play, but also need to consider what "cycle" means in some of the weirder
# cases like a drunk walk.
# TODO: swing?
# TODO: seems like it would simplify a lot of code if we tracked the current
# playback slot in @track in an ivar.


# PlayerBase contains the core functionality for playing back tracks (i.e,
# subclasses of {TrackBase}). Do not make instances of PlayerBase directly.
# Instead use one of its subclasses: {Player} which handles note-based
# {Track}s, or {CCPlayer} which handles {CCTrack}s. But even then, it is
# unlikely you will make explicitly make a player. Instead use
# {track_live_loop}, which will create and manage an appropriate player for you.
#
# If you do want to manually drive a player, the most relevant methods are
# {#play}, {#stop}, and {#sleep}. Note that playback is strictly cycle-based;
# the `play` method will play an entire cycle of the track before it returns.
# You can use {#swap_track} between cycles to seamlessly switch to another
# track.
#
# The {#cycle} attribute tracks the number of times the track has played. It
# begins at 0 and is incremented at the end of every {#play} call. A call to
# {#sleep} does not increment `cycle`.
#
# The {#fill} attribute controls whether steps with the {Prob.fill}
# {StepBase#prob probability} are played. It may be changed at any point, even
# mid-cycle, and will take effect when the next slot is played. When using a
# {track_live_loop} for playback, you can assign a MIDI CC that will toggle
# fill mode with the `fill_cc` parameter.
#
# @abstract Subclasses must implement `play_steps`, `accum_should_trigger?`, and
#   `step_should_trigger?`. If the subclass has additional internal state, it
#   should override `stop` to clear it and `inherit_state` to propagate it to
#   new player instances. There are additional override points that may be of
#   use.
class PlayerBase
  # The track that will be used when {#play} and {#sleep} are called. You may
  # swap to a new track between cycles of playback with {#swap_track}.
  # @return [TrackBase]
  attr_reader :track

  # The number of times this player has played a track. Incremented at the end
  # of every call to {#play}. Reset by {#stop}, and optionally by {#swap_track}.
  # A call to {#sleep} does not increment the cycle.
  # @return [Integer]
  attr_reader :cycle

  # Whether the player is in fill mode. In fill mode steps with a
  # {StepBase#prob probability} of {Prob.fill} will trigger, and those with
  # {Prob.not_fill} will not. Fill mode can be toggled at any point during
  # playback and will take effect when the next slot is played.
  # @return [Boolean]
  attr_accessor :fill

  # Creates a new PlayerBase that will play the given track.
  # @param track [TrackBase] The initial value for {#track}.
  # @param debug [Boolean] If true, the player will log detailed information
  #   about its state during playback.
  def initialize(track, debug: false)
    @track = track
    @debug = debug

    @fill = false

    stop
  end

  # Cleans up after a track has been played via {#play}. Intended to be used
  # when the player is no longer necessary or if you want to restart it with a
  # clean slate. Ends all ongoing steps and resets the internal state, like
  # `cycle` and accumulation values.
  # @return [void]
  def stop
    end_all_steps
    @cycle = 0
    @accum_data = {}  # Step hash keys (step_accum_hash_key) -> {delta:, direction:}
  end

  # Plays one cycle of the track. This method plays all slots in the track and
  # sleeps (i.e. Sonic Pi's `sleep`) for the full {TrackBase#beat_length length}
  # of the track. It honors the track's {TrackBase#timescale timescale} by
  # internally applying a BPM multiplier.
  #
  # The {#cycle} is incremented just before this method returns.
  #
  # @return [void]
  def play
    @slot_idx = 0
    reset_for_new_cycle

    ExtApi.with_bpm_mul(@track.timescale) do
      @track.num_slots.times do |i|
        @slot_idx = i

        calculate_pending_accums
        slot_advanced
        triggering_steps = current_steps.filter { |step| step_should_trigger?(step) }
        commit_accums(triggering_steps)
        accums_committed
        play_steps(triggering_steps)

        # Sleep until it's time for the next slot
        ExtApi.sleep(@track.granularity.to_f)
      end
    end

    @cycle += 1
  end

  # Sleeps (i.e. Sonic Pi's `sleep`) for the duration of the track. All ongoing
  # steps are stopped. The {#cycle} is not incremented.
  # @return [void]
  def sleep
    end_all_steps
    ExtApi.with_bpm_mul(@track.timescale) do
      ExtApi.sleep(@track.beat_length)
    end
  end

  # Swap out the track this player plays.
  #
  # This is intended to be called between calls to {#play} or {#sleep}. The new
  # track will take effect on the next `play` or `sleep`, beginning with its
  # first slot.
  #
  # The set of currently playing steps is not reset; the transition to the new
  # track will seamlessly continue any ongoing steps. For instance, when using
  # a {Player}, if the prior track ended in a tied C4 and the new track begins
  # with a C4, that note will continue without interruption.
  #
  # If you swap to another track, the accumulation state for the current track
  # is cleared (i.e., if you later swap back to the same track, the accumulation
  # of all of its steps will reset). If you call this with the same track as
  # {#track}, accumulation is not reset.
  #
  # @param new_track [TrackBase] The track to use on the next call to {#play} or
  #   {#sleep}.
  # @param reset_cycle [Boolean] If true, resets {#cycle} to 0.
  # @return [void]
  def swap_track(new_track, reset_cycle: false)
    @accum_data&.clear unless @track.equal?(new_track)

    @track = new_track
    @cycle = 0 if reset_cycle
  end

  # Inherits the state of another player, including the set of ongoing steps.
  # This is an internal method intended to be called when one player is handing
  # over playback to another, such as when a sketch is restarted.
  #
  # Subclasses should override this to propagate any extra internal state from
  # `other` to this player.
  #
  # @private
  def inherit_state(other)
    @cycle = other.cycle
    @fill = other.fill
    @accum_data = other.instance_variable_get(:@accum_data)
  end


  protected

  # Note to subclassers:
  # The flow during playback is a little tricky.
  # First, `play` calls `reset_for_new_cycle`. The default does nothing.
  # Then, it iterates over the slots in the track. For each, it:
  # 1. Updates `slot_idx` to the current slot.
  # 2. Calculates potential accumulations for the steps in that slot, calling
  #    `accum_should_trigger?` as needed, which must be implemented.
  # 3. Calls `slot_advanced`. The default does nothing.
  # 4. Gathers the steps that will trigger in this slot by calling
  #    `step_should_trigger?`. Subclassers must implement that method by
  #    evaluating probabilities. If it is needed to evaluate a probability, the
  #    `accum_delta` method may be used at this point to retrieve the
  #    accumulation the step would have if it were to trigger.
  # 5. Commits the accumulation for triggering steps and calls
  #    `accums_committed`. The default does nothing.
  # 6. Calls `play_steps` (must be implemented) with the steps that will
  #    trigger, as determined in step 4.
  # 7. Sleeps until it's time for the next slot.


  # The current index in the track's grid.
  # Note: To support changing the playhead direction and swapping between
  # tracks, it is important that subclassers do not assume anything about the
  # order in which slots were or will be played. They must base their logic
  # solely on the contents of this slot index and possibly some subclass-
  # specific internal state tracking the steps played in the most recent slot.
  # The next steps may not come from slot `slot_idx + 1`, and the previous ones
  # may not have come from slot `slot_idx - 1`. In fact they may not even be
  # from this track, if the track was swapped.
  attr_reader :slot_idx

  # The steps in the current slot in the track.
  def current_steps
    @track.grid[@slot_idx]
  end

  # Called by `play` before beginning a cycle of playback. Provided for use by
  # subclassers.
  def reset_for_new_cycle; end

  # Called by `play` at the beginning of the process to play a slot. `slot_idx`
  # is the new index in the track. Provided for use by subclassers.
  def slot_advanced; end

  # Called by `play` after `triggering_steps_at_slot` has been used to determine
  # which steps should have their accumulation committed. Provided for use by
  # subclassers.
  def accums_committed; end

  # Evaluate the `accum_prob` of the given step in the current slot of @track.
  # Called by `play` at the beginning of the process to play a new slot, before
  # `slot_advanced`. Subclasses must implement this method by calling
  # `accum_should_trigger?` on the step with as much information as it can
  # provide about the current state of playback. It is not legal to call
  # `accum_delta` at this point, since this method is used in the process of
  # calculating those deltas.
  def accum_should_trigger?(_step)
    raise RuntimeError, "subclasses must implement accum_should_trigger?"
  end

  # Evaluate the `prob` of the given step in the current slot of @track. Called
  # by `play` after `slot_advanced`. Subclasses must implement this method by
  # calling `should_trigger?` on the step with as much information as it can
  # provide about the current state of playback. If necessary, subclasses can
  # peek at the potential accumulation for the step with `accum_delta`.
  def step_should_trigger?(_step)
    raise RuntimeError, "subclasses must implement step_should_trigger?"
  end

  # Play the given steps, which are the triggering ones from the current slot.
  # Subclasses must implement this method. In general, they should:
  # 1. Activate the given steps, taking into account their accumulation from
  #    `accum_delta`. For example, a player for Tracks should sound new notes
  #    and continue ties.
  # 2. If necessary, terminate any ongoing steps that are not continued by a
  #    triggering step. For example, a player for Tracks would terminate any
  #    ties that are not continued in the current slot. Since CC events in a
  #    CCTrack are instantaneous, a player for those tracks does not need to
  #    consider such a thing.
  #
  # Note that there may be some elaborate subclass-specific tracking involved to
  # keep track of the world state.
  def play_steps(_steps)
    raise RuntimeError, "subclasses must implement play_steps"
  end

  # Returns the current accumulation delta for the given step in the current
  # slot in @track. Returns 0 if there is no accumulation for the step. This
  # cannot be called until `slot_advanced` (e.g., it is illegal in
  # `accum_should_trigger?`). If this is called before `play_steps`, it
  # represents the potential accumulation a step would have if it were to
  # trigger. If the step does not end up triggering, a call to this method in
  # `play_steps` will return the previous accumulation.
  def accum_delta(step)
    raise ArgumentError, "step is not in the current slot" unless current_steps.include?(step)
    raise RuntimeError, "accumulation deltas are being calculated" if @calculating_pending_accums

    data = @pending_accum_data.nil? ? accum_data(step) : pending_accum_data(step)
    data.nil? ? 0 : data[:delta]
  end

  # End all ongoing steps. Subclasses that manage steps that linger for a
  # duration after they are triggered should implement this method and
  # immediately terminate all such steps. Called by `stop` and `sleep`.
  def end_all_steps; end


  private

  # Returns a hash key for the given step in the current slot in @track, to be
  # used when indexing @accum_data or @pending_accum_data.
  def accum_hash_key(step)
    # Since they're immutable, Steps could theoretically be shared across
    # multiple slots. So we need to hash based on both the step and the slot
    # that contains it.
    [step.object_id, @slot_idx].freeze
  end

  def accum_data(step)
    @accum_data[accum_hash_key(step)]
  end

  def pending_accum_data(step)
    @pending_accum_data[accum_hash_key(step)]
  end

  def set_accum_data(step, data)
    @accum_data[accum_hash_key(step)] = data
  end

  def set_pending_accum_data(step, data)
    @pending_accum_data[accum_hash_key(step)] = data
  end

  # Returns the new accumulation data entry for the step (in the current slot of
  # @track), if the step were to trigger in this cycle of playback. Does not
  # commit any changes to @accum_data. Evaluates the step's accum_prob using
  # step_accum_should_trigger? Returns nil if the step has no accumulation.
  # Returns the current data if the accumulation would not trigger.
  def calculate_accum(step)
    return nil if step.accum_delta == 0

    data = accum_data(step)
    if data.nil?
      # This is the first time we've seen this Step. Accumulation should not
      # trigger, but we should make a note that we've seen it so that we may
      # trigger it the next time it plays.
      return { delta: 0, direction: 1 }
    end

    # This Step has played before, and its accumulation may trigger.
    return data unless accum_should_trigger?(step)

    direction = data[:direction]
    delta = data[:delta] + data[:direction] * step.accum_delta
    if delta <= step.accum_min
      case step.accum_mode
      when :freeze
        delta = step.accum_min
      when :reverse
        # Always reverse direction, but only immediately apply a reversal if we
        # already stepped below the min. If we are exactly at the minimum, then
        # do not change the delta and wait for the next accumulation to take the
        # first step in the right direction.
        direction *= -1
        if delta < step.accum_min
          overage = step.accum_min - delta - 1
          delta = step.accum_min + overage
        end
      when :wrap
        # Again, only actually start wrapping if we already stepped below the
        # min. The next accumulation will take delta below the min and handle
        # the first wrap.
        if delta < step.accum_min
          # We know accum_min <= accum_delta <= accum_max, so we don't need to
          # worry about modding to get the overage here; we can just subtract.
          overage = step.accum_min - delta - 1
          delta = step.accum_max - overage
        end
      end
    elsif delta >= step.accum_max
      case step.accum_mode
      when :freeze
        delta = step.accum_max
      when :reverse
        direction *= -1
        if delta > step.accum_max
          overage = delta - step.accum_max - 1
          delta = step.accum_max - overage
        end
      when :wrap
        if delta > step.accum_max
          overage = delta - step.accum_max - 1
          delta = step.accum_min + overage
        end
      end
    end

    { direction: direction, delta: delta }
  end

  def calculate_pending_accums
    # Collect potential accumulations for peeking purposes. We'll commit the
    # ones for steps that actually trigger in commit_accums.
    @calculating_pending_accums = true  # accum_delta inspects this
    @pending_accum_data = {}
    current_steps.each do |step|
      new_data = calculate_accum(step)
      set_pending_accum_data(step, new_data) unless new_data.nil?
    end
    @calculating_pending_accums = false
  end

  def commit_accums(steps)
    # Commit accumulations for steps that will trigger.
    steps.each do |step|
      raise ArgumentError, "step is not in the current slot" unless current_steps.include?(step)

      data = pending_accum_data(step)
      set_accum_data(step, data) unless data.nil?
    end

    # Causes accum_delta to use the committed values.
    @pending_accum_data = nil
  end
end
