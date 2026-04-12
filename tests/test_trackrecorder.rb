#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../trackrecorder"
require_relative "track_test_helpers"

# The record method is very Sonic Pi-specific, obviously, so we can only really
# test timeline_to_track (which is the most important part anyway).
class TrackRecorderTest < Test::Unit::TestCase
  include TrackTestHelpers

  def test_simple
    # 1 sec / slot:
    bpm = 60
    granularity = :quarter

    # These are well-behaved events in that they start exactly at the beginning
    # of a step.
    timeline = [
      [:a1, 1.0, 2.0, 64],
      [:b2, 1.0, 3.0, 72],
      [:c3, 3.0, 3.25, 127],
      [:d4, 5.0, 6.15, 127]
    ]

    # baseline
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0, end_time: 8,
                                        min_gate: 0.1, quantize_gates: false,
                                        ignore_vel: false)
    assert_gt t, granularity, 1.0
    assert_grid t, [[],
                    [S(:a1, vel: 64), S(:b2, vel: 72)],
                    [S(:b2, vel: 72)],
                    [S(:c3, gate: 0.25)],
                    [],
                    [:d4],
                    [S(:d4, gate: 0.15)],
                    []]

    # ignore_vel
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0, end_time: 8,
                                        min_gate: 0.1, quantize_gates: false,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[],
                    [:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.25)],
                    [],
                    [:d4],
                    [S(:d4, gate: 0.15)],
                    []]

    # quantize_gates
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0, end_time: 8,
                                        min_gate: 0.1, quantize_gates: true,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[],
                    [:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.3)],
                    [],
                    [:d4],
                    [S(:d4, gate: 0.2)],
                    []]

    # left trim
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: nil, end_time: 8,
                                        min_gate: 0.1, quantize_gates: false,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.25)],
                    [],
                    [:d4],
                    [S(:d4, gate: 0.15)],
                    []]

    # left + right trim
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: nil, end_time: nil,
                                        min_gate: 0.1, quantize_gates: false,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.25)],
                    [],
                    [:d4],
                    [S(:d4, gate: 0.15)]]

    # min gate big enough to remove a final step
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0, end_time: 8,
                                        min_gate: 0.2, quantize_gates: false,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[],
                    [:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.25)],
                    [],
                    [:d4],
                    [],
                    []]

    # trimming should remove a rest made by a removed final step
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0, end_time: nil,
                                        min_gate: 0.2, quantize_gates: false,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[],
                    [:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.25)],
                    [],
                    [:d4]]

    # min gate big enough to round up a single step
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0, end_time: 8,
                                        min_gate: 0.5, quantize_gates: false,
                                        ignore_vel: true)
    assert_gt t, granularity, 1.0
    assert_grid t, [[],
                    [:a1, :b2],
                    [:b2],
                    [S(:c3, gate: 0.5)],
                    [],
                    [:d4],
                    [],
                    []]
  end

  def test_unaligned_starts
    # 1 sec / slot:
    bpm = 60
    granularity = :quarter

    # start snaps up to slot 2, end time remains the same
    timeline = [[:a1, 1.5, 2.5, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0)
    assert_grid t, [[], [], [S(:a1, gate: 0.5)]]

    # start snaps down to slot 1, end time remains the same
    timeline = [[:a1, 1.1, 2.5, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0)
    assert_grid t, [[], [:a1], [S(:a1, gate: 0.5)]]

    # starts on a step, end time quantized up to a tie
    timeline = [[:a1, 1.0, 2.95, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 0)
    assert_grid t, [[], [:a1], [:a1]]
  end

  def test_secs_per_slot
    # some spot-checks of bpm/granularity interplay

    timeline = [[:a1, 0.0, 1.0, 127]]

    # 60/quarter -> 1s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 60, granularity: :quarter, quantize_gates: false)
    assert_gt t, :quarter, 1.0
    assert_grid t, [[:a1]]

    # 120/quarter -> 0.5s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 120, granularity: :quarter, quantize_gates: false)
    assert_gt t, :quarter, 1.0
    assert_grid t, [[:a1], [:a1]]

    # 150/quarter -> 0.4s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 150, granularity: :quarter, quantize_gates: false)
    assert_gt t, :quarter, 1.0
    assert_grid t, [[:a1], [:a1], [S(:a1, gate: 0.5)]]

    # 60/whole -> 4s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 60, granularity: :whole, quantize_gates: false)
    assert_gt t, :whole, 1.0
    assert_grid t, [[S(:a1, gate: 0.25)]]

    # 120/whole -> 2s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 120, granularity: :whole, quantize_gates: false)
    assert_gt t, :whole, 1.0
    assert_grid t, [[S(:a1, gate: 0.5)]]

    # 60/sixteenth -> 0.25s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 60, granularity: :sixteenth, quantize_gates: false)
    assert_gt t, :sixteenth, 1.0
    assert_grid t, [[:a1], [:a1], [:a1], [:a1]]

    # 120/sixteenth -> 0.125s/slot
    t = TrackRecorder.timeline_to_track(timeline, bpm: 120, granularity: :sixteenth, quantize_gates: false)
    assert_gt t, :sixteenth, 1.0
    assert_grid t, [[:a1], [:a1], [:a1], [:a1], [:a1], [:a1], [:a1], [:a1]]

    # 45/quarter -> 1.33s/slot
    # quantizing to avoid rounding error
    t = TrackRecorder.timeline_to_track(timeline, bpm: 45, granularity: :quarter,
                                        min_gate: 0.01, quantize_gates: true)
    assert_gt t, :quarter, 1.0
    assert_grid t, [[S(:a1, gate: 0.75)]]

    # 90/quarter -> 0.66s/slot
    # quantizing to avoid rounding error
    t = TrackRecorder.timeline_to_track(timeline, bpm: 90, granularity: :quarter,
                                        min_gate: 0.01, quantize_gates: true)
    assert_gt t, :quarter, 1.0
    assert_grid t, [[:a1], [S(:a1, gate: 0.50)]]
  end

  def test_weird_timeline
    # 1 sec / slot:
    bpm = 60
    granularity = :quarter

    # events starting before the start time should get moved to the start time
    timeline = [[:a1, 0.5, 1.5, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        start_time: 1)
    assert_grid t, [[S(:a1, gate: 0.5)]]

    # events ending after the end time should get snapped to it
    timeline = [[:a1, 0, 1.5, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity,
                                        end_time: 1)
    assert_grid t, [[:a1]]

    # events that end before they start should be ignored
    timeline = [[:a1, 1, 0, 127], [:b2, 0, 1, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity)
    assert_grid t, [[:b2]]

    # events with 0 duration should be ignored
    timeline = [[:a1, 1, 1, 127], [:b2, 0, 1, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity)
    assert_grid t, [[:b2]]

    # events with 0 duration should not extend the track if we're trimming
    timeline = [[:a1, 5, 5, 127], [:b2, 0, 1, 127]]
    t = TrackRecorder.timeline_to_track(timeline,
                                        bpm: bpm, granularity: granularity)
    assert_grid t, [[:b2]]
  end
end
