# The goal here is to keep track of direct calls into SonicPi's library, with
# the long-term plan of allowing (at least some of) the code to run outside of
# that environment.
# For now, there are direct calls to ExtApi scattered around the code. A medium-
# term goal is to move things out of ExtApi into their own higher-level modules
# which can individually call into Sonic Pi, or provide some other
# implementation. See the example of NoteUtils, which requires this module for
# the globals it sets, then uses $__SPI directly to provide an implementation of
# note normalization.

begin
  # FIXME: This is an abject sin, but I can't figure out a good way to reliably
  # get a handle on the Sonic Pi namespace from inside something that's
  # `require`d. The `sp` local is from here:
  # https://github.com/sonic-pi-net/sonic-pi/blob/916d4ea040871756b069b8d7c0e1b21fd6656fa9/app/server/ruby/bin/spider-server.rb#L304
  $__SPI = TOPLEVEL_BINDING.local_variable_get(:sp)
  $__IN_SPI = true
rescue NameError
  $__IN_SPI = false
end


$__SPI_FORWARDS = [
  # General helpers
  :puts,
  :rand, :rand_i, :choose, :one_in,
  :quantise, :spread,

  # Music theory
  :scale, :degree,

  # Internal synth playback & effects
  :play, :kill,
  :with_fx, :control, :set_mixer_control!,

  # MIDI
  :midi, :midi_cc, :midi_pc, :midi_sysex, :midi_start, :midi_stop,
  :midi_note_on, :midi_note_off, :midi_all_notes_off, :midi_sound_off,
  :midi_clock_beat,

  # Timestate and live loops
  :live_loop, :in_thread, :sleep,
  :vt,
  :time_warp,
  :use_real_time, :with_real_time, :with_bpm_mul,
  :get, :set,
  :cue, :sync
]


if $__IN_SPI
  require 'forwardable'

  module ExtApi
    class << self
      extend Forwardable

      def_delegators :$__SPI, *$__SPI_FORWARDS
    end
  end
else
  module ExtApi
    # let these raise for now
  end
end
