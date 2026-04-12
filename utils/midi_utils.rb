# frozen_string_literal: true

require_relative "../extapi"

# Start a live_loop named loop_name that sends MIDI clock beats for the global
# BPM. Sends a MIDI start message on the first iteration if send_start is true.
# Note that the channel argument is only relevant if send_start or send_start is
# true; clock messages are not per-channel.
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

# Given values for a MIDI port and channel, returns an array [port, channel]
# either of which is either the given value if it is not nil, the default set
# via use_cc_control_defaults, or the wildcard "*" if no defaults are set, in
# that order.
def __resolve_cc_port_and_channel(port, channel)
  # TODO: it would be good to fall back to defaults here, but it's a little
  # tricky - we do need actual port and channel strings so we can construct
  # the name of the control_change event we want to sync to.
  defaults = ExtApi.get(:__cc_control_defaults) || {}
  port = defaults[:port] || "*" if port.nil?
  channel = defaults[:channel] || "*" if channel.nil?
  [port, channel]
end

# Resolves a MIDI port and channel in the same manner as
# __resolve_cc_port_and_channel, except it considers the values set by Sonic
# Pi's use_midi_defaults instead of use_cc_control_defaults.
def __resolve_midi_port_and_channel(port, channel)
  defaults = ExtApi.current_midi_defaults || {}
  port = defaults[:port] || "*" if port.nil?
  channel = defaults[:channel] || "*" if channel.nil?
  [port, channel]
end

# Starts a live loop with the given name that listens for MIDI CC events on the
# a MIDI port and channel, either of which may be a wildcard. If either port or
# channel is omitted or nil, the defaults set by use_cc_control_defaults are
# used, or a wildcard if there are no defaults.
#
# The provided block is called whenever a CC message is received. The block must
# take 1 or 2 arguments. The first is the number of the CC and the second, if
# the block takes it, is the value for that CC (0 - 127).
def cc_watcher_live_loop(loop_name, port: nil, channel: nil, &block)
  raise 'block must take 1 - 2 arguments' if block.arity == 0 || block.arity > 2

  port, channel = __resolve_cc_port_and_channel(port, channel)
  cue_path = "/midi:#{port}:#{channel}/control_change"

  ExtApi.live_loop loop_name do
    ExtApi.use_real_time

    cc, val = ExtApi.sync(cue_path)
    block.call([cc, val].take(block.arity))
  end
end

# Some synths do not respond well to MIDI all note off or sound off messages.
# This function sends a MIDI stop, all notes off, sound off, and individual note
# offs for every MIDI note on the given port/channel. Messages are sent in real
# time.
# You can call this function with either `port` and/or `channel` kwargs, or a
# number of hashes of the same, in which case all provided devices will be
# stopped. E.g.:
#     midi_uber_stop(port: "my_device", channel: 7)  # stops one device
#     midi_uber_stop({ channel: 2 }, { port: "another", channel: 5 })  # stops 2
def midi_uber_stop(*args, **kwargs)
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
