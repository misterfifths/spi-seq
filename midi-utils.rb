require_relative "extapi.rb"

# Start a live_loop named loop_name that sends MIDI clock beats for the global
# BPM. Sends a MIDI start message on the first iteration if send_start is true.
# Note that the channel argument is only relevant if send_start or send_start is
# true; clock messages are not per-channel.
def midi_clock_live_loop(loop_name = :midi_clock, send_start: true, send_stop: true, port: nil, start_port: nil, start_channel: nil, auto_cue: false)
  beat_kwargs = port.nil? ? {} : { port: port }

  start_stop_kwargs = {}
  start_stop_kwargs[:port] = start_port unless start_port.nil?
  start_stop_kwargs[:channel] = start_channel unless start_channel.nil?

  ExtApi.live_loop loop_name, auto_cue: auto_cue, init: false do |inited|
    ExtApi.midi_stop(**start_stop_kwargs) if !inited && send_stop

    ExtApi.midi_clock_beat(**beat_kwargs)
    ExtApi.sleep 1

    ExtApi.midi_start(**start_stop_kwargs) if !inited && send_start

    ExtApi.cue(loop_name) unless inited || auto_cue

    true
  end
end


# Returns the Time State key that can be used to control muting of a mutable
# live_loop created by that family of functions.
def mute_key(loop_name)
  ("__live_loop_" + loop_name.to_s + "_muted").to_sym
end

# Mutes the given live_loop, assuming it was created by one of the functions in
# the mutable_live_loop family. Note that muting is not instantaneous; see the
# description of mutable_live_loop for details.
def mute_live_loop(loop_name, mute=true)
  ExtApi.set(mute_key(loop_name), mute)
end

# Starts a new live_loop that can be muted by setting the Time State key given
# by the mute_key function to true. What 'mute' means must be implemented by the
# given block; this function merely manages the muted state and informs the
# block of it. The arguments to the block differ from a normal live_loop. It may
# take 1 or 2 arguments:
# - first argument: a boolean representing whether the live_loop is muted.
# - second argument: the normal argument for a live_loop (optional)
# Note that muting is not instantaneous. The live_loop block is only made aware
# of muting the next time it executes, via its first argument. This way, muting
# will happen only between cycles of a loop, not in the middle of one.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def mutable_live_loop(loop_name, start_muted: false, **kwargs, &block)
  raise "Block must take 1 or 2 arguments" if block.arity == 0 || block.arity > 2

  key = mute_key(loop_name)
  ExtApi.set(key, start_muted)

  ExtApi.live_loop(loop_name, **kwargs) do |arg|
    muted = ExtApi.get(key)

    if block.arity == 2
      block.call(muted, arg)
    else
      block.call(muted)
    end
  end
end

def use_cc_control_defaults(port: nil, channel: nil)
  ExtApi.set(:__cc_control_defaults, { port: port, channel: channel })
end

def __resolve_cc_port_and_channel(port, channel)
  # TODO: it would be good to fall back to defaults here, but it's a little
  # tricky - we do need actual port and channel strings so we can construct
  # the name of the control_change event we want to sync to.
  defaults = ExtApi.get(:__cc_control_defaults) || {}
  port = defaults[:port] || "*" if port.nil?
  channel = defaults[:channel] || "*" if channel.nil?
  [port, channel]
end

# Starts a new live_loop that can be muted by a MIDI CC message with the given
# CC number. A value of 0 for the CC will mute, and any other value will unmute.
# What 'mute' means must be implemented by the given block; this function merely
# manages the muted state and informs the block of it. The arguments to the
# block are as described in mutable_live_loop.
# Note that unlike usual MIDI port/channel arguments, these must be single
# strings that refer to either a single port/channel, or '*' as a wildcard.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def cc_mutable_live_loop(loop_name, cc:, port: nil, channel: nil, start_muted: false, **kwargs, &block)
  port, channel = __resolve_cc_port_and_channel(port, channel)

  cc_watcher_loop_name = ("__live_loop_" + loop_name.to_s + "_cc_mute_watcher").to_sym
  ExtApi.live_loop(cc_watcher_loop_name) do
    ExtApi.use_real_time

    # TODO: could support arrays of ports/channels by constructing {x,y,z}-style
    # strings for the path here.
    incoming_cc, cc_val = ExtApi.sync("/midi:#{port}:#{channel}/control_change")
    if incoming_cc == cc
      muted = cc_val == 0
      ExtApi.puts("[cc mute control] CC #{cc} = #{cc_val} -> #{muted ? '' : 'un'}muting live loop #{loop_name}")
      mute_live_loop(loop_name, muted)
    end
  end

  default_cc_val = start_muted ? 0 : 127
  ExtApi.puts "[cc mute control] sending default CC #{cc} value #{default_cc_val} for live loop #{loop_name}"
  ExtApi.midi_cc(cc, default_cc_val, port: port, channel: channel)

  mutable_live_loop(loop_name, start_muted: start_muted, **kwargs, &block)
end

# Starts a new live_loop that can be muted by setting the Time State key given
# by the mute_key function to true. The live_loop is wrapped in a level effect,
# which will have its amp set to 0 when the live_loop is muted. Thus the block
# itself doesn't need to have any logic related to muting; whatever sound it
# creates will simply be silenced when it is muted. The arguments to the block
# are as described in mutable_live_loop.
# Any additional named arguments (e.g. sync: or init:) to this function are
# passed verbatim to the internal live_loop.
def fx_mutable_live_loop(loop_name, start_muted: false, unmuted_amp: 1, amp_slide: 0, **kwargs, &block)
  raise "Block must take 1 or 2 arguments" if block.arity == 0 || block.arity > 2

  ExtApi.with_fx(:level, amp: start_muted ? 0 : unmuted_amp, amp_slide: amp_slide) do |level_fx|
    mutable_live_loop(loop_name, start_muted: start_muted, **kwargs) do |muted, arg|
      ExtApi.control(level_fx, amp: muted ? 0 : unmuted_amp)

      if block.arity == 2
        block.call(muted, arg)
      else
        block.call(muted)
      end
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
  return if cc_mappings.size == 0

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


# Some synths do not respond well to MIDI all note off or sound off messages.
# This function sends a MIDI stop, all notes off, sound off, and individual note
# offs for every MIDI note on the given port/channel. Messages are sent in real
# time.
def midi_uber_stop(port: nil, channel: nil)
  midi_kwargs = {}
  midi_kwargs[:port] = port unless port.nil?
  midi_kwargs[:channel] = channel unless channel.nil?

  ExtApi.with_real_time do
    ExtApi.midi_stop(**midi_kwargs)
    ExtApi.midi_all_notes_off(**midi_kwargs)
    ExtApi.midi_sound_off(**midi_kwargs)
    0.upto(127) { |n| ExtApi.midi_note_off(n, **midi_kwargs) }
  end
end
