# frozen_string_literal: true

require_relative "../external/midi"
require_relative "../utils/midi"

module SpiSeq; module Internal; module MIDI
  # Given values for a MIDI port and channel, returns an array [port, channel]
  # either of which is either the given value if it is not nil, the default
  # set via use_cc_control_defaults, or the wildcard "*" if no defaults are
  # set, in that order.
  module_function def resolve_cc_port_and_channel(port, channel)
    # TODO: it would be good to fall back to defaults here, but it's a little
    # tricky - we do need actual port and channel strings so we can construct
    # the name of the control_change event we want to sync to.
    defaults = SpiSeq::Utils::MIDI.current_cc_control_defaults
    port = defaults[:port] || "*" if port.nil?
    channel = defaults[:channel] || "*" if channel.nil?
    [port, channel]
  end

  # Resolves a MIDI port and channel in the same manner as
  # resolve_cc_port_and_channel, except it considers the values set by Sonic
  # Pi's use_midi_defaults instead of use_cc_control_defaults.
  module_function def resolve_port_and_channel(port, channel)
    defaults = External::MIDI.current_midi_defaults || {}
    port = defaults[:port] || "*" if port.nil?
    channel = defaults[:channel] || "*" if channel.nil?
    [port, channel]
  end
end; end; end
