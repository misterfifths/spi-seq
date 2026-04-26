#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "player_extapi_stubs"
require_relative "player_test_helpers"
require_relative "../player"
require_relative "../theory/scale"

class PlayerTest < Test::Unit::TestCase
  include PlayerTestHelpers

  def assert_sleep(track)
    # Sleeping should not issue any MIDI events and should last the duration of
    # the track.
    p = player(track)
    es = nil
    assert_duration(track.beat_length / track.timescale) do
      es = events { p.sleep }
    end
    assert_empty es
  end

  def test_sleep
    use_bpm 60

    assert_sleep T(:c4, granularity: :quarter)
    assert_sleep T(:c4)
    assert_sleep T([:c4, :d4])
    assert_sleep T([[:c4, :d4], [:e4, :f4]], granularity: :whole)

    assert_sleep T([:c4, :d4], granularity: :whole, timescale: 2)
    assert_sleep T([:c4, :d4], granularity: :quarter, timescale: 8)
    assert_sleep T([:c4, :d4], granularity: :half, timescale: 0.5)
    assert_sleep T([:c4, :d4], granularity: :half, timescale: 0.125)

    # A sleep should terminate held ties.
    p = player(T([:c4, :c4], granularity: :quarter))
    es = events do
      p.play
      p.sleep
    end
    assert_events es, [[:c4, 0, 2]]
  end

  def test_basics
    use_bpm 60

    # Basics of duration & ties
    assert_playback_events T(:c4), [[:c4, 0, nil]]  # No off event since this is tied.
    assert_playback_events T([:c4, :r], granularity: :quarter), [[:c4, 0, 1]]
    assert_playback_events T([S(:c4, gate: 0.5)], granularity: :quarter), [[:c4, 0, 0.5]]
    assert_playback_events T([:c4, S(:c4, gate: 0.25)], granularity: :quarter), [[:c4, 0, 1.25]]

    # Multiple steps per slot
    assert_playback_events T([[:c4, :d4], :r], granularity: :quarter), [
      [:c4, 0, 1],
      [:d4, 0, 1]
    ]
    assert_playback_events T([[:c4, :d4], :d4], granularity: :quarter), [
      [:c4, 0, 1],
      [:d4, 0, nil]
    ]
    assert_playback_events T([[:c4, :d4], S(:d4, gate: 0.3)], granularity: :quarter), [
      [:c4, 0, 1],
      [:d4, 0, 1.3]
    ]
    assert_playback_events T([[:c4], [:c4, :d4]], granularity: :quarter), [
      [:c4, 0, nil],
      [:d4, 1, nil]
    ]
  end

  def test_midi_devices
    use_midi_defaults
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "*", "*"]]
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "midi_device", "*"]], port: "midi_device"
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "*", 2]], channel: 2
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "midi_device", 8]], port: "midi_device", channel: 8

    use_midi_defaults(port: "default_device")
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "default_device", "*"]]
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "default_device", 5]], channel: 5
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "another_device", "*"]], port: "another_device"

    use_midi_defaults(channel: 4)
    # That should have cleared the default port.
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "*", 4]]
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "another_device", 4]], port: "another_device"
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "*", 3]], channel: 3

    use_midi_defaults(port: "def_dev", channel: 6)
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "def_dev", 6]]
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "another_device", 6]], port: "another_device"
    assert_playback_events T(:c4), [[:c4, 0, nil, 127, "def_dev", 3]], channel: 3

    use_midi_defaults
  end

  def test_vel
    use_bpm 60

    assert_playback_events T(:c4), [[:c4, 0, nil, 127]]
    assert_playback_events T(S(:c4, vel: 64)), [[:c4, 0, nil, 64]]

    # Velocity changes over the lifespan of a tied note are ignored.
    assert_playback_events T([S(:c4, vel: 98), S(:c4, vel: 64), :r], granularity: :quarter), [
      [:c4, 0, 2, 98]
    ]
  end

  def test_bpm
    use_bpm 60
    assert_playback_events T([:c4, :r]), [[:c4, 0, 0.5]]
    assert_playback_events T([:c4, :r], granularity: :quarter), [[:c4, 0, 1]]
    assert_playback_events T([:c4, :r], granularity: :whole), [[:c4, 0, 4]]

    use_bpm 120
    assert_playback_events T([:c4, :r]), [[:c4, 0, 0.25]]
    assert_playback_events T([:c4, :r], granularity: :quarter), [[:c4, 0, 0.5]]
    assert_playback_events T([:c4, :r], granularity: :whole), [[:c4, 0, 2]]

    use_bpm 30
    assert_playback_events T([:c4, :r]), [[:c4, 0, 1]]
    assert_playback_events T([:c4, :r], granularity: :quarter), [[:c4, 0, 2]]
    assert_playback_events T([:c4, :r], granularity: :whole), [[:c4, 0, 8]]
  end

  def test_timescale
    use_bpm 60
    assert_playback_events T([:c4, :r], granularity: :quarter, timescale: 2), [[:c4, 0, 0.5]]
    assert_playback_events T([:c4, :r], granularity: :quarter, timescale: 0.5), [[:c4, 0, 2]]
    assert_playback_events T([:c4, :r], granularity: :whole, timescale: 0.5), [[:c4, 0, 8]]
    assert_playback_events T([:c4, :r], granularity: :whole, timescale: 4), [[:c4, 0, 1]]

    use_bpm 120
    assert_playback_events T([:c4, :r], granularity: :quarter, timescale: 2), [[:c4, 0, 0.25]]
    assert_playback_events T([:c4, :r], granularity: :quarter, timescale: 0.5), [[:c4, 0, 1]]
    assert_playback_events T([:c4, :r], granularity: :whole, timescale: 0.5), [[:c4, 0, 4]]
    assert_playback_events T([:c4, :r], granularity: :whole, timescale: 4), [[:c4, 0, 0.5]]
  end

  def test_scale
    use_bpm 60

    cmaj = Scale.full_scale(:c, :major)

    # Notes should snap to the scale at play time.
    assert_playback_events T([:c4, :cs3, :ds3, :f3, :as3], granularity: :quarter, scale: cmaj), [
      [:c4, 0, 1],
      [:d3, 1, 2],
      [:e3, 2, 3],
      [:f3, 3, 4],
      [:b3, 4, nil]
    ]

    # Snapped notes should tie into their unsnapped version.
    assert_playback_events T([:d3, :cs3, :r], granularity: :quarter, scale: cmaj), [
      [:d3, 0, 2]
    ]
    assert_playback_events T([:cs3, :d3, :r], granularity: :quarter, scale: cmaj), [
      [:d3, 0, 2]
    ]
    assert_playback_events T([:cs3, S(:d3, gate: 0.25), :r], granularity: :quarter, scale: cmaj), [
      [:d3, 0, 1.25]
    ]
    assert_playback_events T([:cs3, :d3], granularity: :quarter, scale: cmaj), [
      [:d3, 0, nil]
    ]

    # If snapping results in duplicate notes, the one with the longest gate
    # should win.
    assert_playback_events T([[S(:d3, gate: 0.5), S(:cs3, gate: 0.75)]], granularity: :quarter, scale: cmaj), [
      [:d3, 0, 0.75]
    ]

    # Duplicate notes from snaps should also tie.
    assert_playback_events T([[:d3, :cs3], [:d3]], scale: cmaj), [[:d3, 0, nil]]
  end

  def test_swap_track
    use_bpm 60

    p = player(T(:c4, granularity: :quarter))
    es = events do
      p.play
      p.play
      assert_equal p.cycle, 2

      p.swap_track(T([:r, :d4]))  # note the granularity
      # cycle is not reset by default
      assert_equal p.cycle, 2
      p.play
      assert_equal p.cycle, 3

      # This should tie to the previous track
      p.swap_track(T(S(:d4, gate: 0.5), granularity: :quarter), reset_cycle: true)
      assert_equal p.cycle, 0
      p.play
      assert_equal p.cycle, 1
    end
    assert_events es, [
      [:c4, 0, 2],
      [:d4, 2.5, 3.5]
    ]

    # Swapping between timescales
    p = player(T(:c4, granularity: :quarter, timescale: 0.5))
    es = events do
      p.play
      p.swap_track(T([:r, :d4, :r], granularity: :whole, timescale: 2))
      p.play
    end
    assert_events es, [
      [:c4, 0, 2],
      [:d4, 4, 6]
    ]

    # Swapping between scales
    cmaj = Scale.full_scale(:c, :major)
    p = player(T(:cs4, granularity: :quarter, scale: cmaj))
    es = events do
      p.play
      p.swap_track(T(:cs4, granularity: :quarter))
      p.play
    end
    assert_events es, [
      [:d4, 0, 1],
      [:cs4, 1, nil]
    ]

    # sleep should function on the new track
    p = player(T(:c4, granularity: :quarter))
    es = events do
      p.play
      p.swap_track(T([:d4, :e4], granularity: :quarter))
      p.sleep
    end
    assert_in_delta secs_per_beat(3), vt
    assert_events es, [[:c4, 0, 1]]
  end

  def test_stop
    use_bpm 60

    # stop should terminate held ties and reset cycle
    p = player(T(:c4, granularity: :quarter))
    es = events do
      p.play
      p.play
      assert_equal p.cycle, 2
      p.stop
      assert_equal p.cycle, 0
    end
    assert_events es, [[:c4, 0, 2]]
  end

  def test_cycle
    # cycle should increase with play but not sleep
    p = player(T(:c4))
    assert_equal p.cycle, 0
    5.times do |i|
      p.play
      assert_equal p.cycle, i + 1
    end
    p.sleep
    assert_equal p.cycle, 5

    # stop and optionally swap_track should reset cycle, but those are tested
    # elsewhere
  end

  def test_final_ties_in_loop
    use_bpm 60

    # A tie at the end of a track should be terminated when that track loops if
    # it's not continued in the first slot.
    assert_playback_events T([:r, :c4], granularity: :quarter), [
      [:c4, 1, 2],
      [:c4, 3, 4],
      [:c4, 5, nil]
    ], play_count: 3

    # Final ties should continue seamlessly into the same note if it's present
    # at the beginning of the track.
    assert_playback_events T([S(:c4, gate: 0.5), :c4], granularity: :quarter), [
      [:c4, 0, 0.5],  # first note
      [:c4, 1, 2.5],  # final tie, looping back to the first note, then ending
      [:c4, 3, 4.5],  # final tie again, looping again
      [:c4, 5, nil]   # final tie, held
    ], play_count: 3

    assert_playback_events T([:c4, :r, :c4], granularity: :quarter), [
      [:c4, 0, 1],  # first note
      [:c4, 2, 4],  # final tie, looping back to the first note, then ending
      [:c4, 5, 7],  # final tie, looping again
      [:c4, 8, nil] # final tie, held
    ], play_count: 3

    # Final ties should loop seamlessly if they are continued.
    assert_playback_events T([:c4, :c4], granularity: :quarter), [
      [:c4, 0, nil]
    ], play_count: 5
  end
end
