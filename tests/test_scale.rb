#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../theory/scale"

class ScaleTest < Test::Unit::TestCase
  def test_basics
    sc = Scale.new(:c4, :major)
    assert_equal sc.name, :major
    assert_equal sc.tonic, :c4
    assert_equal sc.num_octaves, 1
    assert_equal sc.clamp_to_midi, false
    assert_equal sc.notes, [:c4, :d4, :e4, :f4, :g4, :a4, :b4, :c5]
    assert_equal sc.to_a, [:c4, :d4, :e4, :f4, :g4, :a4, :b4, :c5]

    sc = Scale.new(:c4, :minor, num_octaves: 2)
    assert_equal sc.name, :minor
    assert_equal sc.tonic, :c4
    assert_equal sc.num_octaves, 2
    assert_equal sc.clamp_to_midi, false
    assert_equal sc.notes, [:c4, :d4, :ds4, :f4, :g4, :gs4, :as4, :c5, :d5, :ds5, :f5, :g5, :gs5, :as5, :c6]
    assert_equal sc.to_a, [:c4, :d4, :ds4, :f4, :g4, :gs4, :as4, :c5, :d5, :ds5, :f5, :g5, :gs5, :as5, :c6]
  end

  def test_full_scale
    sc = Scale.full_scale(:c, :mixolydian)

    assert_equal sc[0], :"c-1"
    assert_equal sc[-1], :g9

    sc.each do |n|
      assert n >= 0
      assert n <= 127
    end

    # A scale that starts on B should contain notes below :b-1.
    sc = Scale.full_scale(:b, :major)
    assert_equal sc[0], :"cs-1"
    assert_equal sc[-1], :fs9
  end

  def test_degree_methods
    sc = Scale.new(:c4, :major)

    assert_raises { sc.degree(0) }
    assert_raises { sc.degree(9) }

    assert_raises { sc.degree_of(:c3) }
    assert_raises { sc.degree_of(:cs4) }

    [:c4, :d4, :e4, :f4, :g4, :a4, :b4, :c5].each_with_index do |n, i|
      assert_equal sc.degree(i + 1), n
      assert_equal sc.degree_of(n), i + 1
      assert_equal sc.note_at_step(:c4, i), n
      assert_equal sc.steps_between(:c4, n), i
    end

    [
      [1,  :f4, :f4],
      [2,  :f4, :g4],
      [5,  :f4, :c5],
      [-1, :f4, :e4],
      [-2, :f4, :d4],
      [-3, :f4, :c4]
    ].each do |degree, rel_tonic, note|
      assert_equal sc.degree(degree, relative_tonic: rel_tonic), note
      assert_equal sc.degree_of(note, relative_tonic: rel_tonic), degree
      assert_equal sc.note_at_step(rel_tonic, (degree > 0) ? degree - 1 : degree), note
      assert_equal sc.steps_between(rel_tonic, note), (degree > 0) ? degree - 1 : degree
    end

    assert_raises { sc.degree(1, relative_tonic: :d6) }
    assert_raises { sc.degree(3, relative_tonic: :b4) }

    assert_raises { sc.degree_of(:c3, relative_tonic: :d6) }
    assert_raises { sc.degree_of(:d6, relative_tonic: :c3) }
  end

  def test_degree_symbols
    [
      [:c4,  1, :p1, :pi, :dd2, :ddii],
      [:cs4, :a1, :ai, :d2, :dii],
      [:d4,  2, :p2, :pii, :aa1, :aai, :dd3, :ddiii],
      [:ds4, :a2, :aii, :d3, :diii, :dd4, :ddiv],
      [:e4, 3, :p3, :piii, :aa2, :aaii, :d4, :div],
      [:f4, 4, :p4, :piv, :a3, :aiii, :dd5, :ddv],
      [:fs4, :a4, :aiv, :d5, :dv],
      [:g4, 5, :p5, :pv, :aa4, :aaiv, :dd6, :ddvi],
      [:gs4, :a5, :av, :d6, :dvi],
      [:a4, 6, :p6, :pvi, :aa5, :aav, :dd7, :ddvii],
      [:as4, :a6, :avi, :d7, :dvii, :dd8, :ddviii],
      [:b4, 7, :p7, :pvii, :aa6, :aavi, :d8, :dviii],
      [:c5, 8, :p8, :pviii, :a7, :avii, :dd9, :ddix],
      [:cs5, :a8, :aviii, :aa7, :aavii, :d9, :dix],
      [:d5, 9, :p9, :aa8, :aaviii, :dd10, :ddx]
    ].each do |res, *degrees|
      degrees.each do |d|
        assert_equal res, Scale.degree(d, :c4, :major)
        assert_equal res, Scale.degree(d.to_s, :c4, :major)
        assert_equal res, Scale.degree(d.to_s.upcase, :c4, :major)
        assert_equal res, Scale.degree(d.to_s.upcase.to_sym, :c4, :major)

        next unless ExtApi.in_sonic_pi?
        spi_degree = ExtApi.spi_call(:degree, d, :c4, :major)
        assert_equal res, N(spi_degree)
      end
    end

    assert_raises(ArgumentError) { Scale.degree(:nope, :c4, :major) }
    assert_raises(ArgumentError) { Scale.degree(:do, :c4, :major) }

    # The prefixes are parsed greedily, so this reads as double diminished
    # without a number.
    assert_raises(ArgumentError) { Scale.degree(:dd, :c4, :major) }

    # This one will parse, but the scale does not contain a 500th degree, so
    # we get a range error instead.
    assert_raises(RangeError) { Scale.degree(:ddd, :c4, :major) }
  end

  def test_snap
    s = Scale.full_scale(:c, :major)

    assert_equal s.snap(:c4), :c4
    assert_equal s.snap(:d3), :d3
    assert_equal s.snap(:e2), :e2
    assert_equal s.snap(:f1), :f1
    assert_equal s.snap(:"g-1"), :"g-1"

    # We should snap upwards.
    assert_equal s.snap(:cs4), :d4
    assert_equal s.snap(:eb4), :e4
    assert_equal s.snap(:bs4), :c5
  end

  def assert_repr(sc)
    roundtrip = eval(sc.repr)  # rubocop:disable Security/Eval
    assert_equal roundtrip.name, sc.name
    assert_equal roundtrip.tonic, sc.tonic
    assert_equal roundtrip.num_octaves, sc.num_octaves
    assert_equal roundtrip.clamp_to_midi, sc.clamp_to_midi
    assert_equal roundtrip.notes, sc.notes
  end

  def test_repr
    assert_repr Scale.new(:c4, :major)
    assert_repr Scale.new(:c4, :major, num_octaves: 2)
    assert_repr Scale.new(:c4, :major, num_octaves: 10, clamp_to_midi: true)

    assert_repr Scale.full_scale(:c, :minor)
  end
end
