#!/usr/bin/env ruby

# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/player_helpers"
require_relative "../lib/spiseq/external/sync"
require_relative "../lib/spiseq/utils/live_loops"

class MutableLiveLoopTest < Test::Unit::TestCase
  BROKEN_IN_SONIC_PI = true

  include PlayerHelpers
  include SpiSeq::Utils::LiveLoops

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
      sleep(1)
    end
    es = events do
      l.pump 4
      l.stop
    end
    assert_events es, [[:sync, :test_sync, 0]]
  end

  def test_cc_mutable
    # Testing the actual mute functionality isn't possible without a *lot* more
    # stubbing of Sonic Pi methods (actually making `sync` work, e.g.). But we
    # can at least test the initial CC send and use_cc_control_defaults.

    # Should send a CC at creation with value 127. Recreating the same loop name
    # should not send another CC.
    es = events do
      l1 = cc_mutable_live_loop(:t, cc: 64) { |_| sleep(1) }
      l1.pump
      l2 = cc_mutable_live_loop(:t, cc: 64, start_muted: true) { |_| sleep(1) }
      l1.pump
      l2.pump
      l2.stop
      l1.stop
    end
    assert_events es, [[64, 127, 0]]

    # start_muted should send a CC with value 0.
    es = events do
      l = cc_mutable_live_loop(:t, cc: 10, start_muted: true) { |_| sleep(1) }
      l.stop
    end
    assert_events es, [[10, 0, 0]]
  end

  def assert_init_cc_port_channel(port = nil, channel = nil)
    es = events do
      l = cc_mutable_live_loop(:t, cc: 10) { |_| sleep(1) }
      l.pump
      l.stop

      l = cc_mutable_live_loop(:t, cc: 10, port: "specific port") { |_| sleep(1) }
      l.pump
      l.stop

      l = cc_mutable_live_loop(:t, cc: 10, channel: 5) { |_| sleep(1) }
      l.pump
      l.stop

      l = cc_mutable_live_loop(:t, cc: 10, port: "specific port", channel: 3) { |_| sleep(1) }
      l.pump
      l.stop
    end
    assert_events es, [
      [10, 127, 0, port, channel],
      [10, 127, 1, "specific port", channel],
      [10, 127, 2, port, 5],
      [10, 127, 3, "specific port", 3]
    ]
  end

  def test_cc_defaults
    old_defaults = current_cc_control_defaults

    use_cc_control_defaults(port: "default_device")
    assert_init_cc_port_channel("default_device")

    use_cc_control_defaults(channel: 6)  # should have cleared the port
    assert_init_cc_port_channel(nil, 6)

    use_cc_control_defaults(port: "default device", channel: 7)
    assert_init_cc_port_channel("default device", 7)

    use_cc_control_defaults(channel: nil)
    assert_init_cc_port_channel(nil, nil)

    use_cc_control_defaults(**old_defaults)
  end
end
