# frozen_string_literal: true

require_relative "cctrack"
require_relative "extapi"
require_relative "player"
require_relative "trackbase"
require_relative "track"
require_relative "utils/live_loop_utils"
require_relative "utils/misc_utils"


# Create a live_loop that plays the given track.
#
# This method accepts Track and CCTrack instances and internally creates and
# controls an appropriate player instance (a Player or CCPlayer, respectively).
# Certain options are only valid for one track type; see the details below.
#
# The `track` argument may be nil (the default), in which case the live loop
# will play a single-slot rest Track. This is useful if the method is called
# with a block that returns a track. See below for details on the block and its
# arguments.
#
# Takes largely same arguments as `cc_mutable_live_loop`, with the exception
# that `cc` may be nil (the default), in which case the live_loop is not mutable
# by CCs. The MIDI port and channel arguments are split into `port`, `channel`
# and `cc_port`, `cc_channel`. The unprefixed ones control which device the
# internal player instance will target for playback. The `cc_`-prefixed ones are
# passed to `cc_mutable_live_loop` to specify the device whose CC messages will
# be monitored for muting. They also specify the device to monitor for fill
# changes (see `fill_cc`).
#
# The live_loop responds to muting by calling `sleep` on the internal Player for
# muted cycles of playback, rather than `play`. Note that means that muting
# takes effect after the current playback cycle completes, not immediately.
#
# If `fade_in` is true, the track fades in linearly (see `Track.fade_in`)
# whenever it transitions from muted to unmuted. `fade_in` may also have the
# value :quad, in which case the track is faded in with `fade_in_quad`.
#
# If `fade_out` is true, the track fades out linearly (see `Track.fade_out`)
# when it transitions from unmuted to muted. NOTE: This happens *after* the
# track transitions to muted. That is, tracks that are set to fade out will
# actually play for one additional cycle after they become muted, during which
# they will fade out. Like `fade_in`, `fade_out` may also have the value :quad.
#
# `fade_in` and `fade_out` are only applicable when a Track instance is passed;
# it is an error to set them for CCTracks.
#
# If `fill_cc` is provided, a CC message with that number will control whether
# the player is in fill mode. A value of 0 turns off fill, and any other value
# turns it on. Unlike muting, fill takes effect immediately, not at the start
# of a new cycle. The device to watch for CC messages for fill is specified by
# `cc_channel` and `cc_port`, which default to the global values set via a call
# to `use_cc_control_defaults` (or to all ports and channels if that was not
# set).
#
# If `send_cycle_cues` is true, immediately before the live_loop plays a cycle
# of the track, it sends a cue with the name `<loop_name>_cycle` and a single
# value, the number of the cycle iteration that's about to play. Cycle cues are
# not sent while the track is muted.
#
# If `midi` is true and a Track instance is passed, that track will play back
# over MIDI, rather than Sonic Pi's internal synthesis. The `channel` and `port`
# arguments determine what device will be used for playback. `midi` is only
# applicable when a Track is passed; it is ignored for CCTracks because they
# only function over MIDI. If the `midi` argument is omitted, the default value
# from `use_player_defaults` is used (or false if that was not set). If
# `channel` or `port` is omitted, the default value from Sonic Pi's
# `use_midi_defaults` method is used (or all channels and ports if that was
# not set).
#
# A block may be provided, in which case it is called before each cycle is
# played. The block may take 0 - 5 arguments, which are as follows. The block
# may also accept keyword arguments by the names given below.
# 1. the cycle number that the player is about to play (keyword: `cycle`)
# 2. the track that's currently playing (keyword: `track`)
# 3. whether the track is muted (keyword: `muted`)
# 4. whether the track was muted in the previous loop. This argument is true on
#    cycle 0. (keyword: `was_muted`)
# 5. the normal optional live_loop argument (keyword: `arg`)
#
# The internal block that plays the track will sleep, so a user-provided block
# does not need to call `sleep` or `sync`, unlike normal live_loop blocks.
# If it does sync or sleep, it may cause delays between cycles of the track.
#
# If the block returns a value, it is fed back in the next iteration as the
# fifth argument (`arg`).
#
# If the block returns a TrackBase instance (i.e. a Track or CCTrack), the
# internal Player instance used by the live loop will swap to that track. The
# swap takes effect immediately; the current iteration of the live_loop will
# play the new track. The cycle count on the player will not be reset to 0.
#
# It is an error for the block to attempt to switch between types of tracks.
# For example, the block cannot return a CCTrack when the initial call to
# `track_live_loop` was given a Track.
#
# Note: a nil `track` results in playback of a Track, not a CCTrack. So it is
# invalid for a block to return a CCTrack when this method is not passed a
# track, because that would constitute a switch in track type. For that reason,
# it is recommended to use `cc_track_live_loop` when playing back CCTracks, as
# that method uses a single-slot rest CCTrack in that case instead. That method
# is otherwise identical to this one.
#
# Any additional named arguments (e.g. delay: or seed:) to this function are
# passed verbatim to the internal live_loop.
#
# If a `sync` parameter is not specified, the default from `use_player_defaults`
# is used, if there is one. You can explicitly use no sync by passing a nil
# value for the sync parameter.
#
# If the `start_muted` parameter is not specified, the default from
# `use_player_defaults` is used.
#
# If `debug` is true, details about muting, unmuting, and fill state will be
# logged, as well as any information that comes from setting `debug` to true
# on the internal player instance.
def track_live_loop(loop_name, track = nil, start_muted: nil,
                    fade_in: false, fade_out: false,
                    midi: nil, port: nil, channel: nil,
                    cc: nil, fill_cc: nil, cc_port: nil, cc_channel: nil,
                    send_cycle_cues: true, debug: false,
                    init: nil, **kwargs, &block)
  raise "Block must take 0 - 5 arguments" if !block.nil? && block.arity > 5

  raise "If no track is provided, a block must be" if track.nil? && block.nil?

  track ||= Track.rest

  raise "The fade parameters cannot be used with CCTracks" if track.is_a?(CCTrack) && (fade_in || fade_out)

  player = case track
  when Track
    Player.new(track, midi: midi, port: port, channel: channel, debug: debug)
  when CCTrack
    CCPlayer.new(track, port: port, channel: channel, debug: debug)
  end

  # If this is a restart of the same track_live_loop, we will already have a
  # Player instance for the old one. We don't want to reuse it per se (other
  # settings may have changed), but we do want the new player to inherit some of
  # the old one's private state. We shouldn't do that immediately though; we
  # should wait until the old player finishes its final loop so that its
  # internal state is accurate. So we do the inheriting on the first iteration
  # of the new live loop, below.
  old_player = LiveLoopTracker.live_loop_var_get(loop_name, :__player)

  raise "cannot switch track live loop #{loop_name} between track types" unless old_player.nil? || player.is_a?(old_player.class)


  ### Resolve default arguments
  player_defaults = ExtApi.get(:__player_defaults) || {}

  fill_cc = player_defaults[:fill_cc] if fill_cc.nil?
  if fill_cc
    cc_port, cc_channel = __resolve_cc_port_and_channel(cc_port, cc_channel)
    cc_watcher_loop_name = :"__#{loop_name}_cc_fill_watcher"

    ExtApi.live_loop(cc_watcher_loop_name) do
      ExtApi.use_real_time

      # TODO: could support arrays of ports/channels by constructing {x,y,z}-style
      # strings for the path here.
      incoming_cc, cc_val = ExtApi.sync("/midi:#{cc_port}:#{cc_channel}/control_change")
      if incoming_cc == fill_cc
        player.fill = cc_val != 0
        ExtApi.puts("[cc fill control] CC #{cc} = #{cc_val} -> #{player.fill ? '' : 'un'}setting fill for live loop #{loop_name}")
      end
    end

    # Don't send a 0 fill CC for restarts of the same sketch.
    unless LiveLoopTracker.live_loop_is_running(loop_name)
      ExtApi.puts "[cc fill control] sending default CC #{fill_cc} value 0 for live loop #{loop_name}"
      ExtApi.midi_cc(cc, 0, port: cc_port, channel: cc_channel)
    end
  end

  # Use the default sync and start_muted unless we were passed one explicitly.
  unless kwargs.member?(:sync)
    sync = player_defaults[:sync]
    kwargs[:sync] = sync unless sync.nil?
  end
  start_muted = player_defaults[:start_muted] || false if start_muted.nil?


  ### Build the block for the live_loop
  wrapped_block = lambda do |muted, arg|
    # We're smuggling some state between loops via our return value, along with
    # the actual return value of the user's block.
    was_muted = arg[:was_muted]
    unfaded_track = arg[:unfaded_track]
    arg = arg[:block_res]

    unless old_player.nil?
      # This is the first iteration run by a new player; old_player just
      # finished its final loop. So we should have the new player inherit some
      # private state of the old.
      ExtApi.puts("#{loop_name} player: inheriting state from old player") if debug
      player.inherit_state(old_player)
      old_player = nil
    end

    # If we just finished a fade, swap back to the normal version so we don't
    # tell the user's block about it.
    player.swap_track(unfaded_track) unless unfaded_track.nil?
    unfaded_track = nil

    res = nil
    unless block.nil?
      args = [player.cycle, player.track, muted, was_muted, arg].take(block.arity)

      block_kwargs = { cycle: player.cycle, track: player.track, muted: muted, was_muted: was_muted, arg: arg }
      block_kwargs = filter_kwargs_for_proc(block, block_kwargs)

      res = block.call(*args, **block_kwargs)
    end

    if res.is_a?(TrackBase)
      if (res.is_a?(Track) && player.is_a?(CCPlayer)) || (res.is_a?(CCTrack) && player.is_a?(Player))
        raise "cannot switch track live loop #{loop_name} between track types"
      end

      ExtApi.puts("#{loop_name} player: swapping track on cycle #{player.cycle}") if debug
      player.swap_track(res)
    end

    fading_out = false

    # Now that we have the final thing we're going to play, swap it out for the
    # faded version if we need to.
    if !muted && was_muted && fade_in
      ExtApi.puts("#{loop_name} player: fading in track") if debug
      unfaded_track = player.track
      if fade_in == :quad
        faded_track = player.track.fade_in_quad
      else
        faded_track = player.track.fade_in
      end
      player.swap_track(faded_track)
    elsif muted && !was_muted && fade_out
      fading_out = true
      ExtApi.puts("#{loop_name} player: fading out track") if debug
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
      ExtApi.cue(:"#{loop_name}_cycle", player.cycle) if send_cycle_cues
      player.play
    end

    { unfaded_track: unfaded_track, was_muted: muted, block_res: res }
  end


  ### Start the loop
  init_arg = { was_muted: true, block_res: init }

  if cc.nil?
    ll = mutable_live_loop(loop_name, start_muted: start_muted, init: init_arg, **kwargs, &wrapped_block)
  else
    ll = cc_mutable_live_loop(loop_name, start_muted: start_muted, init: init_arg, cc: cc, port: cc_port, channel: cc_channel, **kwargs, &wrapped_block)
  end

  LiveLoopTracker.live_loop_var_set(loop_name, :__player, player)

  ll
end

alias tll track_live_loop


# This method is identical to `track_live_loop` except when the `track`
# parameter is nil. In that case, this method plays a single-slot rest CCTrack,
# rather than a Track. That allows the block of this method to return a CCTrack
# without causing an error.
def cc_track_live_loop(loop_name, track = nil, **kwargs)
  track_live_loop(loop_name, track || CCTrack.rest, **kwargs)
end

alias cctll cc_track_live_loop
