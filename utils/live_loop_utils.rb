# frozen_string_literal: true

require "weakref"
require_relative "internal_utils"
require_relative "midi_utils"
require_relative "../external/midi"
require_relative "../external/sync"

# @private
module SpiSeq
  # Helpers to track running live_loops and associate values with them.
  module LiveLoops
    # Record the live loop with the given name as being associated with `thread`
    # (which is the return value of `live_loop`). You must call this after
    # creating a live loop for this module to be able to track the loop.
    def self.register(loop_name, thread)
      @ll_threads ||= {}
      @ll_threads[loop_name] = WeakRef.new(thread)
    end

    # Returns the Thread object associated with the live loop with the given
    # name. If the live loop is not running (or has not been created), returns
    # nil.
    def self.get_thread(loop_name)
      @ll_threads ||= {}
      thread = @ll_threads[loop_name]
      return thread if !thread.nil? && thread.weakref_alive? && thread.alive?
      nil
    end

    # Returns true if a live loop with the given name is running.
    def self.is_running?(loop_name)
      !get_thread(loop_name).nil?
    end

    # Associates a value with the live loop with the given name. The value can
    # be retrieved with live_loop_var_get. When the live loop stops, this value
    # will no longer be accessible.
    def self.loop_var_set(loop_name, var_name, value)
      get_thread(loop_name)&.thread_variable_set(var_name, value)
    end

    # Returns the value of a variable associated with the live loop with the
    # given name, as set by live_loop_var_set. Returns nil if there is no such
    # variable associated with the loop, or if the live loop has stopped.
    def self.loop_var_get(loop_name, var_name)
      get_thread(loop_name)&.thread_variable_get(var_name)
    end

    def self.mute_loop(loop_name, mute = true)
      # It could potentially make sense to store this state as a thread variable
      # on the loop, but we want it in place before the thread exists in
      # mutable_live_loop. And if it only lived on the thread, we'd have to find
      # a way to inherit it when swapping to new track_live_loops. So it seems
      # cleaner to just hold the state locally.
      @loop_mute_states ||= {}
      @loop_mute_states[loop_name] = mute
    end

    def self.loop_is_muted?(loop_name)
      @loop_mute_states ||= {}
      @loop_mute_states[loop_name] || false
    end
  end

  module Defaults
    class << self
      attr_accessor :cc_control_defaults
    end
  end
end


# @!group Default settings

# Set global default MIDI parameters to use when watching for incoming CC
# messages. Such events are used to control various features, such as muting
# live loops (e.g. those made from {cc_mutable_live_loop} and
# {track_live_loop}), toggling fill mode in {track_live_loop}, and controlling
# recording in {Track.record}.
# @param channel [Integer, String, nil] The default MIDI channel to watch for
#   CC events. If nil, defaults to all channels (i.e. "*").
# @param port [String, nil] The MIDI device to watch for CC events. If nil, also
#   falls back to "*".
# @return [void]
# @see current_cc_control_defaults
def use_cc_control_defaults(port: nil, channel: nil)
  defaults = {}
  defaults[:port] = port unless port.nil?
  defaults[:channel] = channel unless channel.nil?
  SpiSeq::Defaults.cc_control_defaults = defaults.freeze
end

# Returns the current CC control defaults as set by {use_cc_control_defaults},
# or an empty hash if no defaults have been set.
# @return [Hash{Symbol => Object}]
def current_cc_control_defaults
  SpiSeq::Defaults.cc_control_defaults || {}
end

# @!endgroup


# @!group Playback and live loops

# Mutes or unmutes the given `live_loop`, assuming it was created by
# {mutable_live_loop}, {cc_mutable_live_loop}, or {track_live_loop}. Muting is
# not instantaneous; it takes effect after a cycle of the live loop's block. See
# {mutable_live_loop} for details.
# @param loop_name [Symbol] The name of the target live loop.
# @param mute [Boolean] Whether to mute or unmute the loop.
# @return [void]
# @see unmute_live_loop
def mute_live_loop(loop_name, mute=true)
  SpiSeq::LiveLoops.mute_loop(loop_name, mute)
end

