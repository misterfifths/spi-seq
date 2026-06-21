#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "../lib/spiseq/theory/notelength"

include SpiSeq::Theory

class NoteLengthTest < Test::Unit::TestCase
  LENGTHS_IN_ORDER = [
    NoteLength.new(:whole),
    NoteLength.new(:half),
    NoteLength.new(:quarter),
    NoteLength.new(:eighth),
    NoteLength.new(:sixteenth),
    NoteLength.new(:thirty_second),
    NoteLength.new(:sixty_fourth)
  ].freeze

  def assert_attrs(nl, sym, float_val)
    assert_equal nl.to_sym, sym
    assert_in_delta nl.to_f, float_val
    assert_in_delta nl.to_f, float_val
  end

  def assert_eq_notelengths(nl1, nl2)
    assert_attrs nl1, nl2.to_sym, nl2.to_f
    assert_attrs nl2, nl1.to_sym, nl1.to_f
  end

  def test_initializer
    [
      [:whole, 4.0],
      [:half, 2.0],
      [:quarter, 1.0],
      [:eighth, 1 / 2.0],
      [:sixteenth, 1 / 4.0],
      [:thirty_second, 1 / 8.0],
      [:sixty_fourth, 1 / 16.0]
    ].each do |name, number|
      by_name = NoteLength.new(name)
      by_num = NoteLength.new(number)

      assert_attrs by_name, name, number
      assert_attrs by_num, name, number
      assert_eq_notelengths by_name, by_num
    end

    # Aliases should resolve to the canon name with an underscore
    [
      [:thirtysecond, :thirty_second],
      [:sixtyfourth, :sixty_fourth]
    ].each do |name_alias, canon_name|
      assert_eq_notelengths NoteLength.new(name_alias), NoteLength.new(canon_name)
    end

    # Invalid values
    assert_raises(ArgumentError) { NoteLength.new(1.5) }
    assert_raises(ArgumentError) { NoteLength.new([]) }
    assert_raises(ArgumentError) { NoteLength.new(:nope) }
  end

  def test_double_halve
    LENGTHS_IN_ORDER.each_with_index do |nl, i|
      unless i == 0
        prev_nl = LENGTHS_IN_ORDER[i - 1]
        double = nl.double
        assert_eq_notelengths double, prev_nl
        assert_in_delta double.to_f, nl.to_f * 2.0
      end

      next if i == LENGTHS_IN_ORDER.length - 1

      next_nl = LENGTHS_IN_ORDER[i + 1]
      half = nl.halve
      assert_eq_notelengths half, next_nl
      assert_in_delta half.to_f, nl.to_f / 2.0
    end
  end

  def test_steps_to
    LENGTHS_IN_ORDER.each_with_index do |nl, i|
      LENGTHS_IN_ORDER.each_with_index do |other_nl, j|
        assert_equal nl.steps_to(other_nl), (i - j).abs
        assert_equal other_nl.steps_to(nl), (i - j).abs
      end
    end
  end

  def test_comparison
    LENGTHS_IN_ORDER.each do |nl|
      assert_equal nl, nl
      assert_equal nl, nl.to_f
      assert_equal nl, nl.to_sym
      assert nl <= nl
      assert nl <= nl.to_f
      assert nl <= nl.to_sym
      assert nl >= nl
      assert nl >= nl.to_f
      assert nl >= nl.to_sym
      assert_equal nl <=> nl, 0
      assert_equal nl <=> nl.to_f, 0
      assert_equal nl <=> nl.to_sym, 0

      LENGTHS_IN_ORDER.each do |other_nl|
        next if nl.to_sym == other_nl.to_sym

        assert_not_equal nl, other_nl
        assert_not_equal nl, other_nl.to_sym
        assert_not_equal nl, other_nl.to_f

        assert_not_equal other_nl, nl
        assert_not_equal other_nl, nl.to_sym
        assert_not_equal other_nl, nl.to_f


        if nl.to_f > other_nl.to_f
          lesser = other_nl
          greater = nl
        else
          lesser = nl
          greater = other_nl
        end

        assert greater > lesser
        assert greater > lesser.to_sym
        assert greater > lesser.to_f
        assert greater >= lesser
        assert greater >= lesser.to_sym
        assert greater >= lesser.to_f

        assert_equal greater <=> lesser, 1
        assert_equal greater <=> lesser.to_sym, 1
        assert_equal greater <=> lesser.to_f, 1

        assert lesser < greater
        assert lesser < greater.to_sym
        assert lesser < greater.to_f
        assert lesser <= greater
        assert lesser <= greater.to_sym
        assert lesser <= greater.to_f

        assert_equal lesser <=> greater, -1
        assert_equal lesser <=> greater.to_sym, -1
        assert_equal lesser <=> greater.to_f, -1
      end
    end

    # Comparisons to float values that aren't valid lengths should work
    assert NoteLength::Whole < 10
    assert NoteLength::Eighth > 0

    # Comparisons against non-NoteLength values
    assert NoteLength::Whole == 4
    assert NoteLength::Whole != []
    assert NoteLength::Whole != :nope
    assert_raises(ArgumentError) { NoteLength::Whole > [] }
    assert_raises(ArgumentError) { NoteLength::Whole > :nope }
  end

  def test_repr
    LENGTHS_IN_ORDER.each do |nl|
      assert_equal nl, NoteLength.new(eval(nl.repr))  # rubocop:disable Security/Eval
    end
  end
end
