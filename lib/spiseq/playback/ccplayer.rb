# frozen_string_literal: true

require_relative "playerbase"
require_relative "../external/midi"
require_relative "../external/sync"
require_relative "../internal/log"
require_relative "../tracks/cctrack"

module SpiSeq; module Playback
  # A CCPlayer plays a {Tracks::CCTrack} by sending its {CCStep}s' CC messages
  # over MIDI.
  #
  # Generally you will not make instances of CCPlayer directly, and instead use
  # {track_live_loop}, which will create and manage a CCPlayer for you.
  #
  # In the unlikely scenario that you want to manually drive a CCPlayer, see the
  # {PlayerBase} documentation for details.
  class CCPlayer < PlayerBase
    # The MIDI channel to use when this player sends events.
    # @return [Integer, String, nil]
    attr_reader :channel

    # The MIDI port to use when this player sends events.
    # @return [String, nil]
    attr_reader :port

    # Constructs a Player.
    #
    # @param track [Tracks::CCTrack] The initial value for {#track}.
    # @param channel [Integer, String, nil] The MIDI channel to use during
    #   playback. If nil, falls back to the global default set by Sonic Pi's
    #   `use_midi_defaults`, or to all channels (i.e. "*") if that was not set.
    # @param port [String, nil] The MIDI device to use. If nil, falls back in
    #   the same manner as `channel`.
    # @param debug [Boolean] If true, the player will log detailed information
    #   about its state during playback.
    def initialize(track, channel: nil, port: nil, debug: false)
      @channel = channel
      @port = port
      @midi_spi_kwargs = { channel:, port: }
      @midi_spi_kwargs.compact!

      super(track, debug:)
    end


    protected

    def accum_should_trigger?(step)
      step.accum_should_trigger?(cycle: @cycle, fill: @fill)
    end

    def step_should_trigger?(step)
      step.should_trigger?(cycle: @cycle, fill: @fill)
    end

    def play_steps(steps)
      # Unlike in Player, there's no need to do a deduplication pass on these
      # steps because that will already have happened via CCTrack's `gridify`,
      # and accumulation effects the CC value, not the number.

      step_debug_strings = []

      steps.each do |step|
        effective_val = step.value + accum_delta(step)
        External::MIDI.midi_cc(step.cc, effective_val, **@midi_spi_kwargs)

        next unless @debug
        debug_str = step.repr(short: true, safe: true)
        debug_str += " -> #{effective_val}" unless effective_val == step.value
        step_debug_strings << debug_str
      end

      if @debug
        Internal::Log.log("@ t=#{External::Sync.vt} slot=#{slot_idx} cycle=#{@cycle} fill=#{@fill}", "ccplayer")
        Internal::Log.log("new steps: [#{step_debug_strings.join(', ')}]", "ccplayer")
      end
    end
  end
end; end
