# frozen_string_literal: true

require "weakref"
require_relative "../extapi"

# Helpers to track running live_loops and associate values with them.
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
# live_loop created by that family of functions.
def mute_key(loop_name)
  :"__live_loop_#{loop_name}_muted"
end

# Mutes the given live_loop, assuming it was created by one of the functions in
# the mutable_live_loop family. Note that muting is not instantaneous; see the
# description of mutable_live_loop for details.
def mute_live_loop(loop_name, mute=true)
  ExtApi.set(mute_key(loop_name), mute)
end

# Unmutes the given live_loop - alias for mute_live_loop(loop_name, false).
def unmute_live_loop(loop_name)
  mute_live_loop(loop_name, false)
end

# Starts a new live_loop that can be muted by setting the Time State key given
# by the mute_key function to true. What 'mute' means must be implemented by the
# given block; this function merely manages the muted state and informs the
# block of it. The arguments to the block differ from a normal live_loop. It may
# take 1 or 2 arguments:
# - first argument: a boolean representing whether the live_loop is muted.
# - second argument: the normal argument for a live_loop (optional)
# Note that muting is not instantaneous. The live_loop block is only made aware
# of muting the next time it executes, via its first argument. This way, muting
# will happen only between cycles of a loop, not in the middle of one.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def mutable_live_loop(loop_name, start_muted: false, **kwargs, &block)
  raise "Block must take 1 or 2 arguments" if block.arity == 0 || block.arity > 2

  key = mute_key(loop_name)

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

def use_cc_control_defaults(port: nil, channel: nil)
  ExtApi.set(:__cc_control_defaults, { port: port, channel: channel })
end

def __resolve_cc_port_and_channel(port, channel)
  # TODO: it would be good to fall back to defaults here, but it's a little
  # tricky - we do need actual port and channel strings so we can construct
  # the name of the control_change event we want to sync to.
  defaults = ExtApi.get(:__cc_control_defaults) || {}
  port = defaults[:port] || "*" if port.nil?
  channel = defaults[:channel] || "*" if channel.nil?
  [port, channel]
end

# Starts a new live_loop that can be muted by a MIDI CC message with the given
# CC number. A value of 0 for the CC will mute, and any other value will unmute.
# What 'mute' means must be implemented by the given block; this function merely
# manages the muted state and informs the block of it. The arguments to the
# block are as described in mutable_live_loop.
# Note that unlike usual MIDI port/channel arguments, these must be single
# strings that refer to either a single port/channel, or '*' as a wildcard.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def cc_mutable_live_loop(loop_name, cc:, port: nil, channel: nil, start_muted: false, **kwargs, &block)
  port, channel = __resolve_cc_port_and_channel(port, channel)

  cc_watcher_loop_name = :"__#{loop_name}_cc_mute_watcher"
  ExtApi.live_loop(cc_watcher_loop_name) do
    ExtApi.use_real_time

    # TODO: could support arrays of ports/channels by constructing {x,y,z}-style
    # strings for the path here.
    incoming_cc, cc_val = ExtApi.sync("/midi:#{port}:#{channel}/control_change")
    if incoming_cc == cc
      muted = cc_val == 0
      ExtApi.puts("[cc mute control] CC #{cc} = #{cc_val} -> #{muted ? '' : 'un'}muting live loop #{loop_name}")
      mute_live_loop(loop_name, muted)
    end
  end

  # Only send a CC for the start_muted value if this is a fresh definition of
  # the loop (i.e., not a restart of the same sketch).
  unless LiveLoopTracker.live_loop_is_running(loop_name)
    default_cc_val = start_muted ? 0 : 127
    ExtApi.puts "[cc mute control] sending default CC #{cc} value #{default_cc_val} for live loop #{loop_name}"
    ExtApi.midi_cc(cc, default_cc_val, port: port, channel: channel)
  end

  mutable_live_loop(loop_name, start_muted: start_muted, **kwargs, &block)
end

# Starts a new live_loop that can be muted by setting the Time State key given
# by the mute_key function to true. The live_loop is wrapped in a level effect,
# which will have its amp set to 0 when the live_loop is muted. Thus the block
# itself doesn't need to have any logic related to muting; whatever sound it
# creates will simply be silenced when it is muted. The arguments to the block
# are as described in mutable_live_loop.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def fx_mutable_live_loop(loop_name, start_muted: false, unmuted_amp: 1, amp_slide: 0, **kwargs, &block)
  raise "Block must take 1 or 2 arguments" if block.arity == 0 || block.arity > 2

  ExtApi.with_fx(:level, amp: start_muted ? 0 : unmuted_amp, amp_slide: amp_slide) do |level_fx|
    mutable_live_loop(loop_name, start_muted: start_muted, **kwargs) do |muted, arg|
      ExtApi.control(level_fx, amp: muted ? 0 : unmuted_amp)

      if block.arity == 2
        block.call(muted, arg)
      else
        block.call(muted)
      end
    end
  end
end
