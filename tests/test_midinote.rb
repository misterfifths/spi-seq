#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../theory/midinote"

class MIDINoteTest < Test::Unit::TestCase
  def test_initialization
    assert_instance_of MIDINote, N(:c4)
    assert_instance_of MIDINote, N(:c)
    assert_instance_of MIDINote, N("c4")
    assert_instance_of MIDINote, N(60)
    assert_instance_of MIDINote, N(60.5)
    assert_instance_of MIDINote, N(300)
    assert_instance_of MIDINote, N(-10)
    assert_raises { N(:r) }
    assert_raises { N(:rest) }
    assert_raises { N(nil) }
    assert_raises { N(:nonsense) }
    assert_raises { N("nope") }
    assert_raises { N([]) }

    c4 = N(:c4)
    assert_same N(c4), c4

    # Regex edge cases
    assert_raises { N("c-") }
    assert_raises { N(:"c-") }
    assert_raises { N(":c-4") }
    assert_raises { N(:":c-4") }
  end

  def assert_attrs(note, number, sym, pitch_class)
    assert_equal note.number, number
    assert_equal note.to_f, number.to_f
    assert_equal note.to_i, number.to_i
    assert_equal note.to_sym, sym
    assert_equal note.to_s, sym.to_s
    assert_equal note.pitch_class, pitch_class
  end

  def test_attrs
    assert_attrs N(:c4), 60, :c4, :c
    assert_attrs N(:C4), 60, :c4, :c
    assert_attrs N("c4"), 60, :c4, :c
    assert_attrs N("C4"), 60, :c4, :c
    assert_attrs N(60), 60, :c4, :c
    assert_attrs N(60.0), 60, :c4, :c
    assert_attrs N(60.5), 60, :c4, :c

    # Accidental standardization
    assert_attrs N(:cs4), 61, :cs4, :cs
    assert_attrs N(:Cs4), 61, :cs4, :cs
    assert_attrs N("Cs4"), 61, :cs4, :cs
    assert_attrs N(:CS4), 61, :cs4, :cs
    assert_attrs N("CS4"), 61, :cs4, :cs
    assert_attrs N(:db4), 61, :cs4, :cs
    assert_attrs N(:df4), 61, :cs4, :cs

    # Octave wrap-around
    assert_attrs N(:cb3), 47, :b2, :b
    assert_attrs N(:cf3), 47, :b2, :b
    assert_attrs N(:bs3), 60, :c4, :c
    assert_attrs N(:cbb4), 58, :as3, :as
    assert_attrs N(:bss4), 73, :cs5, :cs
  end

  def test_eql
    assert_equal N(:c4), N(:c4)

    assert_equal N(:c4), 60
    assert_equal 60, N(:c4)
    assert_equal N(:c4), N(60)

    assert_equal N(:c4), 60.0
    assert_equal 60.0, N(:c4)
    assert_equal N(:c4), N(60.0)

    assert_equal N(:c4), :c4
    assert_equal :c4, N(:c4)

    assert_equal N(:c4), "c4"
    assert_equal "c4", N(:c4)

    assert_equal N(:c4), :C4
    assert_equal :C4, N(:c4)

    assert_equal N(:c4), "C4"
    assert_equal "C4", N(:c4)

    # Arguable, I suppose, whether these should be true.
    assert_equal N(60.5), 60.5
    assert_equal 60.5, N(60.5)
    assert_equal N(60.5), N(60.5)

    assert_equal N(:c4), 60.5
    assert_equal N(60.5), :c4
    assert_equal N(60.5), N(:c4)
    assert_equal N(60.5), 60

    # Accidentals
    assert_equal N(:cs4), 61
    assert_equal N(:cs4), N(61)
    [:cs4, :Cs4, :CS4, :db4, :Db4, :DB4].each do |name|
      assert_equal N(name), 61
      assert_equal 61, N(name)
      assert_equal N(:cs4), name
      assert_equal name, N(:cs4)
      assert_equal N(:cs4), N(name)
      assert_equal N(:cs4), name.to_s
      assert_equal name.to_s, N(:cs4)
      assert_equal N(:cs4), N(name.to_s)
    end

    # Octave wrap-around
    assert_equal N(:b2), :cb3
    assert_equal :cb3, N(:b2)
    assert_equal N(:b2), :cf3
    assert_equal :cf3, N(:b2)
    assert_equal N(:bs3), :c4
    assert_equal :c4, N(:bs3)
    assert_equal N(:cbb4), :as3
    assert_equal :cbb4, N(:as3)
    assert_equal N(:bss4), :cs5
    assert_equal :cs5, N(:bss4)

    # Comparisons with an invalid non-MIDINote
    # right-hand side
    refute N(:c4) == :nope
    refute N(:c4).eql?(:nope)
    assert N(:c4) != :nope
    refute N(:c4) == "nope"
    refute N(:c4).eql?("nope")
    assert N(:c4) != "nope"
    # left-hand side
    # rubocop:disable Style/YodaCondition
    refute :nope == N(:c4)
    refute :nope.eql?(N(:c4))
    assert :nope != N(:c4)
    refute "nope" == N(:c4)
    refute "nope".eql?(N(:c4))
    assert "nope" != N(:c4)

    assert_nil :nope <=> N(:c4)
    assert_nil "nope" <=> N(:c4)
    # rubocop:enable Style/YodaCondition

    # :r and :rest throw a different error if they hit MIDINote.new, so they're
    # worth testing
    refute N(:c4) == :r
    refute N(:c4) == :rest
  end

  def test_missing_octave
    assert_equal N(:c), :c4

    # Octave wrap-around (e.g. cb -> cb4 -> b3)
    assert_equal N(:cb), :b3
    assert_equal N(:bs), :c5
    assert_equal N(:cbb), :as3
    assert_equal N(:bss), :cs5
  end

  def test_octave_mutators
    assert_equal N(:c4).with_octave(1), :c1
    assert_equal N(:c4).with_octave(0), :c0
    assert_equal N(:c4).with_octave(10), :c10
    assert_equal N(:c4).with_octave(-2), :"c-2"

    assert_equal N(:c4).shift_octave(1), :c5
    assert_equal N(:c4).shift_octave(2), :c6
    assert_equal N(:c4).shift_octave(-1), :c3
    assert_equal N(:c4).shift_octave(-4), :c0
    assert_equal N(:c4).shift_octave(-5), :"c-1"

    assert_equal N(:c4).up(2), :c6
    assert_equal N(:c4).down(2), :c2
  end

  def test_shift_tone
    assert_equal N(:c4).shift_tone(1), :cs4
    assert_equal N(:c4).shift_tone(-1), :b3
    assert_equal N(:c4).shift_tone(12), :c5
    assert_equal N(:c4).shift_tone(13), :cs5
    assert_equal N(:c4).shift_tone(-12), :c3
  end

  def test_with_pitch_class
    assert_equal N(:c4).with_pitch_class(:b), :b4
    assert_equal N(:c4).with_pitch_class("b"), :b4
    assert_equal N(:c4).with_pitch_class(:as), :as4
    assert_equal N(:c4).with_pitch_class(:As), :as4
    assert_equal N(:c4).with_pitch_class(:AS), :as4
    assert_equal N(:c4).with_pitch_class("As"), :as4
    assert_equal N(:c4).with_pitch_class("AS"), :as4
    assert_equal N(:c4).with_pitch_class(:ef), :ds4

    # Octave wrap-around
    assert_equal N(:c4).with_pitch_class(:cb), :b3
    assert_equal N(:c4).with_pitch_class(:bs), :c5
    assert_equal N(:c4).with_pitch_class(:cbb), :as3
    assert_equal N(:c4).with_pitch_class(:bss), :cs5
  end

  def test_match
    assert N(:cs4).match?(N(:cs4))
    assert N(:cs4).match?(N(:db4))
    assert N(:cs4).match?(N(:df4))
    assert N(:cs4).match?(:cs4)
    assert N(:cs4).match?(:db4)
    assert N(:cs4).match?(:df4)
    assert N(:cs4).match?(:cs)
    assert N(:cs4).match?(:db)
    assert N(:cs4).match?(:df)
    assert N(:cs4).match?(61)
    assert N(:cs4).match?(:bss)

    refute N(:cs4).match?(:r)
    refute N(:cs4).match?(:rest)
    refute N(:cs4).match?(nil)
  end

  def test_rest?
    assert MIDINote.rest?(:r)
    assert MIDINote.rest?(:rest)
    assert MIDINote.rest?(nil)
    refute MIDINote.rest?("r")
    refute MIDINote.rest?("rest")
    refute MIDINote.rest?(123)
    refute MIDINote.rest?(:c4)
    refute MIDINote.rest?(N(:c))
  end

  def test_has_octave?
    assert MIDINote.has_octave?(N(:c4))
    assert MIDINote.has_octave?(:c4)
    assert MIDINote.has_octave?("c4")
    assert MIDINote.has_octave?(60)
    assert MIDINote.has_octave?(42.5)

    refute MIDINote.has_octave?(:c)
    refute MIDINote.has_octave?("c")

    assert_raises { MIDINote.has_octave?(:nope) }
    assert_raises { MIDINote.has_octave?("blah") }
    assert_raises { MIDINote.has_octave?([]) }
  end

  def test_numeric
    assert_equal N(:c4) + 1, :cs4
    assert_equal 1 + N(:c4), :cs4
    assert_equal N(:c4) - 1, :b3
    assert_equal N(:c4) + 12, :c5
    assert_equal N(:c4) + 13, :cs5
    assert_equal N(:c4) - 12, :c3

    assert_attrs N(:c4) + 0.5, 60, :c4, :c
    assert_attrs 0.5 + N(:c4), 60, :c4, :c
    assert_attrs N(:c4) - 0.5, 60, :c4, :c

    assert_attrs N(:c4) + 1.5, 61, :cs4, :cs
    assert_attrs 1.5 + N(:c4), 61, :cs4, :cs
    assert_attrs N(:c4) - 1.5, 59, :b3, :b

    assert N(:c4) >= 60
    assert N(:c4) >= 59
    assert N(:c4) > 59

    assert N(:c4) <= 60
    assert N(:c4) <= 61
    assert N(:c4) < 61

    [
      [:c1, :c2, :c3],
      [59, :c4, 65],
      [59, 60, 65],
      [59, 60, "C6"],
      ["c0", 60, "d6"],
      [59.5, 60, 61.5],
      [59.5, :c4, 61.5]
    ].each do |vals|
      a, b, c = *vals

      # a against itself
      assert N(a) <= N(a)
      assert N(a) >= N(a)
      assert_equal N(a) <=> N(a), 0

      assert N(a) <= a
      assert N(a) >= a
      assert_equal N(a) <=> a, 0

      assert_equal N(a), N(a)
      assert_equal N(a), a
      assert_equal a, N(a)
      assert a <= N(a)
      assert a >= N(a)
      assert_equal a <=> N(a), 0

      # a < b
      assert N(a) < N(b)
      assert N(a) < b
      assert_equal N(a) <=> N(b), -1
      assert_equal N(a) <=> b, -1

      assert a < N(b)
      assert_equal a <=> N(b), -1

      # b > a
      assert N(b) > N(a)
      assert N(b) > a
      assert_equal N(b) <=> N(a), 1
      assert_equal N(b) <=> a, 1

      assert b > N(a)
      assert_equal b <=> N(a), 1

      # b < c
      assert N(b) < N(c)
      assert N(b) < c
      assert_equal N(b) <=> N(c), -1
      assert_equal N(b) <=> c, -1

      assert b < N(c)
      assert_equal b <=> N(c), -1

      # c > b
      assert N(c) > N(b)
      assert N(c) > b
      assert_equal N(c) <=> N(b), 1
      assert_equal N(c) <=> b, 1

      assert c > N(b)
      assert_equal c <=> N(b), 1
    end

    assert_equal [N(:c3), N(:c2), N(:c1)].sort, [N(:c1), N(:c2), N(:c3)]

    # Very niche things about Numeric that no one should ever use...
    assert_equal N(60) + N(30), N(90)
    assert_equal N(60) * 2, N(120)
    assert_equal N(60) * N(2), N(120)
    assert_equal N(60) / 2, N(30)
    assert_equal N(60) / N(2), N(30)
  end

  def test_snap
    assert_equal N(60).snap([58, 60, 62]), 60
    assert_equal N(60).snap([50, 80]), 50
    assert_equal N(60).snap([40, 70]), 70
    assert_equal N(60.5).snap([40, 70]), 70
    assert_equal N(60.5).snap([40, 70, 60.5]), 60.5

    # In the case of equal distances, the upper note should win.
    assert_equal N(60).snap([50, 70]), 70
    assert_equal N(60).snap([70, 50]), 70
    assert_equal N(60.5).snap([60, 61]), 60
    assert_equal N(60.5).snap([61, 60]), 60
  end

  def test_snap_to_scale
    assert_equal N(:c4).snap_to_scale(:c, :major), :c4
    assert_equal N(:d3).snap_to_scale(:c, :major), :d3
    assert_equal N(:e2).snap_to_scale(:c, :major), :e2
    assert_equal N(:f1).snap_to_scale(:c, :major), :f1
    assert_equal N(:"g-1").snap_to_scale(:c, :major), :"g-1"

    # We should snap upwards.
    assert_equal N(:cs4).snap_to_scale(:c, :major), :d4
    assert_equal N(:eb4).snap_to_scale(:c, :major), :e4
    assert_equal N(:bs4).snap_to_scale(:c, :major), :c5
  end

  def assert_repr(val)
    n = N(val)

    assert_equal n, eval(n.repr)  # rubocop:disable Security/Eval

    # Short repr should be the same as to_sym
    assert_equal n.to_sym, eval(n.repr(short: true))  # rubocop:disable Security/Eval
  end

  def test_repr
    # repr should be the same as to_sym.

    [:cs4, :Cs4, :CS4, :db4, :Db4, :DB4,
     "cs4", "Cs4", "CS4", "db4", "Db4", "DB4",
     61].each do |val|
      assert_repr val
    end

    # Octave wrap-around
    assert_repr :cb4
    assert_repr :bs4
    assert_repr :cbb4
    assert_repr :bss4
  end

  def test_names
    0.upto(127) do |i|
      n = N(i)
      n.names.each do |name|
        other_n = N(name)
        assert_equal n, other_n
        assert_equal n.names, other_n.names
      end
    end
  end
end
