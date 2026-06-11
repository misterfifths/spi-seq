# frozen_string_literal: true

# All direct calls to Sonic Pi functionality should go through delegating
# methods on ExtApi. The goal is to precisely track what methods we use, for two
# reasons:
# 1. We'd like to have as little dependence on Sonic Pi as possible, so this
#    module serves as sort of a to-do list for what spi-seq needs from the
#    external environment.
# 2. It allows an easy way to mock these methods (and to know which ones we need
#    to mock) for tests.

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
        instances = ObjectSpace.each_object(SonicPiLang).to_a
      rescue NameError
        # We're not in Sonic Pi.
        return
      end

      raise RuntimeError, "Didn't find exactly one instance of SonicPiLang. This is a spi-seq bug; please report it" unless instances.one?
      @spi = instances[0]
    end

    [
      # Output, wrapped in SpiSeq::Log
      :puts,

      # Randomness, wrapped in SpiSeq::Random
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
      :vt, :sleep,
      :with_real_time,

      # Threading and synchronization
      :live_loop,
      :in_thread, :at,
      :cue, :sync,
      :get_event  # undocumented; see trackrecorder.rb for some notes
    ].each do |fwd|
      define_method(fwd) do |*args, **kwargs, &block|
        spi_call(fwd, *args, **kwargs, &block)
      end
    end

    def in_sonic_pi?
      ensure_inited
      !@spi.nil?
    end

    # Make a direct call to a method on the Sonic Pi context. Only for use by
    # tests, to call methods that would not otherwise be exposed on ExtApi.
    def spi_call(method, *args, **kwargs, &block)
      ensure_inited
      raise RuntimeError, "not in Sonic Pi" if @spi.nil?
      @spi.send(method, *args, **kwargs, &block)
    end
  end
end
