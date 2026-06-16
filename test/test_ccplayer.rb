#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "player_extapi_stubs"
require_relative "player_test_helpers"
require_relative "../ccplayer"

# Most of CCPlayer's behavior is inherited from PlayerBase, so there's no real
# need to retest e.g. sleep, stop, and MIDI device targeting.

class CCPlayerTest < Test::Unit::TestCase
  include PlayerTestHelpers

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

  def a_at(t, **kwargs)
    _cc_step_at(A, t, **kwargs)
  end

  def b_at(t, **kwargs)
    _cc_step_at(B, t, **kwargs)
  end

  def c_at(t, **kwargs)
    _cc_step_at(C, t, **kwargs)
  end

  def d_at(t, **kwargs)
    _cc_step_at(D, t, **kwargs)
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
