# frozen_string_literal: true

require "forwardable"
require_relative "live_loop_mock"
require_relative "player_mocks"
require_relative "../../lib/spiseq/playback/ccplayer"
require_relative "../../lib/spiseq/playback/player"
require_relative "../../lib/spiseq/tracks/track"
require_relative "../../lib/spiseq/utils/live_loops"
require_relative "../../lib/spiseq/utils/midi"

module PlayerHelpers
  extend Forwardable

  def_delegators "MockState", :drain_events, :reset_vt
  def_delegators "SpiSeq::External::Sync", :vt, :use_bpm, :current_bpm, :bt, :sleep
  def_delegators "SpiSeq::External::MIDI", :use_midi_defaults
  def_delegators "SpiSeq::Utils::LiveLoops", :mute_live_loop, :unmute_live_loop
  def_delegators "SpiSeq::Utils::MIDI", :use_cc_control_defaults, :current_cc_control_defaults

  QT = ->(*gridish, **kwargs) { SpiSeq::Tracks::Track.new(*gridish, granularity: :quarter, **kwargs) }

  def teardown
    LiveLoopThread.clean_up_loops(name)
  end

  def player(track, port: nil, channel: nil, debug: false)
    if track.is_a?(SpiSeq::Tracks::Track)
      SpiSeq::Playback::Player.new(track, midi: true, port: port, channel: channel, debug: debug)
    else
      SpiSeq::Playback::CCPlayer.new(track, port: port, channel: channel, debug: debug)
    end
  end

  # Returns the events from executing the block, optionally resetting vt. All
  # lingering events and delayed blocks are cleared before executing the block.
  def events(reset_vt: true)
    self.reset_vt if reset_vt
    drain_events(exec_delayed_blocks: false)
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
      _, exp_name, exp_t, *exp_args = *shorthand
      exp_args ||= []
      exp_kwargs = exp_args.last.is_a?(Hash) ? exp_args.pop : {}
      raw_events.index do |ev|
        next false unless ev[:type] == :cue
        ev => {t:, name:, args:, kwargs:}
        next false unless (t - exp_t).abs < tol
        next false unless name == exp_name
        next false unless args == exp_args
        next false unless kwargs == exp_kwargs
        true
      end
    when :sync
      # form: [:sync, name, time]
      _, exp_name, exp_t = *shorthand
      raw_events.index do |ev|
        next false unless ev[:type] == :sync
        ev => {t:, name:}
        next false unless (t - exp_t).abs < tol
        next false unless name == exp_name
        true
      end
    when :midi_cc
      # form [cc number, cc value, time[, port, channel]]
      exp_num, exp_val, exp_t, exp_port, exp_channel = *shorthand
      raw_events.index do |ev|
        next false unless ev[:type] == :midi_cc
        ev => {t:, num:, val:, port:, channel:}
        next false unless (t - exp_t).abs < tol
        next false unless num == exp_num
        next false unless val == exp_val
        next false unless exp_port.nil? || port == exp_port
        next false unless exp_channel.nil? || channel == exp_channel
        true
      end
    when :midi_note
      # form: [note, on time[, off time or nil, velocity, port, channel]]
      # If off time is missing or nil, will not look for a corresponding
      # midi_note_off event.
      exp_note, exp_on_time, exp_off_time, exp_vel, exp_port, exp_channel = *shorthand
      exp_vel ||= 127  # No velocity in the shorthand means 127
      on_event_idx = raw_events.index do |ev|
        next false unless ev[:type] == :midi_note_on
        ev => {t:, note:, vel:, port:, channel:}
        next false unless (t - exp_on_time).abs < tol
        next false unless note == exp_note
        next false unless vel == exp_vel
        next false unless exp_port.nil? || port == exp_port
        next false unless exp_channel.nil? || channel == exp_channel
        true
      end

      off_event_idx = nil
      unless exp_off_time.nil?
        off_event_idx = raw_events.index do |ev|
          next false unless ev[:type] == :midi_note_off
          ev => {t:, note:, port:, channel:}
          next false unless (t - exp_off_time).abs < tol
          next false unless note == exp_note
          next false unless exp_port.nil? || port == exp_port
          next false unless exp_channel.nil? || channel == exp_channel
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

  def assert_playback_events(track, shorthands, play_count: 1, fill: false, port: nil, channel: nil)
    events = playback_events(track, play_count: play_count, fill: fill, port: port, channel: channel)
    assert_events(events, shorthands)
  end

  # Asserts that the block took the given time in beats. Resets vt.
  def assert_duration(beats, tol = 0.001)
    reset_vt
    yield
    assert_in_delta vt, bt(beats), tol
  end
end
