#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "player_extapi_stubs"
require_relative "player_test_helpers"
require_relative "../lib/spiseq/playback/ccplayer"
require_relative "../lib/spiseq/playback/player"
require_relative "../lib/spiseq/theory/midinote"

include SpiSeq::Playback
include SpiSeq::Theory
include SpiSeq::Tracks

# Tests for accumulation during playback
class AccumTest < Test::Unit::TestCase
  include PlayerTestHelpers

  def setup
    use_bpm 60
  end

  # Asserts that playing a standard track will result in sequential events with
  # the given set of deltas from the starting note.
  def assert_std_accum(delta, deltas:, min: 0, max: 12, mode: :wrap, prob: nil, **kwargs)
    expected_events = deltas.map.with_index { |d, i| [N(:c4) + d, i, i + 0.5] }

    assert_playback_events(QT[S(:c4, gate: 0.5).accum(delta, min: min, max: max, mode: mode, prob: prob)],
                           expected_events,
                           **kwargs)
  end

  def test_freeze_mode
    # should freeze at the max delta
    assert_std_accum 1, max: 3, mode: :freeze, play_count: 6, deltas: [0, 1, 2, 3, 3, 3]
    assert_std_accum 1, max: 1, mode: :freeze, play_count: 5, deltas: [0, 1, 1, 1, 1]

    # even if the delta would jump way past it
    assert_std_accum 12, max: 13, mode: :freeze, play_count: 4, deltas: [0, 12, 13, 13]

    # shouldn't step below min
    assert_std_accum(-1, min: -3, mode: :freeze, play_count: 6, deltas: [0, -1, -2, -3, -3, -3])
    assert_std_accum(-1, min: -1, mode: :freeze, play_count: 4, deltas: [0, -1, -1, -1])
    assert_std_accum(-12, min: -13, mode: :freeze, play_count: 4, deltas: [0, -12, -13, -13])
  end

  def test_wrap
    assert_std_accum 1, max: 1, mode: :wrap, play_count: 5, deltas: [0, 1, 0, 1, 0]

    # 0 1 2 3 4->0 1 2
    assert_std_accum 1, max: 3, mode: :wrap, play_count: 7, deltas: [0, 1, 2, 3, 0, 1, 2]

    # 0 3 6->1 4 7->2 5->0
    assert_std_accum 3, max: 4, mode: :wrap, play_count: 6, deltas: [0, 3, 1, 4, 2, 0]

    # 0 -3 -6->4 1 -2 -5 -8->2
    assert_std_accum(-3, min: -5, max: 4, mode: :wrap, play_count: 7, deltas: [0, -3, 4, 1, -2, -5, 2])

    # 0 -3 -6 -9->0 -3 -6
    assert_std_accum(-3, min: -6, max: 2, mode: :wrap, play_count: 6, deltas: [0, -3, -6, 0, -3, -6])

    # 0 -1 -2 -3->0 -1
    assert_std_accum(-1, min: -2, max: 0, mode: :wrap, play_count: 5, deltas: [0, -1, -2, 0, -1])
  end

  def test_reverse
    assert_std_accum 1, max: 1, mode: :reverse, play_count: 5, deltas: [0, 1, 0, 1, 0]

    assert_std_accum 1, max: 3, mode: :reverse, play_count: 7, deltas: [0, 1, 2, 3, 2, 1, 0]

    assert_std_accum 1, min: -2, max: 1, mode: :reverse, play_count: 7, deltas: [0, 1, 0, -1, -2, -1, 0]

    # 0 5 0 -5 -10->-5 0 5
    assert_std_accum 5, min: -7, max: 5, mode: :reverse, play_count: 7, deltas: [0, 5, 0, -5, -5, 0, 5]

    # 0 3 6->3 0 -3 0 3
    assert_std_accum 3, min: -3, max: 4, mode: :reverse, play_count: 7, deltas: [0, 3, 3, 0, -3, 0, 3]

    # 0 3 6->3 0 3 6->3 0
    assert_std_accum 3, min: 0, max: 4, mode: :reverse, play_count: 7, deltas: [0, 3, 3, 0, 3, 3, 0]

    # 0 3 6->3 0 -3->-2 1 4
    assert_std_accum 3, min: -2, max: 4, mode: :reverse, play_count: 7, deltas: [0, 3, 3, 0, -2, 1, 4]
  end

  def test_prob
    # accum shouldn't trigger if the step itself doesn't
    assert_playback_events QT[S(:c4, gate: 0.5, prob: Prob.every_other).accum(1, max: 2, mode: :freeze)], [
      [:c4, 0, 0.5],
      # skipped in cycle 2
      [:cs4, 2, 2.5],
      # skipped
      [:d4, 4, 4.5],
      # skipped, now accum is at its max
      [:d4, 6, 6.5],
      # skipped
      [:d4, 8, 8.5]
    ], play_count: 9

    # accum shouldn't trigger if the accum prob doesn't
    assert_playback_events QT[S(:c4, gate: 0.5).accum(1, max: 2, mode: :freeze, prob: Prob.every_other)], [
      [:c4, 0, 0.5],
      [:c4, 1, 1.5],
      [:cs4, 2, 2.5],
      [:cs4, 3, 3.5],
      [:d4, 4, 4.5],
      [:d4, 5, 5.5],
      [:d4, 6, 6.5],  # maxed out
      [:d4, 7, 7.5]
    ], play_count: 8

    # accum and step probs should stack
    assert_playback_events QT[S(:c4, gate: 0.5, prob: Prob.not_first).accum(1, max: 3, mode: :freeze, prob: Prob.every_other)], [
      # skipped
      [:c4, 1, 1.5],  # first time for this step; accum will never trigger
      [:cs4, 2, 2.5], # this is an every other cycle; accum triggers
      [:cs4, 3, 3.5],
      [:d4, 4, 4.5],
      [:d4, 5, 5.5],
      [:ds4, 6, 6.5],  # maxed out
      [:ds4, 7, 7.5],
      [:ds4, 8, 8.5]
    ], play_count: 9

    # pre_same_note should take accumulation into account
    t0 = QT[S(:c4, gate: 0.5)]
    t1 = QT[S(:c4, gate: 0.5, prob: Prob.pre_same_note).accum(12, max: 24, mode: :freeze, prob: Prob.every(3))]
    p = player(t0)
    es = events do
      p.play
      p.swap_track(t1)
      p.play
      p.play
      p.play
      p.play
    end
    assert_events es, [
      [:c4, 0, 0.5],  # t0
      [:c4, 1, 1.5],  # t1
      [:c4, 2, 2.5]   # accum didn't trigger yet
      # accum triggers; t1 note is now c5, so the prob doesn't pass
    ]
  end

  def test_scale_interaction
    # If a Track has a scale, and a step inside it has accumulation, the result
    # of the accumulation should be snapped to the scale. We do a sort of
    # "double snapping", in fact - the original note of the step is snapped to
    # the scale, then the accumulation delta is applied, and the result is
    # snapped again.
    t = QT[S(:cs4, gate: 0.5).accum(1, max: 5, mode: :freeze), scale: Scale.full_scale(:c, :major)]
    assert_playback_events t, [
      [:d4, 0, 0.5],  # (cs -> d)
      [:e4, 1, 1.5],  # (cs -> d) + 1 = ds -> e
      [:e4, 2, 2.5],  # (cs -> d) + 2 = e
      [:f4, 3, 3.5],  # (cs -> d) + 3 = f
      [:g4, 4, 4.5],  # (cs -> d) + 4 = fs -> g
      [:g4, 5, 5.5],  # (cs -> d) + 5 = g
      [:g4, 6, 6.5]   # (maxed out)
    ], play_count: 7
  end

  def test_duplicate_note
    # If accumulation makes a step have the same note as another, the
    # accumulation should still take effect, even if the step doesn't sound.
    t = QT[[S(:cs4, gate: 0.75), S(:c4, gate: 0.5).accum(1)]]
    assert_playback_events t, [
      [:cs4, 0, 0.75],
      [:c4, 0, 0.5],

      [:cs4, 1, 1.75],  # the accumulating step collided with the other and lost

      [:cs4, 2, 2.75],
      [:d4, 2, 2.5],  # but the accumulation from that cycle still happened

      [:cs4, 3, 3.75],
      [:ds4, 3, 3.5]
    ], play_count: 4
  end

  def test_independence
    # Accumulation on two steps should be independent even if they share a note
    t = QT[
      S(:c4).accum(12, max: 36, mode: :freeze),
      S(:c4).accum(-12, min: -36, mode: :freeze)
    ]
    assert_playback_events t, [
      [:c4, 0, 2], # the first time through, the two are tied

      [:c5, 2, 3],
      [:c3, 3, 4],

      [:c6, 4, 5],
      [:c2, 5, nil]
    ], play_count: 3

    # Things should be independent even if the exact same step is used in
    # multiple slots. In this case accumulation should trigger independently
    # each time the step is used, which will result in both steps playing the
    # same note each time (i.e., accumulation should not be doubled).
    s = S(:c4).accum(12, max: 36, mode: :freeze)
    t = QT[s, :r, s]
    assert_playback_events t, [
      [:c4, 0, 1],
      [:c4, 2, 3],

      [:c5, 3, 4],
      [:c5, 5, 6],

      [:c6, 6, 7],
      [:c6, 8, nil]
    ], play_count: 3
  end

  def test_swap_track
    # Swapping to the same track should not reset accumulation
    t = QT[S(:c4, gate: 0.5).accum(12, max: 36, mode: :freeze)]
    p = player(t)
    es = events do
      p.play
      p.play
      p.swap_track(t)
      p.play
    end
    assert_events es, [
      [:c4, 0, 0.5],
      [:c5, 1, 1.5],
      [:c6, 2, 2.5]
    ]

    # But swapping to another track should
    u = QT[S(:d4, gate: 0.5).accum(12, max: 36, mode: :freeze)]
    p = player(t)
    es = events do
      p.play
      p.play
      p.swap_track(u)
      p.play
      p.play
      p.swap_track(t)
      p.play
      p.play
      p.swap_track(u)
      p.play
      p.play
    end
    assert_events es, [
      [:c4, 0, 0.5],
      [:c5, 1, 1.5],
      [:d4, 2, 2.5],
      [:d5, 3, 3.5],
      [:c4, 4, 4.5],  # accumulation reset in t
      [:c5, 5, 5.5],
      [:d4, 6, 6.5],  # accumulation reset in u
      [:d5, 7, 7.5]
    ]
  end

  def test_cctrack
    # Accumulation applies to the value of CCSteps.
    assert_playback_events CCT[CC(64, 5).accum(1, max: 3, mode: :freeze), granularity: :quarter], [
      [64, 5, 0],
      [64, 6, 1],
      [64, 7, 2],
      [64, 8, 3],
      [64, 8, 4]
    ], play_count: 5
  end

  def test_vel_target
    # The delta calculations are identical between this and standard note
    # accumulation, so we don't need to go crazy here. Just making sure it
    # targets velocity is good enough.
    t = QT[S(:c4, gate: 0.5, vel: 5).accum(10, max: 30, mode: :freeze, target: :vel)]
    assert_playback_events t, [
      [:c4, 0, 0.5, 5],
      [:c4, 1, 1.5, 15],
      [:c4, 2, 2.5, 25],
      [:c4, 3, 3.5, 35],
      [:c4, 4, 4.5, 35],  # maxed out
      [:c4, 5, 5.5, 35]
    ], play_count: 6
  end

  def test_gate_target
    # Again, the delta stepping has been tested thoroughly, so we can keep it
    # pretty simple.

    t = QT[S(:c4, gate: 0.5).accum(0.1, max: 0.5, mode: :freeze, target: :gate)]
    assert_playback_events t, [
      [:c4, 0, 0.5],
      [:c4, 1, 1.6],
      [:c4, 2, 2.7],
      [:c4, 3, 3.8],
      [:c4, 4, 4.9],
      [:c4, 5, nil]  # now tied
    ], play_count: 8

    # If gate exceeds 1, accumulation continues
    t = QT[S(:c4, gate: 0.8).accum(0.1, min: -0.5, max: 0.4, mode: :reverse, target: :gate)]
    assert_playback_events t, [
      [:c4, 0, 0.8],
      [:c4, 1, 1.9],
      [:c4, 2,        # accum +0.2 - now tied from 2 - 3
                      # +0.3, tied 3 - 4
                      # +0.4, tied 4 - 5
                      # now reversing, +0.3, tied 5 - 6
                      # +0.2, tied 6 - 7
               7.9],  # +0.1, gate 0.9, tie ends
      [:c4, 8, 8.8],  # +0
      [:c4, 9, 9.7]   # -0.1
    ], play_count: 10
  end

  def test_float_step
    # When the step is an integer, it makes sent to subtract one when wrapping
    # or reversing after stepping past the min or max. For instance, if you have
    # accum delta 3, min 0, max 7 in wrap mode, the accumulation will go 0, 3,
    # 6, then 9. How do we wrap 9? Well, it's two past the maximum. We use one
    # of those 2 overages to get us back to the minimum, and then add the
    # remainder, so 9 wraps to 1.
    # But for floating point deltas, there's no sensible analogy. If wrapping
    # with delta 0.3, min 0, max 0.7, we go 0, 0.3, 0.6, 0.9. There's an overage
    # of 0.2, but how much of that do we consume to wrap around to 0? We could
    # establish an arbitrary epsilon (say, 0.1) and treat an overage in steps of
    # that amount. Or we could just throw up our hands and not attempt to
    # account for the "wrap around" step when the delta is too small.
    # That's what we do. Luckily, this case will probably only come up with gate
    # accumulation, where the minor difference is unlikely to be impactful.
    t = QT[S(:c4, gate: 0.1).accum(0.3, max: 0.7, mode: :wrap, target: :gate)]
    assert_playback_events t, [
      [:c4, 0, 0.1],  # +0
      [:c4, 1, 1.4],  # +0.3
      [:c4, 2, 2.7],  # +0.6
      [:c4, 3, 3.3],  # +0.9 -> +0.2
      [:c4, 4, 4.6],  # +0.5
      [:c4, 5, 5.2]   # +0.8 -> 0.1
    ], play_count: 6

    # Reverse should behave similarly
    t = QT[S(:c4, gate: 0.1).accum(0.3, max: 0.7, mode: :reverse, target: :gate)]
    assert_playback_events t, [
      [:c4, 0, 0.1],  # +0
      [:c4, 1, 1.4],  # +0.3
      [:c4, 2, 2.7],  # +0.6
      [:c4, 3, 3.6],  # +0.9 -> overage of 0.2 -> +0.5
      [:c4, 4, 4.3],  # +0.2
      [:c4, 5, 5.2],  # -0.1 -> overage of 0.1 -> 0.1
      [:c4, 6, 6.5]   # +0.4
    ], play_count: 7
  end

  def test_tie
    # Accumulation into another tied note should continue/end it.
    t = QT[[S(:cs4, prob: Prob.first), S(:c4, gate: 0.25).accum(1)]]
    assert_playback_events t, [
      [:c4,  0, 0.25],
      [:cs4, 0,         # unaccumulated cs4 triggers @ t=0
                1.25],  # accumulation triggers @t=1 on the c4, ties into the prev slot & ends
      [:d4,  2, 2.25],
      [:ds4, 3, 3.25]
    ], play_count: 4
  end
end
