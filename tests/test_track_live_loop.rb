#!/usr/bin/env ruby

# frozen_string_literal: true

require_relative "test_helper"
require_relative "../track_live_loop"
require_relative "player_test_helpers"

# NOTE: It is very important that you remember to `stop` the mocked live loop
# threads! LiveLoopTracker stores player state by loop name, and that's only
# cleared when a thread exits. So if you don't stop the thread, its state will
# linger and may break distant tests that use the same loop name.

class TrackLiveLoopTest < Test::Unit::TestCase
  include PlayerTestHelpers

  def _tll(name, *args, **kwargs, &block)
    # We only stub MIDI sends, not internal synths, and we don't want to test
    # cues every time.
    track_live_loop name, *args, midi: true, send_cycle_cues: false, **kwargs, &block
  end

  def test_basics
    t = QT[S(:c4, gate: 0.5)]
    l = _tll :t, t, send_cycle_cues: true, sync: :test_sync
    es = events do
      l.pump 4
      l.stop
    end
    assert_events es, [
      [:sync, :test_sync, 0],

      [:cue, :t_cycle, 0, 0],
      [:c4, 0, 0.5],

      [:cue, :t_cycle, 1, 1],
      [:c4, 1, 1.5],

      [:cue, :t_cycle, 2, 2],
      [:c4, 2, 2.5],

      [:cue, :t_cycle, 3, 3],
      [:c4, 3, 3.5]
    ]

    # Ties should work as expected
    l = _tll(:t, QT[:c4])
    es = events do
      l.pump(5)
      l.stop
    end
    assert_equal vt, 5
    assert_events es, [[:c4, 0, nil]]
  end

  def test_mute_unmute
    expected_mutings = [false, false, true, false, false]
    expected_cycle = 0
    loop_iteration = 0
    t = QT[S(:c4, gate: 0.5)]
    l = _tll(:t, t) do |muted:, was_muted:, cycle:|
      assert_equal cycle, expected_cycle
      assert_equal expected_mutings[loop_iteration], muted

      expected_was_muted = (loop_iteration == 0) ? true : expected_mutings[loop_iteration - 1]
      assert_equal expected_was_muted, was_muted

      loop_iteration += 1

      # cycle only increases if we're not muted
      expected_cycle += 1 unless muted
    end

    es = events do
      l.pump 2
      mute_live_loop(:t)
      l.pump
      unmute_live_loop(:t)
      l.pump 2
      l.stop
    end
    assert_events es, [
      [:c4, 0, 0.5],
      [:c4, 1, 1.5],
      # muted
      [:c4, 3, 3.5],
      [:c4, 4, 4.5]
    ]
  end

  def test_start_muted
    l = _tll(:t) do |muted:, was_muted:|
      assert_true was_muted
      assert_false muted
    end
    l.pump
    l.stop

    l = _tll(:t, start_muted: true) do |muted:, was_muted:|
      assert_true was_muted
      assert_true muted
    end
    l.pump
    l.stop
  end

  def test_default_track
    # If no track is provided, should default to a one-slot eighth-note rest.
    l = _tll(:t) { }  # rubocop:disable Lint/EmptyBlock
    assert_duration 2.5 do
      l.pump 5
      l.stop
    end

    # A swap away from the default track should take place right away; the rest
    # should not trigger.
    l = _tll(:t) do
      QT[S(:c4, gate: 0.5)]
    end
    es = events do
      l.pump
      l.stop
    end
    assert_events es, [[:c4, 0, 0.5]]
  end

  def test_arg
    # Non-track returns from the block should not effect what track is playing
    # back, and should be passed back to the block via `arg:`. `init:` should
    # work as expected and be the default for `arg:` in the first cycle.
    expected_args = [5, 6, 7, 8]
    t = QT[S(:c4, gate: 0.5)]
    l = _tll(:t, t, init: 5) do |cycle:, arg:|
      assert_equal expected_args[cycle], arg
      arg + 1
    end
    es = events do
      l.pump 3
      l.stop
    end
    assert_events es, [
      [:c4, 0, 0.5],
      [:c4, 1, 1.5],
      [:c4, 2, 2.5]
    ]
  end

  def test_track_swap
    tracks = [
      QT[S(:c4, gate: 0.5)],
      QT[S(:c5, gate: 0.5), S(:c6, gate: 0.5)],
      QT[S(:c7, gate: 0.5), S(:c8, gate: 0.5), timescale: 2]
    ]

    expected_cycle = 0
    l = _tll :t do |cycle:, track:, arg:|
      # Swapping should have no effect on cycle
      assert_equal cycle, expected_cycle
      expected_cycle += 1

      # Playing two cycles of each track
      track_idx = cycle / 2
      if cycle > 0
        # We should have been passed the previous track in both track: and arg:
        prev_track_idx = (cycle - 1) / 2
        expected_track_arg = tracks[prev_track_idx]
        assert track.equal?(expected_track_arg)
        assert arg.equal?(expected_track_arg)
      end
      tracks[track_idx]
    end

    es = events do
      l.pump 6
      l.stop
    end

    assert_events es, [
      [:c4, 0, 0.5],
      [:c4, 1, 1.5],

      [:c5, 2, 2.5],
      [:c6, 3, 3.5],
      [:c5, 4, 4.5],
      [:c6, 5, 5.5],

      # Timescale swap here:
      [:c7, 6, 6.25],
      [:c8, 6.5, 6.75],
      [:c7, 7, 7.25],
      [:c8, 7.5, 7.75]
    ]
  end

  def test_bad_swaps
    # This is invalid because the default track is a Track.
    l = _tll(:t) { CCT.rest }
    assert_raises(TypeError) { l.pump }
    l.stop

    l = _tll(:t, T.rest) { CCT.rest }
    assert_raises(TypeError) { l.pump }
    l.stop

    # CCTrack -> Track is also invalid
    l = _tll(:t, CCT.rest) { T.rest }
    assert_raises(TypeError) { l.pump }
    l.stop

    # The cctll alias defaults to a CCTrack
    l = cctll(:t) { T.rest }
    assert_raises(TypeError) { l.pump }
    l.stop
  end

  def assert_std_loop_events(shorthands)
    t = QT[S(:c4, gate: 0.5)]

    # Note: not using _tll to make loops here! Want the raw defaults except
    # cycle cues.
    l = track_live_loop(:t, t, send_cycle_cues: false)
    es = events do
      l.pump
      l.stop
    end
    assert_events es, shorthands
  end

  def test_player_defaults
    old_defaults = current_player_defaults

    # midi: false will raise since we don't stub play/kill, so just set true
    # and leave it on throughout.
    use_player_defaults(midi: true)
    assert_std_loop_events [[:c4, 0, 0.5]]

    use_player_defaults(sync: :test_sync)
    assert_std_loop_events [
      [:sync, :test_sync, 0],
      [:c4, 0, 0.5]
    ]
    use_player_defaults(sync: nil)

    use_player_defaults(start_muted: true)
    assert_std_loop_events []
    use_player_defaults(start_muted: false)

    use_player_defaults(**old_defaults)
  end

  def test_cctrack
    t = CCT[CC(127, 0), CC(127, 50), granularity: :quarter]
    u = CCT[CC(64, 80), granularity: :quarter]
    l = _tll(:t, t) do |cycle:|
      u if cycle >= 2
    end

    es = events do
      l.pump 4
      l.stop
    end
    assert_events es, [
      [127, 0, 0],
      [127, 50, 1],

      [127, 0, 2],
      [127, 50, 3],

      # block swaps to u
      [64, 80, 4],

      [64, 80, 5]
    ]
  end

  def test_fade
    t = QT[S(:c4, gate: 0.5)] * 3
    u = QT[S(:d4, gate: 0.5)] * 3
    normal_events = lambda do |start_time, note: :c4|
      [[note, start_time, start_time + 0.5],
       [note, start_time + 1, start_time + 1.5],
       [note, start_time + 2, start_time + 2.5]]
    end
    fade_in_events = lambda do |start_time, quad: false, note: :c4|
      [[note, start_time, start_time + 0.5, 0],
       [note, start_time + 1, start_time + 1.5, quad ? 31 : 63],
       [note, start_time + 2, start_time + 2.5, 127]]
    end
    fade_out_events = lambda do |start_time, quad: false, note: :c4|
      [[note, start_time, start_time + 0.5, 127],
       [note, start_time + 1, start_time + 1.5, quad ? 95 : 63],
       [note, start_time + 2, start_time + 2.5, 0]]
    end

    # Basic immediate fade in. Track yielded to the block should be unfaded.
    l = _tll(:t, t, fade_in: true) do |track:|
      assert track.equal?(t)
    end
    es = events do
      l.pump(3)
      l.stop
    end
    assert_events es, [
      *fade_in_events[0],
      *normal_events[3],
      *normal_events[6]
    ]

    # Quad fade in
    l = _tll(:t, t, fade_in: :quad)
    es = events do
      l.pump
      l.stop
    end
    assert_events es, fade_in_events[0, quad: true]

    # Fade in on unmute. Should work more than once.
    l = _tll(:t, t, fade_in: true, start_muted: true) do |track:|
      assert track.equal?(t)
    end
    es = events do
      l.pump
      unmute_live_loop :t
      l.pump
      l.pump
      mute_live_loop :t
      l.pump
      unmute_live_loop :t
      l.pump
      l.pump
      l.stop
    end
    assert_events es, [
      # muted
      *fade_in_events[3],
      *normal_events[6],
      # muted
      *fade_in_events[12],
      *normal_events[15]
    ]

    # Fade out. Should report muted during the fade out, and block should always
    # get the unfaded track.
    iteration = 0
    l = _tll(:t, t, fade_out: true) do |muted:, track:|
      assert muted == iteration >= 2
      assert track.equal?(t)
      iteration += 1
    end
    es = events do
      l.pump
      l.pump
      mute_live_loop(:t)
      l.pump
      l.pump
      l.stop
    end
    assert_events es, [
      *normal_events[0],
      *normal_events[3],
      *fade_out_events[6]  # The fade happend in an extra cycle while muted
    ]

    # Quad fade out
    l = _tll(:t, t, fade_out: :quad)
    es = events do
      l.pump
      mute_live_loop(:t)
      l.pump
      l.stop
    end
    assert_events es, [
      *normal_events[0],
      *fade_out_events[3, quad: true]
    ]

    # Fade in & out
    l = _tll(:t, t, fade_in: true, fade_out: true, start_muted: true)
    es = events do
      l.pump
      unmute_live_loop(:t)
      l.pump
      mute_live_loop(:t)
      l.pump
      l.pump
      unmute_live_loop(:t)
      l.pump
      mute_live_loop(:t)
      l.pump
      l.stop
    end
    assert_events es, [
      # muted
      *fade_in_events[3],
      *fade_out_events[6],
      # muted
      *fade_in_events[12],
      *fade_out_events[15]
    ]

    # Interaction with track swap. The track yielded from the block is what will
    # be used for a fade in or out.
    iteration = 0
    tracks_to_yield = [t, t, u, u, t, u]
    l = _tll(:t, t, fade_in: true, fade_out: true, start_muted: true) do |track:|
      expected_track_arg = (iteration == 0) ? t : tracks_to_yield[iteration - 1]
      assert track.equal?(expected_track_arg)
      res = tracks_to_yield[iteration]
      iteration += 1
      res
    end
    es = events do
      l.pump  # i=0, sleep with t

      unmute_live_loop(:t)
      l.pump  # i=1, fade in t

      mute_live_loop(:t)
      l.pump  # i=2, fade out u
      l.pump  # i=3, sleep with u

      unmute_live_loop(:t)
      l.pump # i=4, fade in t
      l.pump # i=5, normal play of u

      l.stop
    end
    assert_events es, [
      *fade_in_events[3],
      *fade_out_events[6, note: :d4],
      *fade_in_events[12],
      *normal_events[15, note: :d4]
    ]
  end

  def test_restart
    # If we don't stop a thread and make a new one with the same name, we can
    # simulate running a sketch in Sonic Pi that would redefine the loop. When
    # that happens, much of the state of the player in the previous loop should
    # carry over.

    t = QT[S(:c4, prob: Prob.pre_same_note),
           S(:d4, gate: 0.5).accum(12, max: 36),
           :c4]
    l1 = _tll(:t, t)
    es = events do
      l1.pump

      # Not stopping l1 yet!
      # Also note that we continue to pump l1 for another cycle here. l2 should
      # not inherit the state of l1's player immediately; it should wait until
      # its first iteration of playback.
      l2 = _tll(:t, t)

      l1.pump

      l2.pump
      l2.pump

      l2.stop
      l1.stop
    end
    assert_events es, [
      # prob skips first c4 the first time through
      [:d4, 1, 1.5],
      [:c4, 2, 4],  # prob triggers & ties the final c4 into the next cycle

      [:d5, 4, 4.5],
      [:c4, 5, 7],  # tie again, held into the new live loop

      [:d6, 7, 7.5],  # accumulation was not reset
      [:c4, 8, 10],

      [:d7, 10, 10.5],
      [:c4, 11, nil]
    ]

    # Cycle should be maintained between new loops
    expected_cycle = 0
    l1 = _tll(:t) do |cycle:|
      assert [0, 1].include?(expected_cycle)
      assert_equal expected_cycle, cycle
    end
    l1.pump
    expected_cycle += 1

    # Not stopping l1 yet! Also making this while l1 is still alive, as above.
    l2 = _tll(:t) do |cycle:|
      assert [2, 3].include?(expected_cycle)
      assert_equal expected_cycle, cycle
    end

    l1.pump
    expected_cycle += 1

    l2.pump
    expected_cycle += 1
    l2.pump
    expected_cycle += 1

    l2.stop
    l1.stop

    # start_muted should not mute pre-existing loops
    t = QT[S(:c4, gate: 0.5)]
    l1 = _tll(:t, t)
    es = events do
      l1.pump
      l2 = _tll(:t, t, start_muted: true)
      l1.pump
      l2.pump
      l2.pump

      l2.stop
      l1.stop
    end
    assert_events es, [
      [:c4, 0, 0.5],
      [:c4, 1, 1.5],
      [:c4, 2, 2.5],
      [:c4, 3, 3.5]
    ]
  end

  def test_fill
    # Can't reliably test toggling fill mid-cycle, unfortunately.

    t = QT[S(:c4, gate: 0.5, prob: Prob.not_fill),
           S(:d4, gate: 0.5, prob: Prob.fill)]
    l = _tll(:t, t)
    es = events do
      l.pump
      fill_live_loop :t
      l.pump
      l.pump
      unfill_live_loop :t
      l.pump
      l.stop
    end
    assert_events es, [
      [:c4, 0, 0.5],

      [:d4, 3, 3.5],
      [:d4, 5, 5.5],

      [:c4, 6, 6.5]
    ]
  end
end
