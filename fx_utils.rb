# frozen_string_literal: true

require_relative "extapi"

# Assembles a stack of nested effects and runs the given block inside of them.
# Provide a map from a Time State key to an array:
# [ effect name, hash of arguments for the effect ]
# The hash in each array is optional. In fact, you may provide just a symbol
# for the fx name instead of an array if there are no arguments.
# Effects are stacked with the first one as the outermost; earlier effects apply
# to later ones.
# Each effect will be stored in the Time State with the provided key.
def with_fx_stack(**fx, &block)
  if fx.empty? == 0
    block.call
  else
    key, with_fx_args = fx.shift
    if with_fx_args.is_a?(Symbol)
      name = with_fx_args
    else
      name, params = with_fx_args
    end

    params ||= {}
    ExtApi.puts "#{key} => #{name} / #{params}"

    ExtApi.with_fx(name, **params) do |effect|
      ExtApi.set(key, effect)
      with_fx_stack(**fx, &block)
    end
  end
end


def __midi_val_to_range(midi_val, range, quantum: nil)
  return range.min if midi_val <= 0
  return range.max if midi_val >= 127

  val = range.min + (range.max - range.min) * (midi_val / 127.0)
  val = ExtApi.quantise(val, quantum) unless quantum.nil?

  val = range.max if val > range.max
  val = range.min if val < range.min

  val
end

def __ranged_val_to_midi(val, range)
  return 0 if val <= range.min
  return 127 if val >= range.max

  midi_val = (val - range.min).to_f / (range.max - range.min)
  midi_val = (midi_val * 127).round

  midi_val = 0 if midi_val < 0
  midi_val = 127 if midi_val > 127

  midi_val
end


# Controls an effect based on a MIDI value (0 - 127). Arguments are the MIDI
# value and the values of the array described in cc_fx_control_loop.
def __midi_fx_control(midi_val, effect_key, param, param_val_range, quantum)
  return if effect_key.nil?

  effect = nil
  if effect_key == :global
    effect = :global
  else
    effect = ExtApi.get(effect_key)
  end

  return if effect.nil?

  param_val = __midi_val_to_range(midi_val, param_val_range, quantum: quantum)
  args = { param => param_val }

  ExtApi.puts "#{effect_key}: val=#{midi_val} --> #{param}=#{param_val.round(2)}"
  if effect == :global
    ExtApi.set_mixer_control!(**args)
  else
    ExtApi.control(effect, **args)
  end
end


