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

# @!group Initialization
# Initializes spi-seq. This must be called before attempting to use any other
# functionality. You must call this at the top level of a sketch; you cannot
# call it inside a function or from a module. It is safe to call it multiple
# times, e.g. when you re-run a sketch.
# @return [void]
def init_spi_seq
  raise RuntimeError, "init_spi_seq must be called from the global scope" unless is_a?(SonicPi::Runtime)
  ExtApi.instance_variable_set(:@spi, self)
rescue NameError
  ExtApi.instance_variable_set(:@spi, nil)
end
# @!endgroup

# @private
module ExtApi
  class << self
    [
      # General helpers
      :puts,

      # Randomness. These would be easy to replace with builtins, but we want to
      # tie into Sonic Pi's seed functionality.
      :rand, :rand_i, :choose, :one_in,

      # Internal synth playback
      :play, :kill,

      # MIDI
      :midi, :midi_note_on, :midi_note_off,
      :midi_cc,
      :midi_start, :midi_stop,
      :midi_all_notes_off, :midi_sound_off,
      :midi_clock_beat,
      :current_midi_defaults,

      # BPM
      :current_bpm, :with_bpm_mul,

      # Timing
      :vt, :at,
      :sleep,
      :use_real_time, :with_real_time,

      # Timestate, threading, synchronization
      :live_loop, :in_thread,
      :get, :set,
      :cue, :sync,
      :get_event  # undocumented; see trackrecorder.rb for some notes
    ].each do |fwd|
      define_method(fwd) do |*args, **kwargs, &block|
        m = @spi.nil? ? ExtApiStubs.method(fwd) : @spi.method(fwd)
        m.call(*args, **kwargs, &block)
      end
    end

    def in_sonic_pi?
      # We could check for the existence of a particular module like below, but
      # what we really mean here is: was init_spi_seq called from within Sonic
      # Pi?
      !@spi.nil?
    end

    if Object.const_defined?("SonicPi::Runtime")
      # 'Enumerable' resolves to SonicPi::RuntimeMethods::Enumerable from within
      # Sonic Pi, which e.g. Array does not have as a superclass. So we need to
      # use ::Enumerable to get the built-in class.
      # SPVector is the parent class of RingVector, from e.g. `ring` and
      # `chord`, and potentially other list types in SP. It unfortunately does
      # not derive from (either) Enumerable, so we need to check for it
      # manually. You must make sure to call `to_a` on SPVectors before calling
      # Enumerable methods on them!
      def enumerable?(e)
        e.is_a?(::Enumerable) || e.is_a?(SonicPi::Core::SPVector)
      end

      # Make a direct call to a method in the Sonic Pi context. Only for use by
      # tests, to call methods that would not otherwise be exposed on ExtApi.
      def spi_call(method, *args, **kwargs, &block)
        @spi.send(method, *args, **kwargs, &block)
      end
    else
      def enumerable?(e)
        e.is_a?(Enumerable)
      end
    end
  end
end

# Implementations of some Sonic Pi methods that are both accurate to the
# original and useful for getting spi-seq code running outside of Sonic Pi.
# Various other methods are mocked in far less functional or niche ways for the
# tests - see tests/player_extapi_stubs.rb, for example. The delegator above
# will call these if we're not in Sonic Pi.
# @private
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

# @private
def _log(msg, channel = "spi-seq")
  ExtApi.puts("[#{channel}] #{msg}")
end

# @private
def _warn(msg, channel = "spi-seq")
  _log("warning: #{msg}", channel)
end
