# frozen_string_literal: true

require_relative "../external/sync"
require_relative "../internal/log"

module SpiSeq; module Internal; module MonkeyPatches; module ThreadKill
  # This is a bit of a sin but the alternative is some overriding of Sonic Pi
  # internals and hopping between the special user threads it uses. This way we
  # can at least easily execute the hooks in a sensible thread context.
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
end; end; end; end

# @private
class Thread
  prepend SpiSeq::Internal::MonkeyPatches::ThreadKill
end


module SpiSeq; module Utils; module Lifecycle
  # @private
  module State
    @one_time_init_keys = Set.new
    @stop_hooks = {}
    class << self
      attr_accessor :one_time_init_keys, :stop_hooks
    end
  end

  # @!group Sonic Pi lifecycle utilities

  # Executes its block the first time this sketch runs, and whenever it is
  # restarted after having been stopped. The block will not run if the sketch is
  # simply restarted while already running. `key` is used to uniquely identify
  # each cold-run block. If you need independent cold-run blocks, you should
  # provide different keys for each call to this function.
  # @param key [Symbol] A unique name for the handler.
  # @return [void]
  # @yield
  module_function def on_cold_run(key = :default, &block)
    thread_name = :"__cold_run_#{key}"
    External::Sync.in_thread(name: thread_name) do
      block.call

      # Sleep for a jiffy so Sonic Pi fires off things like logging.
      External::Sync.sleep(1)

      # And permanently park the thread so it lives until killed.
      Thread.stop
    end
  end

  # Executes its block exactly once per run of Sonic Pi. The `key` argument, if
  # provided, disambiguates different blocks; if you need independent one-time
  # initializers, you should provide different keys for each call to this
  # function.
  # @param key [Symbol] A unique name for the handler.
  # @return [void]
  # @yield
  module_function def one_time_init(key = :default)
    unless State.one_time_init_keys.include?(key)
      yield
      State.one_time_init_keys.add(key)
    end
  end

  # Registers a block to execute when Sonic Pi's execution is stopped or when
  # quitting the application. The work you do in the block should be very quick
  # or you will delay the stop operation or shutdown.
  #
  # If you need more than one stop hook, you must give them each different
  # `name`s; calling this function a second time with the same name will remove
  # the previous hook with that name.
  #
  # Hooks are serviced using an internal thread which waits for the sketch to
  # stop. Calling this method will thus prevent your sketch from exiting
  # naturally if there are no other `live_loop`s or `in_thread` calls keeping it
  # alive.
  #
  # @return [void]
  # @yield
  module_function def on_stop(name = :default, &block)
    State.stop_hooks[name] = block

    # Since we give this a name, Sonic Pi will only define it once.
    External::Sync.in_thread(name: :__stop_hook_watcher) do
      # See the monkey-patch above for details on this magic.
      kq = Thread::Queue.new
      Thread.current[:__kill_queue] = kq
      kq.pop

      unless State.stop_hooks.empty?
        State.stop_hooks.each do |name, b|
          Internal::Log.log("Running stop hook #{name}...", "stop-hooks")
          b.call
        end
        Internal::Log.log("Stop hooks complete", "stop-hooks")
      end
    end
  end
end; end; end
