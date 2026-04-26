# frozen_string_literal: true

require "forwardable"
require_relative "test_helper"
require_relative "player_extapi_stubs"
require_relative "../player"

module PlayerTestHelpers
  extend Forwardable

  def_delegators "ExtApi",
    :drain_events, :vt, :reset_vt, :use_bpm, :current_bpm, :secs_per_beat,
    :use_midi_defaults

  def player(track, port: nil, channel: nil)
    Player.new(track, midi: true, port: port, channel: channel)
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
  def playback_events(track, play_count: 1, port: nil, channel: nil)
    es = nil
    assert_duration(track.beat_length / track.timescale * play_count) do
      player = player(track, port: port, channel: channel)
      es = events do
        play_count.times { player.play }
      end
    end
    es
  end

  def _find_event_idxs_for_shorthand(raw_events, shorthand, tol = 0.001)
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

  def _assert_shorthand_event(raw_events, shorthand)
    _, _, off_time, = *shorthand
    on_event_idx, off_event_idx = _find_event_idxs_for_shorthand(raw_events, shorthand)
    refute_nil on_event_idx, "no corresponding midi_on event for #{shorthand.inspect}\nevents:\n#{raw_events.inspect}"
    refute_nil off_event_idx, "no corresponding midi_off event for #{shorthand.inspect}\nevents:\n#{raw_events.inspect}" unless off_time.nil?

    [on_event_idx, off_event_idx]
  end

  def assert_events(raw_events, shorthands)
    raw_events = raw_events.dup
    shorthands.each do |shorthand|
      on_event_idx, off_event_idx = _assert_shorthand_event(raw_events, shorthand)

      # Delete in reverse order
      raw_events.delete_at(off_event_idx) unless off_event_idx.nil?
      raw_events.delete_at(on_event_idx)
    end

    assert_empty raw_events, "unexpected extra events: #{raw_events.inspect}"
  end

  def assert_playback_events(track, shorthands, play_count: 1, reset_vt: true, port: nil, channel: nil)
    self.reset_vt if reset_vt
    events = playback_events(track, play_count: play_count, port: port, channel: channel)
    assert_events(events, shorthands)
  end

  # Asserts that the block took the given time in beats. Resets vt.
  def assert_duration(beats, tol = 0.001)
    reset_vt
    yield
    assert_in_delta vt, secs_per_beat(beats), tol
  end
end
