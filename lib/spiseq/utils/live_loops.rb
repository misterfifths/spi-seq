# frozen_string_literal: true

require_relative "midi"
require_relative "../external/midi"
require_relative "../external/sync"
require_relative "../internal/log"
require_relative "../internal/midi"
require_relative "../internal/thread_tracker"
require_relative "../internal/utils"

module SpiSeq; module Utils; module LiveLoops
  # @private
  module State
    # It could potentially make sense to store this state as a thread variable
    # on the loop, but we want it in place before the thread exists in
    # mutable_live_loop. And if it only lived on the thread, we'd have to find
    # a way to inherit it when swapping to new track_live_loops. So it seems
    # cleaner to just hold the state externally.
    @loop_mute_states = {}

    def self.mute_loop(name, mute = true) = @loop_mute_states[name] = mute

    # This returns the current stored value, which changes immediately upon
    # (un)muting, so it may not reflect the effective status in the middle of a
    # cycle of playback.
    def self.loop_is_muted?(name) = @loop_mute_states[name] || false
  end
  private_constant :State


  # @!group Playback and live loops

  # Mutes or unmutes the given `live_loop`, assuming it was created by
  # {mutable_live_loop}, {cc_mutable_live_loop}, or {Playback.track_live_loop}.
  # Muting is not instantaneous; it takes effect after a cycle of the live
  # loop's block. See {mutable_live_loop} for details.
  # @param loop_name [Symbol] The name of the target live loop.
  # @param mute [Boolean] Whether to mute or unmute the loop.
  # @return [void]
  # @see unmute_live_loop
  module_function def mute_live_loop(loop_name, mute = true) = State.mute_loop(loop_name, mute)

  # Unmutes the given mutable `live_loop` (i.e., one created by
  # {mutable_live_loop}, {cc_mutable_live_loop}, or {Playback.track_live_loop}).
  # An alias passing false to {mute_live_loop}.
  # @param loop_name [Symbol] The name of the target live loop.
  # @return [void]
  module_function def unmute_live_loop(loop_name) = mute_live_loop(loop_name, false)

  # Starts a new `live_loop` that can be muted with {mute_live_loop}. What
  # "mute" means must be implemented by the given block; this function merely
  # manages the muted state and informs the block of it.
  #
  # Any additional named arguments (e.g. `sync` or `init`) to this function are
  # passed verbatim to the internal `live_loop`.
  #
  # The arguments passed to the block differe from a normal `live_loop`. Namely,
  # the first argument is a boolean indicating whether the loop is muted.
  #
  # Muting is not instantaneous. The block is only made aware of the muted
  # status the next time it executes, via its first argument. So, muting will
  # happen only between cycles of a loop, not in the middle of one.
  #
  # @param loop_name [Symbol] The name of the live loop.
  # @param start_muted [Boolean] The initial state of the muted flag.
  # @yieldparam muted [Boolean] Whether the loop is muted.
  # @yieldparam arg [Object] (optional) The usual argument for a `live_loop`:
  #   the value of the `init` argument on the first iteration, and the return of
  #   the prior execution of the block afterwards.
  # @return [void]
  # @see cc_mutable_live_loop
  # @see Playback.track_live_loop
  module_function def mutable_live_loop(loop_name, start_muted: false, **, &block)
    raise ArgumentError, "Block must take 1 or 2 arguments" if block.arity == 0 || block.arity > 2

    # Only apply start_muted if this is a fresh definition of the loop (i.e, not
    # a restart of the same sketch).
    mute_live_loop(loop_name, start_muted) unless Internal::ThreadTracker.is_running?(loop_name)

    ll = External::Sync.live_loop(loop_name, **) do |arg|
      Internal::Utils.call_varargs(block, State.loop_is_muted?(loop_name), arg)
    end

    Internal::ThreadTracker.register(loop_name, ll)
    ll
  end

  # Starts a new `live_loop` that can be muted by a MIDI CC message. A value of
  # 0 for the CC will mute, and any other value will unmute. What "mute" means
  # must be implemented by the given block; this function merely manages the
  # muted state and informs the block of it.
  #
  # Any additional named arguments (e.g. `sync` or `init`) to this function are
  # passed verbatim to the internal `live_loop`.
  #
  # @param (see mutable_live_loop)
  # @param cc [Integer] The CC number to monitor to control muting of the loop.
  # @param channel [Integer, String, nil] The MIDI channel to watch for CC
  #   messages. If nil, falls back to the global default set by
  #   {MIDI.use_cc_control_defaults}, or to all channels (i.e. "*") if that was
  #   not set.
  # @param port [String, nil] The MIDI device to monitor. If nil, falls back in
  #   the same manner as `channel`.
  # @yieldparam (see mutable_live_loop)
  # @return [void]
  # @see mutable_live_loop
  # @see Playback.track_live_loop
  module_function def cc_mutable_live_loop(loop_name, cc:, port: nil, channel: nil, start_muted: false, **, &)
    port, channel = Internal::MIDI.resolve_cc_port_and_channel(port, channel)

    MIDI.cc_watcher_live_loop(:"__#{loop_name}_cc_mute_watcher", port:, channel:) do |incoming_cc, cc_val|
      next if incoming_cc != cc
      muted = cc_val == 0
      Internal::Log.log("CC #{cc} = #{cc_val} -> #{'un' unless muted}muting live loop #{loop_name}", "cc_mute_control")
      mute_live_loop(loop_name, muted)
    end

    # Only send a CC for the start_muted value if this is a fresh definition of
    # the loop (i.e., not a restart of the same sketch).
    unless Internal::ThreadTracker.is_running?(loop_name)
      default_cc_val = start_muted ? 0 : 127
      Internal::Log.log("sending default CC #{cc} value #{default_cc_val} for live loop #{loop_name}", "cc_mute_control")
      External::MIDI.midi_cc(cc, default_cc_val, port:, channel:)
    end

    mutable_live_loop(loop_name, start_muted:, **, &)
  end
end; end; end
