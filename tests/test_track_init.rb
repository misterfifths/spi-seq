#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../track"
require_relative "track_test_helpers"

# TODO: Test arp initializer.

# Test simple Track initialization, Track.new and Track.rest.
class TrackInitTest < Test::Unit::TestCase
  include TrackTestHelpers

  def test_simple
    assert_grid T([[:a1]]), [[:a1]]
    assert_grid T([:a1]), [[:a1]]
    assert_grid T(:a1), [[:a1]]
    assert_grid T([[:a1, :b2]]), [[:a1, :b2]]
    assert_grid T([[:a1, :b2], [:c3]]), [[:a1, :b2], [:c3]]
    assert_grid T([[:a1, :b2], :c3]), [[:a1, :b2], [:c3]]
    assert_grid T([:a1, :b2, :c3]), [[:a1], [:b2], [:c3]]

    assert_raises { T([]) }
  end

  def test_granularity_and_timescale
    assert_gt T(:a1), NoteLength::Eighth, 1

    [:whole, NoteLength::Whole, 4].each do |grain|
      assert_gt T(:a1, granularity: grain), NoteLength::Whole, 1
    end

    assert_gt T(:a1, timescale: 2), NoteLength::Eighth, 2
    assert_gt T(:a1, granularity: 0.25, timescale: 0.5), NoteLength::Sixteenth, 0.5
  end

  def test_explicit_steps
    s1 = S(:a1)
    s2 = S(:b2, gate: 0.5)
    s3 = S(:c3, gate: 0.25, vel: 64)
    s4 = S(:d4, gate: 0.1, vel: 32, prob: Prob.one_in(4))
    assert_grid T([[s1]]), [[s1]]
    assert_grid T([s1]), [[s1]]
    assert_grid T(s1), [[s1]]
    assert_grid T([[s1, s2]]), [[s1, s2]]
    assert_grid T([[s1, s2], [s3]]), [[s1, s2], [s3]]
    assert_grid T([[s1, s2], [s3, s4]]), [[s1, s2], [s3, s4]]
    assert_grid T([s1, s2, [s3, s4]]), [[s1], [s2], [s3, s4]]
  end

  def test_rests
    assert_grid T([[]]), [[]]
    assert_grid T([[], [:a2]]), [[], [:a2]]
    assert_grid T([[], :a2]), [[], [:a2]]

    [:r, :rest, nil].each do |rest|
      assert_grid T([[rest]]), [[]]
      assert_grid T([rest]), [[]]
      assert_grid T(rest), [[]]

      assert_grid T([[rest, rest, rest]]), [[]]
      assert_grid T([[rest, rest, rest, :c4]]), [[:c4]]
      assert_grid T([[rest], [rest], [rest]]), [[], [], []]
      assert_grid T([rest, [rest], rest]), [[], [], []]
      assert_grid T([rest, rest, rest]), [[], [], []]

      assert_grid T([[:a1], [rest], [:a2]]), [[:a1], [], [:a2]]
      assert_grid T([[:a1], rest, [:a2, rest]]), [[:a1], [], [:a2]]
      assert_grid T([:a1, rest, :a2]), [[:a1], [], [:a2]]
    end

    assert_grid Track.rest, [[]]
    assert_grid Track.rest(2), [[], []]

    assert_grid T([:c4, :c4]).clear, [[], []]
    assert_grid T([[:c4, :d4]]).clear, [[]]
    assert_grid Track.rest(3).clear, [[], [], []]
    assert_gt T(:c4, granularity: :whole, timescale: 2).clear, :whole, 2
  end

  def test_dupe_notes
    assert_grid T([[:c4, :c4]]), [[:c4]]
    assert_grid T([[S(:c4, gate: 0.5), :c4]]), [[:c4]]
    assert_grid T([[S(:c4, gate: 0.5), S(:c4, gate: 0.75)]]), [[S(:c4, gate: 0.75)]]

    assert_grid T([[:cs4, :db4]]), [[:cs4]]
    assert_grid T([[S(:cs4, gate: 0.5), :db4]]), [[:cs4]]
    assert_grid T([[S(:cs4, gate: 0.5), S(:df4, gate: 0.75)]]), [[S(:cs4, gate: 0.75)]]
    assert_grid T([[:cs4, :df4, :db4]]), [[:cs4]]
  end

  def test_isorhythm
    ns = [:a1, :b2, :c3, :d4]

    assert_gt Track.iso(ns, [1]), NoteLength::Eighth, 1
    assert_gt Track.iso(ns, [1], granularity: :sixteenth), NoteLength::Sixteenth, 1
    assert_gt Track.iso(ns, [1], timescale: 2), NoteLength::Eighth, 2

    # Single runs, even division.
    assert_grid Track.iso(ns, [1]), [[:a1], [:b2], [:c3], [:d4]]
    assert_grid Track.iso(ns, [0.5]), [
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.5)],
      [S(:c3, gate: 0.5)],
      [S(:d4, gate: 0.5)]
    ]
    assert_grid Track.iso(ns, [1, 0]), [
      [:a1], [],
      [:b2], [],
      [:c3], [],
      [:d4], []
    ]
    assert_grid Track.iso(ns, [1, 0.5]), [
      [:a1], [S(:a1, gate: 0.5)],
      [:b2], [S(:b2, gate: 0.5)],
      [:c3], [S(:c3, gate: 0.5)],
      [:d4], [S(:d4, gate: 0.5)]
    ]
    assert_grid Track.iso(ns, [1, 1]), [
      [:a1], [:a1],
      [:b2], [:b2],
      [:c3], [:c3],
      [:d4], [:d4]
    ]

    # Multiple runs, even division.
    assert_grid Track.iso(ns, [0.5, 0.25]), [
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.25)],

      [S(:c3, gate: 0.5)],
      [S(:d4, gate: 0.25)]
    ]
    assert_grid Track.iso(ns, [0.5, 0.25, 0.1, 1]), [
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.25)],
      [S(:c3, gate: 0.1)],
      [S(:d4, gate: 1)]
    ]
    assert_grid Track.iso(ns, [0.5, 1, 0.25, 0, 1, 0, 1]), [
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 1)],
      [S(:b2, gate: 0.25)],
      [],
      [S(:c3, gate: 1)],
      [],
      [S(:d4, gate: 1)]
    ]

    # Multiple runs, uneven division
    assert_grid Track.iso(ns, [0.5, 0.25, 0, 0.1]), [
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.25)],
      [],
      [S(:c3, gate: 0.1)],

      [S(:d4, gate: 0.5)],
      [S(:a1, gate: 0.25)],
      [],
      [S(:b2, gate: 0.1)],

      [S(:c3, gate: 0.5)],
      [S(:d4, gate: 0.25)],
      [],
      [S(:a1, gate: 0.1)],

      [S(:b2, gate: 0.5)],
      [S(:c3, gate: 0.25)],
      [],
      [S(:d4, gate: 0.1)]
    ]

    # gates longer than notes, uneven division
    assert_grid Track.iso(ns, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0]), [
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.5)],
      [S(:c3, gate: 0.5)],
      [S(:d4, gate: 0.5)],
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.5)],
      [],

      [S(:c3, gate: 0.5)],
      [S(:d4, gate: 0.5)],
      [S(:a1, gate: 0.5)],
      [S(:b2, gate: 0.5)],
      [S(:c3, gate: 0.5)],
      [S(:d4, gate: 0.5)],
      []
    ]

    # Boolean gates
    assert_grid Track.iso(ns, [true, false, false]), [
      [:a1], [], [],
      [:b2], [], [],
      [:c3], [], [],
      [:d4], [], []
    ]
  end

  def test_euclid
    assert_raises { Track.euclid([:c4], "nope", 2) }
    assert_raises { Track.euclid([:c4], 2, "nope") }
    assert_raises { Track.euclid([:c4], 2, 3, rotate: "nope") }

    assert_raises { Track.euclid([:c4], -1, 2) }
    assert_raises { Track.euclid([:c4], 2, -1) }

    assert_raises { Track.euclid([], 3, 4) }

    # We should gridify a single stepish thing.
    assert_grid Track.euclid(:c4, 2, 2), [[:c4], [:c4]]

    assert_grid Track.euclid([:a1], 3, 4), [[:a1], [], [:a1], [:a1]]
    assert_grid Track.euclid([:a1, :b2], 3, 4), [[:a1], [], [:b2], [:a1]]
    assert_grid Track.euclid([:a1, [:b2, :c3]], 3, 4), [[:a1], [], [:b2, :c3], [:a1]]

    assert_grid Track.euclid([:a1, :b2], 3, 4, rotate: 1), [[], [:a1], [:b2], [:a1]]
    assert_grid Track.euclid([:a1, :b2], 3, 4, rotate: 2), [[:a1], [:b2], [:a1], []]

    assert_grid Track.euclid([:a1], 3, 4, invert: true), [[], [:a1], [], []]
    assert_grid Track.euclid([:a1], 3, 4, invert: true, rotate: 1), [[:a1], [], [], []]

    assert_grid Track.euclid([:a1, :b2, :c3, :d4], 3, 4), [[:a1], [], [:b2], [:c3]]
    assert_grid Track.euclid([:a1, :b2, :c3, :d4], 3, 4, cycle: false), [[:a1], [], [:c3], [:d4]]
    assert_grid Track.euclid([:a1, :b2, :c3, :d4], 3, 4, full_cycle: true), [
      [:a1], [], [:b2], [:c3],
      [:d4], [], [:a1], [:b2],
      [:c3], [], [:d4], [:a1],
      [:b2], [], [:c3], [:d4]
    ]
    # full_cycle always implies cycle
    assert_grid Track.euclid([:a1, :b2, :c3, :d4], 3, 4, cycle: false, full_cycle: true), [
      [:a1], [], [:b2], [:c3],
      [:d4], [], [:a1], [:b2],
      [:c3], [], [:d4], [:a1],
      [:b2], [], [:c3], [:d4]
    ]

    assert_gt Track.euclid([:c4], 3, 4, granularity: :whole), :whole, 1
    assert_gt Track.euclid([:c4], 3, 4, timescale: 2), :eighth, 2
    assert_gt Track.euclid([:c4], 3, 4, granularity: :half, timescale: 2), :half, 2
  end
end
