# frozen_string_literal: true

require_relative "../external/sync"

# Dummy implementation of live_loop for testing purposes. As with the other
# testing stubs, requiring this file in Sonic Pi will break spi-seq playback
# until it is restarted.
#
# No attempt is made to enforce uniquely named live loops. And, since there is
# only one global event tracker in player_extapi_stubs, you should only attempt
# to deal with one of these fake live loops at a time.

class LiveLoopThread < Thread
  def initialize(init: nil, sync: nil, &block)
    @pump_queue = Thread::Queue.new
    @cycle_queue = Thread::Queue.new
    first = true

    super do
      loop do
        break unless @pump_queue.pop

        SpiSeq::External::Sync.sync(sync) if first && !sync.nil?
        first = false

        init = (block.arity == 1) ? block.call(init) : block.call
        @cycle_queue << true
      end
    end

    # We want assertion failures (or any other exceptions) to terminate the
    # thread and be re-raised on the main thread.
    self.abort_on_exception = true

    # And since we're going to re-raise, we don't need to report them at the
    # thread level. Especially if, e.g., we're doing an `assert_raises`.
    self.report_on_exception = false
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
      def self.live_loop(_name, init: nil, sync: nil, **_kwargs, &block)
        LiveLoopThread.new(init: init, sync: sync, &block)
      end
    end
  end
end
