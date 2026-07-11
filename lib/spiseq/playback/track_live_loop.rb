# frozen_string_literal: true

require_relative "ccplayer"
require_relative "player"
require_relative "../external/midi"
require_relative "../external/sync"
require_relative "../internal/log"
require_relative "../internal/midi"
require_relative "../internal/thread_tracker"
require_relative "../internal/utils"
require_relative "../tracks/cctrack"
require_relative "../tracks/track"
require_relative "../utils/live_loops"
require_relative "../utils/midi"

module SpiSeq; module Internal; module TrackLiveLoopUtils
  module_function def get_player(loop_name) = ThreadTracker.var_get(loop_name, :__player)

  module_function def set_player(loop_name, player) = ThreadTracker.var_set(loop_name, :__player, player)

  module_function def track_live_loop_block_state(block_arg:, was_muted: true, unfaded_track: nil)
    { block_arg:, was_muted:, unfaded_track: }
  end

  # Returns a lambda for use as a live_loop block which handles playback of
  # a track. A helper for track_live_loop.
  module_function def track_live_loop_block(loop_name:, player:, old_player:,
                                            send_cycle_cues:, fade_in:, fade_out:,
                                            user_block:, debug:)
    # It is tempting to maintain state in captured variables rather than passing
    # it between iterations of the loop, but such state gets lost when the loop
    # is recreated (e.g. if the sketch is re-run). Sonic Pi makes sure to pass
    # the block's return between iterations even across recreations however, so
    # that's a more appropriate mechanism.
    lambda do |muted, smuggled_state|
      smuggled_state => {was_muted:, unfaded_track:, block_arg:}

      ### Inherit state from an old player
      # If old_player is not nil, this must be our first iteration after it
      # finished its final loop. Pick up where it left off.
      unless old_player.nil?
        Log.log("#{loop_name}: inheriting state from old player", "track_live_loop") if debug
        player.inherit_state(old_player)
        old_player = nil
      end

      ### Restore the original track if we just finished a fade
      # We want to play the original (unless it gets swapped via the block),
      # and we don't want to tell the user block about the faded version we
      # made. We don't reset accum here so that it persists between the faded
      # and unfaded version of the track (see PlayerBase.accum_data).
      player.swap_track(unfaded_track, reset_accum: false) unless unfaded_track.nil?
      unfaded_track = nil

      ### Call the user's block & possibly swap tracks
      block_res = nil
      unless user_block.nil?
        block_res = Utils.call_varargs(user_block,
                                       cycle: player.cycle, track: player.track,
                                       muted:, was_muted:, arg: block_arg)

        if block_res.is_a?(Tracks::TrackBase)
          raise TypeError, "cannot switch track live loop #{loop_name} between track types" unless block_res.instance_of?(player.track.class)
          Log.log("#{loop_name}: swapping track on cycle #{player.cycle}", "track_live_loop") if debug
          player.swap_track(block_res)
        end
      end

      ### Swap to a faded track if needed
      fading_in = !muted && was_muted && fade_in
      fading_out = muted && !was_muted && fade_out

      if fading_in || fading_out
        Log.log("#{loop_name}: fading #{fading_in ? 'in' : 'out'} track", "track_live_loop") if debug

        unfaded_track = player.track  # For restoration in the next iteration

        quad = fading_in ? (fade_in == :quad) : (fade_out == :quad)
        fade_method = :"fade_#{fading_in ? 'in' : 'out'}#{'_quad' if quad}"
        faded_track = player.track.send(fade_method)

        # We're not resetting accum here; we want accumulation to carry into
        # the faded track. PlayerBase.accum_data has details.
        player.swap_track(faded_track, reset_accum: false)
      end

      ### Play or sleep
      if muted && !fading_out
        player.sleep
      else
        External::Sync.cue(:"#{loop_name}_cycle", player.cycle) if send_cycle_cues
        player.play
      end

      ### Assemble state for the next iteration.
      track_live_loop_block_state(block_arg: block_res, was_muted: muted, unfaded_track:)
    end
  end
end; end; end


