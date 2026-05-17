# frozen_string_literal: true

require "forwardable"
require_relative "test_helper"
require_relative "player_extapi_stubs"
require_relative "live_loop_extapi_stubs"
require_relative "../player"
require_relative "../ccplayer"

module PlayerTestHelpers
  extend Forwardable

  def_delegators "ExtApi",
    :drain_events, :vt, :reset_vt, :use_bpm, :current_bpm, :secs_per_beat,
    :use_midi_defaults

  QT = ->(*gridish, **kwargs) { Track.new(*gridish, granularity: :quarter, **kwargs) }

  def player(track, port: nil, channel: nil)
    if track.is_a?(Track)
      Player.new(track, midi: true, port: port, channel: channel)
    else
      CCPlayer.new(track, port: port, channel: channel)
    end
  end

  # Returns the events from executing the block, optionally resetting vt. All
  # lingering events and timewarps are cleared before executing the block.
  def events(reset_vt: true)
    self.reset_vt if reset_vt
    drain_events(exec_timewarps: false)
    yield
    drain_events
  end

  # Returns the events from a single playback of the given track, and asserts
  # that playback took the correct duration. Resets vt.
  def playback_events(track, play_count: 1, fill: false, port: nil, channel: nil)
    es = nil
    assert_duration(track.beat_length / track.timescale * play_count) do
      player = player(track, port: port, channel: channel)
      player.fill = fill
      es = events do
        play_count.times { player.play }
      end
    end
    es
  end

  def _event_shorthand_type(shorthand)
    case shorthand.first
    when :cue
      :cue
    when :sync
      :sync
    when Integer
      :midi_cc
    else
      :midi_note
    end
  end

  # Finds index(es) in raw_events corresponding to the given event shorthand.
  # For MIDI note events, returns [on index, off index], where the off index
  # will be nil if no off time was specified. Otherwise returns a single index
  # or nil.
  def _find_event_idxs_for_shorthand(raw_events, shorthand, tol = 0.001)
    case _event_shorthand_type(shorthand)
    when :cue
      # form: [:cue, name, time[, arg1, ..., argN, kwarg1: ..., ..., kwargN: ...]]
      _, name, time, *args = *shorthand
      args ||= []
      kwargs = args.last.is_a?(Hash) ? args.pop : {}
      raw_events.index do |ev|
        ev_type = ev[:type]
        ev_t = ev[:t]
        ev_name = ev[:name]
        ev_args = ev[:args]
        ev_kwargs = ev[:kwargs]

        next false unless ev_type == :cue
        next false unless (ev_t - time).abs < tol
        next false unless ev_name == name
        next false unless ev_args == args
        next false unless ev_kwargs == kwargs
        true
      end
    when :sync
      # form: [:sync, name, time]
      _, name, time = *shorthand
      args ||= []
      kwargs = args.last.is_a?(Hash) ? args.pop : {}
      raw_events.index do |ev|
        ev_type = ev[:type]
        ev_t = ev[:t]
        ev_name = ev[:name]

        next false unless ev_type == :sync
        next false unless (ev_t - time).abs < tol
        next false unless ev_name == name
        true
      end
    when :midi_cc
      # form [cc number, cc value, time[, port, channel]]
      cc_num, val, time, port, channel = *shorthand
      raw_events.index do |ev|
        ev_type = ev[:type]
        ev_t = ev[:t]
        ev_num = ev[:num]
        ev_val = ev[:val]
        ev_port = ev[:port]
        ev_channel = ev[:channel]

        next false unless ev_type == :midi_cc
        next false unless (ev_t - time).abs < tol
        next false unless ev_num == cc_num
        next false unless ev_val == val
        next false unless port.nil? || ev_port == port
        next false unless channel.nil? || ev_channel == channel
        true
      end
    when :midi_note
      # form: [note, on time[, off time or nil, velocity, port, channel]]
      # If off time is missing or nil, will not look for a corresponding
      # midi_note_off event.
      note, on_time, off_time, vel, port, channel = *shorthand
      on_event_idx = raw_events.index do |ev|
        ev_type = ev[:type]
        ev_t = ev[:t]
        ev_note = ev[:note]
        ev_vel = ev[:vel]
        ev_port = ev[:port]
        ev_channel = ev[:channel]

        next false unless ev_type == :midi_note_on
        next false unless (ev_t - on_time).abs < tol
        next false unless ev_note == note
        next false unless vel.nil? || ev_vel == vel
        next false unless port.nil? || ev_port == port
        next false unless channel.nil? || ev_channel == channel
        true
      end

      off_event_idx = nil
      unless off_time.nil?
        off_event_idx = raw_events.index do |ev|
          ev_type = ev[:type]
          ev_t = ev[:t]
          ev_note = ev[:note]
          ev_port = ev[:port]
          ev_channel = ev[:channel]

          next false unless ev_type == :midi_note_off
          next false unless (ev_t - off_time).abs < tol
          next false unless ev_note == note
          next false unless port.nil? || ev_port == port
          next false unless channel.nil? || ev_channel == channel
          true
        end
      end

      [on_event_idx, off_event_idx]
    end
  end

  def assert_events(raw_events, shorthands)
    raw_events = raw_events.dup
    shorthands.each do |shorthand|
      type = _event_shorthand_type(shorthand)
      if type == :midi_note
        _, _, off_time = *shorthand
        on_event_idx, off_event_idx = _find_event_idxs_for_shorthand(raw_events, shorthand)
        refute_nil on_event_idx, "no corresponding midi_note_on event for #{shorthand.inspect}\nevents:\n#{raw_events.inspect}"
        refute_nil off_event_idx, "no corresponding midi_note_off event for #{shorthand.inspect}\nevents:\n#{raw_events.inspect}" unless off_time.nil?

        # Delete in reverse order
        raw_events.delete_at(off_event_idx) unless off_event_idx.nil?
        raw_events.delete_at(on_event_idx)
      else
        event_idx = _find_event_idxs_for_shorthand(raw_events, shorthand)
        refute_nil event_idx, "no corresponding #{type} event for #{shorthand.inspect}\nevents:\n#{raw_events.inspect}"

        raw_events.delete_at(event_idx)
      end
    end

    assert_empty raw_events, "unexpected extra events: #{raw_events.inspect}"
  end

  def assert_playback_events(track, shorthands, play_count: 1, fill: false, reset_vt: true, port: nil, channel: nil)
    self.reset_vt if reset_vt
    events = playback_events(track, play_count: play_count, fill: fill, port: port, channel: channel)
    assert_events(events, shorthands)
  end

  # Asserts that the block took the given time in beats. Resets vt.
  def assert_duration(beats, tol = 0.001)
    reset_vt
    yield
    assert_in_delta vt, secs_per_beat(beats), tol
  end
end