# Unmutes the given mutable `live_loop`. An alias passing false to
# {mute_live_loop}.
# @param loop_name [Symbol] The name of the target live loop.
# @return [void]
def unmute_live_loop(loop_name)
  mute_live_loop(loop_name, false)
end

# Starts a new `live_loop` that can be muted with {mute_live_loop}. What "mute"
# means must be implemented by the given block; this function merely manages the
# muted state and informs the block of it.
#
# Any additional named arguments (e.g. `sync` or `init`) to this function are
# passed verbatim to the internal `live_loop`.
#
# The arguments passed to the block differe from a normal `live_loop`. Namely,
# the first argument is a boolean indicating whether the loop is muted.
#
# Muting is not instantaneous. The block is only made aware of the muted status
# the next time it executes, via its first argument. So, muting will happen only
# between cycles of a loop, not in the middle of one.
#
# @param loop_name [Symbol] The name of the live loop.
# @param start_muted [Boolean] The initial state of the muted flag.
# @yieldparam muted [Boolean] Whether the loop is muted.
# @yieldparam arg [Object] (optional) The usual argument for a `live_loop`: the
#   value of the `init` argument on the first iteration, and the return of the
#   prior execution of the block afterwards.
# @return [void]
# @see cc_mutable_live_loop
# @see track_live_loop
def mutable_live_loop(loop_name, start_muted: false, **kwargs, &block)
  raise ArgumentError, "Block must take 1 or 2 arguments" if block.arity == 0 || block.arity > 2

  # Only apply start_muted if this is a fresh definition of the loop (i.e, not a
  # restart of the same sketch).
  mute_live_loop(loop_name, start_muted) unless SpiSeq::LiveLoops.is_running?(loop_name)

  ll = SpiSeq::External::Sync.live_loop(loop_name, **kwargs) do |arg|
    muted = SpiSeq::LiveLoops.loop_is_muted?(loop_name)
    SpiSeq::Utils.call_varargs(block, muted, arg)
  end

  SpiSeq::LiveLoops.register(loop_name, ll)
  ll
end

# Starts a new `live_loop` that can be muted by a MIDI CC message. A value of 0
# for the CC will mute, and any other value will unmute. What "mute" means must
# be implemented by the given block; this function merely manages the muted
# state and informs the block of it.
#
# Any additional named arguments (e.g. `sync` or `init`) to this function are
# passed verbatim to the internal `live_loop`.
#
# @param (see mutable_live_loop)
# @param cc [Integer] The CC number to monitor to control muting of the loop.
# @param channel [Integer, String, nil] The MIDI channel to watch for CC
#   messages. If nil, falls back to the global default set by
#   {use_cc_control_defaults}, or to all channels (i.e. "*") if that was not
#   set.
# @param port [String, nil] The MIDI device to monitor. If nil, falls back in
#   the same manner as `channel`.
# @yieldparam (see mutable_live_loop)
# @return [void]
# @see mutable_live_loop
# @see track_live_loop
def cc_mutable_live_loop(loop_name, cc:, port: nil, channel: nil, start_muted: false, **kwargs, &block)
  port, channel = SpiSeq::MIDI.resolve_cc_port_and_channel(port, channel)

  cc_watcher_live_loop(:"__#{loop_name}_cc_mute_watcher",
                       port: port, channel: channel) do |incoming_cc, cc_val|
    next if incoming_cc != cc
    muted = cc_val == 0
    SpiSeq::Log.log("CC #{cc} = #{cc_val} -> #{'un' unless muted}muting live loop #{loop_name}", "cc_mute_control")
    mute_live_loop(loop_name, muted)
  end

  # Only send a CC for the start_muted value if this is a fresh definition of
  # the loop (i.e., not a restart of the same sketch).
  unless SpiSeq::LiveLoops.is_running?(loop_name)
    default_cc_val = start_muted ? 0 : 127
    SpiSeq::Log.log("sending default CC #{cc} value #{default_cc_val} for live loop #{loop_name}", "cc_mute_control")
    SpiSeq::External::MIDI.midi_cc(cc, default_cc_val, port: port, channel: channel)
  end

  mutable_live_loop(loop_name, start_muted: start_muted, **kwargs, &block)
end
