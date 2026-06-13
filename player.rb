# frozen_string_literal: true

require_relative "extapi"
require_relative "playerbase"
require_relative "track"
require_relative "utils/internal_utils"

# @!group Playback and live loops

# @private
module SpiSeq
  module Defaults
    class << self
      attr_accessor :player_defaults
    end
  end
end

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
  SpiSeq::Defaults.player_defaults = defaults.freeze
end

# Returns the current player defaults as set by {use_player_defaults}, or an
# empty hash if no defaults have been set.
# @return [Hash{Symbol => Object}]
def current_player_defaults
  SpiSeq::Defaults.player_defaults || {}
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

    @effective_attrs_cache = {}

    super(track, debug: debug)
  end

  # (see PlayerBase#stop)
  def stop
    super

    @prev_steps = []
    @attrs_for_prev_steps = {}
  end

  # @private
  def inherit_state(other)
    super

    @prev_steps = other.prev_steps
    @attrs_for_prev_steps = other.attrs_for_prev_steps
    @active_synth_nodes = other.active_synth_nodes
    @active_midi_notes = other.active_midi_notes
  end


  protected

  attr_reader :active_synth_nodes, :active_midi_notes, :prev_steps, :attrs_for_prev_steps

  def slot_advanced
    @effective_attrs_cache.clear
  end

  def accums_committed
    # accum_delta is no longer peeking at potential accumulations, so we can't
    # rely on anything we already cached.
    @effective_attrs_cache.clear
  end

  # Returns the effective attributes for the given step in the current slot of
  # the track, accounting for the track's scale and the step's accumulation.
  # If this is called before `play_steps`, it will account for potential
  # accumulation if the step were to trigger. Result is [note, gate, vel].
  def effective_attrs(step)
    attrs = @effective_attrs_cache[step]
    return attrs unless attrs.nil?

    delta = accum_delta(step)  # this will ensure step is in the current slot

    note = step.note
    note = @track.scale.snap(step.note) unless @track.scale.nil?
    if delta != 0 && step.accum_target == :note
      note += delta
      # Snap to the scale again after accumulation
      note = @track.scale.snap(note) unless @track.scale.nil?
    end

    gate = step.gate
    if delta != 0 && step.accum_target == :gate
      gate += delta
      gate = 0 if gate < 0
      gate = 1 if gate > 1
    end

    vel = step.vel
    if delta != 0 && step.accum_target == :vel
      vel += delta
      vel = vel.to_i
      vel = 0 if vel < 0
      vel = 127 if vel > 127
    end

    attrs = [note, gate, vel]
    @effective_attrs_cache[step] = attrs
    attrs
  end

  def effective_note(step)
    note, = effective_attrs(step)
    note
  end

  def effective_gate(step)
    _, gate, = effective_attrs(step)
    gate
  end

  # Returns the attributes for the given step as it was played in a previous
  # slot. The step must be in prev_steps. Returns [note, gate, vel].
  def prev_attrs(step)
    attrs = @attrs_for_prev_steps[step]
    raise ArgumentError, "step is not in prev_steps" if attrs.nil?
    attrs
  end

  def prev_note(step)
    note, = prev_attrs(step)
    note
  end

  # Returns the notes of all steps that were active during the previous slot.
  def prev_notes
    @attrs_for_prev_steps.map { |_, attrs| attrs[0] }
  end

  def accum_should_trigger?(step)
    # Accumulation deltas are in the middle of being calculated, so we can't use
    # effective_note here (which would take it into account). That means that
    # the `pre_same_note` family of probs won't work; they don't really make
    # sense on an accum anyway.
    step.accum_should_trigger?(cycle: @cycle, fill: @fill, prev_notes: prev_notes)
  end

  def step_should_trigger?(step)
    step.should_trigger?(cycle: @cycle, fill: @fill,
                         effective_note: effective_note(step),
                         prev_notes: prev_notes)

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
      step_note, step_gate, = effective_attrs(step)
      old_step_with_same_note = steps_by_note[step_note]
      if old_step_with_same_note.nil?
        steps_by_note[step_note] = step
      else
        if @debug && !yelled
          SpiSeq::Log.warn("wound up with more than one Step with note #{step_note} in the same slot! Picking one with the longest gate!", "player")
          yelled = true
        end
        old_step_gate = effective_gate(old_step_with_same_note)
        steps_by_note[step_note] = step if old_step_gate < step_gate
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
  # Steps in the first array are deduplicated if accumulation would result in
  # multiple steps with the same note.
  #
  # The returned array of ended steps does not strictly contain steps that ended
  # exactly at the beginning of this step. It also contains steps that ended
  # between this step and the previous one - e.g. Steps with gates less than 1.
  def categorize_steps(triggering_steps)
    # As noted in PlayerBase, it is important that this method assume nothing
    # about the order in which slots were or will be played. @prev_steps and
    # @attrs_for_prev_steps track active steps from previous slots.
    new_steps = []
    tied_steps = []
    ended_steps = []

    # Even though the Track will not have any Steps with the same note in the
    # same slot, accumulation may result in duplicates. So we need to do another
    # deduplication pass here, based on the actual notes we'll be playing.
    cur_steps = dedupe_steps(triggering_steps)

    # distinguish between tied notes and newly started ones
    cur_steps.each do |step|
      note, gate, = effective_attrs(step)

      # Steps with 0 gate do not exist from our perspective. They won't play or
      # continue ties.
      next if gate == 0

      # were we just playing this note as a tie?
      is_tie = @prev_steps.any? do |prev_step|
        prev_note, prev_gate, = prev_attrs(prev_step)
        prev_gate == 1 && prev_note == note
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
      note_continues = tied_steps.any? { |tie| effective_note(tie) == prev_note(prev_step) }
      ended_steps << prev_step unless note_continues
    end

    [new_steps, tied_steps, ended_steps]
  end

  def steps_debug_string(steps, from_prev: false)
    s = "["
    steps.each_with_index do |step, i|
      s += ", " if i > 0
      s += step.repr(safe: true)

      note, gate, vel = from_prev ? prev_attrs(step) : effective_attrs(step)
      next if step.note == note && step.gate == gate && step.vel == vel

      accum_bits = []
      accum_bits << ":#{note}" unless note == step.note
      accum_bits << "gate=#{gate.round(2)}" unless gate == step.gate
      accum_bits << "vel=#{vel}" unless vel == step.vel
      s += " -> #{accum_bits.join(' ')}"
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
      SpiSeq::Log.log("@ t=#{ExtApi.vt} slot=#{slot_idx} cycle=#{@cycle} fill=#{@fill}", "player")
      SpiSeq::Log.log("new steps: #{steps_debug_string(new_steps)}", "player")
      SpiSeq::Log.log("tied steps: #{steps_debug_string(tied_steps)}", "player")
      SpiSeq::Log.log("ended steps: #{steps_debug_string(ended_steps, from_prev: true)}", "player")
    end

    # Turn off or kill ended steps. ended_steps is a subset of @prev_steps;
    # end_step will handle finding the correct note for them from
    # @attrs_for_prev_steps.
    ended_steps.each { |step| end_step(step) }

    # Start new steps
    new_steps.each { |step| start_step(step) }

    # Update prev_steps for the next round
    @prev_steps = tied_steps + new_steps

    # The next slot may not come from @track, so we can't safely use
    # effective_attrs in the next iteration on anything in @prev_steps. We need
    # to cache the resolved notes we actually played for each of those steps, so
    # that we can detect ties and ended notes in the next call to play_steps/
    # categorize_steps.
    @attrs_for_prev_steps.clear
    @prev_steps.each do |step|
      @attrs_for_prev_steps[step] = effective_attrs(step)
    end

    # Schedule ends for continued steps that end before the next slot.
    # We don't need to do this for new steps - those are either:
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
      gate = effective_gate(step)
      next if gate == 1

      ExtApi.at(gate * @track.granularity.to_f) do
        SpiSeq::Log.log("killing #{step.inspect} @ t=#{ExtApi.vt}", "player") if @debug
        end_step(step)
      end
    end
  end

  # Stop the MIDI note or kill the synth node corresponding to the given Step,
  # which is assumed to be in @prev_steps (and thus may not be part of @track).
  # We may have already ended the step if it didn't have a full gate, in which
  # case it will not have an entry in active_midi_notes or active_synth_nodes.
  # Do nothing in that case.
  def end_step(step)
    step_note = prev_note(step)

    if @midi
      # @active_midi_notes is a Set, and Set.delete acts differently than
      # Array.delete. We want delete? to remove and return nil if nothing was
      # removed.
      ExtApi.midi_note_off(step_note, **@midi_spi_kwargs) unless @active_midi_notes.delete?(step_note).nil?
    else
      node = @active_synth_nodes.delete(step_note)
      ExtApi.kill(node) unless node.nil?
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
    note, gate, vel = effective_attrs(step)

    if gate == 1
      # Step has indeterminate duration; it may be continued in the next played
      # slot. Start it and we'll kill it later when it ends in play_steps.
      if @midi
        ExtApi.midi_note_on(note, velocity: vel, **@midi_spi_kwargs)
        @active_midi_notes << note
      else
        # TODO: there's no good way to just have a synth note go forever and
        # eventually gracefully kick it into release. Luckily I'm really only
        # using this for previewing stuff away from my real synth...
        # For now just having ties go for 100 * the length of the whole track.
        # Obviously that's ridiculous.
        node = ExtApi.play(note, amp: vel / 127.0, sustain: @track.beat_length * 100)
        @active_synth_nodes[note] = node
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
        ExtApi.midi(note, velocity: vel, sustain: gate * @track.granularity.to_f, **@midi_spi_kwargs)
      else
        ExtApi.play(note, amp: vel / 127.0, sustain: gate * @track.granularity.to_f)
      end
      # rubocop:enable Style/IfInsideElse
    end
  end
end
