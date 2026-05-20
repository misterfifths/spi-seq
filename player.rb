# frozen_string_literal: true

require_relative "extapi"
require_relative "playerbase"
require_relative "track"

# @!group Playback and live loops

# Set global default {Player} and {track_live_loop} behaviors. Removes any
# previous defaults.
# @param midi [Boolean, nil] The default value for the `midi` parameter of
#   {Player#initialize} and by extension {track_live_loop}. Default: false.
# @param sync [Symbol, nil] The default value for the `sync` parameter of
#   {track_live_loop}. Default: nil (no sync).
# @param start_muted [Boolean, nil]: The default value for the `start_muted`
#   parameter of {track_live_loop} Default: false.
# @param fill_cc [Integer, nil]: The default value for the `fill_cc` parameter
#   of `track_live_loop`. Default: nil (no fill CC).
# @param send_cycle_cues [Boolean, nil]: The default value for the
#   `send_cycle_cues` parameter of {track_live_loop}. Default: true.
# @return [void]
# @see current_player_defaults
def use_player_defaults(midi: nil, sync: nil, start_muted: nil, fill_cc: nil, send_cycle_cues: nil)
  defaults = {}
  defaults[:midi] = midi unless midi.nil?
  defaults[:sync] = sync unless sync.nil?
  defaults[:start_muted] = start_muted unless start_muted.nil?
  defaults[:fill_cc] = fill_cc unless fill_cc.nil?
  defaults[:send_cycle_cues] = send_cycle_cues unless send_cycle_cues.nil?
  $__PLAYER_DEFAULTS = defaults  # rubocop:disable Style/GlobalVars
end

# Returns the current player defaults as set by {use_player_defaults}, or an
# empty hash if no defaults have been set.
# @return [Hash{Symbol => Object}]
def current_player_defaults
  $__PLAYER_DEFAULTS || {}  # rubocop:disable Style/GlobalVars
end

# @!endgroup


