# frozen_string_literal: true

require_relative "ccplayer"
require_relative "cctrack"
require_relative "extapi"
require_relative "player"
require_relative "trackbase"
require_relative "track"
require_relative "utils/live_loop_utils"
require_relative "utils/misc_utils"

# @!group Playback and live loops

# Creates a `live_loop` that plays a track.
#
# This method accepts {Track} and {CCTrack} instances and will create and
# control an appropriate {Player} or {CCPlayer}, respectively. Certain options
# are only valid for one track type; those are called out below.
#
# The `track` argument may be nil (the default), in which case the live loop
# will play a single-slot {Track} containing just a rest. This is useful if
# track_live_loop is called with a block that returns a track; see below for
# details.
#
# Each iteration of the live loop will either {PlayerBase#play play} a cycle of
# the track, or, if the loop is currently muted, {PlayerBase#sleep sleep} for
# its duration. That means that muting takes effect only after a full cycle of
# the track completes. track_live_loops can be muted via MIDI CCs (the `cc`
# argument) or with the {mute_live_loop} function.
#
# The internal player can be put into {PlayerBase#fill fill mode} via a MIDI CC
# if the `fill_cc` argument is provided. Unlike muting, changes to fill mode
# take effect immediately.
#
# Any additional named arguments (e.g. `delay` or `seed`) to this function are
# used verbatim when creating the internal `live_loop`. If a `sync` parameter is
# not specified, the default from {use_player_defaults} is used, if there is
# one. You can explicitly use no sync by passing a nil value for `sync`.
#
# ### The block
#
# A block may be provided, in which case it is called before each cycle of
# playback. The block may accept any of the following keyword arguments:
# - `cycle` (Integer): The current {PlayerBase#cycle cycle} of the internal
#   player.
# - `track` ({Track} or {CCTrack}): The internal player's current track.
# - `muted` (Boolean): Whether the loop is muted.
# - `was_muted` (Boolean): Whether the track was muted in the previous loop.
#   This argument is true the first time the block executes.
# - `arg`: The usual argument for a `live_loop` - the value of the `init`
#   argument on the first iteration, and the return of the prior execution of
#   the block afterwards.
#
# The internal block that plays the track will sleep, so a user-provided block
# does not need to call `sleep` or `sync`, unlike normal `live_loop` blocks.
# If it does sync or sleep, it may cause delays between cycles of the track.
#
# If the block returns a {Track} or {CCTrack}, the internal player instance
# will swap to that track. The swap takes effect immediately; the new track will
# play as soon as it is returned. The {PlayerBase#cycle cycle} will not reset to
# 0 when a track is swapped in this way.
#
# It is an error for the block to attempt to switch between types of tracks.
# For example, the block cannot return a {CCTrack} when the initial call to
# `track_live_loop` was given a {Track}.
#
# Note: a nil `track` argument results in playback of a Track, not a CCTrack. So
# it is invalid for a block to return a CCTrack when this method is not passed a
# track, because that would constitute a switch in track type. If you find
# yourself in that situation, you can use {cc_track_live_loop}, as that method
# uses a single-slot rest {CCTrack} instead but is otherwise identical to this
# one.
#
# @example Simple playback
#   t = T[:c4, :d4, :e4, :f4]
#   track_live_loop :t, t
#
# @example Changing the track every iteration
#   t = T[:c4, :d4, :e4, :f4]
#   track_live_loop :t do
#     # This block will run before each cycle of playback. And since it returns
#     # a Track, playback will switch to it. Each cycle will get a different
#     # random arrangement of slots.
#     t.shuffle
#   end
#
# @example Varying playback based on cycle
#   t = T[:c4, :d4, :e4, :f4]
#   track_live_loop :t do |cycle:|
#     # `cycle` increases after every round of playback, `gate` here will step
#     # up to 1.0 every 10 cycles, then reset.
#     gate = ((cycle + 1) % 10) / 10.0
#     t.gate(gate)
#   end
#
# @param loop_name [Symbol] The name of the live loop.
# @param track [Track, CCTrack] The track that this loop will play, or nil to
#   play a single-slot {Track} containing only a rest (in which case you will
#   almost certainly want to provide a block).
# @param start_muted [Boolean] The initial mute state of the loop. If nil, uses
#   the global default set by {use_player_defaults}, or false if that was not
#   set.
# @param fade_in [Boolean, :quad] If true, the track fades in linearly (via
#   velocity; see {Track#fade_in}) whenever the loop transitions from muted to
#   unmuted. Pass `:quad` to fade the track in with {Track#fade_in_quad}. It is
#   an error to pass any value other than false if `track` is a {CCTrack}.
# @param fade_out [Boolean, :quad] If out, the track fades out linearly (via
#   velocity; see {Track#fade_out}) whenever the loop transitions from unmuted
#   to muted. Pass `:quad` to fade the track out with {Track#fade_out_quad}. It
#   is an error to pass any value other than false if `track` is a {CCTrack}.
#   NOTE: The playback of the faded track happens *after* the loop becomes
#   muted. That is, tracks that are set to fade out will actually play for one
#   additional cycle after the loop is muted, during which they will fade out.
# @param midi [Boolean] If true, the track will play over MIDI rather than
#   Sonic Pi's internal synthesis. This argument is ignored for {CCTrack}s,
#   since they only function over MIDI. If nil, the global default from
#   {use_player_defaults} is used, or false if that was not set.
# @param port [String, nil] The MIDI device to use when `midi` is true. If
#   nil, If nil, falls back to the global default set by Sonic Pi's
#   `use_midi_defaults`, or to all ports (i.e. "*") if that was not set.
# @param channel [Integer, String, nil] The MIDI channel to use when `midi` is
#   true. If nil, falls back in the same manner as `port`.
# @param cc [Integer] The CC number to monitor to control muting of the loop.
#   A value of 0 for this CC will mute the loop; any other value will unmute.
# @param fill_cc [Integer] The CC number to monitor to control {PlayerBase#fill
#   fill mode} on the internal player. A value of 0 for this CC will turn off
#   fill; any other value will turn it on.
# @param cc_port [String, nil] The MIDI port to monitor for CC messages, if
#   either `cc` or `fill_cc` are set. If nil, falls back to the global default
#   set with {use_cc_control_defaults} or all ports (i.e. "*") if no default was
#   set.
# @param cc_channel [Integer, String, nil] The MIDI channel to monitor for CC
#   messages. If nil, falls back in the same manner as `cc_port`.
# @param send_cycle_cues [Boolean] If true, sends sends a cue immediately before
#   each cycle of play with the name `<loop_name>_cycle` and a single value,
#   the {PlayerBase#cycle cycle} that's about to play. Cycle cues are not sent
#   while the loop is muted.
# @param debug [Boolean] If true, details about muting, unmuting, and fill state
#   will be logged, as well as any debug information from the internal player.
# @param init [Object] The initial value to pass to the `arg` parameter of the
#   block.
# @yield See the potential parameters to the block above.
# @yieldreturn [void, Object, Track, CCTrack] A value to pass to the next
#   iteration of the block as the `arg` argument, and potentially a track to
#   switch to. See above.
# @return [void]
def track_live_loop(loop_name, track = nil, start_muted: nil,
                    fade_in: false, fade_out: false,
                    midi: nil, port: nil, channel: nil,
                    cc: nil, fill_cc: nil, cc_port: nil, cc_channel: nil,
                    send_cycle_cues: true, debug: false,
                    init: nil, **kwargs, &block)
  raise ArgumentError, "Block must take 0 - 5 arguments" if !block.nil? && block.arity > 5

  raise ArgumentError, "If no track is provided, a block must be" if track.nil? && block.nil?

  track ||= Track.rest

  raise ArgumentError, "The fade parameters cannot be used with CCTracks" if track.is_a?(CCTrack) && (fade_in || fade_out)

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
  old_player = __player_for_live_loop(loop_name)

  raise TypeError, "cannot switch track live loop #{loop_name} between track types" unless old_player.nil? || player.is_a?(old_player.class)


  ### Resolve default arguments
  player_defaults = current_player_defaults

  fill_cc = player_defaults[:fill_cc] if fill_cc.nil?
  if fill_cc
    cc_watcher_live_loop(:"__#{loop_name}_cc_fill_watcher",
                         port: cc_port, channel: cc_channel) do |incoming_cc, cc_val|
      next if incoming_cc != fill_cc

      player.fill = cc_val != 0
      log("CC #{cc} = #{cc_val} -> #{'un' unless player.fill}setting fill for live loop #{loop_name}", "cc_fill_control")
    end

    # Don't send a 0 fill CC for restarts of the same sketch.
    unless LiveLoopTracker.live_loop_is_running(loop_name)
      log("sending default CC #{fill_cc} value 0 for live loop #{loop_name}", "cc_fill_control")
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
      log("#{loop_name}: inheriting state from old player", "track_live_loop") if debug
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
      block_kwargs = __filter_kwargs_for_proc(block, block_kwargs)

      res = block.call(*args, **block_kwargs)
    end

    if res.is_a?(TrackBase)
      raise TypeError, "cannot switch track live loop #{loop_name} between track types" if (res.is_a?(Track) && player.is_a?(CCPlayer)) || (res.is_a?(CCTrack) && player.is_a?(Player))

      log("#{loop_name}: swapping track on cycle #{player.cycle}", "track_live_loop") if debug
      player.swap_track(res)
    end

    fading_out = false

    # Now that we have the final thing we're going to play, swap it out for the
    # faded version if we need to.
    if !muted && was_muted && fade_in
      log("#{loop_name}: fading in track", "track_live_loop") if debug
      unfaded_track = player.track
      if fade_in == :quad
        faded_track = player.track.fade_in_quad
      else
        faded_track = player.track.fade_in
      end
      player.swap_track(faded_track)
    elsif muted && !was_muted && fade_out
      fading_out = true
      log("#{loop_name}: fading out track", "track_live_loop") if debug
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


