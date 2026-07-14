#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "../lib/spiseq/theory/interval"

class IntervalTest < Test::Unit::TestCase
  include SpiSeq::Theory

  def assert_attrs(i, size, quality, number, sym, octave_span = 1, simple_interval = nil)
    assert_equal i.size, size
    assert_equal i.to_i, size
    assert_equal i.quality, quality
    assert_equal i.number, number
    assert_equal i.to_sym, sym
    assert_equal i.octave_span, octave_span
    assert i.names.include?(i.to_sym)

    # We want to very specifically check the simple_interval value, not just
    # its equality with the argument; hence the comparison of symbols.
    assert_equal i.simple_interval.to_sym, simple_interval.nil? ? i.to_sym : simple_interval.to_sym
  end

  def assert_new(size, quality, number, sym, octave_span = 1, simple_interval = nil)
    # Instances constructed in any of these ways should be equivalent.

    i = I(sym)
    assert_attrs i, size, quality, number, sym, octave_span, simple_interval

    i = I(size:, quality:)
    assert_attrs i, size, quality, number, sym, octave_span, simple_interval

    i = I(number:, quality:)
    assert_attrs i, size, quality, number, sym, octave_span, simple_interval
  end

  def test_initialization
    assert_raises(ArgumentError) { Interval.new }

    assert_raises(ArgumentError) { Interval.new(:P1, number: 1)}
    assert_raises(ArgumentError) { Interval.new(:P1, size: 0)}
    assert_raises(ArgumentError) { Interval.new(:P1, quality: :perfect)}

    assert_raises(ArgumentError) { Interval.new(number: 1, size: 0) }
    assert_raises(RangeError) { Interval.new(number: -1) }
  end

  def test_simple_intervals
    assert_new 0, :perfect, 1, :P1
    assert_new 0, :dim, 2, :d2
    assert_raises(ArgumentError) { Interval.new(size: 0, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 0, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 0, quality: :aug) }

    assert_new 1, :minor, 2, :m2
    assert_new 1, :aug, 1, :A1
    assert_raises(ArgumentError) { Interval.new(size: 1, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 1, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 1, quality: :dim) }

    assert_new 2, :major, 2, :M2
    assert_new 2, :dim, 3, :d3
    assert_raises(ArgumentError) { Interval.new(size: 2, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 2, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 2, quality: :aug) }

    assert_new 3, :minor, 3, :m3
    assert_new 3, :aug, 2, :A2
    assert_raises(ArgumentError) { Interval.new(size: 3, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 3, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 3, quality: :dim) }

    assert_new 4, :major, 3, :M3
    assert_new 4, :dim, 4, :d4
    assert_raises(ArgumentError) { Interval.new(size: 4, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 4, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 4, quality: :aug) }

    assert_new 5, :perfect, 4, :P4
    assert_new 5, :aug, 3, :A3
    assert_raises(ArgumentError) { Interval.new(size: 5, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 5, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 5, quality: :dim) }

    assert_new 6, :dim, 5, :d5
    assert_new 6, :aug, 4, :A4
    assert_raises(ArgumentError) { Interval.new(size: 6, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 6, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 6, quality: :minor) }

    assert_new 7, :perfect, 5, :P5
    assert_new 7, :dim, 6, :d6
    assert_raises(ArgumentError) { Interval.new(size: 7, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 7, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 7, quality: :aug) }

    assert_new 8, :minor, 6, :m6
    assert_new 8, :aug, 5, :A5
    assert_raises(ArgumentError) { Interval.new(size: 8, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 8, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 8, quality: :dim) }

    assert_new 9, :major, 6, :M6
    assert_new 9, :dim, 7, :d7
    assert_raises(ArgumentError) { Interval.new(size: 9, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 9, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 9, quality: :aug) }

    assert_new 10, :minor, 7, :m7
    assert_new 10, :aug, 6, :A6
    assert_raises(ArgumentError) { Interval.new(size: 10, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 10, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 10, quality: :dim) }

    assert_new 11, :major, 7, :M7
    assert_new 11, :dim, 8, :d8
    assert_raises(ArgumentError) { Interval.new(size: 11, quality: :perfect) }
    assert_raises(ArgumentError) { Interval.new(size: 11, quality: :minor) }
    assert_raises(ArgumentError) { Interval.new(size: 11, quality: :aug) }

    assert_new 12, :perfect, 8, :P8, 2, :P1
    assert_new 12, :aug, 7, :A7, 2, :P1
    assert_raises(ArgumentError) { Interval.new(size: 12, quality: :major) }
    assert_raises(ArgumentError) { Interval.new(size: 12, quality: :minor) }
    # 12 semitones with diminished quality is valid but compound (d9)
  end

  def assert_compound(size, quality, number, sym, octave_span = 1, simple_interval = nil)
    assert_new size, quality, number, sym, octave_span, simple_interval
    assert Interval.new(sym).compound?
    refute Interval.new(sym).simple?
    assert Interval.new(number:, quality:).compound?
    refute Interval.new(number:, quality:).simple?
    if size > 12
      # d9 is a weird case that is compound even though its size is 12.
      assert Interval.new(size:).compound?
      refute Interval.new(size:).simple?
    end
  end

  def test_compound_intervals
    assert_compound 12, :dim, 9, :d9, 2, :P1

    assert_compound 13, :minor, 9, :m9, 2, :m2
    assert_compound 13, :aug, 8, :A8, 2, :A1

    assert_compound 14, :major, 9, :M9, 2, :M2
    assert_compound 14, :dim, 10, :d10, 2, :d3

    assert_compound 15, :minor, 10, :m10, 2, :m3
    assert_compound 15, :aug, 9, :A9, 2, :A2

    assert_compound 16, :major, 10, :M10, 2, :M3
    assert_compound 16, :dim, 11, :d11, 2, :d4

    assert_compound 17, :perfect, 11, :P11, 2, :P4
    assert_compound 17, :aug, 10, :A10, 2, :A3

    assert_compound 18, :dim, 12, :d12, 2, :d5
    assert_compound 18, :aug, 11, :A11, 2, :A4

    assert_compound 19, :perfect, 12, :P12, 2, :P5
    assert_compound 19, :dim, 13, :d13, 2, :d6

    assert_compound 20, :minor, 13, :m13, 2, :m6
    assert_compound 20, :aug, 12, :A12, 2, :A5

    assert_compound 21, :major, 13, :M13, 2, :M6
    assert_compound 21, :dim, 14, :d14, 2, :d7

    assert_compound 22, :minor, 14, :m14, 2, :m7
    assert_compound 22, :aug, 13, :A13, 2, :A6

    assert_compound 23, :major, 14, :M14, 2, :M7
    assert_compound 23, :dim, 15, :d15, 2, :d8

    assert_compound 24, :perfect, 15, :P15, 3, :P1
    assert_compound 24, :aug, 14, :A14, 3, :P1

    assert_compound 25, :aug, 15, :A15, 3, :A1

    assert_compound 28, :major, 17, :M17, 3, :M3
    assert_compound 40, :major, 24, :M24, 4, :M3
    assert_compound 52, :major, 31, :M31, 5, :M3
    assert_compound 64, :major, 38, :M38, 6, :M3
  end

  def assert_def_qual_for_size(size, quality, number, sym, octave_span = 1, simple_interval = nil)
    i = Interval.new(size:)  # Note: not passing quality here
    assert_attrs i, size, quality, number, sym, octave_span, simple_interval
  end

  def assert_def_qual_for_num(size, quality, number, sym, octave_span = 1, simple_interval = nil)
    i = Interval.new(number:)  # Note: not passing quality here
    assert_attrs i, size, quality, number, sym, octave_span, simple_interval
  end

  # Test the default quality for an Interval if given only a size/number.
  def test_default_qualities
    assert_def_qual_for_size 0, :perfect, 1, :P1
    assert_def_qual_for_size 1, :minor, 2, :m2
    assert_def_qual_for_size 2, :major, 2, :M2
    assert_def_qual_for_size 3, :minor, 3, :m3
    assert_def_qual_for_size 4, :major, 3, :M3
    assert_def_qual_for_size 5, :perfect, 4, :P4
    assert_def_qual_for_size 6, :dim, 5, :d5
    assert_def_qual_for_size 7, :perfect, 5, :P5
    assert_def_qual_for_size 8, :minor, 6, :m6
    assert_def_qual_for_size 9, :major, 6, :M6
    assert_def_qual_for_size 10, :minor, 7, :m7
    assert_def_qual_for_size 11, :major, 7, :M7
    assert_def_qual_for_size 12, :perfect, 8, :P8, 2, :P1

    assert_def_qual_for_num 0, :perfect, 1, :P1
    assert_def_qual_for_num 2, :major, 2, :M2
    assert_def_qual_for_num 4, :major, 3, :M3
    assert_def_qual_for_num 5, :perfect, 4, :P4
    assert_def_qual_for_num 7, :perfect, 5, :P5
    assert_def_qual_for_num 9, :major, 6, :M6
    assert_def_qual_for_num 11, :major, 7, :M7
    assert_def_qual_for_num 12, :perfect, 8, :P8, 2, :P1
    assert_def_qual_for_num 14, :major, 9, :M9, 2, :M2
    assert_def_qual_for_num 16, :major, 10, :M10, 2, :M3
    assert_def_qual_for_num 17, :perfect, 11, :P11, 2, :P4
    assert_def_qual_for_num 19, :perfect, 12, :P12, 2, :P5
    assert_def_qual_for_num 21, :major, 13, :M13, 2, :M6
  end

  def test_arithmetic
    aug1 = Interval.new(:A1)

    # This behavior is a little surprising. Doing arithmetic on an Interval will
    # collapse it to its default quality, which for 1 semitone is minor.
    assert_attrs aug1 + 0, 1, :minor, 2, :m2  # rubocop:disable Lint/UselessNumericOperation

    assert_attrs aug1 + 1, 2, :major, 2, :M2
    assert_attrs aug1 + 2, 3, :minor, 3, :m3
    assert_attrs aug1 + 3, 4, :major, 3, :M3
    assert_attrs aug1 + 4, 5, :perfect, 4, :P4
    assert_attrs aug1 + 5, 6, :dim, 5, :d5
    assert_attrs aug1 + 6, 7, :perfect, 5, :P5
    assert_attrs aug1 + 7, 8, :minor, 6, :m6
    assert_attrs aug1 + 8, 9, :major, 6, :M6
    assert_attrs aug1 + 9, 10, :minor, 7, :m7
    assert_attrs aug1 + 10, 11, :major, 7, :M7
    assert_attrs aug1 + 11, 12, :perfect, 8, :P8, 2, :P1

    assert_attrs aug1 * 7, 7, :perfect, 5, :P5
    assert_attrs aug1 * 12, 12, :perfect, 8, :P8, 2, :P1

    assert_attrs aug1 * 12 + aug1, 13, :minor, 9, :m9, 2, :m2
    assert_attrs aug1 * 12 + aug1 + 1, 14, :major, 9, :M9, 2, :M2

    assert_attrs aug1 - 1, 0, :perfect, 1, :P1
    assert_attrs Interval.new(:A6) - 2, 8, :minor, 6, :m6

    # I don't know why anyone would use division but it's there.
    assert_attrs Interval.new(size: 6) / 2, 3, :minor, 3, :m3
    assert_attrs Interval.new(size: 6) / Interval.new(size: 2), 3, :minor, 3, :m3

    # Math with a non-Interval LHS will excercise .coerce()
    assert_attrs 1 + aug1, 2, :major, 2, :M2

    # Symbols and strings should be coerced
    # rubocop:disable Style/StringConcatenation
    assert_equal Interval.new(:P5) + :P1, :P5
    assert_equal Interval.new(:P5) + "P1", :P5
    assert_equal Interval.new(:P5) + :m2, :A5
    assert_equal Interval.new(:P5) + "m2", :A5
    assert_equal Interval.new(:A5) - :m2, :P5
    assert_equal Interval.new(:A5) - "m2", :P5
    assert_equal Interval.new(size: 5) * Interval.new(size: 2).to_sym, Interval.new(size: 10)
    assert_equal Interval.new(size: 5) * Interval.new(size: 2).to_s, Interval.new(size: 10)
    assert_equal Interval.new(size: 10) / Interval.new(size: 2).to_sym, Interval.new(size: 5)
    assert_equal Interval.new(size: 10) / Interval.new(size: 2).to_s, Interval.new(size: 5)

    assert_raises { Interval.new(:P5) + :nope }
    assert_raises { Interval.new(:P5) + "nope" }
    # rubocop:enable Style/StringConcatenation
  end

  def test_comparisons
    [
      [:P1, :m2, :M2],
      [:m3, :P4, :P8],
      [:A3, :d5, :M6],
      [:m2, :d9, :A8],
      [:M9, :m13, :M24]
    ].each do |vals|
      a, b, c = *vals
      ai = Interval.new(a)
      bi = Interval.new(b)
      ci = Interval.new(c)

      # a against itself
      assert_equal ai, ai
      assert_equal ai, a
      assert_equal ai, a.to_s
      assert_equal ai, ai.size

      assert ai <= ai
      assert ai >= ai
      assert_equal ai <=> ai, 0

      assert ai <= a
      assert ai >= a
      assert_equal ai <=> a, 0

      assert ai <= ai.size
      assert ai >= ai.size
      assert_equal ai <=> ai.size, 0

      assert_equal a, ai
      assert a >= ai
      assert a <= ai
      assert_equal a <=> ai, 0

      # a < b
      refute_equal ai, bi
      refute_equal ai, b
      refute_equal ai, b.size

      assert ai < bi
      assert ai < bi.size
      assert ai < b
      assert_equal ai <=> bi, -1
      assert_equal ai <=> bi.size, -1
      assert_equal ai <=> b, -1

      assert a < bi
      assert_equal a <=> bi, -1

      # b > a
      assert bi > ai
      assert bi > ai.size
      assert bi > a
      assert_equal bi <=> ai, 1
      assert_equal bi <=> ai.size, 1
      assert_equal bi <=> a, 1

      assert b > ai
      assert_equal b <=> ai, 1

      # b < c
      refute_equal bi, ci
      refute_equal bi, c
      refute_equal bi, c.size

      assert bi < ci
      assert bi < ci.size
      assert bi < c
      assert_equal bi <=> ci, -1
      assert_equal bi <=> ci.size, -1
      assert_equal bi <=> c, -1

      assert b < ci
      assert_equal b <=> ci, -1

      # c > b
      assert ci > bi
      assert ci > bi.size
      assert ci > b
      assert_equal ci <=> bi, 1
      assert_equal ci <=> bi.size, 1
      assert_equal ci <=> b, 1

      assert c > bi
      assert_equal c <=> bi, 1
    end

    # Equality is based solely on the size; quality is ignored.
    assert_equal Interval.new(size: 7, quality: :perfect), Interval.new(size: 7, quality: :dim)
    assert_equal Interval.new(size: 7, quality: :perfect), Interval.new(number: 6, quality: :dim)
    assert_equal Interval.new(size: 7, quality: :perfect), :d6
    assert_equal Interval.new(size: 7, quality: :perfect), 7
    assert_equal Interval.new(size: 8, quality: :minor), Interval.new(size: 8, quality: :aug)
    assert_equal Interval.new(size: 8, quality: :minor), Interval.new(number: 5, quality: :aug)
    assert_equal Interval.new(size: 8, quality: :minor), :A5
    assert_equal Interval.new(size: 8, quality: :minor), 8

    # Comparison against non-Intervals
    assert Interval.new(:A1) == 1.0  # rubocop:disable Lint/FloatComparison
    assert Interval.new(:P1) != []
    assert Interval.new(:P1) != :nope
    assert_raises(ArgumentError) { Interval.new(:P1) > [] }
    assert_raises(ArgumentError) { Interval.new(:P1) > :nope }

    # Right-hand side equality
    # rubocop:disable Style/YodaCondition
    assert :P1 == Interval.new(:P1)
    assert :P1.eql?(Interval.new(:P1))
    assert "P1" == Interval.new(:P1)
    assert "P1".eql?(Interval.new(:P1))
    assert :A1 != Interval.new(:P1)

    assert_nil :nope <=> Interval.new(:P1)
    assert_nil "nope" <=> Interval.new(:P1)
    # rubocop:enable Style/YodaCondition
  end

  def test_attrs
    assert Interval.new(:P5).perfect?
    refute Interval.new(:P5).minor?
    refute Interval.new(:P5).major?
    refute Interval.new(:P5).augmented?
    refute Interval.new(:P5).diminished?
    refute Interval.new(:P5).compound?
    assert Interval.new(:P5).simple?

    refute Interval.new(:M7).perfect?
    refute Interval.new(:M7).minor?
    assert Interval.new(:M7).major?
    refute Interval.new(:M7).augmented?
    refute Interval.new(:M7).diminished?
    refute Interval.new(:M7).compound?
    assert Interval.new(:M7).simple?

    refute Interval.new(:m7).perfect?
    assert Interval.new(:m7).minor?
    refute Interval.new(:m7).major?
    refute Interval.new(:m7).augmented?
    refute Interval.new(:m7).diminished?
    refute Interval.new(:m7).compound?
    assert Interval.new(:m7).simple?

    refute Interval.new(:d7).perfect?
    refute Interval.new(:d7).minor?
    refute Interval.new(:d7).major?
    refute Interval.new(:d7).augmented?
    assert Interval.new(:d7).diminished?
    refute Interval.new(:d7).compound?
    assert Interval.new(:d7).simple?

    refute Interval.new(:A7).perfect?
    refute Interval.new(:A7).minor?
    refute Interval.new(:A7).major?
    assert Interval.new(:A7).augmented?
    refute Interval.new(:A7).diminished?
    refute Interval.new(:A7).compound?
    assert Interval.new(:A7).simple?

    assert Interval.new(:A8).compound?
    refute Interval.new(:A8).simple?
    assert Interval.new(:d9).compound?
    refute Interval.new(:d9).simple?
    assert Interval.new(:M13).compound?
    refute Interval.new(:M13).simple?
  end

  def assert_as(qual1, num1, qual2, num2)
    i1 = Interval.new(number: num1, quality: qual1)
    i2 = Interval.new(number: num2, quality: qual2)

    assert i1.expressible_as(num2)
    refute_nil i1.as(num2)
    # Checking against symbols here since we want a strict quality/number match.
    assert_equal i1.as(num2).to_sym, i2.to_sym

    assert i2.expressible_as(num1)
    refute_nil i2.as(num1)
    assert_equal i2.as(num1).to_sym, i1.to_sym

    assert_equal Set.new(i1.names), Set.new(i2.names)
    assert_equal Set.new(i2.names), Set.new(i1.names)
  end

  def test_as
    assert_as :perfect, 1, :dim, 2
    assert_as :minor,   2, :aug, 1
    assert_as :major,   2, :dim, 3
    assert_as :minor,   3, :aug, 2
    assert_as :major,   3, :dim, 4
    assert_as :perfect, 4, :aug, 3
    assert_as :dim,     5, :aug, 4
    assert_as :perfect, 5, :dim, 6
    assert_as :minor,   6, :aug, 5
    assert_as :major,   6, :dim, 7
    assert_as :minor,   7, :aug, 6
    assert_as :major,   7, :dim, 8
    assert_as :perfect, 8, :aug, 7

    assert_as :perfect, 15, :aug, 14
    assert_as :perfect, 15, :dim, 16
    assert_as :minor, 23, :aug, 22
    assert_as :major, 30, :dim, 31

    assert_as :perfect, 5, :perfect, 5
    assert_as :major, 30, :major, 30

    assert_nil Interval.new(:P5).as(7)
    assert_nil Interval.new(:M3).as(5)
  end

  def test_names
    [
      [:P1, :d2],
      [:M2, :d3],
      [:m3, :A2],
      [:M3, :d4],
      [:P5, :d6],
      [:P8, :A7, :d9],
      [:M10, :d11],
      [:m17, :A16],
      [:P12, :d13],
      [:P22, :A21, :d23]
    ].each do |names|
      names.each do |name|
        i = Interval.new(name)
        assert_equal Set.new(i.names), Set.new(names), name
      end
    end

    0.upto(54) do |semitones|
      i = Interval.new(size: semitones)
      i_names = Set.new(i.names)
      i_names.map do |name|
        other = Interval.new(name)
        assert_equal i.size, other.size
        assert_equal i_names, Set.new(other.names)
      end
    end
  end
end
