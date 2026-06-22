#!/usr/bin/env ruby
# frozen_string_literal: true

require "weakref"
require_relative "lib/init"
# We don't need player_mocks in any real sense, but it gets us an implementation
# of External::Sync.sleep, which on_cold_run calls.
require_relative "lib/player_mocks"
require_relative "../lib/spiseq/external/sync"
require_relative "../lib/spiseq/utils/lifecycle"

include SpiSeq::Utils::Lifecycle

# We obviously can't test an actual shutdown of the hosting process, but we can
# simulate it by killing the threads that serve this functionality and seeing
# that everything reacts appropriately.

module SpiSeq; module External; module Sync
  def self.in_thread(name: nil, &block)
    @in_threads ||= {}
    if name
      t = @in_threads[name]
      return if t && t.weakref_alive? && t.alive?
    end

    t = Thread.new do
      block.call
      @in_threads.delete(name) unless name.nil?
    end
    t.abort_on_exception = true
    t.report_on_exception = false

    @in_threads[name] = WeakRef.new(t) unless name.nil?
    Kernel.sleep(0.1)  # Need to make sure the block actually started...
    t
  end

  def self._kill_in_threads
    return if @in_threads.nil?

    @in_threads.each_value do |t|
      next unless t.weakref_alive? && t.alive?
      t.kill
      t.join
    end

    @in_threads.clear
  end
end; end; end

class LifeCycleTest < Test::Unit::TestCase
  def kill_in_threads
    SpiSeq::External::Sync._kill_in_threads
  end

  def test_on_stop
    # Default name
    flag = false
    on_stop { flag = true }
    kill_in_threads
    assert flag

    # Unnamed redefinition
    flag1 = flag2 = false
    on_stop { flag1 = true }
    on_stop { flag2 = true }
    kill_in_threads
    assert_false flag1
    assert flag2

    # Independent names & redefinition
    flag1 = flag2 = flag3 = false
    on_stop(:flag1) { flag3 = true }
    on_stop(:flag2) { flag2 = true }
    on_stop(:flag1) { flag1 = true }
    kill_in_threads
    assert flag1
    assert flag2
    assert_false flag3
  end

  def test_one_time_init
    # Default block
    flag1 = flag2 = false
    one_time_init { flag1 = true }
    one_time_init { flag2 = true }
    assert flag1
    assert_false flag2

    # Named
    flag1 = flag2 = flag3 = false
    one_time_init(:flag1) { flag1 = true }
    one_time_init(:flag2) { flag2 = true }
    one_time_init(:flag1) { flag3 = true }
    assert flag1
    assert flag2
    assert_false flag3
  end

  def test_on_cold_run
    # Default name
    flags = []
    on_cold_run { flags << true }
    on_cold_run { flags << true }
    kill_in_threads
    on_cold_run { flags << true }
    assert flags.length == 2

    # Named
    flags1 = []
    flags2 = []
    flags3 = []
    on_cold_run(:flags1) { flags1 << true }
    on_cold_run(:flags2) { flags2 << true }
    on_cold_run(:flags1) { flags3 << true }
    kill_in_threads
    on_cold_run(:flags1) { flags1 << true }
    on_cold_run(:flags2) { flags2 << true }
    on_cold_run(:flags1) { flags3 << true }
    assert flags1.length == 2
    assert flags2.length == 2
    assert flags3.empty?
  end
end
