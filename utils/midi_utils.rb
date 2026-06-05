# frozen_string_literal: true

require_relative "../extapi"
require_relative "../utils/internal_utils"

# @!group MIDI utilities

# @private
module SpiSeq
  module MIDI
    # Given values for a MIDI port and channel, returns an array [port, channel]
    # either of which is either the given value if it is not nil, the default
    # set via use_cc_control_defaults, or the wildcard "*" if no defaults are
    # set, in that order.
    def self.resolve_cc_port_and_channel(port, channel)
      # TODO: it would be good to fall back to defaults here, but it's a little
      # tricky - we do need actual port and channel strings so we can construct
      # the name of the control_change event we want to sync to.
      defaults = current_cc_control_defaults
      port = defaults[:port] || "*" if port.nil?
      channel = defaults[:channel] || "*" if channel.nil?
      [port, channel]
    end

    # Resolves a MIDI port and channel in the same manner as
    # resolve_cc_port_and_channel, except it considers the values set by Sonic
    # Pi's use_midi_defaults instead of use_cc_control_defaults.
    def self.resolve_port_and_channel(port, channel)
      defaults = ExtApi.current_midi_defaults || {}
      port = defaults[:port] || "*" if port.nil?
      channel = defaults[:channel] || "*" if channel.nil?
      [port, channel]
    end
  end
end

# Starts a `live_loop` named `loop_name` that sends MIDI clock beats for the
# global BPM.
# @param loop_name [Symbol] The name for the live loop.
# @param send_start [Boolean] If true, a MIDI start message will be sent on the
#   first iteration of the live loop, after the first clock pulse.
# @param send_stop [Boolean] If true, a MIDI stop message will be sent on the
#   first iteration of the live loop, before the first clock pulse.
# @param port [String, nil] The MIDI port on which to send the clock signal, or
#   "*" to send to all ports. If nil, falls back to the global default set by
#   Sonic Pi's `use_midi_defaults`, or to all channels if that was not set.
# @param start_port [String, nil] The MIDI port on which to send the start and
#   stop messages, if `send_start` or `send_stop` is true. Falls back in the
#   same manner as `port`.
# @param start_channel [Integer, String, nil] The MIDI channel on which to send
#   the start and stop messages, if `send_start` or `send_stop` is true. Falls
#   back in the same manner as `port`.
# @return [void]
def midi_clock_live_loop(loop_name = :midi_clock, send_start: false, send_stop: true, port: nil, start_port: nil, start_channel: nil)
  beat_kwargs = port.nil? ? {} : { port: port }

  start_stop_kwargs = {}
  start_stop_kwargs[:port] = start_port unless start_port.nil?
  start_stop_kwargs[:channel] = start_channel unless start_channel.nil?

  ExtApi.live_loop loop_name, init: false do |inited|
    ExtApi.midi_stop(**start_stop_kwargs) if !inited && send_stop

    ExtApi.midi_clock_beat(**beat_kwargs)
    ExtApi.sleep 1

    ExtApi.midi_start(**start_stop_kwargs) if !inited && send_start

    true
  end
end

# Starts a `live_loop` that listens for MIDI CC events. The provided block is
# called whenever any CC message is received on the given device(s).
#
# @param loop_name [Symbol] The name for the live loop.
# @param channel [Integer, String, nil] The MIDI channel to watch for CC
#   messages. If nil, falls back to the global default set by Sonic Pi's
#   `use_midi_defaults`, or to all channels (i.e. "*") if that was not set.
# @param port [String, nil] The MIDI device to monitor. If nil, falls back in
#   the same manner as `channel`.
# @yieldparam cc_num [Integer] The CC number (0 - 127) of a received message.
# @yieldparam cc_val [Integer] (optional) The value for the CC event (0 - 127).
# @return [void]
def cc_watcher_live_loop(loop_name, port: nil, channel: nil, &block)
  raise ArgumentError, "block must take 1 - 2 arguments" if block.arity == 0 || block.arity > 2

  port, channel = SpiSeq::MIDI.resolve_cc_port_and_channel(port, channel)
  cue_path = "/midi:#{port}:#{channel}/control_change"

  ExtApi.live_loop loop_name do
    ExtApi.with_real_time do
      cc, val = ExtApi.sync(cue_path)
      SpiSeq::Utils.call_varargs(block, cc, val)
    end
  end
end

# Tries very hard to silence a MIDI device.
#
# Some synths do not respond well to MIDI all note off or sound off messages.
# This function sends a MIDI stop, all notes off, sound off, and individual note
# offs for every MIDI note.
#
# You can call this function with either `port` and/or `channel` kwargs, or a
# number of hashes of the same, in which case all provided devices will be
# stopped. E.g.:
#   midi_panic(port: "my_device", channel: 7)  # stops one device
#   midi_panic({ channel: 2 }, { port: "another", channel: 5 })  # stops 2
# @return [void]
def midi_panic(*args, **kwargs)
  uber_stop = lambda do |port: nil, channel: nil|
    midi_kwargs = {}
    midi_kwargs[:port] = port unless port.nil?
    midi_kwargs[:channel] = channel unless channel.nil?

    ExtApi.with_real_time do
      ExtApi.midi_stop(**midi_kwargs)
      ExtApi.midi_all_notes_off(**midi_kwargs)
      ExtApi.midi_sound_off(**midi_kwargs)
      0.upto(127) { |n| ExtApi.midi_note_off(n, **midi_kwargs) }
    end
  end

  if kwargs.empty?
    args.each { |midi_hash| uber_stop.call(**midi_hash) }
  else
    uber_stop.call(**kwargs)
  end
end

alias midi_uber_stop midi_panic

# Registers a hook with {on_stop} that will call {midi_panic} when playback in
# Sonic Pi is stopped or when the application exits.
#
# `hook_name` is used as the `name` passed to {on_stop}. If you need more than
# one hook, you must give them each different `hook_name`s; calling this
# function a second time with the same name will remove the previous hook with
# that name.
#
# Takes the same arguments as {midi_panic}, with the addition of `hook_name`.
#
# `midi_panic` will *not* be called if a Sonic Pi sketch exits gracefully (e.g.
# if it has no `live_loops` or they all stop). It is only executed when hitting
# the stop button or quitting the app.
#
# @return [void]
def midi_panic_on_stop(*args, hook_name: :midi_panic, **kwargs)
  on_stop(hook_name) do
    midi_panic(*args, **kwargs)
  end
end
