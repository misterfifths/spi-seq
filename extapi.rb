# frozen_string_literal: true

# The goal here is to keep track of direct calls into SonicPi's library, with
# the long-term plan of allowing (at least some of) the code to run outside of
# that environment.
# For now, there are direct calls to ExtApi scattered around the code. A medium-
# term goal is to move things out of ExtApi into their own higher-level modules
# which can individually call into Sonic Pi, or provide some other
# implementation.

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


if $__IN_SPI
  require 'forwardable'

  module ExtApi
    SPI_FORWARDS = [
      # General helpers
      :puts,
      :rand, :rand_i, :choose, :one_in,
      :quantise,

      # Music theory
      :scale, :degree,
      :spread,

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
    ].freeze

    class << self
      extend Forwardable
      def_delegators :$__SPI, *SPI_FORWARDS
    end
  end
else
  module ExtApi
    def self.puts(s)
      Kernel.puts(s)
    end

    def self.rand(max_or_range = 1)
      # Sonic Pi's is float-oriented
      max_or_range = 0..max_or_range if max_or_range.is_a?(Numeric)
      max_or_range.min + Kernel.rand * max_or_range.max
    end

    def self.rand_i(max_or_range = 2)
      Kernel.rand(max_or_range)
    end

    def self.choose(list = nil)
      return ->(l) { l.sample } if list.nil?
      list.sample
    end

    def self.one_in(n)
      return false if n == 0
      Kernel.rand < (1 / n.to_f)
    end

    def self.quantise(n, step)
      (n.to_f / step).round * step
    end

    def self.get(key = nil)
      @__timespace_vals ||= {}

      # This behavior is kind of undocumented, but shows up in the examples.
      return ->(k) { @__timespace_vals[k] } if key.nil?

      @__timespace_vals[key]
    end

    def self.set(key, val)
      @__timespace_vals ||= {}
      @__timespace_vals[key] = val
    end
  end
end
