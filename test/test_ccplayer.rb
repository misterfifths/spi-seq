#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/player_helpers"
require_relative "../lib/spiseq/playback/ccplayer"

include SpiSeq::Playback
include SpiSeq::Tracks

# Most of CCPlayer's behavior is inherited from PlayerBase, so there's no real
# need to retest e.g. sleep, stop, and MIDI device targeting.

class CCPlayerTest < Test::Unit::TestCase
  include PlayerHelpers

  def setup
    use_bpm 60
  end

  A = CC(1, 11)
  B = CC(2, 12)
  C = CC(3, 13)
  D = CC(4, 14)

  def _cc_step_at(step, t, val: nil, port: nil, channel: nil)
    shorthand = [step.num, val || step.val, t]
    shorthand << port unless port.nil? && channel.nil?
    shorthand << channel unless channel.nil?
    shorthand
  end

  def a_at(t, **)
    _cc_step_at(A, t, **)
  end

  def b_at(t, **)
    _cc_step_at(B, t, **)
  end

  def c_at(t, **)
    _cc_step_at(C, t, **)
  end

  def d_at(t, **)
    _cc_step_at(D, t, **)
  end

  def test_basics
    # Correct basic start times
    assert_playback_events CCT[A], [a_at(0)]
    assert_playback_events CCT[A, B], [a_at(0), b_at(0.5)]
    assert_playback_events CCT[A, :r, B, granularity: :quarter], [a_at(0), b_at(2)]

    # Multiple steps per slot
    assert_playback_events CCT[[A, B], :r, [C, D], granularity: :quarter], [
      a_at(0), b_at(0),
      c_at(2), d_at(2)
    ]

    # There is no such thing as a tie
    assert_playback_events CCT[A, A, granularity: :quarter], [
      a_at(0), a_at(1)
    ]
    assert_playback_events CCT[A, A.with_val(127), granularity: :quarter], [
      a_at(0),
      a_at(1, val: 127),
      a_at(2),
      a_at(3, val: 127)
    ], play_count: 2
  end
end
