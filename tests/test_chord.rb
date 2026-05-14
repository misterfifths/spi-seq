#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../theory/chord"
require_relative "../extapi"

class ChordTest < Test::Unit::TestCase
  def test_initializer
    assert_equal Chord.new([:P1]).intervals, [:P1]
    assert_equal Chord.new([:P1, :M3]).intervals, [:P1, :M3]

    # Duplicates are removed
    assert_equal Chord.new([:P1, :M3, :P1]).intervals, [:P1, :M3]
    assert_equal Chord.new([:P1, :M3, :P1, :M3]).intervals, [:P1, :M3]

    # Intervals are always sorted
    assert_equal Chord.new([:M3, :P1, :m3]).intervals, [:P1, :m3, :M3]

    # Numbers are taken as major/perfect interval numbers
    assert_equal Chord.new([1, 3, 5]).intervals, [:P1, :M3, :P5]
  end

  def test_append_remove
    c = Chord.new([:P1, :m3])
    c += :P5
    assert_equal c.intervals, [:P1, :m3, :P5]
    c = c.without(:P1)
    assert_equal c.intervals, [:m3, :P5]
    assert_raises(ArgumentError) { c.without(:P1) }

    # No duplicates
    c = Chord.new([:P1, :m3])
    c += :m3
    assert_equal c.intervals, [:P1, :m3]

    # Intervals are always sorted
    c = Chord.new([:m3, :P5])
    c += :P1
    assert_equal c.intervals, [:P1, :m3, :P5]

    # Adding other chords or enumerables
    c = Chord.new([:P1]) + [:P5, :m3]
    assert_equal c.intervals, [:P1, :m3, :P5]
    c = Chord.new([:P1]) + Chord.new([:P5, :m3])
    assert_equal c.intervals, [:P1, :m3, :P5]

    # Integers -> major or perfect
    c = Chord.new([:P1, :m3])
    c += 5
    assert_equal c.intervals, [:P1, :m3, :P5]
    c += 3
    assert_equal c.intervals, [:P1, :m3, :M3, :P5]
  end

  def test_suspend
    assert_equal Chord.new([:P1, :m3]).sus4.intervals, [:P1, :P4]
    assert_equal Chord.new([:P1, :M3]).sus4.intervals, [:P1, :P4]
    assert_equal Chord.new([:P1, :M3, :P4]).sus4.intervals, [:P1, :P4]  # no duplicates
    assert_raises(ArgumentError) { Chord.new([:P1, :m3, :M3]).sus4 }
    assert_raises(ArgumentError) { Chord.new([:P1]).sus4 }

    assert_equal Chord.new([:P1, :m3]).sus2.intervals, [:P1, :M2]
    assert_equal Chord.new([:P1, :M3]).sus2.intervals, [:P1, :M2]
    assert_equal Chord.new([:P1, :M3, :M2]).sus2.intervals, [:P1, :M2]  # no duplicates
    assert_raises(ArgumentError) { Chord.new([:P1, :m3, :M3]).sus2 }
    assert_raises(ArgumentError) { Chord.new([:P1]).sus2 }

    assert_equal Chord.new([:P1, :m3]).sus9.intervals, [:P1, :P4, :M9]
    assert_equal Chord.new([:P1, :M3]).sus9.intervals, [:P1, :P4, :M9]
    assert_equal Chord.new([:P1, :M3, :P4, :M9]).sus9.intervals, [:P1, :P4, :M9]  # no duplicates
    assert_raises(ArgumentError) { Chord.new([:P1, :m3, :M3]).sus9 }
    assert_raises(ArgumentError) { Chord.new([:P1]).sus9 }
  end

  def test_flat_sharp
    assert_equal Chord.new([:M3]).flat(3).intervals, [:m3]
    assert_equal Chord.new([:M3]).flat(:M3).intervals, [:m3]
    assert_equal Chord.new([:P5]).flat(5).intervals, [:d5]
    assert_equal Chord.new([:P5]).flat(:P5).intervals, [:d5]
    assert_raises(ArgumentError) { Chord.new([:P5]).flat(2) }

    assert_equal Chord.new([:M3]).sharp(3).intervals, [:A3]
    assert_equal Chord.new([:M3]).sharp(:M3).intervals, [:A3]
    assert_equal Chord.new([:P5]).sharp(5).intervals, [:A5]
    assert_equal Chord.new([:P5]).sharp(:P5).intervals, [:A5]
    assert_raises(ArgumentError) { Chord.new([:P5]).sharp(2) }

    assert_equal Chord.new([:M3]).sharp3.intervals, [:A3]
    assert_raises(ArgumentError) { Chord.new([:m3]).sharp3 }
    assert_equal Chord.new([:M3]).flat3.intervals, [:m3]
    assert_raises(ArgumentError) { Chord.new([:m3]).flat3 }

    assert_equal Chord.new([:P5]).sharp5.intervals, [:A5]
    assert_raises(ArgumentError) { Chord.new([:m5]).sharp5 }
    assert_equal Chord.new([:P5]).flat5.intervals, [:d5]
    assert_raises(ArgumentError) { Chord.new([:m5]).flat5 }

    assert_equal Chord.new([:M9]).sharp9.intervals, [:A9]
    assert_raises(ArgumentError) { Chord.new([:m9]).sharp9 }
    assert_equal Chord.new([:M9]).flat9.intervals, [:m9]
    assert_raises(ArgumentError) { Chord.new([:m9]).flat9 }
  end

  def test_basics
    # Spot checks of chord abbreviations; we test more thoroughly in Sonic Pi.
    assert_equal Chord.new(:major9).intervals, [:P1, :M3, :P5, :M7, :M9]
    assert_equal Chord.major_ninth.flat5.intervals, [:P1, :M3, :d5, :M7, :M9]

    assert_equal Chord.new(:power).intervals, [:P1, :P5]
    assert_equal Chord.new(:power2).intervals, [:P1, :P5, :M9]
    assert_equal Chord.new(:fr6).intervals, [:P1, :M3, :d5, :A6]
  end

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

  def try_spi_chord(root, name, *args, **kwargs)
    return nil unless ExtApi.in_sonic_pi?

    begin
      ns = ExtApi.spi_call(:chord, root, name, *args, **kwargs)
      ns.to_a.map { |n| N(n) }
    rescue RuntimeError
      nil
    end
  end

  def assert_eq_spi_chord(root, name, *args, sort: false, uniq: false, **kwargs)
    us = Chord.voiced(root, name, *args, **kwargs)
    them = try_spi_chord(root, name, *args, **kwargs)
    them.sort! if sort
    them.uniq! if uniq
    assert_equal them, us, "#{root} #{name} #{args.inspect} #{kwargs.inspect}"
  end

  def test_chords_vs_sonic_pi
    return unless ExtApi.in_sonic_pi?

    Chord::ABBREVS.each_key do |name|
      spi_chord = try_spi_chord(:c4, name)
      next if spi_chord.nil?  # Skip names Sonic Pi doesn't know.
      num_notes = spi_chord.length

      [:c4, :a4, :fs2].each do |root|
        assert_eq_spi_chord root, name

        1.upto(num_notes - 1) do |invert|
          # Sonic Pi will duplicate notes in an inversion.
          assert_eq_spi_chord root, name, uniq: true, invert: invert
        end

        2.upto(4) do |octaves|
          # Sonic Pi doesn't use the order we do for extra octaves, so sort.
          # It will also, in some circumstances (e.g. 7-11 chord, 2 octaves),
          # duplicate notes.
          assert_eq_spi_chord root, name, sort: true, uniq: true, num_octaves: octaves
        end

        # Since Sonic Pi's ordering is weird with num_octaves, we can't really
        # test invert + num_octaves (the inversion relies on the order). Also
        # Sonic Pi returns duplicate notes when you mix the two, so it's not
        # likely that gets much use.
      end
    end

    # We should understand all the names that Sonic Pi does.
    ExtApi.spi_call(:chord_names).to_a.each do |name|
      assert_nothing_raised("should support chord #{name}") { Chord.new(name) }
    end
  end
end
