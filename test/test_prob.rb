#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/player_helpers"
require_relative "../lib/spiseq/playback/player"
require_relative "../lib/spiseq/tracks/prob"

include SpiSeq::Playback
include SpiSeq::Tracks

# Tests for step probabilities during playback
class ProbTest < Test::Unit::TestCase
  include PlayerHelpers

  def setup
    use_bpm 60
  end

  def test_chance
    if in_sonic_pi?
      SpiSeq::External::Random.use_random_seed(1234)
      assert_playback_events QT[[:a1, S(:b2, prob: Prob.chance(0.5))]], [
        [:a1, 0, nil],
        [:b2, 0, 2]
      ], play_count: 4
    else
      srand 143131231
      assert_playback_events QT[[:a1, S(:b2, prob: Prob.chance(0.5))]], [
        [:a1, 0, nil],
        [:b2, 0, 1],
        [:b2, 2, nil]
      ], play_count: 4
    end

    assert_playback_events QT[[:a1, S(:b2, prob: Prob.chance(1))]], [
      [:a1, 0, nil],
      [:b2, 0, nil]
    ]

    assert_playback_events QT[[:a1, S(:b2, prob: Prob.chance(0))]], [
      [:a1, 0, nil]
    ]
  end

  def test_one_in
    if in_sonic_pi?
      SpiSeq::External::Random.use_random_seed(1234)
      assert_playback_events QT[[:a1, S(:b2, prob: Prob.one_in(2))]], [
        [:a1, 0, nil],
        [:b2, 0, 2]
      ], play_count: 4
    else
      srand 2
      assert_playback_events QT[[:a1, S(:b2, prob: Prob.one_in(2))]], [
        [:a1, 0, nil],
        [:b2, 0, 2],
        [:b2, 3, nil]
      ], play_count: 4
    end

    assert_playback_events QT[[:a1, S(:b2, prob: Prob.one_in(1))]], [
      [:a1, 0, nil],
      [:b2, 0, nil]
    ]

    assert_raises(ArgumentError) { Prob.one_in(0) }
  end

  def test_x_of_y
    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.x_of_y(1, 2))]], [
      [:a1, 0, 0.5],
      [:b2, 0, 0.5],

      [:a1, 1, 1.5],

      [:a1, 2, 2.5],
      [:b2, 2, 2.5],

      [:a1, 3, 3.5]
    ], play_count: 4

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.x_of_y(2, 2))]], [
      [:a1, 0, 0.5],

      [:a1, 1, 1.5],
      [:b2, 1, 1.5],

      [:a1, 2, 2.5],

      [:a1, 3, 3.5],
      [:b2, 3, 3.5]
    ], play_count: 4

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.x_of_y(2, 3))]], [
      [:a1, 0, 0.5],

      [:a1, 1, 1.5],
      [:b2, 1, 1.5],

      [:a1, 2, 2.5],

      [:a1, 3, 3.5],

      [:a1, 4, 4.5],
      [:b2, 4, 4.5],

      [:a1, 5, 5.5],

      [:a1, 6, 6.5]
    ], play_count: 7

    # This is a general thing, but this is a convenient place to test it: notes
    # that play (or don't) because of their probability should participate in
    # (or terminate) ties.
    assert_playback_events QT[:b1, :b1, S(:b1, prob: Prob.x_of_y(2, 3))], [
      # Step with a prob is skipped on first go-round, ending the tie.
      [:b1, 0, 2],

      # Step with a prob triggers on second go-round, ties into the loop, but is
      # skipped on the third iteration, ending the tie.
      [:b1, 3, 8]
    ], play_count: 3
  end

  def test_not_x_of_y
    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.not_x_of_y(1, 2))]], [
      [:a1, 0, 0.5],

      [:a1, 1, 1.5],
      [:b2, 1, 1.5],

      [:a1, 2, 2.5],

      [:a1, 3, 3.5],
      [:b2, 3, 3.5]
    ], play_count: 4

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.not_x_of_y(2, 2))]], [
      [:a1, 0, 0.5],
      [:b2, 0, 0.5],

      [:a1, 1, 1.5],

      [:a1, 2, 2.5],
      [:b2, 2, 2.5],

      [:a1, 3, 3.5]
    ], play_count: 4

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.not_x_of_y(2, 3))]], [
      [:a1, 0, 0.5],
      [:b2, 0, 0.5],

      [:a1, 1, 1.5],

      [:a1, 2, 2.5],
      [:b2, 2, 2.5],

      [:a1, 3, 3.5],
      [:b2, 3, 3.5],

      [:a1, 4, 4.5],

      [:a1, 5, 5.5],
      [:b2, 5, 5.5],

      [:a1, 6, 6.5],
      [:b2, 6, 6.5]
    ], play_count: 7
  end

  def test_every
    es = [
      [:a1, 0, 0.5],
      [:b2, 0, 0.5],

      [:a1, 1, 1.5],

      [:a1, 2, 2.5],
      [:b2, 2, 2.5],

      [:a1, 3, 3.5],

      [:a1, 4, 4.5],
      [:b2, 4, 4.5]
    ]

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.every_other)]], es, play_count: 5
    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.every(2))]], es, play_count: 5

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.every(3))]], [
      [:a1, 0, 0.5],
      [:b2, 0, 0.5],

      [:a1, 1, 1.5],

      [:a1, 2, 2.5],

      [:a1, 3, 3.5],
      [:b2, 3, 3.5],

      [:a1, 4, 4.5],

      [:a1, 5, 5.5],

      [:a1, 6, 6.5],
      [:b2, 6, 6.5]
    ], play_count: 7
  end

  def test_first
    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.first)]], [
      [:a1, 0, 0.5],
      [:b2, 0, 0.5],

      [:a1, 1, 1.5],

      [:a1, 2, 2.5],

      [:a1, 3, 3.5]
    ], play_count: 4

    assert_playback_events QT[[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.not_first)]], [
      [:a1, 0, 0.5],

      [:a1, 1, 1.5],
      [:b2, 1, 1.5],

      [:a1, 2, 2.5],
      [:b2, 2, 2.5],

      [:a1, 3, 3.5],
      [:b2, 3, 3.5]
    ], play_count: 4
  end

  def test_pre
    assert_playback_events QT[:a1, S(:b2, prob: Prob.pre)], [
      [:a1, 0, 1],
      [:b2, 1, 2],
      [:a1, 2, 3],
      [:b2, 3, nil]
    ], play_count: 2
    assert_playback_events QT[:a1, S(:b2, prob: Prob.not_pre)], [
      [:a1, 0, 1],
      [:a1, 2, 3]
    ], play_count: 2

    assert_playback_events QT[:r, S(:b2, prob: Prob.pre)], [], play_count: 2
    assert_playback_events QT[:r, S(:b2, prob: Prob.not_pre)], [
      [:b2, 1, 2],
      [:b2, 3, nil]
    ], play_count: 2

    # Previous steps triggering or not due to a probability
    assert_playback_events QT[S(:a1, prob: Prob.every_other), S(:b2, prob: Prob.pre)], [
      [:a1, 0, 1],
      [:b2, 1, 2],

      # second cycle is skipped

      [:a1, 4, 5],
      [:b2, 5, nil]
    ], play_count: 3
    assert_playback_events QT[S(:a1, prob: Prob.every_other), S(:b2, prob: Prob.not_pre)], [
      [:a1, 0, 1],

      [:b2, 3, 4],

      [:a1, 4, 5]
    ], play_count: 3

    # pre/not_pre in the first slot
    assert_playback_events QT[S(:a1, prob: Prob.pre), :b2], [
      [:b2, 1, 2],

      [:a1, 2, 3],
      [:b2, 3, 4],

      [:a1, 4, 5],
      [:b2, 5, nil]
    ], play_count: 3
    assert_playback_events QT[S(:a1, prob: Prob.not_pre), :b2], [
      [:a1, 0, 1],
      [:b2, 1, 2],

      [:b2, 3, 4],

      [:b2, 5, nil]
    ], play_count: 3

    # Functioning across track swaps
    p = player(QT[:a1])
    es = events do
      p.play

      p.swap_track(QT[S(:b2, prob: Prob.pre)])
      p.play

      p.swap_track(QT[S(:c3, prob: Prob.not_pre)])
      p.play
      p.play
    end
    assert_events es, [
      [:a1, 0, 1],
      [:b2, 1, 2],
      # the first c3 step did not play, but the second did
      [:c3, 3, nil]
    ]
  end

  def test_pre_same_note
    assert_playback_events QT[:c4, S(:c4, prob: Prob.pre_same_note)], [
      [:c4, 0, nil]
    ], play_count: 2
    assert_playback_events QT[:c4, S(:c4, prob: Prob.not_pre_same_note)], [
      [:c4, 0, 1],
      [:c4, 2, 3]
    ], play_count: 2

    assert_playback_events QT[:c4, S(:c4, gate: 0.5, prob: Prob.pre_same_note)], [
      [:c4, 0, 1.5],
      [:c4, 2, 3.5]
    ], play_count: 2
    assert_playback_events QT[:c4, S(:c4, gate: 0.5, prob: Prob.not_pre_same_note)], [
      [:c4, 0, 1],
      [:c4, 2, 3]
    ], play_count: 2

    assert_playback_events QT[:d4, S(:c4, prob: Prob.pre_same_note)], [
      [:d4, 0, 1],
      [:d4, 2, 3]
    ], play_count: 2
    assert_playback_events QT[:d4, S(:c4, prob: Prob.not_pre_same_note)], [
      [:d4, 0, 1],
      [:c4, 1, 2],
      [:d4, 2, 3],
      [:c4, 3, nil]
    ], play_count: 2

    assert_playback_events QT[:r, S(:c4, prob: Prob.pre_same_note)], [], play_count: 2
    assert_playback_events QT[:r, S(:c4, prob: Prob.not_pre_same_note)], [
      [:c4, 1, 2],
      [:c4, 3, nil]
    ], play_count: 2

    # Functioning across track swaps
    p = player(QT[:a1])
    es = events do
      p.play

      p.swap_track(QT[S(:a1, prob: Prob.pre_same_note)])
      p.play

      p.swap_track(QT[S(:c3, prob: Prob.pre_same_note)])
      p.play

      p.swap_track(QT[S(:d4, prob: Prob.not_pre_same_note)])
      p.play
    end
    assert_events es, [
      [:a1, 0, 2],
      [:d4, 3, nil]
    ]
  end

  def test_fill
    assert_playback_events QT[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.fill)], [
      [:a1, 0, 0.5],
      [:a1, 2, 2.5]
    ], play_count: 2
    assert_playback_events QT[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.not_fill)], [
      [:a1, 0, 0.5],
      [:b2, 1, 1.5],
      [:a1, 2, 2.5],
      [:b2, 3, 3.5]
    ], play_count: 2

    assert_playback_events QT[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.fill)], [
      [:a1, 0, 0.5],
      [:b2, 1, 1.5],
      [:a1, 2, 2.5],
      [:b2, 3, 3.5]
    ], play_count: 2, fill: true
    assert_playback_events QT[S(:a1, gate: 0.5), S(:b2, gate: 0.5, prob: Prob.not_fill)], [
      [:a1, 0, 0.5],
      [:a1, 2, 2.5]
    ], play_count: 2, fill: true

    # Changing fill on the same player
    p = player(QT[S(:a1, gate: 0.5, prob: Prob.fill), S(:b2, gate: 0.5, prob: Prob.not_fill)])
    es = events do
      p.play

      p.fill = true
      p.play

      p.fill = false
      p.play
    end
    assert_events es, [
      [:b2, 1, 1.5],
      [:a1, 2, 2.5],
      [:b2, 5, 5.5]
    ]
  end

  def test_custom
    # All the other probabilities exercise this functionality, so this is just
    # a spot check.

    pred = ->(cycle:, fill:) { cycle == 1 || fill }
    t = QT[:a1, S(:b2, prob: Prob.custom(pred))]
    assert_playback_events t, [
      [:a1, 0, 1],

      [:a1, 2, 3],
      [:b2, 3, 4],

      [:a1, 4, 5]
    ], play_count: 3

    assert_playback_events t, [
      [:a1, 0, 1],
      [:b2, 1, 2],

      [:a1, 2, 3],
      [:b2, 3, 4],

      [:a1, 4, 5],
      [:b2, 5, nil]
    ], play_count: 3, fill: true

    # Validity checks on custom predicates
    # rubocop:disable Lint/UnusedBlockArgument
    assert_raises(ArgumentError) { Prob.custom(->(x) { true }) }  # positional arguments are invalid
    assert_raises(ArgumentError) { Prob.custom(->(x = 2) { true }) }  # even optional ones
    assert_raises(ArgumentError) { Prob.custom(->(cycle:, nonsense:) { true }) }
    assert_nothing_raised { Prob.custom(->(cycle:, nonsense: false) { true }) }  # this is ok because the invalid kwarg is optional
    # rubocop:enable Lint/UnusedBlockArgument
  end

  def assert_repr(p)
    roundtrip = eval(p.repr)  # rubocop:disable Security/Eval
    assert_equal roundtrip, p
  end

  def test_repr
    # Just spot-checks
    assert_repr Prob.every_other
    assert_repr Prob.x_of_y(2, 5)
    assert_repr Prob.chance(0.25)

    assert_raises(ArgumentError) { Prob.custom(->{ true }).repr }
    assert_nothing_raised { Prob.custom(->{ true }).repr(safe: true) }
  end

  def test_eql
    assert_equal Prob.every_other, Prob.every_other
    assert_equal Prob.every(5), Prob.every(5)
    assert_equal Prob.chance(0.25), Prob.chance(0.25)
    assert_equal Prob.x_of_y(1, 3), Prob.x_of_y(1, 3)

    custom = Prob.custom(->{ true })
    assert_equal custom, custom

    assert Prob.chance(0.25) != Prob.chance(0.2)
    assert Prob.pre != "nope"
  end
end
