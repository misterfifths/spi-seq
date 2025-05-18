# frozen_string_literal: true

require_relative "track"
require_relative "extapi"


# Set global default Player behaviors.
# midi: Specifies the default value for the midi parameter of Player's
# initializer, used when that parameter is not explicitly passed. May be
# overridden on a per-Player basis by specifying the parameter.
# sync: Specifies the default value for the sync parameter of track_live_loops.
# May be overridden by specifying the parameter manually in the call to
# track_live_loop. Passing nil as the sync parameter to this function unsets the
# default.
# start_muted: Specifies the default value for the start_muted parameter of
# track_live_loop. May be overridden by specifying the parameter manually in the
# call to track_live_loop. Default: false.
# fill_cc: Specifies the default value for the fill_cc parameter of
# track_live_loop. May be overridden by specifying the parameter manually in the
# call to track_live_loop. Default: nil (no fill CC).
def use_player_defaults(midi: nil, sync: :__dummy_sync_sentinel, start_muted: nil, fill_cc: nil)
  # `set` hashes become SPMaps, apparently, so we need to call to_h on this.
  defaults = ExtApi.get(:__player_defaults).to_h
  defaults[:midi] = midi unless midi.nil?
  defaults.delete(:sync) if sync.nil?
  defaults[:sync] = sync unless sync == :__dummy_sync_sentinel
  defaults[:start_muted] = start_muted unless start_muted.nil?
  defaults[:fill_cc] = fill_cc unless fill_cc.nil?
  ExtApi.set(:__player_defaults, defaults)
end


