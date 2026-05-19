#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "player_extapi_stubs"
require_relative "player_test_helpers"
require_relative "../player"
require_relative "../ccplayer"

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
    assert_std_accum -1, min: -3, mode: :freeze, play_count: 6, deltas: [0, -1, -2, -3, -3, -3]
    assert_std_accum -1, min: -1, mode: :freeze, play_count: 4, deltas: [0, -1, -1, -1]
    assert_std_accum -12, min: -13, mode: :freeze, play_count: 4, deltas: [0, -12, -13, -13]
  end

  def test_wrap
    assert_std_accum 1, max: 1, mode: :wrap, play_count: 5, deltas: [0, 1, 0, 1, 0]

    # 0 1 2 3 4->0 1 2
    assert_std_accum 1, max: 3, mode: :wrap, play_count: 7, deltas: [0, 1, 2, 3, 0, 1, 2]

    # 0 3 6->1 4 7->2 5->0
    assert_std_accum 3, max: 4, mode: :wrap, play_count: 6, deltas: [0, 3, 1, 4, 2, 0]

    # 0 -3 -6->4 1 -2 -5 -8->2
    assert_std_accum -3, min: -5, max: 4, mode: :wrap, play_count: 7, deltas: [0, -3, 4, 1, -2, -5, 2]

    # 0 -1 -2 -3->0 -1
    assert_std_accum -1, min: -2, max: 0, mode: :wrap, play_count: 5, deltas: [0, -1, -2, 0, -1]
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
end
