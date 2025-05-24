# frozen_string_literal: true

require_relative "cctrack"
require_relative "extapi"
require_relative "playerbase"


class CCPlayer < PlayerBase
  attr_reader :channel, :port


  def initialize(track, channel: nil, port: nil, debug: false)
    @channel = channel
    @port = port
    @midi_spi_kwargs = {}
    @midi_spi_kwargs[:channel] = channel unless channel.nil?
    @midi_spi_kwargs[:port] = port unless port.nil?

    super(track, debug: debug)
  end


  protected

  def step_accum_should_trigger?(step, _slot_idx)
    step.accum_should_trigger?(@cycle, @fill, nil, [])
  end

  def play_slot(i)
    steps = @track.grid[i % @track.length].filter do |step|
      step.should_trigger?(@cycle, @fill, nil, [])
    end

    # Note that, unlike in Player, there's no need to do a deduplication pass on
    # these steps because that will already have happened via CCTrack's
    # `gridify`, and accumulation effects the CC value, not the number.

    step_debug_strings = []

    steps.each do |step|
      apply_accum(step, i)

      effective_val = step.value + accum_delta_for_step(step, i)
      ExtApi.midi_cc(step.cc, effective_val, **@midi_spi_kwargs)

      debug_str = step.repr
      debug_str += " -> #{effective_val}" unless effective_val == step.value
      step_debug_strings << debug_str
    end

    if @debug
      ExtApi.puts "@ slot=#{i} cycle=#{@cycle} fill=#{@fill}"
      ExtApi.puts "new steps: [#{step_debug_strings.join(', ')}]"
    end
  end
end
