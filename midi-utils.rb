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


# Controls an effect based on a MIDI value (0 - 127). Arguments are the MIDI
# value and the values of the array described in cc_fx_control_loop.
def __midi_fx_control(val, effect_key, param, val_range, quantum)
  return if effect_key.nil?

  effect = nil
  if effect_key == :global
    effect = :global
  else
    effect = $spi.get(effect_key)
  end

  return if effect.nil?

  val_range = 0..1 if val_range.nil?
  quantum = 0.01 if quantum.nil?

  val = val_range.min + (val_range.max - val_range.min) * (val / 127.0)
  val = $spi.quantise(val, quantum)
  # quantise might round past the edges of the range
  val = val_range.max if val > val_range.max
  val = val_range.min if val < val_range.min

  args = { param => val }

  $spi.puts "#{effect_key}: val=#{val} --> #{args}"
  if effect == :global
    $spi.set_mixer_control!(**args)
  else
    $spi.control(effect, **args)
  end
end


# Starts a live_loop named loop_name that watches for MIDI CC events on the
# given source and translates them to `control` calls for synths/effects in the
# Time State.
# Provide a map from a CC number to an array:
# [ fx time state key, fx parameter symbol, value range, quantum, default: ]
# The latter three values in each array are optional. Range defaults to 0..1 and
# quantum defaults to 0.1.
# When the given CC number is received, its value will be converted into the
# given range and quantized to quantum. That value will then be set with
# `control` for the given parameter on the given fx as retrieved from the
# Time State by its key.
# The special Time State key `:global` may be used to refer to the parameters
# of the global mixer. Those will be set with `set_mixer_control!`.
# If the `default` hash key is given, a CC message for the given value (which
# will be scaled to a MIDI value based on the value range) is sent the first
# time the loop executes. This can be useful to synchronize external MIDI
# devices with the starting value for the parameter.
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
      $spi.puts "[cc control] waiting on fx from the time state: #{needed_fx.to_a}"
      $spi.sleep(1) until needed_fx.none? { |key| $spi.get(key).nil? }
      $spi.puts "[cc control] got all fx!"

      cc_mappings.each do |cc, mapping|
        effect_key, _, val_range = mapping
        next if effect_key == :global
        val_range = 0..1 if val_range.nil? || !val_range.is_a?(Range)

        if mapping[-1].is_a? Hash
          kwargs = mapping.pop
          default = kwargs[:default]
          unless default.nil?
            midi_default = (default - val_range.min) / (val_range.max - val_range.min).to_f * 127.0
            midi_default = midi_default.round
            midi_default = 127 if midi_default > 127
            midi_default = 0 if midi_default < 0

            puts "[cc control] sending default CC #{cc} value #{default} --> midi #{midi_default}"
            midi_cc(cc, midi_default)
          end
        end
      end
    end

    # wait for a cc on the source
    cc, val = $spi.sync("/midi:#{midi_source}/control_change")
    effect_key, param, val_range, quantum = cc_mappings[cc]

    __midi_fx_control(val, effect_key, param, val_range, quantum)

    true
  end
end


# Control the given parameter of the given effect with polyphonic aftertouch.
# Arguments are as described in cc_fx_control_loop.
def aftertouch_fx_control_loop(effect_key, param, val_range=0..1, quantum=0.1, midi_source: "*")
  pressed_notes = []  # we're using this like a Set, but we want order

  # TODO: combine this into one live_loop with a broader glob that catches note events & aftertouch?

  $spi.live_loop :_midi_note_tracker do
    $spi.use_real_time

    event_glob = "/midi:#{midi_source}/note_{on,off}"

    note, _ = $spi.sync(event_glob)

    # get_event is undocumented. it gives the name of the event we just `sync`ed to
    on = $spi.get_event(event_glob).split_path[-1] == 'note_on'

    if on
      pressed_notes << note unless pressed_notes.include?(note)
    else
      pressed_notes.delete(note)
    end
  end

  $spi.live_loop :_aftertouch_fx_control do
    $spi.use_real_time

    $spi.puts "[aftertouch control] waiting on fx from the time state: #{effect_key}"
    $spi.sleep(1) while $spi.get(effect_key).nil?
    $spi.puts "[aftertouch control] got fx"

    note, vel = $spi.sync("/midi:#{midi_source}/aftertouch")

    # only care about changes on the oldest pressed note
    # the "vel != 0" is intended to not do a jarring cutoff when you lift your finger, but it's not great
    # TODO: all of this is not great
    if pressed_notes.find_index(note) == 0 && vel != 0
      __midi_fx_control(vel, effect_key, param, val_range, quantum)
    end
  end
end
