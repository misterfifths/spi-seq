# frozen_string_literal: true

# All direct calls to Sonic Pi functionality should go through delegating
# methods on ExtApi. The goal is to precisely track what methods we use, for two
# reasons:
# 1. We'd like to have as little dependence on Sonic Pi as possible, so this
#    module serves as sort of a to-do list for what spi-seq needs from the
#    external environment.
# 2. It allows an easy way to mock these methods (and to know which ones we need
#    to mock), both for tests and so that some portion of the code can run
#    outside of Sonic Pi.

# @private
module ExtApi
  class << self
    private def ensure_inited
      return if @tried_init
      @tried_init = true

      # Other extensions seem to get away with just calling Sonic Pi methods
      # without any preamble, but I've never been able to get that to work from
      # a `require`d file. Unfortunately it's pretty tricky to get ahold of the
      # context in which user code runs. This is the best thing I've come up
      # with.
      #
      # See server/ruby/bin/spider-server.rb in Sonic Pi. User code is eval'd
      # in an instance of a dynamic class named SonicPiLang. There should be
      # only one instance of it, so let's hackily try to find it.

      begin
        spi_ctx_cls = Object.const_get("SonicPiLang")
      rescue NameError
        # We're not in Sonic Pi.
        return
      end

      instances = ObjectSpace.each_object(spi_ctx_cls).to_a
      raise RuntimeError, "Didn't find exactly one instance of SonicPiLang. This is a spi-seq bug; please report it" unless instances.one?
      @spi = instances[0]
    end

    [
      # General helpers
      :puts,

      # Randomness. We could easily use builtins, but we want to tie into Sonic
      # Pi's seed functionality.
      :rand,

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
        ensure_inited
        m = @spi.nil? ? Stubs.method(fwd) : @spi.method(fwd)
        m.call(*args, **kwargs, &block)
      end
    end

    def in_sonic_pi?
      ensure_inited
      !@spi.nil?
    end

    # Make a direct call to a method on the Sonic Pi context. Only for use by
    # tests, to call methods that would not otherwise be exposed on ExtApi.
    def spi_call(method, *args, **kwargs, &block)
      raise RuntimeError, "not in Sonic Pi" unless in_sonic_pi?
      @spi.send(method, *args, **kwargs, &block)
    end
  end
end

# Implementations of some Sonic Pi methods that are both accurate to the
# original and useful for getting spi-seq code running outside of Sonic Pi.
# Various other methods are mocked in far less functional or niche ways for the
# tests - see tests/player_extapi_stubs.rb, for example. The delegator above
# will call these if we're not in Sonic Pi.
# @private
module ExtApi
  module Stubs
    def self.puts(s)
      Kernel.puts(s)
    end

    def self.rand(max_or_range = 1)
      # Sonic Pi's is float-oriented
      max_or_range = 0..max_or_range if max_or_range.is_a?(Numeric)
      max_or_range.min + Kernel.rand * max_or_range.max
    end

    def self.get(key = nil)
      @timespace_vals ||= {}

      # This behavior is kind of undocumented, but shows up in the examples.
      return ->(k) { @timespace_vals[k] } if key.nil?

      @timespace_vals[key]
    end

    def self.set(key, val)
      @timespace_vals ||= {}
      @timespace_vals[key] = val
    end
  end
end
