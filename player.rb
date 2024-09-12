$spi ||= self

# Depends on piano-roll2 and midi-utils


# Set global default Player behaviors.
# midi: Specifies the default value for the midi parameter of Player's
# initializer, used when that parameter is not explicitly passed. May be
# overridden on a per-Player basis by specifying the parameter.
def use_player_defaults(midi:)
  $spi.set(:__player_defaults, { midi: midi })
end


# TODO: playhead direction - mostly just a matter of how we move the slot index
# in play, but also need to consider what "cycle" means in some of the weirder
# cases like a drunk walk.
# TODO: probably special-case Steps with a 0 gate
# TODO: swing?
class Player
  attr_reader :midi, :track, :cycle, :channel, :port

  def initialize(track, midi: nil, channel: nil, port: nil, debug: false)
    @track = track

    @midi = resolve_midi_arg(midi)
    @channel = channel
    @port = port
    @midi_spi_kwargs = {}
    @midi_spi_kwargs[:channel] = channel unless channel.nil?
    @midi_spi_kwargs[:port] = port unless port.nil?

    @debug = debug

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
    @prev_steps = nil
    @cycle = 0
  end

  # Plays one cycle of the track
  def play
    $spi.with_bpm_mul(@track.timescale) do
      @track.num_slots.times do |i|
        play_slot(i)

        # Sleep until it's time for the next slot
        $spi.sleep(@track.granularity.to_f)
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
    $spi.with_bpm_mul(@track.timescale) do
      $spi.sleep(@track.beat_length)
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
  end


  private

  def resolve_midi_arg(midi)
    defaults = $spi.get(:__player_defaults) || {}
    midi = defaults[:midi] || false if midi.nil?
    return midi
  end

  def play_slot(i)
    # To support changing the playhead direction and swapping between Tracks,
    # as with Track.steps_at_slot, it is important that this code does not
    # assume anything about the order in which slots were or will be played. It
    # must base its logic entirely off the result of steps_at_slot(i) and the
    # most recently played steps in @prev_steps. The next steps may not come
    # from slot i+1, and the previous ones may not have come from slot i-1. In
    # fact they may not even be from this Track, if the track is swapped.
    new_steps, tied_steps, ended_steps = @track.steps_at_slot(i, prev_steps: @prev_steps, cycle: @cycle)

    if @debug
      $spi.puts "@ slot=#{i} cycle=#{@cycle}"
      $spi.puts "new steps: #{new_steps}"
      $spi.puts "tied steps: #{tied_steps}"
      $spi.puts "ended steps: #{ended_steps}"
    end

    # Turn off or kill ended steps
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
  end

  def end_step(step)
    # Stop the MIDI note or kill the synth node. Note that we may have already
    # ended the step if it didn't have a full gate, in which case it will not
    # be in active_midi_notes or active_synth_nodes. Do nothing in that case.
    if @midi
      # Note that @active_midi_notes is a Set, and Set.delete acts differently
      # than Array.delete. We want delete? to remove and return nil if nothing
      # was removed.
      $spi.midi_note_off(step.note, **@midi_spi_kwargs) unless @active_midi_notes.delete?(step.note).nil?
    else
      node = @active_synth_nodes.delete(step.note)
      $spi.kill(node) if !node.nil?
    end
  end

  def schedule_end_for_step_with_partial_gate(step)
    $spi.time_warp(step.gate * @track.granularity.to_f) do
      $spi.puts "killing #{step.inspect} @ t=#{$spi.vt}" if @debug
      end_step(step)
    end
  end

  def end_all_steps
    if @midi
      @active_midi_notes.each { |n| $spi.midi_note_off(n, **@midi_spi_kwargs) }
      @active_midi_notes.clear
    else
      @active_synth_nodes.each { |_, node| $spi.kill(node) }
      @active_synth_nodes.clear
    end
  end

  def start_step(step)
    if step.tied?
      # Step has indeterminate duration; it may be continued in the next played
      # slot. Start it and we'll kill it later when it ends in play_slot.
      if @midi
        $spi.midi_note_on(step.note, velocity: step.vel, **@midi_spi_kwargs)
        @active_midi_notes << step.note
      else
        # TODO: there's no good way to just have a synth note go forever and
        # eventually gracefully kick it into release. Luckily I'm really only
        # using this for previewing stuff away from my real synth...
        # For now just having ties go for 100 * the length of the whole track.
        # Obviously that's ridiculous.
        node = $spi.play(step.note, amp: step.velf, sustain: @track.beat_length * 100)
        @active_synth_nodes[step.note] = node
      end
    else
      # Step has a known duration, so we can specify it now and don't have to
      # kill it later.
      # There's no reason for us to keep track of these steps in
      # @active_midi_notes or @active_synth_nodes. They have an explicit
      # duration, so we won't need to kill them later in normal playback. And
      # stop/end_all_steps will only be called between cycles, so we don't need
      # to hold on to them for that either.
      if @midi
        $spi.midi(step.note, velocity: step.vel, sustain: step.gate * @track.granularity.to_f, **@midi_spi_kwargs)
      else
        $spi.play(step.note, amp: step.velf, sustain: step.gate * @track.granularity.to_f)
      end
    end
  end