def __send_cc_name_sysex(cc, name, port: nil, channel: nil)
  # Ad-hoc format parsed by a script in TouchOSC. sysex messages have to be
  # bookended by 0xf0 and 0xf7.
  bytes = [0xf0, "=".ord, cc, *name.bytes, 0xf7]

  kwargs = port.nil? ? {} : { port: port }
  kwargs[:channel] = channel unless channel.nil?
  ExtApi.midi_sysex(*bytes, **kwargs)
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
# quantum defaults to 0.01.
# When the given CC number is received, its MIDI value will be converted into
# the given range and quantized to quantum. The result will then be set with
# `control` for the given parameter on the given fx as retrieved from the
# Time State by its key.
# The special Time State key `:global` may be used to refer to the parameters
# of the global mixer. Those will be set with `set_mixer_control!`.
#
# MAPPING TYPE 2: MANUAL CALLBACK
# [ name symbol, value range, quantum, callback:, default: ]
# Type type of CC mapping calls the given callback with the value of the CC
# whenever one is received. `callback` must be a Proc or something that responds
# to `call`. It will be invoked with one argument, the value of the CC. The
# value range, quantum are optional and default behave as in type 1 mappings,
# except that the default value range for a callback mapping is 0..127 and the
# quantum is 1 (i.e., the callback will receive raw CC values by default).
# If you provide a different range, the callback will be invoked with a value
# mapped into that range, rather than the raw CC value.
# The first element of the array in this case is solely used for formulating
# the name used in the sysex message; it can be whatever you wish.
#
# Note that unlike usual MIDI port/channel arguments, these must be single
# strings that refer to either a single port/channel, or '*' as a wildcard.
#
# To synchronize external MIDI controllers, for each mapping, an initial CC
# message is sent representing the default value. This is constructed from the
# `default` argument, or the minimum of the value's range if no default is set.
# The default will be scaled to a MIDI value between 0 and 127, based on the
# given range for the value.
#
# If send_name_sysex is true, a special MIDI sysex message with the name of the
# control and its CC number will be sent on the given port the first time the
# loop executes.
# The loop will initially sleep until all needed fx keys exist in the Time
# State.
# Received CCs that are not in the given map will be ignored by this loop.
def cc_fx_control_loop(loop_name = :cc_fx_control, send_name_sysex: true,
                       port: nil, channel: nil, **cc_mappings)
  return if cc_mappings.empty?

  port, channel = __resolve_cc_port_and_channel(port, channel)

  # time state keys for all effects we'll be controlling
  needed_fx = Set.new

  # massage the arguments into a consistent structure and gather needed fx keys
  # CC number => { :type = :fx|:callback, :key, :range, :quantum, :default,
  #                :param (only for fx), :callback (only for callback) }
  mappings = {}
  cc_mappings.each do |cc, mapping|
    if mapping[-1].is_a?(Hash)
      mapping = mapping.dup
      mapping_hash = mapping.pop
    else
      mapping_hash = {}
    end

    default = mapping_hash[:default]

    if mapping_hash.has_key?(:callback)
      key, range, quantum = mapping
      quantum = 1 if quantum.nil?
      range = 0..127 if range.nil?
      default = range.min if default.nil?
      callback = mapping_hash[:callback]

      mappings[cc] = { type: :callback, key: key, range: range, quantum: quantum, default: default, callback: callback }
    else
      key, param, range, quantum = mapping
      quantum = 0.01 if quantum.nil?
      range = 0..1 if range.nil?
      default = range.min if default.nil?

      mappings[cc] = { type: :fx, key: key, range: range, quantum: quantum, default: default, param: param }

      needed_fx << key unless key == :global
    end
  end


  # fire up the live loop that will actually service incoming CCs
  ExtApi.live_loop loop_name, init: true do |first_run|
    ExtApi.use_real_time

    if first_run
      # hang out until all the effect keys exist
      ExtApi.puts "[cc control] waiting on fx from the time state: #{needed_fx.to_a}"
      ExtApi.sleep(1) until needed_fx.none? { |key| ExtApi.get(key).nil? }
      ExtApi.puts "[cc control] got all fx!"

      # send out the sysex name messages & defaults for all mappings
      mappings.each do |cc, mapping|
        if send_name_sysex
          pretty_name = mapping[:key].to_s.delete_suffix("_fx")
          pretty_name += "\n#{mapping[:param]}" if mapping[:type] == :fx
          pretty_name.gsub!("_", " ")
          ExtApi.puts "[cc control] sending name '#{pretty_name}' for CC #{cc}"
          __send_cc_name_sysex(cc, pretty_name, port: port, channel: channel)
        end

        # TODO: support a default on :global effects by doing an initial
        # set_mixer_control?
        next if mapping[:key] == :global

        # Compute the MIDI equivalent of the default, if one was given, and send
        # it out as a CC.
        # TODO: also set the default on the effect itself?
        midi_default = __ranged_val_to_midi(mapping[:default], mapping[:range])
        ExtApi.puts "[cc control] sending default CC #{cc} value #{mapping[:default]} --> midi #{midi_default}"
        ExtApi.midi_cc(cc, midi_default, port: port, channel: channel)
      end
    end

    # wait for a cc on the source
    # TODO: could support arrays of ports/channels by constructing {x,y,z}-style
    # strings for the path here.
    cc_number, cc_val = ExtApi.sync("/midi:#{port}:#{channel}/control_change")

    mapping = mappings[cc_number]
    unless mapping.nil?
      if mapping[:type] == :fx
        __midi_fx_control(cc_val, mapping[:key], mapping[:param], mapping[:range], mapping[:quantum])
      else
        mapped_val = __midi_val_to_range(cc_val, mapping[:range], quantum: mapping[:quantum])
        ExtApi.puts "#{mapping[:key]}: val=#{cc_val} --> callback #{mapped_val.round(2)}"
        mapping[:callback].call(mapped_val)
      end
    end

    false
  end
end
