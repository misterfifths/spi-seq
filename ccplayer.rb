# frozen_string_literal: true

require_relative "cctrack"
require_relative "extapi"
require_relative "playerbase"

# A CCPlayer plays a {CCTrack} by sending its {CCStep}s' CC messages over MIDI.
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
  # @param track [CCTrack] The initial value for {#track}.
  # @param channel [Integer, String, nil] The MIDI channel to use during
  #   playback. If nil, falls back to the global default set by Sonic Pi's
  #   `use_midi_defaults`, or to all channels (i.e. "*") if that was not set.
  # @param port [String, nil] The MIDI device to use. If nil, falls back in the
  #   same manner as `channel`.
  # @param debug [Boolean] If true, the player will log detailed information
  #   about its state during playback.
  def initialize(track, channel: nil, port: nil, debug: false)
    @channel = channel
    @port = port
    @midi_spi_kwargs = {}
    @midi_spi_kwargs[:channel] = channel unless channel.nil?
    @midi_spi_kwargs[:port] = port unless port.nil?

    super(track, debug: debug)
  end


  protected

  def accum_should_trigger?(step)
    step.accum_should_trigger?(@cycle, @fill, nil, [])
  end

  def triggering_steps_in_slot
    current_steps.filter do |step|
      step.should_trigger?(@cycle, @fill, nil, [])
    end
  end

  def play_steps(steps)
    # Note that, unlike in Player, there's no need to do a deduplication pass on
    # these steps because that will already have happened via CCTrack's
    # `gridify`, and accumulation effects the CC value, not the number.

    step_debug_strings = []

    steps.each do |step|
      effective_val = step.value + accum_delta(step)
      ExtApi.midi_cc(step.cc, effective_val, **@midi_spi_kwargs)

      next unless @debug
      debug_str = step.repr
      debug_str += " -> #{effective_val}" unless effective_val == step.value
      step_debug_strings << debug_str
    end

    if @debug
      log("@ slot=#{slot_idx} cycle=#{@cycle} fill=#{@fill}", "ccplayer")
      log("new steps: [#{step_debug_strings.join(', ')}]", "ccplayer")
    end
  end
end
