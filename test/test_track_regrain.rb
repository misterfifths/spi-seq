#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/track_helpers"
require_relative "../lib/spiseq/theory/notelength"
require_relative "../lib/spiseq/tracks/track"

# Test Track's methods for regranularizing.
class TrackRegrainTest < Test::Unit::TestCase
  include TrackHelpers
  include SpiSeq::Theory
  include SpiSeq::Tracks

  def test_expand
    x = T[S(:a1, gate: 0.25), S(:b1, gate: 0.5), S(:c1, gate: 0.75), :d1]

    t = x.expand
    assert_gt t, :sixteenth, 1
    assert_grid t, [
      [S(:a1, gate: 0.5)], [],
      [:b1], [],
      [:c1], [S(:c1, gate: 0.5)],
      [:d1], [:d1]
    ]

    t = t.expand
    assert_gt t, :thirty_second, 1
    assert_grid t, [
      [:a1], [], [], [],
      [:b1], [:b1], [], [],
      [:c1], [:c1], [:c1], [],
      [:d1], [:d1], [:d1], [:d1]
    ]
    oneshot = x.expand(2)
    assert_grid t, oneshot.grid
    assert_gt t, oneshot.granularity, oneshot.timescale

    t = t.expand
    assert_gt t, :sixty_fourth, 1
    oneshot = x.expand(3)
    assert_grid t, oneshot.grid
    assert_gt t, oneshot.granularity, oneshot.timescale

    assert_raises { t.expand }


    # Probabilities should only go to the second step if one expands to two
    # slots.
    t = T[S(:a1, gate: 0.5, prob: Prob.fill), S(:b1, prob: Prob.fill)]
    t = t.expand
    assert_grid t, [
      [S(:a1, prob: Prob.fill)], [],
      [:b1], [S(:b1, prob: Prob.fill)]
    ]
  end

  def test_condense
    x = T[[:a1], [], [], [],
          [:b1], [:b1], [], [],
          [:c1], [:c1], [:c1], [],
          [:d1], [:d1], [:d1], [:d1]]

    t = x.condense
    assert_gt t, :quarter, 1
    assert_grid t, [
      [S(:a1, gate: 0.5)], [],
      [:b1], [],
      [:c1], [S(:c1, gate: 0.5)],
      [:d1], [:d1]
    ]

    t = t.condense
    assert_gt t, :half, 1
    assert_grid t, [
      [S(:a1, gate: 0.25)],
      [S(:b1, gate: 0.5)],
      [S(:c1, gate: 0.75)],
      [:d1]
    ]
    oneshot = x.condense(2)
    assert_grid t, oneshot.grid
    assert_gt t, oneshot.granularity, oneshot.timescale

    t = t.condense
    assert_gt t, :whole, 1
    oneshot = x.condense(3)
    assert_grid t, oneshot.grid
    assert_gt t, oneshot.granularity, oneshot.timescale

    assert_raises { t.condense }


    # Steps that only appear in odd-indexed slots disappear.
    t = T[:a1, :b1, :c1].condense
    assert_grid t, [[S(:a1, gate: 0.5)], [S(:c1, gate: 0.5)]]


    # When condensing two steps into one, the probability and velocity of the
    # first are the ones that win.
    t = T[S(:a1, prob: Prob.fill, vel: 64),
          S(:a1, gate: 0.5, prob: Prob.every_other, vel: 99)]
    t = t.condense
    assert_grid t, [[S(:a1, gate: 0.75, prob: Prob.fill, vel: 64)]]
  end

  def test_regranularize
    t = T[S(:a1, gate: 0.25), S(:b1, gate: 0.5), S(:c1, gate: 0.75), :d1]

    t = t.regrain(:thirty_second)
    assert_gt t, :thirty_second, 1
    assert_grid t, [
      [:a1], [], [], [],
      [:b1], [:b1], [], [],
      [:c1], [:c1], [:c1], [],
      [:d1], [:d1], [:d1], [:d1]
    ]

    t = t.regrain(:eighth)
    assert_gt t, :eighth, 1
    assert_grid t, [[S(:a1, gate: 0.25)], [S(:b1, gate: 0.5)], [S(:c1, gate: 0.75)], [:d1]]
  end
end
