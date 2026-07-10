# frozen_string_literal: true

require_relative "lifecycle"
require_relative "../external/midi"
require_relative "../external/sync"
require_relative "../internal/midi"
require_relative "../internal/utils"

module SpiSeq; module Utils; module MIDI
  # @private
  module State
    @cc_control_defaults = {}
    class << self
      attr_accessor :cc_control_defaults
    end
  end
  private_constant :State


  # @!group Default settings

  # Set global default MIDI parameters to use when watching for incoming CC
  # messages. Such events are used to control various features, such as muting
  # live loops (e.g. those made from {LiveLoops.cc_mutable_live_loop} and
  # {Playback.track_live_loop}), toggling fill mode in `track_live_loop`, and
  # controlling recording in {Tracks::Track.record}.
  # @param channel [Integer, String, nil] The default MIDI channel to watch for
  #   CC events. If nil, defaults to all channels (i.e. "*").
  # @param port [String, nil] The MIDI device to watch for CC events. If nil,
  #   also falls back to "*".
  # @return [void]
  # @see current_cc_control_defaults
  module_function def use_cc_control_defaults(port: nil, channel: nil)
    defaults = { port: port, channel: channel }
    defaults.compact!
    State.cc_control_defaults = defaults.freeze
  end

  # Returns the current CC control defaults as set by {use_cc_control_defaults},
  # or an empty hash if no defaults have been set.
  # @return [Hash{Symbol => Object}]
  module_function def current_cc_control_defaults
    State.cc_control_defaults
  end


  # @!group MIDI utilities

  # Starts a `live_loop` named `loop_name` that sends MIDI clock beats for the
  # global BPM.
  # @param loop_name [Symbol] The name for the live loop.
  # @param send_start [Boolean] If true, a MIDI start message will be sent on
  #   the first iteration of the live loop, after the first clock pulse.
  # @param send_stop [Boolean] If true, a MIDI stop message will be sent on the
  #   first iteration of the live loop, before the first clock pulse.
  # @param port [String, nil] The MIDI port on which to send the clock signal,
  #   or "*" to send to all ports. If nil, falls back to the global default set
  #   by Sonic Pi's `use_midi_defaults`, or to all channels if that was not set.
  # @param start_port [String, nil] The MIDI port on which to send the start and
  #   stop messages, if `send_start` or `send_stop` is true. Falls back in the
  #   same manner as `port`.
  # @param start_channel [Integer, String, nil] The MIDI channel on which to
  #   send the start and stop messages, if `send_start` or `send_stop` is true.
  #   Falls back in the same manner as `port`.
  # @return [void]
  module_function def midi_clock_live_loop(loop_name = :midi_clock, send_start: false, send_stop: true, port: nil, start_port: nil, start_channel: nil)
    beat_kwargs = port.nil? ? {} : { port: port }
    start_stop_kwargs = { port: start_port, channel: start_channel }
    start_stop_kwargs.compact!

    External::Sync.live_loop loop_name, init: false do |inited|
      External::MIDI.midi_stop(**start_stop_kwargs) if !inited && send_stop

      External::MIDI.midi_clock_beat(**beat_kwargs)
      External::Sync.sleep 1

      External::MIDI.midi_start(**start_stop_kwargs) if !inited && send_start

      true
    end
  end

  # Starts a `live_loop` that listens for MIDI CC events. The provided block is
  # called whenever any CC message is received on the given device(s).
  #
  # @param loop_name [Symbol] The name for the live loop.
  # @param channel [Integer, String, nil] The MIDI channel to watch for CC
  #   messages. If nil, falls back to the global default set by
  #   {use_cc_control_defaults}, or to all channels (i.e. "*") if that was not
  #   set.
  # @param port [String, nil] The MIDI device to monitor. If nil, falls back in
  #   the same manner as `channel`.
  # @yieldparam cc_num [Integer] The CC number (0 - 127) of a received message.
  # @yieldparam cc_val [Integer] (optional) The value for the CC event (0 -
  #   127).
  # @return [void]
  module_function def cc_watcher_live_loop(loop_name, port: nil, channel: nil, &block)
    raise ArgumentError, "block must take 1 - 2 arguments" if block.arity == 0 || block.arity > 2

    port, channel = Internal::MIDI.resolve_cc_port_and_channel(port, channel)
    cue_path = "/midi:#{port}:#{channel}/control_change"

    External::Sync.live_loop loop_name do
      External::Sync.with_real_time do
        cc, val = External::Sync.sync(cue_path)
        Internal::Utils.call_varargs(block, cc, val)
      end
    end
  end

  # Tries very hard to silence a MIDI device.
  #
  # Some synths do not respond well to MIDI all note off or sound off messages.
  # This function sends a MIDI stop, all notes off, sound off, and individual
  # note offs for every MIDI note.
  #
  # You can call this function with either `port` and/or `channel` kwargs, or a
  # number of hashes of the same, in which case all provided devices will be
  # stopped. E.g.:
  #   midi_panic(port: "my_device", channel: 7)  # stops one device
  #   midi_panic({ channel: 2 }, { port: "another", channel: 5 })  # stops 2
  #
  # If no arguments are provided, or a port or channel is unspecified in any
  # circumstance, the default Sonic Pi target from `use_midi_defaults` is used.
  #
  # @param ports_and_channels [Array<Hash>] An number of hashes specifying MIDI
  #   ports and/or channels to silence. Mutually exclusive with the `port` and
  #   `channel` arguments.
  # @param port [String, nil] The MIDI port to silence. Mutually exclusive with
  #   the positional hashes.
  # @param channel [Integer, String, nil] The MIDI channel to silence. Mutually
  #   exclusive with the positional hashes.
  # @return [void]
  module_function def midi_panic(*ports_and_channels, port: nil, channel: nil)
    panic = lambda do |port: nil, channel: nil|
      midi_kwargs = { port: port, channel: channel }
      midi_kwargs.compact!

      External::Sync.with_real_time do
        External::MIDI.midi_stop(**midi_kwargs)
        External::MIDI.midi_all_notes_off(**midi_kwargs)
        External::MIDI.midi_sound_off(**midi_kwargs)
        0.upto(127) { |n| External::MIDI.midi_note_off(n, **midi_kwargs) }
      end
    end

    if port.nil? && channel.nil?
      if ports_and_channels.empty?
        panic.call
      else
        ports_and_channels.each { |h| panic.call(**h) }
      end
    else
      raise ArgumentError, "positional and keyword arguments are mutually exclusive" unless ports_and_channels.empty?
      panic.call(port: port, channel: channel)
    end
  end

  # Registers a hook with {Lifecycle.on_stop} that will call {midi_panic} when
  # playback in Sonic Pi is stopped or when the application exits.
  #
  # `hook_name` is used as the `name` passed to `on_stop`. If you need more than
  # one hook, you must give them each different `hook_name`s; calling this
  # function a second time with the same name will remove the previous hook with
  # that name.
  #
  # Takes the same arguments as {midi_panic}, with the addition of `hook_name`.
  #
  # `midi_panic` will *not* be called if a Sonic Pi sketch exits gracefully
  # (e.g. if it has no `live_loops` or they all stop). It is only executed when
  # hitting the stop button or quitting the app.
  #
  # @param (see #midi_panic)
  # @param hook_name [Symbol] The name of the stop hook. See
  #   {Lifecycle.on_stop}.
  # @return [void]
  module_function def midi_panic_on_stop(*ports_and_channels, hook_name: :midi_panic, port: nil, channel: nil)
    Lifecycle.on_stop(hook_name) do
      midi_panic(*ports_and_channels, port: port, channel: channel)
    end
  end
end; end; end
