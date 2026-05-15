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
    assert_equal Chord.new([:A1, :m2, :P5, :d6]).intervals, [:m2, :P5]

    # Intervals are always sorted
    assert_equal Chord.new([:M3, :P1, :m3]).intervals, [:P1, :m3, :M3]

    # Numbers are taken as major/perfect interval numbers
    assert_equal Chord.new([1, 3, 5]).intervals, [:P1, :M3, :P5]

    # Chords can't be empty
    assert_raises(ArgumentError) { Chord.new([]) }
    assert_raises(ArgumentError) { Chord.new([:P1]).without(1) }
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

    # No duplicates
    assert_equal Chord.new([:M9, :m9]).flat9.intervals, [:m9]
    assert_equal Chord.new([:M9, :A9]).sharp9.intervals, [:A9]
  end

  def test_basics
    # Spot checks of chord abbreviations; we test more thoroughly in Sonic Pi.
    assert_equal Chord.new(:major9).intervals, [:P1, :M3, :P5, :M7, :M9]
    assert_equal Chord.major_ninth.flat5.intervals, [:P1, :M3, :d5, :M7, :M9]

    assert_equal Chord.new(:power).intervals, [:P1, :P5]
    assert_equal Chord.new(:power2).intervals, [:P1, :P5, :M9]
    assert_equal Chord.new(:fr6).intervals, [:P1, :M3, :d5, :A6]
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

    Chord::CHORD_NAMES.each do |name|
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