module SpiSeq; module Playback
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
  # Each iteration of the live loop will either {PlayerBase#play play} a cycle
  # of the track, or, if the loop is currently muted, {PlayerBase#sleep sleep}
  # for its duration. That means that muting takes effect only after a full
  # cycle of the track completes. track_live_loops can be muted via MIDI CCs
  # (the `cc` argument) or with the {Utils::LiveLoops.mute_live_loop} function.
  #
  # The internal player can be put into {PlayerBase#fill fill mode} via a MIDI
  # CC if the `fill_cc` argument is provided, or with the {fill_live_loop}
  # function. Unlike muting, changes to fill mode take effect immediately.
  #
  # Any additional named arguments (e.g. `delay` or `seed`) to this function are
  # used verbatim when creating the internal `live_loop`. If a `sync` parameter
  # is not specified, the default from {use_player_defaults} is used, if there
  # is one. You can explicitly use no sync by passing a nil value for `sync`.
  #
  # ### The block
  #
  # A block may be provided, in which case it is called before each cycle of
  # playback. The block may accept any of the following keyword arguments:
  # - `cycle` (Integer): The current {PlayerBase#cycle cycle} of the internal
  #   player.
  # - `track` ({Track} or {CCTrack}): The track the internal player will play in
  #   this cycle, unless the block returns a new one (see below).
  # - `muted` (Boolean): Whether playback from this loop is muted.
  # - `was_muted` (Boolean): Whether playback was muted in this loop in the
  #   previous cycle. This argument is true the first time the block executes.
  # - `arg`: The usual argument for a `live_loop` - the value of the `init`
  #   argument on the first iteration, and the return of the prior execution of
  #   the block afterwards.
  #
  # A block is mandatory if the `track` argument is nil.
  #
  # The internal block that plays the track will sleep, so a user-provided block
  # does not need to call `sleep` or `sync`, unlike normal `live_loop` blocks.
  # If it does sync or sleep, it may cause delays between cycles of the track.
  #
  # If the block returns a {Track} or {CCTrack}, the internal player instance
  # will swap to that track. The swap takes effect immediately; the new track
  # will play as soon as it is returned. The {PlayerBase#cycle cycle} will not
  # reset to 0 when a track is swapped in this way. Any other return type from
  # the block is ignored, though it will be passed to the next iteration of the
  # block via the `arg` parameter.
  #
  # It is an error for the block to attempt to switch between types of tracks.
  # For example, the block cannot return a {CCTrack} when the initial call to
  # `track_live_loop` was given a {Track}.
  #
  # Note: a nil `track` argument results in playback of a Track, not a CCTrack.
  # So it is invalid for a block to return a CCTrack when this method is not
  # passed a track, because that would constitute a switch in track type. If you
  # find yourself in that situation, you can use {cc_track_live_loop}, as that
  # method uses a single-slot rest CCTrack instead but is otherwise identical to
  # this one.
  #
  # @example Simple playback
  #   t = T[:c4, :d4, :e4, :f4]
  #   track_live_loop :t, t
  #
  # @example Changing the track every iteration
  #   t = T[:c4, :d4, :e4, :f4]
  #   track_live_loop :t do
  #     # This block will run before each cycle of playback. And since it
  #     # returns a Track, playback will switch to it. Each cycle will get a
  #     # different random arrangement of slots.
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
  #   play a single-slot {Track} containing only a rest. If this is nil, a block
  #   must be provided, and you will almost certainly want to return a track
  #   from it.
  # @param start_muted [Boolean] The initial mute state of the loop. If nil,
  #   uses the global default set by {use_player_defaults}, or false if that was
  #   not set.
  # @param fade_in [Boolean, :quad] If true, the track fades in linearly (via
  #   velocity; see {Tracks::Track#fade_in}) whenever the loop transitions from
  #   muted to unmuted. Pass `:quad` to fade the track in with
  #   {Tracks::Track#fade_in_quad}. It is an error to pass any value other than
  #   false if `track` is a {CCTrack}.
  # @param fade_out [Boolean, :quad] If true, the track fades out linearly (via
  #   velocity; see {Tracks::Track#fade_out}) whenever the loop transitions from
  #   unmuted to muted. Pass `:quad` to fade the track out with
  #   {Tracks::Track#fade_out_quad}. It is an error to pass any value other than
  #   false if `track` is a {CCTrack}. The playback of the faded track happens
  #   *after* the loop becomes muted. That is, tracks that are set to fade out
  #   will actually play for one additional cycle after the loop is muted,
  #   during which they will fade out.
  # @param midi [Boolean] If true, the track will play over MIDI rather than
  #   Sonic Pi's internal synthesis. This argument is ignored for {CCTrack}s,
  #   since they only function over MIDI. If nil, the global default from
  #   {use_player_defaults} is used, or false if that was not set.
  # @param port [String, nil] The MIDI device to use when `midi` is true. If
  #   nil, falls back to the global default set by Sonic Pi's
  #   `use_midi_defaults`, or to all ports (i.e. "*") if that was not set.
  # @param channel [Integer, String, nil] The MIDI channel to use when `midi` is
  #   true. If nil, falls back in the same manner as `port`.
  # @param cc [Integer] The CC number to monitor to control muting of the loop.
  #   A value of 0 for this CC will mute the loop; any other value will unmute.
  #   You can also mute loops with {Utils::LiveLoops.mute_live_loop}.
  # @param fill_cc [Integer] The CC number to monitor to control
  #   {PlayerBase#fill fill mode} on the internal player. A value of 0 for this
  #   CC will turn off fill; any other value will turn it on. If this argument
  #   is nil, falls back to the global default set with {use_player_defaults},
  #   or no CC fill control if no default was set. You can also set fill mode
  #   for a loop with {fill_live_loop}.
  # @param cc_port [String, nil] The MIDI port to monitor for CC messages, if
  #   either `cc` or `fill_cc` are set. If nil, falls back to the global default
  #   set with {Utils::MIDI.use_cc_control_defaults} or all ports (i.e. "*") if
  #   no default was set.
  # @param cc_channel [Integer, String, nil] The MIDI channel to monitor for CC
  #   messages. If nil, falls back in the same manner as `cc_port`.
  # @param send_cycle_cues [Boolean] If true, sends sends a cue immediately
  #   before each cycle of play with the name `<loop_name>_cycle` and a single
  #   value, the {PlayerBase#cycle cycle} that's about to play. Cycle cues are
  #   not sent while the loop is muted. If nil, falls back to the global default
  #   set with {use_player_defaults}, or true if no default was set.
  # @param debug [Boolean] If true, details about muting, unmuting, and fill
  #   state will be logged, as well as any debug information from the internal
  #   player.
  # @param init [Object] The initial value to pass to the `arg` parameter of the
  #   block.
  # @param sync [Symbol, nil] The name of the initial cue to wait for before
  #   starting the live loop (as with `live_loop`). If `:default_sync`, uses the
  #   global default set with {use_player_defaults}, if any. If `nil`, the loop
  #   does not wait for a cue.
  # @yield See the potential parameters to the block above.
  # @yieldreturn [void, Object, Track, CCTrack] A value to pass to the next
  #   iteration of the block as the `arg` argument, and potentially a track to
  #   switch to. See above.
  # @return [void]
  module_function def track_live_loop(loop_name, track = nil, start_muted: nil,
                                      fade_in: false, fade_out: false,
                                      midi: nil, port: nil, channel: nil,
                                      cc: nil, fill_cc: nil, cc_port: nil, cc_channel: nil,
                                      send_cycle_cues: nil, debug: false,
                                      init: nil, sync: :default_sync, **, &block)
    ### Validate arguments
    unless block.nil?
      req_pos_args, opt_pos_args, req_keywords, = Internal::Utils.describe_args(block)
      # We could allow optional required arguments, but a block's positional
      # arguments are all reported as optional, so let's play it safe.
      raise ArgumentError, "Block cannot have positional arguments" unless req_pos_args == 0 && opt_pos_args == 0
      valid_keywords = %i[cycle track muted was_muted arg]
      raise ArgumentError, "Block requires an invalid keyword argument" if req_keywords.any? { |k| !valid_keywords.include?(k) }
    end

    raise ArgumentError, "If no track is provided, a block must be" if track.nil? && block.nil?

    ### Make the player (and possibly track)
    track ||= Tracks::Track.rest
    raise ArgumentError, "The fade parameters cannot be used with CCTracks" if track.is_a?(Tracks::CCTrack) && (fade_in || fade_out)

    player = case track
    when Tracks::Track
      Player.new(track, midi:, port:, channel:, debug:)
    when Tracks::CCTrack
      CCPlayer.new(track, port:, channel:, debug:)
    end

    ### Fetch & validate against an existing player
    # If this is a restart of the same track_live_loop, we will already have a
    # player instance for the old one. We don't want to reuse it per se (other
    # settings may have changed), but we do want the new player to inherit some
    # of the old one's private state. We shouldn't do that immediately though;
    # we should wait until the old player finishes its final loop so that its
    # internal state is accurate. So we do the inheriting on the first iteration
    # of the new live loop (see track_live_loop_block).
    old_player = Internal::TrackLiveLoopUtils.get_player(loop_name)
    raise TypeError, "cannot switch track live loop #{loop_name} between track types" unless old_player.nil? || player.is_a?(old_player.class)

    ### Resolve default arguments
    player_defaults = current_player_defaults
    cc_port, cc_channel = Internal::MIDI.resolve_cc_port_and_channel(cc_port, cc_channel)
    fill_cc = player_defaults[:fill_cc] if fill_cc.nil?
    sync = player_defaults[:sync] if sync == :default_sync
    start_muted = player_defaults[:start_muted] || false if start_muted.nil?
    send_cycle_cues = player_defaults.fetch(:send_cycle_cues, true) if send_cycle_cues.nil?

    ### Start a fill CC watcher if needed
    if fill_cc
      Utils::MIDI.cc_watcher_live_loop(:"__#{loop_name}_cc_fill_watcher",
                          port: cc_port, channel: cc_channel) do |incoming_cc, cc_val|
        next if incoming_cc != fill_cc

        player.fill = cc_val != 0
        Internal::Log.log("CC #{fill_cc} = #{cc_val} -> #{'un' unless player.fill}setting fill for live loop #{loop_name}", "cc_fill_control")
      end

      # Don't send a 0 fill CC for restarts of the same sketch.
      unless Internal::ThreadTracker.is_running?(loop_name)
        Internal::Log.log("sending default CC #{fill_cc} value 0 for live loop #{loop_name}", "cc_fill_control")
        External::MIDI.midi_cc(fill_cc, 0, port: cc_port, channel: cc_channel)
      end
    end

    ### Kick off the loop
    ll_block = Internal::TrackLiveLoopUtils.track_live_loop_block(
      loop_name:, player:, old_player:, send_cycle_cues:, fade_in:, fade_out:,
      user_block: block, debug:)

    init = Internal::TrackLiveLoopUtils.track_live_loop_block_state(block_arg: init)

    ll = if cc.nil?
      Utils::LiveLoops.mutable_live_loop(loop_name, start_muted:, init:, sync:, **, &ll_block)
    else
      Utils::LiveLoops.cc_mutable_live_loop(loop_name, start_muted:, init:, sync:, cc:, port: cc_port, channel: cc_channel, **, &ll_block)
    end

    Internal::TrackLiveLoopUtils.set_player(loop_name, player)

    ll
  end
  alias tll track_live_loop
  class << self; alias tll track_live_loop; end


  # This method is identical to {track_live_loop} except that it plays a dummy
  # {CCTrack} (rather than a {Track}) when the `track` parameter is nil. That
  # allows the block of this method to return a CCTrack without causing an
  # error.
  #
  # If you are passing a {CCTrack} as the `track` parameter (rather than nil),
  # you can just use {track_live_loop} to play CCTracks.
  #
  # @return [void]
  module_function def cc_track_live_loop(loop_name, track = nil, **, &)
    track_live_loop(loop_name, track || Tracks::CCTrack.rest, **, &)
  end
  alias cctll cc_track_live_loop
  class << self; alias cctll cc_track_live_loop; end


  # Sets the {PlayerBase#fill fill mode} on the player associated with a
  # `live_loop` made by {track_live_loop}. Unlike
  # {Utils::LiveLoops.mute_live_loop muting}, setting fill mode takes effect
  # immediately.
  # @param loop_name [Symbol] The name of the target live loop.
  # @param fill [Boolean] The desired fill mode for the loop's internal player.
  # @return [void]
  # @see PlayerBase#fill
  # @see Tracks::Prob.fill
  # @see unset_live_loop_fill
  module_function def set_live_loop_fill(loop_name, fill = true)
    Internal::TrackLiveLoopUtils.get_player(loop_name)&.fill = fill
  end
  alias fill_live_loop set_live_loop_fill
  class << self; alias fill_live_loop set_live_loop_fill; end

  # Turns off {PlayerBase#fill fill mode} on the player associated with a
  # `live_loop` made by {track_live_loop}.
  # @param loop_name [Symbol] The name of the target live loop.
  # @return [void]
  # @see PlayerBase#fill
  # @see Tracks::Prob.fill
  # @see set_live_loop_fill
  module_function def unset_live_loop_fill(loop_name) = set_live_loop_fill(loop_name, false)
  alias unfill_live_loop unset_live_loop_fill
  class << self; alias unfill_live_loop unset_live_loop_fill; end
end; end
