#!/usr/bin/env ruby
# frozen_string_literal: true

require "test/unit"
require_relative "../track"
require_relative "track_test_helpers"

# Test basic Track methods - simple methods, direct attr mutators, etc.
class TrackBasicTest < Test::Unit::TestCase
  include TrackTestHelpers

  def test_basic_methods
    assert_equal T(:c4).num_slots, 1
    assert_equal T([:c4, :d4]).num_slots, 2

    assert_equal T(:c4).beat_length, 0.5
    assert_equal T([:c4, :d4]).beat_length, 1
    assert_equal T([:c4, :d4], granularity: :whole).beat_length, 8

    assert T(:r).empty?
    assert T([:r, :r]).empty?
    refute T(:c4).empty?

    assert T(:r).mono?
    assert T(:c4).mono?
    assert T([:c4, :d4]).mono?
    refute T([:c4, [:d4, :e4]]).mono?

    refute T(:r).poly?
    refute T(:c4).poly?
    refute T([:c4, :d4]).poly?
    assert T([:c4, [:d4, :e4]]).poly?
  end

  def test_attr_mutators
    assert_gt T(:c4).with_granularity(:whole), NoteLength::Whole, 1
    assert_gt T(:c4, granularity: :half).with_granularity(:sixteenth), NoteLength::Sixteenth, 1

    assert_gt T(:c4).with_rate(2), NoteLength::Eighth, 2
    assert_gt T(:c4, timescale: 5).with_rate(0.5), NoteLength::Eighth, 0.5
  end
end
