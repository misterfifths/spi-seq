#!/usr/bin/env ruby

# frozen_string_literal: true

require_relative "test_helper"
require_relative "../track_live_loop"
require_relative "player_test_helpers"

# NOTE: It is very important that you remember to `stop` the mocked live loop
# threads! SpiSeq::LiveLoops stores player state by loop name, and that's only
# cleared when a thread exits. So if you don't stop the thread, its state will
# linger and may break distant tests that use the same loop name.

class TrackLiveLoopTest < Test::Unit::TestCase
  include PlayerTestHelpers

  def setup
    # We only stub MIDI sends, not internal synths, and we don't want to test
    # cues every time.
    use_player_defaults midi: true, send_cycle_cues: false
  end

  def test_basics
    t = QT[S(:c4, gate: 0.5)]
    l = tll :t, t, send_cycle_cues: true, sync: :test_sync
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
    l = tll(:t, QT[:c4])
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
    l = tll(:t, t) do |muted:, was_muted:, cycle:|
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
    l = tll(:t) do |muted:, was_muted:|
      assert_true was_muted
      assert_false muted
    end
    l.pump
    l.stop

    l = tll(:t, start_muted: true) do |muted:, was_muted:|
      assert_true was_muted
      assert_true muted
    end
    l.pump
    l.stop
  end

  def test_default_track
    # If no track is provided, should default to a one-slot eighth-note rest.
    l = tll(:t) { }  # rubocop:disable Lint/EmptyBlock
    assert_duration 2.5 do
      l.pump 5
      l.stop
    end

    # A swap away from the default track should take place right away; the rest
    # should not trigger.
    l = tll(:t) do
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
    l = tll(:t, t, init: 5) do |cycle:, arg:|
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
    l = tll :t do |cycle:, track:, arg:|
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
    l = tll(:t) { CCT.rest }
    assert_raises(TypeError) { l.pump }
    l.stop

    l = tll(:t, T.rest) { CCT.rest }
    assert_raises(TypeError) { l.pump }
    l.stop

    # CCTrack -> Track is also invalid
    l = tll(:t, CCT.rest) { T.rest }
    assert_raises(TypeError) { l.pump }
    l.stop

    # The cctll alias defaults to a CCTrack
    l = cctll(:t) { T.rest }
    assert_raises(TypeError) { l.pump }
    l.stop
  end

  def assert_std_loop_events(shorthands)
    t = QT[S(:c4, gate: 0.5)]

    l = tll(:t, t)
    es = events do
      l.pump
      l.stop
    end
    assert_events es, shorthands
  end

  def test_player_defaults
    old_defaults = current_player_defaults

    use_player_defaults(midi: true)
    assert_std_loop_events [
      [:cue, :t_cycle, 0, 0],
      [:c4, 0, 0.5]
    ]

    use_player_defaults(midi: true, sync: :test_sync)
    assert_std_loop_events [
      [:sync, :test_sync, 0],
      [:cue, :t_cycle, 0, 0],
      [:c4, 0, 0.5]
    ]

    use_player_defaults(midi: true, send_cycle_cues: false, sync: :test_sync)
    assert_std_loop_events [
      [:sync, :test_sync, 0],
      [:c4, 0, 0.5]
    ]

    use_player_defaults(midi: true, start_muted: true)
    assert_std_loop_events []

    # Explicit arguments should override defaults
    use_player_defaults(midi: false, start_muted: true, send_cycle_cues: true, sync: :test_sync)
    l = tll(:t, QT[S(:c4, gate: 0.5)], midi: true, start_muted: false, send_cycle_cues: false, sync: nil)
    es = events do
      l.pump
      l.pump
      l.stop
    end
    assert_events es, [
      [:c4, 0, 0.5],
      [:c4, 1, 1.5]
    ]

    use_player_defaults(**old_defaults)
  end

  def test_cctrack
    t = CCT[CC(127, 0), CC(127, 50), granularity: :quarter]
    u = CCT[CC(64, 80), granularity: :quarter]
    l = tll(:t, t) do |cycle:|
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
    l = tll(:t, t, fade_in: true) do |track:|
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
    l = tll(:t, t, fade_in: :quad)
    es = events do
      l.pump
      l.stop
    end
    assert_events es, fade_in_events[0, quad: true]

    # Fade in on unmute. Should work more than once.
    l = tll(:t, t, fade_in: true, start_muted: true) do |track:|
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
    l = tll(:t, t, fade_out: true) do |muted:, track:|
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
    l = tll(:t, t, fade_out: :quad)
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
    l = tll(:t, t, fade_in: true, fade_out: true, start_muted: true)
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
    l = tll(:t, t, fade_in: true, fade_out: true, start_muted: true) do |track:|
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
    l1 = tll(:t, t)
    es = events do
      l1.pump

      # Not stopping l1 yet!
      # Also note that we continue to pump l1 for another cycle here. l2 should
      # not inherit the state of l1's player immediately; it should wait until
      # its first iteration of playback.
      l2 = tll(:t, t)

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
    l1 = tll(:t) do |cycle:|
      assert [0, 1].include?(expected_cycle)
      assert_equal expected_cycle, cycle
    end
    l1.pump
    expected_cycle += 1

    # Not stopping l1 yet! Also making this while l1 is still alive, as above.
    l2 = tll(:t) do |cycle:|
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
    l1 = tll(:t, t)
    es = events do
      l1.pump
      l2 = tll(:t, t, start_muted: true)
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

    # Muted state should persist
    t = QT[S(:c4, gate: 0.5)]
    l1 = tll(:t, t)
    es = events do
      l1.pump
      mute_live_loop :t

      l2 = tll(:t, t)
      l1.pump
      l2.pump
      l2.pump

      l2.stop
      l1.stop
    end
    assert_events es, [
      [:c4, 0, 0.5]
    ]
  end

  def test_fill
    # Can't reliably test toggling fill mid-cycle, unfortunately.

    t = QT[S(:c4, gate: 0.5, prob: Prob.not_fill),
           S(:d4, gate: 0.5, prob: Prob.fill)]
    l = tll(:t, t)
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

  def test_fill_cc
    # Testing the actual CC fill functionality isn't possible without a *lot*
    # more stubbing of Sonic Pi methods (actually making `sync` work, e.g.). But
    # we can at least test the initial CC send and use_cc_control_defaults.

    # Should send a CC at creation with value 0. Recreating the same loop name
    # should not send another CC.
    es = events do
      l1 = track_live_loop(:t, fill_cc: 64) { ExtApi.sleep(1) }
      l1.pump
      fill_live_loop :t
      l1.pump
      l2 = track_live_loop(:t, fill_cc: 64) { ExtApi.sleep(1) }
      l1.pump
      l2.pump
      l2.stop
      l1.stop
    end
    assert_events es, [[64, 0, 0]]
  end

  def assert_fill_cc_port_channel(port = nil, channel = nil)
    t = T[:r, granularity: :quarter]
    es = events do
      l = track_live_loop(:t, t, fill_cc: 10)
      l.pump
      l.stop

      l = track_live_loop(:t, t, fill_cc: 10, cc_port: "specific port")
      l.pump
      l.stop

      l = track_live_loop(:t, t, fill_cc: 10, cc_channel: 5)
      l.pump
      l.stop

      l = track_live_loop(:t, t, fill_cc: 10, cc_port: "specific port", cc_channel: 3)
      l.pump
      l.stop
    end
    assert_events es, [
      [10, 0, 0, port, channel],
      [10, 0, 1, "specific port", channel],
      [10, 0, 2, port, 5],
      [10, 0, 3, "specific port", 3]
    ]
  end

  def test_fill_cc_defaults
    old_defaults = current_cc_control_defaults

    use_cc_control_defaults(port: "default_device")
    assert_fill_cc_port_channel("default_device")

    use_cc_control_defaults(channel: 6)  # should have cleared the port
    assert_fill_cc_port_channel(nil, 6)

    use_cc_control_defaults(port: "default device", channel: 7)
    assert_fill_cc_port_channel("default device", 7)

    use_cc_control_defaults(channel: nil)
    assert_fill_cc_port_channel(nil, nil)

    use_cc_control_defaults(**old_defaults)
  end

  def test_mute_cc
    # As with fill_cc, we can't test this very well, but we can test the initial
    # send. track_live_loop delegates to cc_mutable_live_loop, so we don't need
    # to be particularly thorough; that method has its own tests.

    # Should send a CC at creation with a value matching start_muted. Recreating
    # the same loop name should not send another CC.
    es = events do
      l1 = track_live_loop(:t, cc: 64) { ExtApi.sleep(1) }
      l1.pump
      fill_live_loop :t
      l1.pump
      l2 = track_live_loop(:t, cc: 64, start_muted: true) { ExtApi.sleep(1) }
      l1.pump
      l2.pump
      l2.stop
      l1.stop
    end
    assert_events es, [[64, 127, 0]]

    es = events do
      l = track_live_loop(:t, cc: 64, start_muted: true) { ExtApi.sleep(1) }
      l.pump
      l.stop
    end
    assert_events es, [[64, 0, 0]]
  end

  def test_block_args
    # rubocop:disable Lint/UnusedBlockArgument
    assert_raises(ArgumentError) { tll(:t) { |x| :r } }  # positional arguments are invalid
    assert_raises(ArgumentError) { tll(:t) { |x = 2| :r } }  # even optional ones

    assert_raises(ArgumentError) { tll(:t) { |cycle:, nonsense:| :r } }
    assert_nothing_raised do
      l = tll(:t) { |cycle:, nonsense: false| :r }  # unknown optional kwargs are ok
      l.stop
    end
    # rubocop:enable Lint/UnusedBlockArgument
  end

  def test_accum_fade
    # Accumulation should persist into and out of a fade
    t = QT[S(:c4, gate: 0.5).accum(12, max: 48, mode: :freeze), S(:d2, gate: 0.5)]
    l = tll(:t, t, fade_in: true, fade_out: true)
    es = events do
      l.pump
      l.pump
      l.pump
      mute_live_loop(:t)
      l.pump
      l.stop
    end
    assert_events es, [
      [:c4, 0, 0.5, 0],  # fade in
      [:d2, 1, 1.5, 127],

      [:c5, 2, 2.5, 127],  # fade complete, accum should take effect immediately since primed during the fade
      [:d2, 3, 3.5, 127],

      [:c6, 4, 4.5, 127],
      [:d2, 5, 5.5, 127],

      [:c7, 6, 6.5, 127],  # fade out
      [:d2, 7, 7.5, 0]
    ]
  end
end
