# frozen_string_literal: true

require_relative "../extapi"
require_relative "internal_utils"

# @!group Sonic Pi lifecycle utilities

# @private
module SpiSeq
  module Lifecycle
    class << self
      attr_accessor :one_time_init_keys, :stop_hooks
    end

    self.one_time_init_keys = Set.new
    self.stop_hooks = {}
  end
end

# Executes its block the first time this sketch runs, and whenever it is
# restarted after having been stopped. The block will not run if the sketch is
# simply restarted while already running. `key` is used to uniquely identify
# each cold-run block. If you need independent cold-run blocks, you should
# provide different keys for each call to this function.
# @param key [Symbol] A unique name for the handler.
# @return [void]
# @yield
def on_cold_run(key = :default, &block)
  thread_name = :"__cold_run_#{key}"
  ExtApi.in_thread(name: thread_name) do
    block.call

    # spin to keep this thread alive until the script is manually stopped
    loop { ExtApi.sleep(100) }
  end
end

# Executes its block exactly once per run of Sonic Pi. The `key` argument, if
# provided, disambiguates different blocks; if you need independent one-time
# initializers, you should provide different keys for each call to this
# function.
# @param key [Symbol] A unique name for the handler.
# @return [void]
# @yield
def one_time_init(key = :default)
  keys = SpiSeq::Lifecycle.one_time_init_keys
  unless keys.include?(key)
    yield
    keys.add(key)
  end
end

# Registers a block to execute when Sonic Pi's execution is stopped or when
# quitting the application. The work you do in the block should be very quick or
# you will delay the stop operation or shutdown.
#
# If you need more than one stop hook, you must give them each different
# `name`s; calling this function a second time with the same name will remove
# the previous hook with that name.
#
# Hooks are serviced using an internal thread which waits for the sketch to
# stop. Calling this method will thus prevent your sketch from exiting naturally
# if there are no other `live_loop`s or `in_thread` calls keeping it alive.
#
# @return [void]
# @yield
def on_stop(name = :default, &block)
  SpiSeq::Lifecycle.stop_hooks[name] = block

  # Since we give this a name, Sonic Pi will only define it once.
  ExtApi.in_thread(name: :__stop_hook_watcher) do
    kq = Thread::Queue.new
    Thread.current[:__kill_queue] = kq
    kq.pop

    hooks = SpiSeq::Lifecycle.stop_hooks
    unless hooks.empty?
      SpiSeq::Log.log("Running stop hooks...", "stop-hooks")
      hooks.each_value { |b| b.call }
      hooks.clear
      SpiSeq::Log.log("Stop hooks complete", "stop-hooks")
    end
  end
end

# @!endgroup

# This is a bit of a sin but the alternative is some overriding of Sonic Pi
# internals and hopping between the special user threads it uses. This way we
# can at least easily execute the hooks in a sensible thread context.
# @private
module SpiSeq
  module MonkeyPatches
    module ThreadKill
      def kill
        # If there's a magic Thread::Queue thread-local variable, signal it and
        # join; we hope the thread exits quickly after we push to the queue.
        kill_queue = self[:__kill_queue]
        if kill_queue.nil?
          super
        else
          kill_queue << true
          join
        end
      end
    end
  end
end

# @private
class Thread
  prepend SpiSeq::MonkeyPatches::ThreadKill
end