# TODO: playhead direction - mostly just a matter of how we move the slot index
# in play, but also need to consider what "cycle" means in some of the weirder
# cases like a drunk walk.
# TODO: probably special-case Steps with a 0 gate
# TODO: swing?
# The fill attribute controls whether steps with the 'fill' probability are
# played. It may be changed at any point, and will take effect when the next
# slot is played.
class Player
  attr_reader :midi, :track, :cycle, :channel, :port
  attr_accessor :fill

  def initialize(track, midi: nil, channel: nil, port: nil, debug: false)
    @track = track

    @midi = resolve_midi_arg(midi)
    @channel = channel
    @port = port
    @midi_spi_kwargs = {}
    @midi_spi_kwargs[:channel] = channel unless channel.nil?
    @midi_spi_kwargs[:port] = port unless port.nil?

    @debug = debug

    @fill = false

    # These track the current synth nodes or MIDI notes that are playing. Note
    # that steps with a gate < 1 that do not continue a tie are not added to
    # these, since they have a definite length that we can specify when starting
    # them; they'll terminate themselves.
    @active_synth_nodes = {}  # note symbols -> synth nodes. unused when playing midi
    @active_midi_notes = Set.new  # active midi note symbols. unused when playing built-in synths

    stop
  end

  def stop
    end_all_steps
    @prev_steps = []
    @notes_for_prev_steps = {}
    @cycle = 0

    @accum_data = {}  # Step hash keys (step_accum_hash_key) -> hash
  end

  # Plays one cycle of the track
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

  # Sleeps for the duration of the track. Cycle count and tie tracking are not
  # effected. All currently playing Steps are stopped.
  # TODO: do we want to increment cycle count here? kinda depends on what this
  # is philosophically - is it a muted play, or just a way to stall until we
  # start playing for the first time? if it's a muted play, it should just be an
  # argument to play. The only thing I can think of that would be screwed up is
  # Steps with a 'first' probability.
  # TODO: should this reset @prev_steps? feels like yes
  def sleep
    end_all_steps
    ExtApi.with_bpm_mul(@track.timescale) do
      ExtApi.sleep(@track.beat_length)
    end
  end

  # Swap out the Track this player plays for new_track. Resets the cycle count
  # to 0 if reset_cycle is true.
  # This is intended to be called between calls to play or sleep. The new track
  # will then play from slot 0 on the next call to play or sleep.
  # The set of currently playing steps is not reset; the transition to the new
  # track will seamlessly continue tied notes.
  def swap_track(new_track, reset_cycle: false)
    @track = new_track
    @cycle = 0 if reset_cycle

    # TODO: clear accum_data?
  end


  protected

  attr_reader :active_synth_nodes, :active_midi_notes, :prev_steps, :notes_for_prev_steps, :accum_data


  private

  # Inherits the state of another Player, including the set of currently active
  # notes. This will be called after a sketch is restarted, just before this
  # player is to take over from `other`.
  def inherit_state(other)
    @cycle = other.cycle
    @fill = other.fill
    @prev_steps = other.prev_steps
    @notes_for_prev_steps = other.notes_for_prev_steps
    @active_synth_nodes = other.active_synth_nodes
    @active_midi_notes = other.active_midi_notes
    @accum_data = other.accum_data
  end

  def resolve_midi_arg(midi)
    defaults = ExtApi.get(:__player_defaults) || {}
    midi = defaults[:midi] || false if midi.nil?
    midi
  end

  # Returns a hash key for the given Step from the given slot in @track, to be
  # used when indexing @accum_data.
  def step_accum_hash_key(step, slot_idx)
    # Since they're immutable, Steps could theoretically be shared across
    # multiple slots in different tracks. So we need to hash based on enough
    # information to uniquely identify the step within the track.
    [step.object_id, slot_idx, @track.object_id]
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
    return unless step.accum_should_trigger?(@cycle, @fill, note_for_step(step, slot_idx), @notes_for_prev_steps.values)

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

  # Returns the effective note for the given Step (which must be from @track!)
  # playing in the given slot index. You must call apply_accum for the step
  # prior to this method, so that the Step's accumulation parameters will take
  # effect.
  def note_for_step(step, slot_idx)
    note = if @track.scale.nil?
      step.note
    else
      @track.scale.snap(step.note)
    end

    acc_data = @accum_data[step_accum_hash_key(step, slot_idx)]
    note += acc_data[:delta] unless acc_data.nil?

    note
  end

  def dedupe_steps(steps, slot_idx)
    steps_by_note = {}
    yelled = false
    steps.each do |step|
      step_note = note_for_step(step, slot_idx)
      old_step_with_same_note = steps_by_note[step_note]
      if old_step_with_same_note.nil?
        steps_by_note[step_note] = step
      else
        if @debug && !yelled
          ExtApi.puts("warning: wound up with more than one Step with note #{step_note} in the same slot! Picking one with the longest gate!")
          yelled = true
        end
        steps_by_note[step_note] = step if old_step_with_same_note.gate < step.gate
      end
    end

    steps_by_note.values
  end

  # Returns an array of arrays of Steps representing the state of playback for
  # the current track at slot i in the current cycle, assuming that the steps in
  # @prev_steps were the Steps played in the most recently evaluated slot. The
  # array has the following elements:
  #   [newly triggered Steps, continued (tied) Steps, newly ended Steps]
  # Step probabilities are evaluated, and steps that should not trigger are not
  # returned. Accumulation is also applied to steps with those options, should
  # it trigger.
  # Note that the returned array of ended steps does not strictly contain steps
  # that ended exactly at the beginning of this step. It also contains steps
  # that ended between this step and the previous one - i.e. steps with gates
  # less than 1.
  # Wraps the slot index if it exceeds the number of slots in the track.
  def steps_at_slot(i)
    # To support changing the playhead direction and swapping between Tracks,
    # it is important that this method does not assume anything about the order
    # in which slots were or will be played. It must base its logic solely on
    # the contents of slot i and prev_steps. The next steps may not come from
    # slot i+1, and the previous ones may not have come from slot i-1. In fact
    # they may not even be from this Track, if the track was swapped.
    new_steps = []
    tied_steps = []
    ended_steps = []

    cur_steps = @track.grid[i % @track.length].filter do |step|
      # TODO: using `note_for_step` here is tricky, since it means that the
      # predicate will not take accumulation into account. Perhaps it's worth
      # just getting rid of the `pre_same_note` predicates; they're causing a
      # lot of trouble.
      step.should_trigger?(@cycle, @fill, note_for_step(step, i), @notes_for_prev_steps.values)
    end

    cur_steps.each { |step| apply_accum(step, i) }

    cur_steps = dedupe_steps(cur_steps, i)

    # distinguish between tied notes and newly started ones
    cur_steps.each do |step|
      # were we just playing this note as a tie?
      is_tie = @prev_steps.any? do |prev_step|
        prev_step.tied? && @notes_for_prev_steps[prev_step] == note_for_step(step, i)
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
      note_continues = tied_steps.any? { |tie| note_for_step(tie, i) == @notes_for_prev_steps[prev_step] }
      ended_steps << prev_step unless note_continues
    end

    [new_steps, tied_steps, ended_steps]
  end

  def steps_debug_string(steps, slot_idx, from_prev: false)
    s = "["
    steps.each_with_index do |step, i|
      s += ", " if i > 0
      s += step.repr

      note = from_prev ? @notes_for_prev_steps[step] : note_for_step(step, slot_idx)
      s += " -> :#{note}" unless note == step.note
    end

    s += "]"
    s
  end

  def play_slot(i)
    # To support changing the playhead direction and swapping between Tracks,
    # as with steps_at_slot, it is important that this method does not assume
    # anything about the order in which slots were or will be played.
    new_steps, tied_steps, ended_steps = steps_at_slot(i)

    if @debug
      ExtApi.puts "@ slot=#{i} cycle=#{@cycle} fill=#{@fill}"
      ExtApi.puts "new steps: #{steps_debug_string(new_steps, i)}"
      ExtApi.puts "tied steps: #{steps_debug_string(tied_steps, i)}"
      ExtApi.puts "ended steps: #{steps_debug_string(ended_steps, i, from_prev: true)}"
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
    new_steps.each { |step| start_step(step, i) }

    # Update prev_steps for the next round
    @prev_steps = tied_steps + new_steps

    # The next slot may not come from @track, so we can't safely use
    # note_for_step in the next iteration on anything in @prev_steps. We need to
    # cache the resolved notes we actually played for each of those steps, so
    # that we can detect ties and ended notes in the next call to play_slot/
    # steps_at_slot.
    @notes_for_prev_steps.clear
    @prev_steps.each { |step| @notes_for_prev_steps[step] = note_for_step(step, i) }
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

  def schedule_end_for_step_with_partial_gate(step)
    ExtApi.time_warp(step.gate * @track.granularity.to_f) do
      ExtApi.puts "killing #{step.inspect} @ t=#{ExtApi.vt}" if @debug
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
  end

  def start_step(step, slot_idx)
    step_note = note_for_step(step, slot_idx)

    if step.tied?
      # Step has indeterminate duration; it may be continued in the next played
      # slot. Start it and we'll kill it later when it ends in play_slot.
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