# This method is identical to {track_live_loop} except that it plays a dummy
# {CCTrack} (rather than a {Track}) when the `track` parameter is nil. That
# allows the block of this method to return a CCTrack without causing an error.
#
# If you are passing a {CCTrack} as the `track` parameter (rather than nil),
# you can just use {track_live_loop} to play CCTracks.
#
# @return [void]
def cc_track_live_loop(loop_name, track = nil, **kwargs, &block)
  track_live_loop(loop_name, track || CCTrack.rest, **kwargs, &block)
end

alias cctll cc_track_live_loop


# Returns the player instance for a live loop with the given name, or nil if
# the loop is not running or doesn't have a player.
# @private
def __player_for_live_loop(loop_name)
  LiveLoopTracker.live_loop_var_get(loop_name, :__player)
end

# Sets the {PlayerBase#fill fill mode} on the player associated with a
# `live_loop` made by {track_live_loop}. Unlike {mute_live_loop muting}, setting
# fill mode takes effect immediately.
# @param loop_name [Symbol] The name of the target live loop.
# @param fill [Boolean] The desired fill mode for the loop's internal player.
# @return [void]
# @see PlayerBase#fill
# @see Prob.fill
# @see unset_live_loop_fill
def set_live_loop_fill(loop_name, fill = true)
  __player_for_live_loop(loop_name)&.fill = fill
end
alias fill_live_loop set_live_loop_fill

# Turns off {PlayerBase#fill fill mode} on the player associated with a
# `live_loop` made by {track_live_loop}.
# @param loop_name [Symbol] The name of the target live loop.
# @return [void]
# @see PlayerBase#fill
# @see Prob.fill
# @see set_live_loop_fill
def unset_live_loop_fill(loop_name)
  set_live_loop_fill(loop_name, false)
end
alias unfill_live_loop unset_live_loop_fill
