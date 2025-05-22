# frozen_string_literal: true

require_relative "extapi"
require_relative "track"


# TODO: playhead direction - mostly just a matter of how we move the slot index
# in play, but also need to consider what "cycle" means in some of the weirder
# cases like a drunk walk.
# TODO: swing?
# TODO: seems like it would simplify a lot of code if we tracked the current
# playback slot in @track in an ivar.


# PlayerBase contains the core functionality for playing back tracks (i.e,
# subclasses of TrackBase). Do not make instances of PlayerBase directly;
# instead use one of its subclasses like Player, which handles note-based
# Track instances. But even then, it is unlikely you will make players directly,
# and instead use `track_live_loop`, which will create and manage an appropriate
# player for you.
#
# If you do want to manually drive a player, the most relevant methods are
# `play`, `stop`, and `sleep`. Note that playback is strictly cycle-based; the
# `play` method will play an entire cycle of the track before it returns. You
# can use `swap_track` between cycles to seamlessly switch to another track.
#
# The `cycle` attribute is the number of times the track has played. It begins
# at 0 and is incremented at the end of every `play` call. By default,
# `swap_track` does not reset the cycle.
#
# The `fill` attribute controls whether steps with the 'fill' probability are
# played. It may be changed at any point, even mid-cycle, and will take effect
# when the next slot is played.
#
# Notes for subclasses:
# - You must implement `play_slot` and `step_accum_should_trigger?`
# - If you have additional internal state, you should override `stop` to clear
#   it and `inherit_state` to propagate it to new player instances.
class PlayerBase
  attr_reader :track, :cycle
  attr_accessor :fill

  # Creates a new PlayerBase that will play the given track (an instance of a
  # subclass of TrackBase). If `debug` is true, detailed information about the
  # starting and stopping of steps will be printed.
  def initialize(track, debug: false)
    @track = track
    @debug = debug

    @fill = false

    stop
  end

  # Stops playback of the track. Intended to be called between cycles of the
  # track. Ends all ongoing steps and resets internal state like `cycle` and
  # accumulation state.
  def stop
    end_all_steps
    @cycle = 0
    @accum_data = {}  # Step hash keys (step_accum_hash_key) -> {delta:, direction:}
  end

  # Plays one cycle of the track. This method plays all slots in the track and
  # sleeps (i.e. Sonic Pi's `sleep`) for the full `beat_length` of the track.
  # The `cycle` is incremented just before this method returns.
  def play
    ExtApi.with_bpm_mul(@track.timescale) do
      @track.num_slots.times do |i|
        play_slot(i)

        # Sleep until it's time for the next slot
        ExtApi.sleep(@track.granularity.to_f)
      end
    end

    @cycle += 1
  end

  # Sleeps (i.e. Sonic Pi's `sleep`) for the duration of the track. All ongoing
  # steps are stopped.
  def sleep
    end_all_steps
    ExtApi.with_bpm_mul(@track.timescale) do
      ExtApi.sleep(@track.beat_length)
    end
  end

  # Swap out the track this player plays for `new_track`. Resets the cycle count
  # to 0 if `reset_cycle` is true.
  #
  # This is intended to be called between calls to `play` or `sleep`. The new
  # track will take effect on the next `play` or `sleep`, beginning from slot 0.
  #
  # The set of currently playing steps is not reset; the transition to the new
  # track will seamlessly continue any ongoing steps.
  def swap_track(new_track, reset_cycle: false)
    @track = new_track
    @cycle = 0 if reset_cycle

    # TODO: clear accum_data?
  end

  # Inherits the state of another player, including the set of ongoing steps.
  # This is an internal method intended to be called when one player is handing
  # over playback to another, such as when a sketch is restarted.
  #
  # Subclasses should override this to propagate any extra internal state from
  # `other` to this player.
  def inherit_state(other)
    @cycle = other.cycle
    @fill = other.fill
    @accum_data = other.accum_data
  end


  protected

  attr_reader :accum_data

  # Returns a hash key for the given step from the given slot in @track, to be
  # used when indexing @accum_data.
  def step_accum_hash_key(step, slot_idx)
    # Since they're immutable, Steps could theoretically be shared across
    # multiple slots in different tracks. So we need to hash based on enough
    # information to uniquely identify the step within the track.
    [step.object_id, slot_idx, @track.object_id]
  end

  # Returns the current accumulation delta for the given step from the given
  # slot in @track. Returns 0 if there is no accumulation for the step.
  # Note: this is only valid for the current slot, after `apply_accum` has been
  # called.
  def accum_delta_for_step(step, slot_idx)
    data = @accum_data[step_accum_hash_key(step, slot_idx)]
    data.nil? ? 0 : data[:delta]
  end

  # Evaluate the `accum_prob` of the given step from the given slot in @track.
  # Subclasses must implement this method by calling `accum_should_trigger?` on
  # the step with as much information as it can provide about the current state
  # of playback.
  def step_accum_should_trigger?(_step, _slot_idx)
    raise "subclasses must implement step_accum_should_trigger?"
  end

  # Updates the accumulation state of the given Step, which is assumed to be
  # triggering (i.e. its `prob` predicate passed). Evaluates the Step's
  # `accum_prob` (if any) and updates the Step's entry in @accum_data
  # appropriately with the new total semitone delta and other state.
  def apply_accum(step, slot_idx)
    return if step.accum_delta == 0

    hash_key = step_accum_hash_key(step, slot_idx)
    data = @accum_data[hash_key]
    if data.nil?
      # This is the first time we've seen this Step. Accumulation should not
      # trigger, but we should make a note that we've seen it so that we may
      # trigger it the next time it plays.
      @accum_data[hash_key] = { delta: 0, direction: 1 }
      return
    end

    # This Step has played before, and its accumulation may trigger.
    return unless step_accum_should_trigger?(step, slot_idx)

    delta = data[:delta] + data[:direction] * step.accum_delta
    if delta < step.accum_min
      case step.accum_mode
      when :freeze
        delta = step.accum_min
      when :reverse
        data[:direction] *= -1
        delta += data[:direction] * step.accum_delta
      when :wrap
        # We know accum_min <= accum_delta <= accum_max, so we don't need to
        # worry about modding to get the overage here; we can just subtract.
        overage = step.accum_min - delta
        delta = step.accum_max - overage
      end
    elsif delta > step.accum_max
      case step.accum_mode
      when :freeze
        delta = step.accum_max
      when :reverse
        data[:direction] *= -1
        delta += data[:direction] * step.accum_delta
      when :wrap
        overage = delta - step.accum_max
        delta = step.accum_min + overage
      end
    end

    data[:delta] = delta
  end

  # Plays the slot at index `i`. Subclasses must implement this method. In
  # general, they should:
  #
  # 1. Gather steps from slot `i` and filter out ones whose probabilities
  #    indicate that they ought not to play.
  # 2. Apply accumulation for each newly triggered step via `apply_accum`.
  # 3. Update the state of the world by activating new steps (accounting for
  #    accumulation) and, possibly, terminating ongoing ones. E.g., Track plays
  #    new notes, continues ties, and terminates ongoing notes that are no
  #    longer playing in the current slot. Note that this step may involve some
  #    elaborate subclass-specific state tracking.
  #
  # Note: To support changing the playhead direction and swapping between
  # tracks, it is important that this method does not assume anything about the
  # order in which slots were or will be played. It must base its logic solely
  # on the contents of slot `i` and possibly some subclass-specific internal
  # state tracking the steps played in the most recent call to `play_slot`. The
  # next steps may not come from slot `i + 1`, and the previous ones may not
  # have come from slot `i - 1`. In fact they may not even be from this track,
  # if the track was swapped.
  def play_slot(_i)
    raise "subclasses must implement play_slot"
  end

  # End all ongoing steps. Subclasses that manage steps that linger for a
  # duration after they are triggered should implement this method and
  # immediately terminate all such steps. Called by `stop` and `sleep`.
  def end_all_steps; end
end