# A Player plays a {Track} by sending its {Step}s' notes over MIDI or playing
# them with Sonic Pi's internal synthesis.
#
# Generally you will not make instances of Player directly, and instead use
# {track_live_loop}, which will create and manage a Player for you.
#
# In the unlikely scenario that you want to manually drive a Player, see the
# {PlayerBase} documentation for details.
class Player < PlayerBase
  # Whether this player should send MIDI note events for {Step}s, or use Sonic
  # Pi's internal synthesis instead.
  # @return [Boolean]
  attr_reader :midi

  # The MIDI channel to use when this player sends events. Only relevant if
  # {#midi} is true.
  # @return [Integer, String, nil]
  attr_reader :channel

  # The MIDI port to use when this player sends events. Only relevant if {#midi}
  # is true.
  # @return [String, nil]
  attr_reader :port

  # Constructs a Player.
  #
  # @param track [Track] The initial value for {#track}.
  # @param midi [Boolean, nil] Whether playback will happen via MIDI or Sonic
  #   Pi's internal synthesis. If nil, the global default set by
  #   {use_player_defaults} will be used, or false if that was not set.
  # @param channel [Integer, String, nil] The MIDI channel to use when `midi` is
  #   true. If nil, falls back to the global default set by Sonic Pi's
  #   `use_midi_defaults`, or to all channels (i.e. "*") if that was not set.
  # @param port [String, nil] The MIDI device to use when `midi` is true. If
  #   nil, falls back in the same manner as `channel`.
  # @param debug [Boolean] If true, the player will log detailed information
  #   about its state during playback.
  def initialize(track, midi: nil, channel: nil, port: nil, debug: false)
    @midi = midi
    @midi = current_player_defaults[:midi] || false if @midi.nil?
    @channel = channel
    @port = port
    @midi_spi_kwargs = {}
    @midi_spi_kwargs[:channel] = channel unless channel.nil?
    @midi_spi_kwargs[:port] = port unless port.nil?

    # These track the current synth nodes or MIDI notes that are playing. Note
    # that steps with a gate < 1 that do not continue a tie are not added to
    # these, since they have a definite length that we can specify when starting
    # them; they'll terminate themselves.
    @active_synth_nodes = {}  # note symbols -> synth nodes. unused when playing midi
    @active_midi_notes = Set.new  # active midi note symbols. unused when playing built-in synths

    @effective_note_cache = {}

    super(track, debug: debug)
  end

  # (see PlayerBase#stop)
  def stop
    super

    @prev_steps = []
    @notes_for_prev_steps = {}
  end

  # @private
  def inherit_state(other)
    super

    @prev_steps = other.prev_steps
    @notes_for_prev_steps = other.notes_for_prev_steps
    @active_synth_nodes = other.active_synth_nodes
    @active_midi_notes = other.active_midi_notes
  end


  protected

  attr_reader :active_synth_nodes, :active_midi_notes, :prev_steps, :notes_for_prev_steps

  def slot_advanced
    @effective_note_cache.clear
  end

  def accums_committed
    # accum_delta is no longer peeking at potential accumulations, so we can't
    # rely on anything we already cached.
    @effective_note_cache.clear
  end

  # Returns the effective note for the given step in the current slot of the
  # track, accounting for the track's scale and the step's accumulation. If this
  # is called before `play_steps`, it will account for potential accumulation if
  # the step were to trigger.
  def note_for_step(step)
    note = @effective_note_cache[step]
    return note unless note.nil?

    note = step.note
    note = @track.scale.snap(step.note) unless @track.scale.nil?
    note += accum_delta(step)

    # Snap to the scale again after accumulation, if needed.
    note = @track.scale.snap(note) unless @track.scale.nil?

    @effective_note_cache[step] = note
    note
  end

  def accum_should_trigger?(step)
    step.accum_should_trigger?(@cycle, @fill, note_for_step(step), @notes_for_prev_steps.values)
  end

  def step_should_trigger?(step)
    step.should_trigger?(@cycle, @fill, note_for_step(step), @notes_for_prev_steps.values)

    # We don't want to (and can't) dedupe on effective note yet. We want the
    # accumulation data for all of those steps to be committed so PlayerBase
    # will register their accumulation, even if we don't end up playing them.
    # We'll dedupe them at play time below.
  end

  # Deduplicate the given steps, which must come from the current slot, based on
  # their effective note (accounting for accumulation). In the case that more
  # than one Step has the same effective note, chooses one with the longest
  # gate.
  def dedupe_steps(steps)
    steps_by_note = {}
    yelled = false
    steps.each do |step|
      step_note = note_for_step(step)
      old_step_with_same_note = steps_by_note[step_note]
      if old_step_with_same_note.nil?
        steps_by_note[step_note] = step
      else
        if @debug && !yelled
          warn("wound up with more than one Step with note #{step_note} in the same slot! Picking one with the longest gate!", "player")
          yelled = true
        end
        steps_by_note[step_note] = step if old_step_with_same_note.gate < step.gate
      end
    end

    steps_by_note.values
  end

  # Returns an array of arrays of steps representing the state of playback,
  # given the steps that are about to trigger.
  #
  # The returned array has the following elements:
  #   [new steps to trigger, continued (tied) steps, newly ended steps]
  #
  # Step probabilities are evaluated, and steps that should not trigger are not
  # returned. Steps in the first array are deduplicated if accumulation would
  # result in multiple steps with the same note.
  #
  # Note that the returned array of ended steps does not strictly contain steps
  # that ended exactly at the beginning of this step. It also contains steps
  # that ended between this step and the previous one - e.g. Steps with gates
  # less than 1.
  def categorize_steps(triggering_steps)
    # As noted in PlayerBase, it is important that this method assume nothing
    # about the order in which slots were or will be played. @prev_steps and
    # @notes_for_prev_steps track the steps that were played from the previous
    # slot.
    new_steps = []
    tied_steps = []
    ended_steps = []

    # Even though the Track will not have any Steps with the same note in the
    # same slot, accumulation may result in duplicates. So we need to do another
    # deduplication pass here, based on the actual notes we'll be playing.
    cur_steps = dedupe_steps(triggering_steps)

    # distinguish between tied notes and newly started ones
    cur_steps.each do |step|
      # Steps with 0 gate do not exist from our perspective. They won't play or
      # continue ties.
      next if step.gate == 0

      # were we just playing this note as a tie?
      is_tie = @prev_steps.any? do |prev_step|
        prev_step.tied? && @notes_for_prev_steps[prev_step] == note_for_step(step)
      end

      if is_tie
        tied_steps << step
      else
        new_steps << step
      end
    end

    # find notes from the last slot that have ended.
    @prev_steps.each do |prev_step|
      # any note we were playing that is not tied has ended
      note_continues = tied_steps.any? { |tie| note_for_step(tie) == @notes_for_prev_steps[prev_step] }
      ended_steps << prev_step unless note_continues
    end

    [new_steps, tied_steps, ended_steps]
  end

  def steps_debug_string(steps, from_prev: false)
    s = "["
    steps.each_with_index do |step, i|
      s += ", " if i > 0
      s += step.repr

      note = from_prev ? @notes_for_prev_steps[step] : note_for_step(step)
      s += " -> :#{note}" unless note == step.note
    end

    s += "]"
    s
  end

  def play_steps(steps)
    # To support changing the playhead direction and swapping between Tracks,
    # as with categorize_steps, it is important that this method does not assume
    # anything about the order in which slots were or will be played.
    new_steps, tied_steps, ended_steps = categorize_steps(steps)

    if @debug
      log("@ slot=#{slot_idx} cycle=#{@cycle} fill=#{@fill}", "player")
      log("new steps: #{steps_debug_string(new_steps)}", "player")
      log("tied steps: #{steps_debug_string(tied_steps)}", "player")
      log("ended steps: #{steps_debug_string(ended_steps, from_prev: true)}", "player")
    end

    # Turn off or kill ended steps. Note that ended_steps is a subset of
    # @prev_steps; end_step will handle finding the correct note for them from
    # @notes_for_prev_steps.
    ended_steps.each { |step| end_step(step) }

    # Schedule ends for continued steps that end before the next slot.
    # Note that we don't need to do this for new steps - those are either:
    # - of some specific length less than the granularity (i.e., not tied), in
    #   which case we provide the length to the sustain or duration argument
    #   when playing the note; or
    # - tied, and so of indeterminant length since it may continue in the next
    #   played slot. In this case we start the note with an indefinite time
    #   (midi_note_on, e.g.), and terminate it (midi_note_off or kill) later
    #   when it either (a) ends at the beginning of a step (the end_step call
    #   above), or (b) ends between steps (i.e., a tie ending with a step with
    #   gate < 1.0), in which case we schedule its end at the appropriate time
    #   here.
    tied_steps.each do |step|
      schedule_end_for_step_with_partial_gate(step) unless step.tied?
    end

    # Start new steps
    new_steps.each { |step| start_step(step) }

    # Update prev_steps for the next round
    @prev_steps = tied_steps + new_steps

    # The next slot may not come from @track, so we can't safely use
    # note_for_step in the next iteration on anything in @prev_steps. We need to
    # cache the resolved notes we actually played for each of those steps, so
    # that we can detect ties and ended notes in the next call to play_steps/
    # categorize_steps.
    @notes_for_prev_steps.clear
    @prev_steps.each { |step| @notes_for_prev_steps[step] = note_for_step(step) }
  end

  # Stop the MIDI note or kill the synth node corresponding to the given Step,
  # which is assumed to be in @prev_steps (and thus may not be part of @track).
  # Note that we may have already ended the step if it didn't have a full gate,
  # in which case it will not have an entry in active_midi_notes or
  # active_synth_nodes. Do nothing in that case.
  def end_step(step)
    step_note = @notes_for_prev_steps[step]

    if @midi
      # Note that @active_midi_notes is a Set, and Set.delete acts differently
      # than Array.delete. We want delete? to remove and return nil if nothing
      # was removed.
      ExtApi.midi_note_off(step_note, **@midi_spi_kwargs) unless @active_midi_notes.delete?(step_note).nil?
    else
      node = @active_synth_nodes.delete(step_note)
      ExtApi.kill(node) unless node.nil?
    end
  end

  # Schedules a call to `end_step` for a tied Step that will end between slots
  # (i.e., before the next call to `play_steps`).
  def schedule_end_for_step_with_partial_gate(step)
    ExtApi.time_warp(step.gate * @track.granularity.to_f) do
      log("killing #{step.inspect} @ t=#{ExtApi.vt}", "player") if @debug
      end_step(step)
    end
  end

  def end_all_steps
    if @midi
      @active_midi_notes.each { |n| ExtApi.midi_note_off(n, **@midi_spi_kwargs) }
      @active_midi_notes.clear
    else
      @active_synth_nodes.each_value { |node| ExtApi.kill(node) }
      @active_synth_nodes.clear
    end

    @prev_steps&.clear
  end

  # Begins playback of the given Step, which must be from the current slot in
  # @track. Updates @active_midi_notes or @active_synth_nodes as needed to track
  # ongoing steps.
  def start_step(step)
    step_note = note_for_step(step)

    if step.tied?
      # Step has indeterminate duration; it may be continued in the next played
      # slot. Start it and we'll kill it later when it ends in play_steps.
      if @midi
        ExtApi.midi_note_on(step_note, velocity: step.vel, **@midi_spi_kwargs)
        @active_midi_notes << step_note
      else
        # TODO: there's no good way to just have a synth note go forever and
        # eventually gracefully kick it into release. Luckily I'm really only
        # using this for previewing stuff away from my real synth...
        # For now just having ties go for 100 * the length of the whole track.
        # Obviously that's ridiculous.
        node = ExtApi.play(step_note, amp: step.velf, sustain: @track.beat_length * 100)
        @active_synth_nodes[step_note] = node
      end
    else
      # Step has a known duration, so we can specify it now and don't have to
      # kill it later.
      # There's no reason for us to keep track of these steps in
      # @active_midi_notes or @active_synth_nodes. They have an explicit
      # duration, so we won't need to kill them later in normal playback. And
      # stop/end_all_steps will only be called between cycles, so we don't need
      # to hold on to them for that either.
      # rubocop:disable Style/IfInsideElse
      if @midi
        ExtApi.midi(step_note, velocity: step.vel, sustain: step.gate * @track.granularity.to_f, **@midi_spi_kwargs)
      else
        ExtApi.play(step_note, amp: step.velf, sustain: step.gate * @track.granularity.to_f)
      end
      # rubocop:enable Style/IfInsideElse
    end
  end
end
