#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../theory/chord"
require_relative "../extapi"

class ChordTest < Test::Unit::TestCase
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
end
