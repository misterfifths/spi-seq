# frozen_string_literal: true

require "weakref"
require_relative "midi_utils"
require_relative "../extapi"

# @!group Playback and live loops

# Helpers to track running live_loops and associate values with them.
# @private
module LiveLoopTracker
  # Record the live loop with `name` as being associated with `thread` (which is
  # the return value of `live_loop`). You must call this after creating a live
  # loop for this module to be able to track the loop.
  def self.register_live_loop(name, thread)
    @ll_threads ||= {}
    @ll_threads[name] = WeakRef.new(thread)
  end

  # Returns the Thread object associated with the live loop with the given name.
  # If the live loop is not running (or has not been created), returns nil.
  def self.thread_for_live_loop(name)
    @ll_threads ||= {}
    thread = @ll_threads[name]
    return thread if !thread.nil? && thread.weakref_alive? && thread.alive?
    nil
  end

  # Returns true if a live loop with the given name is running.
  def self.live_loop_is_running(name)
    !thread_for_live_loop(name).nil?
  end

  # Associates a value with the live loop with the given name. The value can be
  # retrieved with live_loop_var_get. When the live loop stops, this value will
  # no longer be accessible.
  def self.live_loop_var_set(loop_name, var_name, value)
    thread_for_live_loop(loop_name)&.thread_variable_set(var_name, value)
  end

  # Returns the value of a variable associated with the live loop with the given
  # name, as set by live_loop_var_set. Returns nil if there is no such variable
  # associated with the loop, or if the live loop has stopped.
  def self.live_loop_var_get(loop_name, var_name)
    thread_for_live_loop(loop_name)&.thread_variable_get(var_name)
  end
end


# Returns the Time State key that can be used to control muting of a mutable
# `live_loop` created by that family of functions.
# @private
def __mute_key(loop_name)
  :"__live_loop_#{loop_name}_muted"
end

# Mutes or unmutes the given `live_loop`, assuming it was created by
# {mutable_live_loop}, {cc_mutable_live_loop}, or {track_live_loop}. Note that
# muting is not instantaneous; see the description of {mutable_live_loop} for
# details.
# @param loop_name [Symbol] The name of the target live loop.
# @param mute [Boolean] Whether to mute or unmute the loop.
# @return [void]
# @see unmute_live_loop
def mute_live_loop(loop_name, mute=true)
  ExtApi.set(__mute_key(loop_name), mute)
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
# Note that the arguments passed to the block differe from a normal `live_loop`.
# Namely, the first argument is a boolean indicating whether the loop is muted.
#
# Note that muting is not instantaneous. The block is only made aware of the
# muted status the next time it executes, via its first argument. So, muting
# will happen only between cycles of a loop, not in the middle of one.
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

  key = __mute_key(loop_name)

  # Only apply start_muted if this is a fresh definition of the loop (i.e, not a
  # restart of the same sketch).
  ExtApi.set(key, start_muted) unless LiveLoopTracker.live_loop_is_running(loop_name)

  ll = ExtApi.live_loop(loop_name, **kwargs) do |arg|
    muted = ExtApi.get(key)

    if block.arity == 2
      block.call(muted, arg)
    else
      block.call(muted)
    end
  end

  LiveLoopTracker.register_live_loop(loop_name, ll)
  ll
end

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
  $__CC_CONTROL_DEFAULTS = defaults  # rubocop:disable Style/GlobalVars
end

# Returns the current CC control defaults as set by {use_cc_control_defaults},
# or an empty hash if no defaults have been set.
# @return [Hash{Symbol => Object}]
def current_cc_control_defaults
  $__CC_CONTROL_DEFAULTS || {}  # rubocop:disable Style/GlobalVars
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
    _log("CC #{cc} = #{cc_val} -> #{'un' unless muted}muting live loop #{loop_name}", "cc_mute_control")
    mute_live_loop(loop_name, muted)
  end

  # Only send a CC for the start_muted value if this is a fresh definition of
  # the loop (i.e., not a restart of the same sketch).
  unless LiveLoopTracker.live_loop_is_running(loop_name)
    default_cc_val = start_muted ? 0 : 127
    _log("sending default CC #{cc} value #{default_cc_val} for live loop #{loop_name}", "cc_mute_control")
    ExtApi.midi_cc(cc, default_cc_val, port: port, channel: channel)
  end

  mutable_live_loop(loop_name, start_muted: start_muted, **kwargs, &block)
end
