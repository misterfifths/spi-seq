# frozen_string_literal: true

require_relative "utils/misc_utils"

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
  raise RuntimeError, "init_spi_seq must be called from the global scope" unless is_a?(SonicPi::Runtime)
  ExtApi.instance_variable_set(:@spi, self)
rescue NameError
  ExtApi.instance_variable_set(:@spi, nil)
end

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
      :with_midi_logging,

      # BPM
      :current_bpm, :with_bpm_mul,

      # Timing
      :vt, :time_warp,
      :sleep,
      :use_real_time, :with_real_time,

      # Timestate, threading, synchronization
      :live_loop, :in_thread,
      :get, :set,
      :cue, :sync,
      :get_event  # undocumented; see TrackRecorder for some notes
    ].each do |fwd|
      define_method(fwd) do |*args, **kwargs, &block|
        m = @spi.nil? ? ExtApiStubs.method(fwd) : @spi.method(fwd)
        m.call(*args, **kwargs, &block)
      end
    end

    def in_sonic_pi?
      !@spi.nil?
    end

    begin
      Object.const_get("SonicPi::Core::SPVector")

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
    rescue NameError
      def enumerable?(e)
        e.is_a?(Enumerable)
      end
    end
  end
end

begin
  Object.const_get("SonicPi::RuntimeMethods")

  # TODO: This is a sin, but is the only way I find to catch hitting the stop
  # button (or quitting) Sonic Pi. Trying to catch ThreadExit in a Sonic Pi
  # thread doesn't work for whatever reason.
  # See runtime.rb in the Sonic Pi source for what we're overriding here.
  # https://github.com/sonic-pi-net/sonic-pi/blob/e3e305164d9b5c4e29caceed9fb60666fc7cbbb1/app/server/ruby/lib/sonicpi/runtime.rb#L549
  module SonicPi
    module RuntimeMethods
      alias __orig_stop_jobs __stop_jobs
      def __stop_jobs
        __orig_stop_jobs

        if __any_stop_hooks?
          __info("Running stop hooks...")
          # We need to hop into a Sonic Pi thread context so its builtins will
          # work. __in_thread seems preferable but I couldn't get it to work,
          # so __spider_eval it is. It does seem to run the code in a relatively
          # fresh context though, since it's not a child thread of the sketch.
          # Global settings like `use_midi_logging` are lost.
          __clear_stop_hook_event
          __spider_eval("__run_stop_hooks")
          unless __wait_for_stop_hooks(timeout: 1)
            __info("Stop hooks timed out! Killing them...")
            __orig_stop_jobs
          end
        end
      end
    end
  end
rescue NameError  # rubocop:disable Lint/SuppressedException
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

def log(msg, channel = "spi-seq")
  ExtApi.puts("[#{channel}] #{msg}")
end

def warn(msg, channel = "spi-seq")
  log("warning: #{msg}", channel)
end
