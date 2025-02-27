require_relative "track.rb"
require_relative "midi-utils.rb"

# Set global default Player behaviors.
# midi: Specifies the default value for the midi parameter of Player's
# initializer, used when that parameter is not explicitly passed. May be
# overridden on a per-Player basis by specifying the parameter.
# sync: Specifies the default value for the sync parameter of track_live_loops.
# May be overridden by specifying the parameter manually in the call to
# track_live_loop. Passing nil as the sync parameter to this function unsets the
# default.
def use_player_defaults(midi: nil, sync: :__dummy_sync_sentinel)
  # `set` hashes become SPMaps, apparently, so we need to call to_h on this.
  defaults = ExtApi.get(:__player_defaults).to_h
  defaults[:midi] = midi unless midi.nil?
  defaults.delete(:sync) if sync.nil?
  defaults[:sync] = sync unless sync == :__dummy_sync_sentinel
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
    @prev_steps = nil
    @cycle = 0
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
  end


  private

  def resolve_midi_arg(midi)
    defaults = ExtApi.get(:__player_defaults) || {}
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
    new_steps, tied_steps, ended_steps = @track.steps_at_slot(i, prev_steps: @prev_steps, cycle: @cycle, fill: @fill)

    if @debug
      ExtApi.puts "@ slot=#{i} cycle=#{@cycle}"
      ExtApi.puts "new steps: #{new_steps}"
      ExtApi.puts "tied steps: #{tied_steps}"
      ExtApi.puts "ended steps: #{ended_steps}"
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
      ExtApi.midi_note_off(step.note, **@midi_spi_kwargs) unless @active_midi_notes.delete?(step.note).nil?
    else
      node = @active_synth_nodes.delete(step.note)
      ExtApi.kill(node) if !node.nil?
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
      @active_synth_nodes.each { |_, node| ExtApi.kill(node) }
      @active_synth_nodes.clear
    end
  end

  def start_step(step)
    if step.tied?
      # Step has indeterminate duration; it may be continued in the next played
      # slot. Start it and we'll kill it later when it ends in play_slot.
      if @midi
        ExtApi.midi_note_on(step.note, velocity: step.vel, **@midi_spi_kwargs)
        @active_midi_notes << step.note
      else
        # TODO: there's no good way to just have a synth note go forever and
        # eventually gracefully kick it into release. Luckily I'm really only
        # using this for previewing stuff away from my real synth...
        # For now just having ties go for 100 * the length of the whole track.
        # Obviously that's ridiculous.
        node = ExtApi.play(step.note, amp: step.velf, sustain: @track.beat_length * 100)
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
        ExtApi.midi(step.note, velocity: step.vel, sustain: step.gate * @track.granularity.to_f, **@midi_spi_kwargs)
      else
        ExtApi.play(step.note, amp: step.velf, sustain: step.gate * @track.granularity.to_f)
      end
    end
  end
end


# Given a proc and a hash of keyword arguments, returns a new hash containing
# only the members of the hash that are valid keyword arguments for the proc.
# If the proc takes a double-star **kwargs argument, the hash is not filtered.
def __filter_kwargs_for_proc(proc, kwargs)
  params = proc.parameters
  return {} if params.empty?

  # If there's a **kwargs param, just pass everything.
  return kwargs if params.last[0] == :keyrest

  # We want the key names from parameters that look like [:key, :keyname] or
  # [:keyreq, :keyname].
  key_args = params.filter { |p| [:key, :keyreq].member?(p[0]) }.map { |p| p[1] }
  kwargs.filter { |k, _| key_args.member?(k) }
end


