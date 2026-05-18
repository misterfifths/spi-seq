#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../theory/chord"
require_relative "../extapi"

class ChordVoicingTest < Test::Unit::TestCase
  MAJOR_CHORD_DEGREES = [
    :major,
    :minor,
    :minor,
    :major,
    :major,
    :minor,
    :dim
  ].freeze

  SCALE_ROTATIONS = {
    major: 0,
    dorian: 1,
    phrygian: 2,
    lydian: 3,
    mixolydian: 4,
    aeolian: 5,
    minor: 5,
    locrian: 6
  }.freeze

  def _test_one_diatonic_degree(chord_root, chord_name, degree, tonic, scale_name, degree_rotation)
    assert_msg = "#{tonic} #{scale_name} deg #{degree} => #{chord_root}#{chord_name} (rotation #{degree_rotation})"

    expected_chord = Chord.voiced(chord_root, chord_name)

    # The triads should agree; after that things diverge.
    degree_chord = Chord.degree(degree, tonic, scale_name, 3)
    assert_equal expected_chord, degree_chord, assert_msg

    # Inversions on the triads should work
    0.upto(2) do |i|
      expected_chord = Chord.voiced(chord_root, chord_name, invert: i)
      degree_chord = Chord.degree(degree, tonic, scale_name, 3, invert: i)
      assert_equal expected_chord, degree_chord
    end

    # Note count should work
    1.upto(7) do |i|
      assert_equal Chord.degree(degree, tonic, scale_name, i).length, i
    end

    # All notes should be a major or minor 3rd (4 or 3 semitones) apart.
    degree_chord = Chord.degree(degree, tonic, scale_name, 7)
    degree_chord.each_cons(2) do |a, b|
      assert (b - a) == 3 || (b - a) == 4, "#{assert_msg}: expected #{b} and #{a} to be a third apart"
    end

    # Sonic Pi is the source of truth.
    if ExtApi.in_sonic_pi?
      1.upto(7) do |i|
        spi_notes = ExtApi.spi_call(:chord_degree, degree, tonic, scale_name, i).to_a.map { |n| N(n) }
        degree_chord = Chord.degree(degree, tonic, scale_name, i)

        # Sonic Pi seems to limit results to 2 octaves. Doesn't seem worth
        # emulating that behavior; we prefer to return the number of notes the
        # user asked for. Just drop any extra notes we were able to make.
        degree_chord = degree_chord.take(spi_notes.length) if spi_notes.length != i
        assert_equal spi_notes, degree_chord, "#{assert_msg}, #{i} notes"

        # Inversion will only match if they returned as many notes as us.
        next unless spi_notes.length == i
        1.upto(i - 1) do |invert|
          spi_notes = ExtApi.spi_call(:chord_degree, degree, tonic, scale_name, i, invert: invert).to_a.map { |n| N(n) }
          degree_chord = Chord.degree(degree, tonic, scale_name, i, invert: invert)
          assert_equal spi_notes, degree_chord, "#{assert_msg}, #{invert} inversions"
        end
      end
    end
  end

  def test_diatonic_degree
    SCALE_ROTATIONS.each do |scale_name, r|
      chords = MAJOR_CHORD_DEGREES.rotate(r)

      # Not worth testing beyond degree 7.
      1.upto(7) do |degree|
        0.upto(12) do |tonic_shift|
          tonic = N(:c4) + tonic_shift
          scale = Scale.full_scale(tonic, scale_name)
          root_note = scale.degree(degree, relative_tonic: tonic)

          rounded_degree = degree % 8
          rounded_degree = 1 if rounded_degree == 0
          chord_name = chords[rounded_degree - 1]

          _test_one_diatonic_degree(root_note, chord_name, degree, tonic, scale_name, r)
        end
      end
    end
  end

  def test_non_diatonic_degree
    # Here we diverge from Sonic Pi quite a bit, in that we only stack 3rds,
    # stopping when there is no third on the scale. That means quite a few
    # scales will have basically no useful results, or that we must return fewer
    # notes than requested.

    assert_equal [:c4, :e4, :g4], Chord.degree(1, :c4, :major_pentatonic)
    assert_equal [:c4, :e4, :g4], Chord.degree(1, :c4, :major_pentatonic, 4)
    assert_equal [:d4], Chord.degree(2, :c4, :major_pentatonic, 7)
    assert_equal [:a4, :c5, :e5, :g5], Chord.degree(5, :c4, :major_pentatonic, 7)

    # A big inversion should get truncated when we couldn't supply enough notes.
    assert_equal [:g4, :c5, :e5], Chord.degree(1, :c4, :major_pentatonic, 7, invert: 6)
  end

  def test_degree_roman_numerals
    %i[i ii iii iv v vi vii].each_with_index do |roman, i|
      c = Chord.degree(i + 1, :c4, :major, 7)
      assert_equal Chord.degree(roman, :c4, :major, 7), c
      assert_equal Chord.degree(roman.to_s, :c4, :major, 7), c
      assert_equal Chord.degree(roman.to_s.upcase, :c4, :major, 7), c
      assert_equal Chord.degree(roman.to_s.upcase.to_sym, :c4, :major, 7), c
    end

    # The prefixed sorts of Roman numerals accepted by Scale.degree are invalid.
    assert_raises(ArgumentError) { Chord.degree(:ai, :c4, :major) }
    assert_raises(ArgumentError) { Chord.degree(:div, :c4, :major) }
  end

  def test_closed
    assert_equal C(:c4, :maj), %i[c4 e4 g4]
    assert_equal C(:c4, :maj, invert: 1), %i[e4 g4 c5]
    assert_equal C(:c4, :maj, invert: 2), %i[g4 c5 e5]
    assert_equal C(:c4, :maj, num_octaves: 2), %i[c4 e4 g4 c5 e5 g5]
    assert_equal C(:c4, :maj, num_octaves: 2, invert: 2), %i[g4 c5 e5 g5]  # duplicates dropped
  end

  def test_rootless
    assert_equal C(:c4, :maj, :rootless), %i[e4 g4]

    # Inversion happens before voicing, so these no longer have a P1 to drop
    assert_equal C(:c4, :maj, :rootless, invert: 1), %i[e4 g4 c5]
    assert_equal C(:c4, :maj, :rootless, invert: 2), %i[g4 c5 e5]

    assert_equal C(:c4, :maj, :rootless, num_octaves: 2), %i[e4 g4 c5 e5 g5]

    assert_equal Chord.new([:P1]).voice(:c4, :rootless), []
  end

  def test_shell
    assert_equal Chord.new([:P5]).voice(:c4, :shell), []

    assert_equal(Chord.new(%i[P1 m2 M3 m3 A3 P5 d7 m7 M7 M9]).voice(:c4, :shell),
                 %i[P1 m3 M3 m7 M7].map { |i| N(:c4) + Interval.new(i) })

    # Should voice 1sts, 3rds, & 7ths in other octaves.
    assert_equal(Chord.new(%i[P1 P8 m10 M10 P12 m14 M14 P15]).voice(:c4, :shell),
                 %i[P1 P8 m10 M10 m14 M14 P15].map { |i| N(:c4) + Interval.new(i) })
  end

  def test_drop
    # C4 maj9 => %i[c4 e4 g4 b4 d5]
    assert_equal C(:c4, :maj9, :drop2), %i[b3 c4 e4 g4 d5]
    assert_equal C(:c4, :maj9, :drop3), %i[g3 c4 e4 b4 d5]
    assert_equal C(:c4, :maj9, :drop4), %i[e3 c4 g4 b4 d5]
    assert_equal C(:c4, :maj9, :drop23), %i[g3 b3 c4 e4 d5]
    assert_equal C(:c4, :maj9, :drop24), %i[e3 b3 c4 g4 d5]
    assert_equal C(:c4, :maj9, :drop34), %i[e3 g3 c4 b4 d5]

    # No effect if there aren't enough notes
    assert_equal Chord.new([:P1]).voice(:c4, :drop2), [:c4]
    assert_equal Chord.new([:P1]).voice(:c4, :drop3), [:c4]
    assert_equal Chord.new([:P1]).voice(:c4, :drop4), [:c4]
    assert_equal Chord.new([:P1]).voice(:c4, :drop23), [:c4]
    assert_equal Chord.new([:P1]).voice(:c4, :drop24), [:c4]
    assert_equal Chord.new([:P1]).voice(:c4, :drop34), [:c4]

    # The duplicate e4 is dropped
    assert_equal C(:c4, :maj, :drop2, num_octaves: 2), %i[c4 e4 g4 c5 g5]

    # Here the duplicate c5=>c4 (position 3) is dropped, but the g4 (position 4)
    # still becomes a g3
    assert_equal C(:c4, :maj, :drop34, num_octaves: 2), %i[g3 c4 e4 e5 g5]
  end

  def test_double_bass
    assert_equal C(:c4, :maj, :double_bass), %i[c3 c4 e4 g4]
    assert_equal C(:c4, :maj, :double_bass_up), %i[c4 e4 g4 c5]

    assert_equal C(:c4, :maj, :double_bass, invert: 1), %i[e3 e4 g4 c5]
    assert_equal C(:c4, :maj, :double_bass_up, invert: 1), %i[e4 g4 c5 e5]
  end

  def test_double_intervals
    assert_equal C(:c4, :maj, :double3), %i[e3 c4 e4 g4]
    assert_equal C(:c4, :min, :double3), %i[ds3 c4 ds4 g4]
    assert_equal C(:c4, :maj, :double3_up), %i[c4 e4 g4 e5]
    assert_equal C(:c4, :min, :double3_up), %i[c4 ds4 g4 ds5]
    assert_equal Chord.new(%i[P1 A3 P5]).voice(:c4, :double3), %i[c4 f4 g4]  # no effect
    assert_equal Chord.new(%i[P1 P5]).voice(:c4, :double3), %i[c4 g4]  # no effect
    # 3rds in other octaves are doubled
    assert_equal Chord.new(%i[m10 M10]).voice(:c4, :double3), %i[ds4 e4 ds5 e5]
    assert_equal Chord.new(%i[m17 M17]).voice(:c4, :double3), %i[ds5 e5 ds6 e6]

    assert_equal C(:c4, :maj, :double5), %i[g3 c4 e4 g4]
    assert_equal C(:c4, :maj, :double5_up), %i[c4 e4 g4 g5]
    assert_equal Chord.new(%i[P1 M3 A5]).voice(:c4, :double5), %i[c4 e4 gs4]  # no effect
    assert_equal Chord.new(%i[P1 M3]).voice(:c4, :double5), %i[c4 e4]  # no effect
    # 5ths in other octaves are doubled
    assert_equal Chord.new(%i[P12]).voice(:c4, :double5), %i[g4 g5]
    assert_equal Chord.new(%i[P19]).voice(:c4, :double5), %i[g5 g6]

    assert_equal C(:c4, :maj7, :double7), %i[b3 c4 e4 g4 b4]
    assert_equal C(:c4, :min7, :double7), %i[as3 c4 ds4 g4 as4]
    assert_equal C(:c4, :maj7, :double7_up), %i[c4 e4 g4 b4 b5]
    assert_equal C(:c4, :min7, :double7_up), %i[c4 ds4 g4 as4 as5]
    assert_equal Chord.new(%i[P1 A7]).voice(:c4, :double7), %i[c4 c5]  # no effect
    assert_equal Chord.new(%i[P1 P5]).voice(:c4, :double7), %i[c4 g4]  # no effect
    # 7ths in other octaves are doubled
    assert_equal Chord.new(%i[m14 M14]).voice(:c4, :double7), %i[as4 b4 as5 b5]
    assert_equal Chord.new(%i[m21 M21]).voice(:c4, :double7), %i[as5 b5 as6 b6]
  end

  def test_open
    # Raise the 2nd lowest note an octave.
    assert_equal C(:c4, :maj7, :open), %i[c4 g4 b4 e5]
    assert_equal Chord.new([:P1]).voice(:c4, :open), [:c4]  # no effect

    # Raise the lowest note an octave and lower the third lowest note an octave.
    assert_equal C(:c4, :maj7, :open2), %i[g3 e4 b4 c5]
    assert_equal Chord.new([:P1]).voice(:c4, :open2), [:c5]

    # Lower the 2nd lowest note an octave.
    assert_equal C(:c4, :maj7, :open3), %i[e3 c4 g4 b4]
    assert_equal Chord.new([:P1]).voice(:c4, :open3), [:c4]  # no effect
  end
end
