$spi ||= self

# Start a live_loop named loop_name that sends MIDI clock beats for the global
# BPM. Sends all notes off, stop, and start messages on the first iteration.
def midi_clock_live_loop(loop_name = :midi_clock)
  $spi.live_loop loop_name do
    if $spi.tick == 0
      # kill any residual notes. this doesn't seem to work for the microfreak :-(
      # $spi.midi_all_notes_off
      # $spi.midi_stop

      $spi.midi_start
    end

    $spi.midi_clock_beat
    $spi.sleep 1
  end
end


# Starts a live_loop named loop_name that watches for MIDI CC events on the
# given source and translates them to `control` calls for synths/effects in the
# Time State.
# Provide a map from a CC number to an array:
# [ fx time state key, fx parameter symbol, value range, quantum ]
# The latter two values in each array are optional. Range defaults to 0..1 and
# quantum defaults to 0.1.
# When the given CC number is received, its value will be converted into the
# given range and quantized to quantum. That value will then be set with
# `control` for the given parameter on the given fx as retrieved from the
# Time State by its key.
# The special Time State key `:global` may be used to refer to the parameters
# of the global mixer. Those will be set with `set_mixer_control!`.
# The loop will initially sleep until all needed fx keys exist in the Time
# State. CCs not in the given map will be ignored.
def cc_fx_control_loop(loop_name = :cc_fx_control, midi_source: "*", **cc_mappings)
  $spi.live_loop loop_name, init: false do |got_fx|
    $spi.use_real_time

    $spi.stop if cc_mappings.size == 0

    unless got_fx
      # first run? hang out until all the effect keys exist
      needed_fx = Set.new(cc_mappings.values) { |fx_info| fx_info[0] }
      needed_fx.delete(:global)
      $spi.puts "waiting on fx from the time state: #{needed_fx.to_a}"
      $spi.sleep(1) until needed_fx.none? { |key| $spi.get(key).nil? }
      $spi.puts "got all fx!"
    end

    # wait for a cc on the source
    cc, val = $spi.sync("/midi:#{midi_source}/control_change")
    effect_key, param, val_range, quantum = cc_mappings[cc]

    if effect_key.nil?
      effect = nil
    elsif effect_key == :global
      effect = :global
    else
      effect = $spi.get(effect_key)
    end

    unless effect.nil?
      val_range = 0..1 if val_range.nil?
      quantum = 0.01 if quantum.nil?

      val = val_range.min + (val_range.max - val_range.min) * (val / 127.0)
      val = $spi.quantise(val, quantum)
      # quantise might round past the edges of the range
      val = val_range.max if val > val_range.max
      val = val_range.min if val < val_range.min

      args = { param => val }

      $spi.puts "val=#{val} --> #{args}"
      if effect == :global
        $spi.set_mixer_control!(**args)
      else
        $spi.control(effect, **args)
      end
    end

    true
  end
end
