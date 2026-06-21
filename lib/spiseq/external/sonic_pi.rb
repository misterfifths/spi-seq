# frozen_string_literal: true

# All methods needed from Sonic Pi should be imported explicitly here. The goal
# is to precisely track what methods we use, for two reasons:
# 1. We'd like to have as little dependence on Sonic Pi as possible, so this
#    module serves as sort of a to-do list for what spi-seq needs from the
#    external environment.
# 2. It allows us to easily account for what we need to mock in tests.
#
# There should be no bare calls to the SonicPi module outside of submodules of
# External; all methods should be grouped together in related chunks and placed
# in their own submodule of External (see, e.g., MIDI). Ideally there would be
# no calls to `in_sonic_pi?` outside of those modules either - all such
# switching should be isolated.
#
# There is an escape hatch intended solely for tests that need to make direct
# calls to non-imported methods: spi_call.
#-

module SpiSeq; module External
  module SonicPi
    extend self

    private def ensure_inited
      return if @tried_init
      @tried_init = true

      # Other extensions seem to get away with just calling Sonic Pi methods
      # without any preamble, but I've never been able to get that to work
      # from a `require`d file. Unfortunately it's pretty tricky to get
      # ahold of the context in which user code runs. This is the best thing
      # I've come up with.
      #
      # See server/ruby/bin/spider-server.rb in Sonic Pi. User code is
      # eval'd in an instance of a dynamic class named SonicPiLang. There
      # should be only one instance of it, so let's hackily try to find it.

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
      # Output: the IO module, expanded in SpiSeq::Log
      :puts,

      # Randomness: the Random module, expanded in SpiSeq::Random
      :rand,

      # Internal synth playback: the Synth module
      :play, :kill,

      # MIDI: the MIDI module
      :midi, :midi_note_on, :midi_note_off,
      :midi_cc,
      :midi_start, :midi_stop,
      :midi_all_notes_off, :midi_sound_off,
      :midi_clock_beat,
      :current_midi_defaults,

      # Threading, timing, and synchronization: the Sync module
      :current_bpm, :with_bpm_mul,
      :vt, :sleep,
      :with_real_time,
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

    # Make a direct call to a method on the Sonic Pi context. Only for use
    # by tests, to call methods that would not otherwise be exposed.
    def spi_call(method, *args, **kwargs, &block)
      ensure_inited
      raise RuntimeError, "not in Sonic Pi" if @spi.nil?
      @spi.send(method, *args, **kwargs, &block)
    end
  end

  module_function def in_sonic_pi?
    SonicPi.in_sonic_pi?
  end
end; end
