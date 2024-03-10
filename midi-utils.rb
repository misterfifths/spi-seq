$spi ||= self


# Start a live_loop named loop_name that sends MIDI clock beats for the global
# BPM. Sends a MIDI start message on the first iteration if send_start is true.
def midi_clock_live_loop(loop_name = :midi_clock, send_start: true, port: nil)
  beat_kwargs = port.nil? ? {} : { port: port }

  $spi.live_loop loop_name, init: true do |first_run|
    if first_run
      # kill any residual notes. this doesn't seem to work for the microfreak :-(
      # $spi.midi_all_notes_off
      # $spi.midi_stop
      $spi.midi_start if send_start
    end

    $spi.midi_clock_beat(**beat_kwargs)
    $spi.sleep 1

    false
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


def __send_cc_name_sysex(cc, name, port: nil)
  # Ad-hoc format parsed by a script in TouchOSC. sysex messages have to be
  # bookended by 0xf0 and 0xf7.
  bytes = [0xf0, "=".ord, cc, *name.bytes, 0xf7]

  kwargs = port.nil? ? {} : { port: port }
  $spi.midi_sysex(*bytes, **kwargs)
end


# Starts a live_loop named loop_name that watches for MIDI CC events and acts
# on them.
# Provide a map from a CC number to one of two types of array:
#
# MAPPING TYPE 1: AUTOMATIC EFFECT CONTROL
# [ fx time state key, fx parameter symbol, value range, quantum, default: ]
# This type of CC mapping automatically translates incoming CC events into
# `control` calls for effects in the type state.
# The latter three values in each array are optional. Range defaults to 0..1 and
# quantum defaults to 0.1.
# When the given CC number is received, its MIDI value will be converted into
# the given range and quantized to quantum. The result will then be set with
# `control` for the given parameter on the given fx as retrieved from the
# Time State by its key.
# The special Time State key `:global` may be used to refer to the parameters
# of the global mixer. Those will be set with `set_mixer_control!`.
# If the `default` hash key is given, a CC message for the given value (which
# will be scaled to a MIDI value based on the value range) is sent the first
# time the loop executes. This can be useful to synchronize external MIDI
# controllers with the starting value for the parameter.
#
# MAPPING TYPE 2: MANUAL CALLBACK
# [ name symbol, callback:, default: ]
# Type type of CC mapping calls the given callback with the value of the CC
# whenever one is received. `callback` must be a Proc or something that responds
# to `call`. It will be invoked with one argument, the value of the CC. If
# `default` is provided, it acts identically to type 1 mappings, except that it
# is not subject to a value range or quantum; it should be a verbatim MIDI
# value (0 - 127).
# The first element of the array in this case is solely used for formulating
# the name used in the sysex message; it can be whatever you wish.
#
# If send_name_sysex is true, a special MIDI sysex message with the name of the
# control and its CC number will be sent on sysex_name_port the first time the
# loop executes. If sysex_name_port is nil, the message will be sent on all
# ports.
# The loop will initially sleep until all needed fx keys exist in the Time
# State.
# Received CCs that are not in the given map will be ignored by this loop.
def cc_fx_control_loop(loop_name = :cc_fx_control, midi_source: "*", send_name_sysex: true, sysex_name_port: nil, **cc_mappings)
  return if cc_mappings.size == 0

  # time state keys for all effects we'll be controlling
  needed_fx = Set.new

  # all effect control mappings.
  # CC number => [fx time state key, parameter sym, value range, quantum]
  # any trailing hash is stripped from the values
  fx_mappings = Hash.new

  # all callback mappings.
  # CC number => callable
  callback_mappings = Hash.new

  # defaults & the name sysexes are handled in the first go-round of the
  # live_loop by iterating over the raw cc_mappings hash.

  # collate the mappings and gather needed effects keys
  cc_mappings.each do |cc, mapping|
    if mapping[-1].is_a?(Hash) and mapping[-1].has_key?(:callback)
      callback_mappings[cc] = mapping[-1][:callback]
    else
      needed_fx << mapping[0]
      cloned_mapping = mapping.clone
      cloned_mapping.pop if mapping[-1].is_a?(Hash)
      fx_mappings[cc] = cloned_mapping
    end
  end

  needed_fx.delete(:global)


  $spi.live_loop loop_name, init: false do |got_fx|
    $spi.use_real_time

    unless got_fx
      # first run? hang out until all the effect keys exist
      $spi.puts "[cc control] waiting on fx from the time state: #{needed_fx.to_a}"
      $spi.sleep(1) until needed_fx.none? { |key| $spi.get(key).nil? }
      $spi.puts "[cc control] got all fx!"

      # send out the sysex name messages & defaults for all mappings
      cc_mappings.each do |cc, mapping|
        effect_key, param, val_range = mapping

        # Send out the name of this control as a sysex
        if send_name_sysex
          pretty_name = effect_key.to_s.delete_suffix("_fx")
          pretty_name += "\n#{param.to_s}" if param.is_a?(Symbol)
          pretty_name.gsub!("_", " ")
          $spi.puts "[cc control] sending name '#{pretty_name}' for CC #{cc}"
          __send_cc_name_sysex(cc, pretty_name, port: sysex_name_port)
        end

        # TODO: support a default on :global effects by doing an initial
        # set_mixer_control?
        next if effect_key == :global

        # Compute the MIDI equivalent of the default, if one was given, and send
        # it out as a CC.
        # TODO: also set the default on the effect itself?
        if mapping[-1].is_a?(Hash)
          default = mapping[-1][:default]
          unless default.nil?
            val_range = 0..1 if val_range.nil? || !val_range.is_a?(Range)

            midi_default = (default - val_range.min) / (val_range.max - val_range.min).to_f * 127.0
            midi_default = midi_default.round
            midi_default = 127 if midi_default > 127
            midi_default = 0 if midi_default < 0

            $spi.puts "[cc control] sending default CC #{cc} value #{default} --> midi #{midi_default}"
            midi_cc(cc, midi_default)
          end
        end
      end
    end

    # wait for a cc on the source
    cc, val = $spi.sync("/midi:#{midi_source}/control_change")

    if fx_mappings.has_key?(cc)
      effect_key, param, val_range, quantum = fx_mappings[cc]
      __midi_fx_control(val, effect_key, param, val_range, quantum)
    elsif callback_mappings.has_key?(cc)
      lambda = callback_mappings[cc]
      lambda.call(val)
    end

    true
  end
