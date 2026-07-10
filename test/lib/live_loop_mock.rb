# frozen_string_literal: true

require_relative "../../lib/spiseq/internal/log"
require_relative "../../lib/spiseq/external/sync"

# Dummy implementation of live_loop for testing purposes. As with the other
# testing stubs, requiring this file in Sonic Pi will break spi-seq playback
# until it is restarted.
#
# Loops are tracked by name to ensure Sonic Pi-like behavior for the argument
# passed to the block between iterations. Namely, the `init` value is only used
# the first time a live loop executes. If it is later redefined (e.g. the sketch
# is restarted), the value the block most recently returned is used across the
# definitions.
#
# NOTE: It is very important that you remember to `stop` the mocked live loop
# threads! State is stored by loop name both here and in TrackLiveLoopUtils, and
# that's only cleared when a thread is stopped. If you don't stop the thread,
# state will linger and may break distant tests that use the same loop name.

class LiveLoopThread < Thread
  @loops = {}
  @last_block_return_by_name = {}

  def self.add_loop_thread(name, thread)
    loops_for_name = @loops[name]
    if loops_for_name.nil?
      @loops[name] = [thread]
    else
      loops_for_name << thread
    end
  end

  def self.remove_loop_thread(name, thread)
    loops_for_name = @loops[name]
    loops_for_name.delete(thread)
    if loops_for_name.empty?
      @loops.delete(name)

      # Clean up the last block return if this was the last thread with that name.
      @last_block_return_by_name.delete(name) if loops_for_name.empty?
    end
  end

  def self.set_block_return(loop_name, val)
    @last_block_return_by_name[loop_name] = val
  end

  def self.get_block_return(loop_name, default: nil)
    @last_block_return_by_name.fetch(loop_name, default)
  end

  def self.clean_up_loops(caller)
    @loops.dup.each do |name, threads|
      expected_loop = name.to_s.end_with?("_cc_fill_watcher") || name.to_s.end_with?("_cc_mute_watcher")
      SpiSeq::Internal::Log.err("lingering loop #{name} in #{caller}") unless expected_loop
      threads.each(&:stop)
    end
  end

  def initialize(name, init: nil, sync: nil, &block)
    @name = name
    @pump_queue = Thread::Queue.new
    @cycle_queue = Thread::Queue.new
    first = true

    super do
      loop do
        break unless @pump_queue.pop

        # Kind of a TODO: this shouldn't be sent on a restart of the same loop.
        # But that's functionality implemented by Sonic Pi that's kind of
        # outside of what we care to test here, so not particularly worth fixing
        SpiSeq::External::Sync.sync(sync) if first && !sync.nil?
        first = false

        # Call the block with the most recent thing it returned (persisted
        # across threads by name), or with `init` if this looks like the first
        # run.
        block_arg = LiveLoopThread.get_block_return(name, default: init)
        block_res = (block.arity == 1) ? block.call(block_arg) : block.call
        LiveLoopThread.set_block_return(name, block_res)
        @cycle_queue << true
      end
    end

    # We want assertion failures (or any other exceptions) to terminate the
    # thread and be re-raised on the main thread.
    self.abort_on_exception = true

    # And since we're going to re-raise, we don't need to report them at the
    # thread level. Especially if, e.g., we're doing an `assert_raises`.
    self.report_on_exception = false

    LiveLoopThread.add_loop_thread(name, self)
  end

  # Runs n many iterations of the given loop. Does not return until all cycles
  # have completed.
  def pump(n = 1)
    raise ArgumentError, "thread is not alive" unless alive?
    n.times do
      @pump_queue << true
      @cycle_queue.pop
    end
  end

  # Gracefully stops and joins the thread. Currently executing loop iterations
  # are allowed to finish. Will not return until the thread exits or the timeout
  # expires. If the timeout expires, the thread is not forcefully stopped.
  # Returns immediately if the thread is already stopped.
  def stop(timeout = 1)
    LiveLoopThread.remove_loop_thread(@name, self)
    return unless alive?
    @pump_queue << false
    raise RuntimeError, "thread join timed out!" if join(timeout).nil?
  end
end

module SpiSeq
  module External
    module Sync
      # The thread this returns is parked and can be signaled to run an
      # iteration with its `pump` method. It can be stopped and joined with
      # `stop`.
      def self.live_loop(name, init: nil, sync: nil, **_kwargs, &)
        LiveLoopThread.new(name, init:, sync:, &)
      end
    end
  end
end
