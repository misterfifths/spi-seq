# frozen_string_literal: true

# The goal here is to keep track of direct calls into SonicPi's library, with
# the long-term plan of allowing (at least some of) the code to run outside of
# that environment.
# For now, there are direct calls to ExtApi scattered around the code. A medium-
# term goal is to move things out of ExtApi into their own higher-level modules
# which can individually call into Sonic Pi, or provide some other
# implementation.

# For the life of me, I cannot figure out a good way to get a reference to the
# context that Sonic Pi code executes in when trying to do so from a required
# file. Forcing a call to something like this is the best I've come up with.
# This method must be global (otherwise `self` will evaluate to the module that
# contains it).
def init_spi_seq
  method(:live_loop)  # Is this Sonic Pi?
  ExtApi.instance_variable_set(:@spi, self)
rescue NameError
  ExtApi.instance_variable_set(:@spi, nil)
end

module ExtApi
  class << self
    [
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
    ].each do |fwd|
      define_method(fwd) do |*args, **kwargs, &block|
        m = @spi.nil? ? ExtApiStubs.method(fwd) : @spi.method(fwd)
        m.call(*args, **kwargs, &block)
      end
    end
  end
end

module ExtApiStubs
  class << self
    def puts(s)
      Kernel.puts(s)
    end

    def rand(max_or_range = 1)
      # Sonic Pi's is float-oriented
      max_or_range = 0..max_or_range if max_or_range.is_a?(Numeric)
      max_or_range.min + Kernel.rand * max_or_range.max
    end

    def rand_i(max_or_range = 2)
      return 0 if max_or_range == 0
      Kernel.rand(max_or_range)
    end

    def choose(list = nil)
      return ->(l) { l.sample } if list.nil?
      list.sample
    end

    def one_in(n)
      return false if n == 0
      Kernel.rand < (1 / n.to_f)
    end

    def quantise(n, step)
      (n.to_f / step).round * step
    end

    def get(key = nil)
      @timespace_vals ||= {}

      # This behavior is kind of undocumented, but shows up in the examples.
      return ->(k) { @timespace_vals[k] } if key.nil?

      @timespace_vals[key]
    end

    def set(key, val)
      @timespace_vals ||= {}
      @timespace_vals[key] = val
    end
  end
end
