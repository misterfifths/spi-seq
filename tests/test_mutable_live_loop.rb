#!/usr/bin/env ruby

# frozen_string_literal: true

require_relative "test_helper"
require_relative "../utils/live_loop_utils"
require_relative "player_test_helpers"

class MutableLiveLoopTest < Test::Unit::TestCase
  include PlayerTestHelpers

  def test_start_muted
    l = mutable_live_loop(:t) do |muted|
      assert_false muted
    end
    l.pump
    l.stop

    l = mutable_live_loop(:t, start_muted: true) do |muted|
      assert_true muted
    end
    l.pump
    l.stop
  end

  def test_mute_unmute
    expected_mutings = [false, false, true, false, false]
    cycle = 0
    l = mutable_live_loop(:t) do |muted|
      assert_equal expected_mutings[cycle], muted
      cycle += 1
    end
    l.pump 2
    mute_live_loop(:t)
    l.pump
    unmute_live_loop(:t)
    l.pump 2
    l.stop
  end

  def test_arg
    expected_args = [5, 6, 7, 8]
    cycle = 0
    l = mutable_live_loop(:t, init: 5) do |_, arg|
      assert_equal expected_args[cycle], arg
      cycle += 1
      arg + 1
    end
    l.pump 4
    l.stop
  end

  def test_sync
    l = mutable_live_loop(:t, sync: :test_sync) do |_|
      ExtApi.sleep(1)
    end
    es = events do
      l.pump 4
    end
    assert_events es, [[:sync, :test_sync, 0]]
  end
end
