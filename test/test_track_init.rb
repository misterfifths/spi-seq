#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/track_helpers"
require_relative "../lib/spiseq/theory/arp"
require_relative "../lib/spiseq/theory/notelength"
require_relative "../lib/spiseq/tracks/track"

include SpiSeq::Theory
include SpiSeq::Tracks

# Test simple Track initialization, Track.new and Track.rest.
class TrackInitTest < Test::Unit::TestCase
  include TrackHelpers

  def test_simple
    assert_grid T[[:a1]], [[:a1]]
    assert_grid T[:a1], [[:a1]]
    assert_grid T[[:a1, :b2]], [[:a1, :b2]]
    assert_grid T[[:a1, :b2], [:c3]], [[:a1, :b2], [:c3]]
    assert_grid T[[:a1, :b2], :c3], [[:a1, :b2], [:c3]]
    assert_grid T[:a1, :b2, :c3], [[:a1], [:b2], [:c3]]

    assert_raises { T[] }
    assert_raises(ArgumentError) { T[false] }
    assert_raises(ArgumentError) { T[[false]] }
  end

  def test_enums
    assert_grid T[60...65], [[:c4, :cs4, :d4, :ds4, :e4]]
    assert_grid T.from_grid(60...65), [[:c4], [:cs4], [:d4], [:ds4], [:e4]]

    return unless in_sonic_pi?

    # Make sure things work with Sonic Pi's wrapped enumerables.
    cmaj = SpiSeq::External::Theory.chord(:c4, :major)
    assert_grid T[cmaj], [[:c4, :e4, :g4]]
    assert_grid T.from_grid(cmaj), [[:c4], [:e4], [:g4]]

    ring_slot = SpiSeq::External::Enumerables.ring(:c4, :c5)
    assert_grid T[ring_slot], [[:c4, :c5]]
    ring_grid = SpiSeq::External::Enumerables.ring(ring_slot, ring_slot)
    assert_grid T.from_grid(ring_grid), [[:c4, :c5], [:c4, :c5]]
  end

  def test_zero_gate
    # Steps with a zero gate are maintained, though they will not play.
    assert_grid T[S(:c4, gate: 0), S(:c5, gate: 0)],
                [[S(:c4, gate: 0)], [S(:c5, gate: 0)]]
    assert_grid T[:c4, :c5].gate(0),
                [[S(:c4, gate: 0)], [S(:c5, gate: 0)]]
    assert_grid T[S(:c4, gate: 0), S(:c5, gate: 0)].gate(1), [[:c4], [:c5]]
  end

  def test_from_grid
    assert_grid Track.from_grid(:r), [[]]
    assert_grid Track.from_grid([]), [[]]
    assert_grid Track.from_grid([[:a1]]), [[:a1]]
    assert_grid Track.from_grid(:a1), [[:a1]]
    assert_grid Track.from_grid([:a1]), [[:a1]]
    assert_grid Track.from_grid([[:a1, :b2]]), [[:a1, :b2]]
    assert_grid Track.from_grid([[:a1, :b2], [:c3]]), [[:a1, :b2], [:c3]]
    assert_grid Track.from_grid([[:a1, :b2], :c3]), [[:a1, :b2], [:c3]]
    assert_grid Track.from_grid([:a1, :b2, :c3]), [[:a1], [:b2], [:c3]]

    # Make sure the alias works
    assert_grid Tg([:a1, :b2, :c3]), [[:a1], [:b2], [:c3]]
  end

  def test_granularity_and_timescale
    assert_gt T[:a1], :eighth, 1

    [:whole, NoteLength::Whole, 4].each do |grain|
      assert_gt T[:a1, granularity: grain], :whole, 1
    end

    assert_gt T[:a1, timescale: 2], :eighth, 2
    assert_gt T[:a1, granularity: 0.25, timescale: 0.5], :sixteenth, 0.5
  end

  def test_explicit_steps
    s1 = S(:a1)
    s2 = S(:b2, gate: 0.5)
    s3 = S(:c3, gate: 0.25, vel: 64)
    s4 = S(:d4, gate: 0.1, vel: 32, prob: Prob.one_in(4))
    assert_grid T[[s1]], [[s1]]
    assert_grid T[s1], [[s1]]
    assert_grid T[[s1, s2]], [[s1, s2]]
    assert_grid T[[s1, s2], [s3]], [[s1, s2], [s3]]
    assert_grid T[[s1, s2], [s3, s4]], [[s1, s2], [s3, s4]]
    assert_grid T[s1, s2, [s3, s4]], [[s1], [s2], [s3, s4]]
  end

  def test_rests
    assert_grid T[[]], [[]]
    assert_grid T[[], [:a2]], [[], [:a2]]
    assert_grid T[[], :a2], [[], [:a2]]

    [:r, :rest, nil].each do |rest|
      assert_grid T[[rest]], [[]]
      assert_grid T[rest], [[]]

      assert_grid T[[rest, rest, rest]], [[]]
      assert_grid T[[rest, rest, rest, :c4]], [[:c4]]
      assert_grid T[[rest], [rest], [rest]], [[], [], []]
      assert_grid T[rest, [rest], rest], [[], [], []]
      assert_grid T[rest, rest, rest], [[], [], []]

      assert_grid T[[:a1], [rest], [:a2]], [[:a1], [], [:a2]]
      assert_grid T[[:a1], rest, [:a2, rest]], [[:a1], [], [:a2]]
      assert_grid T[:a1, rest, :a2], [[:a1], [], [:a2]]
    end

    assert_grid Track.rest, [[]]
    assert_grid Track.rest(2), [[], []]

    assert_grid T[:c4, :c4].clear, [[], []]
    assert_grid T[[:c4, :d4]].clear, [[]]
    assert_grid Track.rest(3).clear, [[], [], []]
    assert_gt T[:c4, granularity: :whole, timescale: 2].clear, :whole, 2
  end

  def test_dupe_notes
    assert_grid T[[:c4, :c4]], [[:c4]]
    assert_grid T[[S(:c4, gate: 0.5), :c4]], [[:c4]]
    assert_grid T[[S(:c4, gate: 0.5), S(:c4, gate: 0.75)]], [[S(:c4, gate: 0.75)]]

    assert_grid T[[:cs4, :db4]], [[:cs4]]
    assert_grid T[[S(:cs4, gate: 0.5), :db4]], [[:cs4]]
    assert_grid T[[S(:cs4, gate: 0.5), S(:df4, gate: 0.75)]], [[S(:cs4, gate: 0.75)]]
    assert_grid T[[:cs4, :df4, :db4]], [[:cs4]]
  end

  def test_isorhythm
    ns = [:a1, :b2, :c3, :d4]

    assert_gt Track.iso(ns, [1]), :eighth, 1
    assert_gt Track.iso(ns, [1], granularity: :sixteenth), :sixteenth, 1
    assert_gt Track.iso(ns, [1], timescale: 2), :eighth, 2

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

  def test_arp
    directions = [:up, :alterninout]
    spreads = (0..2).to_a
    extra_octaves = [[], [1], [-2, 1]]
    ns = %i[c4 c6 c5]

    directions.each do |direction|
      spreads.each do |spread|
        extra_octaves.each do |extra_octaves|
          # With no Euclid stuff, arp should just act like making a track with
          # the result of the arpeggiated notes.
          arped_ns = Arp.arpeggiate(ns, direction, spread:, extra_octaves:)
          assert_grid Track.arp(ns, direction, spread:, extra_octaves:),
                      Track.new(*arped_ns).grid

          0.upto(4) do |pulses|
            1.upto(3) do |length|
              0.upto(3) do |rotate|
                # With Euclid arguments, acts like applying Track.euclid to the
                # arpeggiated notes.
                arp_track = Track.arp(ns, direction, spread:, extra_octaves:,
                                      pulses:, length:, rotate:)
                euc_track = Track.euclid(arped_ns, pulses, length, rotate:, full_cycle: true)
                assert_grid arp_track, euc_track.grid

                arp_track = Track.arp(ns, direction, spread:, extra_octaves:,
                                      pulses:, length:, rotate:, full_cycle: false)
                euc_track = Track.euclid(arped_ns, pulses, length, rotate:)
                assert_grid arp_track, euc_track.grid
              end
            end
          end
        end
      end
    end

    assert_gt Track.arp([:c4], granularity: :whole), :whole, 1
    assert_gt Track.arp([:c4], timescale: 2), :eighth, 2
    assert_gt Track.arp([:c4], granularity: :half, timescale: 2), :half, 2
  end
end