end


# Control the given parameter of the given effect with polyphonic aftertouch.
# Arguments are as described in cc_fx_control_loop.
def aftertouch_fx_control_loop(effect_key, param, val_range=0..1, quantum=0.1, midi_source: "*")
  pressed_notes = []  # we're using this like a Set, but order is important

  $spi.live_loop :_aftertouch_fx_control, init: false do |got_fx|
    $spi.use_real_time

    unless got_fx
      $spi.puts "[aftertouch control] waiting on fx from the time state: #{effect_key}"
      $spi.sleep(1) while $spi.get(effect_key).nil?
      $spi.puts "[aftertouch control] got fx"
    end

    event_glob = "/midi:#{midi_source}/{note_on,note_off,aftertouch}"
    note, vel = $spi.sync(event_glob)

    # get_event is undocumented. it gives the name of the event we just `sync`ed to
    event = $spi.get_event(event_glob).split_path[-1]

    case event
    when "note_on"
      # TODO: consider initial velocity?
      pressed_notes << note unless pressed_notes.include?(note)
    when "note_off"
      pressed_notes.delete(note)
    when "aftertouch"
      # only care about changes on the oldest pressed note
      # the "vel != 0" is intended to not do a jarring cutoff when you lift your finger, but it's not great
      # TODO: all of this is not great
      if pressed_notes.find_index(note) == 0 && vel != 0
        __midi_fx_control(vel, effect_key, param, val_range, quantum)
      end
    end

    true
  end
end