end


# Create a live_loop that plays the given track. Takes largely same arguments as
# cc_mutable_live_loop, with the exception that cc may be nil (the default), in
# which case the live_loop is not mutable by CCs. Also the port and channel
# arguments are split into player_port, player_channel and cc_port, cc_channel.
# The player_* ones are used for the internal Player instance, and the cc_* ones
# are passed to cc_mutable_live_loop.
# The live_loop responds to muting by calling sleep on the player for muted
# iterations, rather than play. Note that muting takes effect after cycles of
# playback, not immediately.
# If send_cycle_cues is true, immediately before the live_loop plays a cycle of
# the track, it sends a cue with the name <loop_name>_cycle and a single value,
# the number of the cycle iteration that's about to play. Cycle cues are not
# sent while the track is muted.
# A block may be provided, in which case it is called before each cycle is
# played. The block may take 0 - 4 arguments, which are as follows:
# 1. the cycle number that the player is about to play
# 2. the track that's currently playing
# 3. whether the track is muted
# 4. whether the track was muted in the previous loop. This argument is true on
#    cycle 0.
# 5. the normal optional live_loop argument
# If the block returns a value, it is fed back in the next iteration as the
# fifth argument.
# If the block returns a Track instance, the internal Player instance used by
# the live loop will swap to that track. The swap takes effect immediately; the
# current iteration of the live_loop will play the new track. The cycle count on
# the player will not be reset to 0.
# Note that the internal block that plays the track will sleep, so a user-
# provided block does not need to sleep or sync, unlike normal live_loop blocks.
# If it does sync or sleep, it may cause delays between cycles of the track.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def track_live_loop(loop_name, track = nil, init: nil, start_muted: false, midi: nil, player_port: nil, player_channel: nil, cc: nil, cc_port: nil, cc_channel: nil, send_cycle_cues: true, debug: false, **kwargs, &block)
  raise "Block must take 0 - 5 arguments" if !block.nil? && block.arity > 5

  track ||= Track.rest

  player = Player.new(track, midi: midi, debug: debug, port: player_port, channel: player_channel)
  cycle_cue_sym = (loop_name.to_s + "_cycle").to_sym

  wrapped_block = lambda do |muted, arg|
    # We're smuggling the previous state of the muted flag through the return
    # value of wrapped_block, along with the actual return value of the user's
    # block.
    was_muted = arg[:was_muted]
    arg = arg[:block_res]

    res = nil
    unless block.nil?
      args = [player.cycle, player.track, muted, was_muted, arg].take(block.arity)
      res = block.call(*args)
    end

    if res.is_a?(Track)
      $spi.puts("#{loop_name} player: swapping track on cycle #{player.cycle}") if @debug
      player.swap_track(res)
    end

    if muted
      player.sleep
    else
      $spi.cue(cycle_cue_sym, player.cycle) if send_cycle_cues
      player.play
    end

    { was_muted: muted, block_res: res }
  end

  init_arg = { was_muted: true, block_res: init }

  if cc.nil?
    mutable_live_loop(loop_name, start_muted: start_muted, init: init_arg, **kwargs, &wrapped_block)
  else
    cc_mutable_live_loop(loop_name, start_muted: start_muted, init: init_arg, cc: cc, port: cc_port, channel: cc_channel, **kwargs, &wrapped_block)
  end
end
