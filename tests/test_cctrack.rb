#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../track"
require_relative "../cctrack"
require_relative "../math/curves"

class CCTrackTest < Test::Unit::TestCase
  def equal_steps?(a, b)
    a.cc == b.cc &&
      a.val == b.val &&
      a.prob.to_s == b.prob.to_s  # TODO: this is a crappy way to test Prob equality
  end

  def assert_grid(track, slots)
    assert_equal track.length, slots.length, "grid length mismatch between #{track.repr} and #{slots.inspect}"

    track.grid.each_with_index do |slot, slot_idx|
      target_slot = slots[slot_idx]
      assert_equal slot.length, target_slot.length, "slot #{slot_idx} length mismatch: expected #{slot.inspect}, got #{target_slot.inspect}, track: #{track.repr}"

      # Step order is not significant and may be changed by the initializer, so
      # we need to check each target step against all steps in the track's slot.
      candidates = slot.dup
      target_slot.each do |step|
        winning_idx = candidates.index { |candstep| equal_steps?(candstep, step) }
        refute_nil winning_idx, "no Step in slot #{slot_idx} matched #{step.inspect}, track: #{track.repr}"
        candidates.delete_at(winning_idx)
      end
    end
  end

  def test_basics
    a = CC(1, 1)
    b = CC(2, 2)
    c = CC(3, 3)

    assert_grid CCT([[a]]), [[a]]
    assert_grid CCT([a]), [[a]]
    assert_grid CCT(a), [[a]]
    assert_grid CCT([[a, b]]), [[a, b]]
    assert_grid CCT([[a, b], [c]]), [[a, b], [c]]
    assert_grid CCT([[a, b], c]), [[a, b], [c]]
    assert_grid CCT([a, b, c]), [[a], [b], [c]]

    assert_raises { CCT([]) }
  end

  def test_dupe_numbers
    low = CC(1, 1)
    high = CC(1, 127)

    assert_grid CCT([[low, high]]), [[high]]
    assert_grid CCT([[low, high, high]]), [[high]]
  end

  def test_simple
    a = CC(5, 1)
    b = CC(5, 2)
    c = CC(5, 3)

    assert_grid CCTrack.simple(5, [1, 2, 3]), [[a], [b], [c]]
    assert_grid CCTrack.simple(5, [1, :r, 2]), [[a], [], [b]]

    x = CC(50, 50)
    assert_grid CCTrack.simple(5, [1, x, 3]), [[a], [x], [c]]
  end

  def test_track_to_cc
    t = T([:c4, :r, :d4, :c5])
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
    t = T([:c4, :r, :d4, :c5])
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
end