# Create a live_loop that plays the given track. Takes largely same arguments as
# cc_mutable_live_loop, with the exception that cc may be nil (the default), in
# which case the live_loop is not mutable by CCs. Also the port and channel
# arguments are split into port, channel and cc_port, cc_channel. The unprefixed
# ones are used for the internal Player instance, and the cc_* ones are passed
# to cc_mutable_live_loop.
# The live_loop responds to muting by calling sleep on the player for muted
# iterations, rather than play. Note that muting takes effect after cycles of
# playback, not immediately.
# If fade_in is true, the track fades in linearly (see Track.fade_in) whenever
# it transitions from muted to unmuted. fade_in may also have the value :quad,
# in which case the track is faded in with fade_in_quad.
# If fade_out is true, the track fades out linearly (see Track.fade_out) when
# it transitions from unmuted to muted. NOTE: This happens *after* the track
# transitions to muted. That is, tracks that are set to fade out will actually
# play for one additional cycle after they become muted, during which they will
# fade out. Like fade_in, fade_out may also have the value :quad.
# If fill_cc is provided, a CC message with that number will control whether the
# player is in fill mode. A value of 127 turns on fill, and any other value
# turns it off. Unlike muting, fill takes effect immediately, not at the start
# of a new cycle.
# If send_cycle_cues is true, immediately before the live_loop plays a cycle of
# the track, it sends a cue with the name <loop_name>_cycle and a single value,
# the number of the cycle iteration that's about to play. Cycle cues are not
# sent while the track is muted.
# A block may be provided, in which case it is called before each cycle is
# played. The block may take 0 - 4 arguments, which are as follows. The block
# may also accept keyword arguments by the names given below.
# 1. the cycle number that the player is about to play (keyword: cycle)
# 2. the track that's currently playing (keyword: track)
# 3. whether the track is muted (keyword: muted)
# 4. whether the track was muted in the previous loop. This argument is true on
#    cycle 0. (keyword: was_muted)
# 5. the normal optional live_loop argument (keyword: arg)
# If the block returns a value, it is fed back in the next iteration as the
# fifth argument.
# If the block returns a Track instance, the internal Player instance used by
# the live loop will swap to that track. The swap takes effect immediately; the
# current iteration of the live_loop will play the new track. The cycle count on
# the player will not be reset to 0.
# Note that the internal block that plays the track will sleep, so a user-
# provided block does not need to sleep or sync, unlike normal live_loop blocks.
# If it does sync or sleep, it may cause delays between cycles of the track.
# Any additional named arguments (e.g. delay: or seed:) to this function are
# passed verbatim to the internal live_loop. If a sync parameter is not
# specified, the default from use_player_defaults is used, if there is one. You
# can explicitly use no sync by providing a nil value for the sync parameter.
def track_live_loop(loop_name, track = nil, start_muted: false,
                    fade_in: false, fade_out: false,
                    midi: nil, port: nil, channel: nil,
                    cc: nil, fill_cc: nil, cc_port: nil, cc_channel: nil,
                    send_cycle_cues: true, debug: false,
                    init: nil, **kwargs, &block)
  raise "Block must take 0 - 5 arguments" if !block.nil? && block.arity > 5

  track ||= Track.rest

  player = Player.new(track, midi: midi, debug: debug, port: port, channel: channel)
  cycle_cue_sym = (loop_name.to_s + "_cycle").to_sym

  if fill_cc
    _cc_port, _cc_channel = __resolve_cc_port_and_channel(cc_port, cc_channel)
    cc_watcher_loop_name = ("__live_loop_" + loop_name.to_s + "_cc_fill_watcher").to_sym

    ExtApi.live_loop(cc_watcher_loop_name) do
      ExtApi.use_real_time

      # TODO: could support arrays of ports/channels by constructing {x,y,z}-style
      # strings for the path here.
      incoming_cc, cc_val = ExtApi.sync("/midi:#{_cc_port}:#{_cc_channel}/control_change")
      if incoming_cc == fill_cc
        player.fill = cc_val == 127
        ExtApi.puts("[cc fill control] CC #{cc} = #{cc_val} -> #{player.fill ? '' : 'un'}setting fill for live loop #{loop_name}")
      end
    end

    ExtApi.puts "[cc fill control] sending default CC #{fill_cc} value 0 for live loop #{loop_name}"
    ExtApi.midi_cc(cc, 0, port: _cc_port, channel: _cc_channel)
  end

  # Use the default sync unless we were passed one explicitly.
  unless kwargs.member?(:sync)
    defaults = ExtApi.get(:__player_defaults) || {}
    sync = defaults[:sync]
    kwargs[:sync] = sync unless sync.nil?
  end

  wrapped_block = lambda do |muted, arg|
    # We're smuggling some state between loops via our return value, along with
    # the actual return value of the user's block.
    was_muted = arg[:was_muted]
    unfaded_track = arg[:unfaded_track]
    arg = arg[:block_res]

    # If we just finished a fade, swap back to the normal version so we don't
    # tell the user's block about it.
    player.swap_track(unfaded_track) unless unfaded_track.nil?
    unfaded_track = nil

    res = nil
    unless block.nil?
      args = [player.cycle, player.track, muted, was_muted, arg].take(block.arity)

      block_kwargs = { cycle: player.cycle, track: player.track, muted: muted, was_muted: was_muted, arg: arg }
      block_kwargs = __filter_kwargs_for_proc(block, block_kwargs)

      res = block.call(*args, **block_kwargs)
    end

    if res.is_a?(Track)
      ExtApi.puts("#{loop_name} player: swapping track on cycle #{player.cycle}") if debug
      player.swap_track(res)
    end

    fading_out = false

    # Now that we have the final thing we're going to play, swap it out for the
    # faded version if we need to.
    if !muted && was_muted && fade_in
      ExtApi.puts("#{loop_named} player: fading in track") if debug
      unfaded_track = player.track
      if fade_in == :quad
        faded_track = player.track.fade_in_quad
      else
        faded_track = player.track.fade_in
      end
      player.swap_track(faded_track)
    elsif muted && !was_muted && fade_out
      fading_out = true
      ExtApi.puts("#{loop_named} player: fading out track") if debug
      unfaded_track = player.track
      if fade_out == :quad
        faded_track = player.track.fade_out_quad
      else
        faded_track = player.track.fade_out
      end
      player.swap_track(faded_track)
    end

    if muted && !fading_out
      player.sleep
    else
      ExtApi.cue(cycle_cue_sym, player.cycle) if send_cycle_cues
      player.play
    end

    { unfaded_track: unfaded_track, was_muted: muted, block_res: res }
  end

  init_arg = { was_muted: true, block_res: init }

  if cc.nil?
    mutable_live_loop(loop_name, start_muted: start_muted, init: init_arg, **kwargs, &wrapped_block)
  else
    cc_mutable_live_loop(loop_name, start_muted: start_muted, init: init_arg, cc: cc, port: cc_port, channel: cc_channel, **kwargs, &wrapped_block)
  end
end

alias tll track_live_loop
