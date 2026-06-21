# frozen_string_literal: true

require "forwardable"
require_relative "sonic_pi"

module SpiSeq; module External; module MIDI
  extend Forwardable
  extend self

  def_delegators "SpiSeq::External::SonicPi",
    :midi, :midi_note_on, :midi_note_off,
    :midi_cc,
    :midi_start, :midi_stop,
    :midi_all_notes_off, :midi_sound_off,
    :midi_clock_beat,
    :current_midi_defaults
end; end; end
