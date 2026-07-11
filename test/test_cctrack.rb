#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/track_helpers"
require_relative "../lib/spiseq/math/curves"
require_relative "../lib/spiseq/tracks/cctrack"
require_relative "../lib/spiseq/tracks/track"

class CCTrackTest < Test::Unit::TestCase
  include TrackHelpers
  include SpiSeq::Math
  include SpiSeq::Tracks

  def assert_grid(track, slots)
    assert_equal track.length, slots.length, "grid length mismatch between #{track.repr} and #{slots.inspect}"

    i = 0
    track.grid.zip(slots) do |actual_slot, expected_slot|
      assert_equal expected_slot.length, actual_slot.length, "slot #{i} length mismatch: expected #{expected_slot.inspect}, got #{actual_slot.inspect}, track: #{track.repr}"
      expected_slot.each do |step|
        assert actual_slot.include?(step), "no CCStep in slot #{i} matched #{step.inspect}, track: #{track.repr}"
      end
      i += 1
    end
  end

  def test_basics
    a = CC(1, 1)
    b = CC(2, 2)
    c = CC(3, 3)

    assert_grid CCT[[a]], [[a]]
    assert_grid CCT[a], [[a]]
    assert_grid CCT[[a, b]], [[a, b]]
    assert_grid CCT[[a, b], [c]], [[a, b], [c]]
    assert_grid CCT[[a, b], c], [[a, b], [c]]
    assert_grid CCT[a, b, c], [[a], [b], [c]]
    assert_grid CCT.from_grid([a, b, c]), [[a], [b], [c]]
    assert_grid CCTg([a, b, c]), [[a], [b], [c]]

    assert_raises { CCT[] }
    assert_raises(ArgumentError) { CCT[:c4] }
    assert_raises(ArgumentError) { CCT[[:c4]] }
    assert_raises(ArgumentError) { CCT.from_grid([[:c4]]) }
  end

  def test_dupe_numbers
    low = CC(1, 1)
    high = CC(1, 127)

    assert_grid CCT[[low, high]], [[high]]
    assert_grid CCT[[low, high, high]], [[high]]
  end

  def test_simple
    a = CC(5, 1)
    b = CC(5, 2)
    c = CC(5, 3)

    assert_grid CCTrack.simple(5, [1, 2, 3]), [[a], [b], [c]]
    assert_grid CCTrack.simple(5, [1, :r, 2]), [[a], [], [b]]

    x = CC(50, 50)
    assert_grid CCTrack.simple(5, [1, x, 3]), [[a], [x], [c]]

    assert_raises(TypeError) { CCTrack.simple(5, [:nope]) }
  end

  def test_track_to_cc
    t = T[:c4, :r, :d4, :c5]
    a = CC(5, 1)
    b = CC(6, 2)
    c = CC(7, 3)
    d = CC(8, 4)
    opts = [a, b, c, d]

    # Single step -> one-step slot
    cct = t.to_cc do |slot, i|
      slot.empty? ? :r : opts[i]
    end
    assert_grid cct, [[a], [], [c], [d]]

    # Multiple steps -> a slot with those elements
    cct = t.to_cc do |slot, _|
      next [] if slot.empty?
      (slot[0].note.pitch_class == :c) ? [a, b] : c
    end
    assert_grid cct, [[a, b], [], [c], [a, b]]

    # Gridish -> expanded into multiple slots
    cct = t.to_cc do |slot, _|
      next [] if slot.empty?
      (slot[0].note.pitch_class == :c) ? [[a], [b, d]] : c
    end
    assert_grid cct, [[a], [b, d], [], [c], [a], [b, d]]
  end

  def test_track_to_simple_cc
    t = T[:c4, :r, :d4, :c5]
    a = CC(5, 1)
    b = CC(5, 2)
    c = CC(5, 3)
    d = CC(5, 4)

    # Single number -> one-step slot
    cct = t.to_simple_cc(5) do |slot, i|
      slot.empty? ? :r : i + 1
    end
    assert_grid cct, [[a], [], [c], [d]]

    # Multiple numbers -> expanded into multiple slots
    cct = t.to_simple_cc(5) do |slot, _|
      next [] if slot.empty?
      (slot[0].note.pitch_class == :c) ? [1, 2] : 3
    end
    assert_grid cct, [[a], [b], [], [c], [a], [b]]
  end

  def test_add_curve
    t = CCTrack.rest(7)
    t = t.add_curve(1, 20, 60, Curves::UpLinear, 1, 3)
    assert_grid t, [
      [],
      [CC(1, 20)],
      [CC(1, 40)],
      [CC(1, 60)],
      [],
      [],
      []
    ]

    t = t.add_curve(2, 0, 60, Curves::DownLinear, 0, 6)
    assert_grid t, [
      [CC(2, 60)],
      [CC(1, 20), CC(2, 50)],
      [CC(1, 40), CC(2, 40)],
      [CC(1, 60), CC(2, 30)],
      [CC(2, 20)],
      [CC(2, 9)],  # rounding error
      [CC(2, 0)]
    ]
  end

  def test_curve
    # curve should function like add_curve over the whole track
    t = CCTrack.curve(127, 50, 80, Curves::UpLinear, 8)
    u = CCTrack.rest(8).add_curve(127, 50, 80, Curves::UpLinear, 0, 7)
    assert_grid t, u.grid

    t = CCTrack.curve(127, 0, 100, Curves::UpDown2Sine, 16)
    u = CCTrack.rest(16).add_curve(127, 0, 100, Curves::UpDown2Sine, 0, 15)
    assert_grid t, u.grid
  end

  def test_repr
    a = CC(1, 1)
    b = CC(2, 2)
    c = CC(3, 3)

    assert_repr CCT[:r]
    assert_repr CCT[a]
    assert_repr CCT[a, b]
    assert_repr CCT[a, :r, b]
    assert_repr CCT[[a, b], :r, c]

    assert_repr CCT[a, granularity: :whole]
    assert_repr CCT[a, granularity: :whole, timescale: 2]

    assert_repr CCT[a.accum(1)]
    assert_repr CCT[a.accum(1, min: -5)]
    assert_repr CCT[a.accum(1, min: -5, max: 22)]
    assert_repr CCT[a.accum(1, min: -5, max: 22, mode: :freeze)]

    # Prob spot-checks
    assert_repr CCT[a.with_prob(Prob.every_other).accum(1, min: -5, max: 22, mode: :freeze)]
    assert_repr CCT[a.with_prob(Prob.x_of_y(2, 5)).accum(1, min: -5, max: 22, mode: :freeze)]
    assert_repr CCT[a.with_prob(0.25).accum(1, min: -5, max: 22, mode: :freeze)]

    # Custom probs
    p = Prob.custom(-> { true })
    assert_raises(ArgumentError) { CCT[a.with_prob(p)].repr }
    assert_nothing_raised { CCT[a.with_prob(p)].repr(safe: true) }
    assert_raises(ArgumentError) { CCT[a.accum(1, prob: p)].repr }
    assert_nothing_raised { CCT[a.accum(1, prob: p)].repr(safe: true) }
  end

  def test_enums
    a = CC(127, 5)
    b = CC(127, 10)
    steps = [a, b].lazy.cycle.take(5)
    assert_grid CCT[steps], [[b]]  # duplicate CC numbers collapsed
    assert_grid CCT.from_grid(steps), [[a], [b], [a], [b], [a]]
  end
end
