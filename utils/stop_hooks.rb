# frozen_string_literal: true

$__STOP_HOOKS = {}

# @!group Sonic Pi lifecycle utilities

# Registers a block to execute when Sonic Pi's execution is stopped or when
# quitting the application. Note that the work you do in the block should be
# very quick or you will delay the stop operation or shutdown.
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
  __ensure_stop_watcher
  $__STOP_HOOKS[name] = block
end

# @!endgroup

# This is a bit of a sin but the alternative is some overriding of Sonic Pi
# internals and hopping between the special user threads it uses. This way we
# can at least easily execute the hooks in a sensible thread context.
# @private
module ThreadKillPatch
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

# @private
class Thread
  prepend ThreadKillPatch
end

# Ensures that the thread that services stop hooks is running.
# @private
def __ensure_stop_watcher
  ExtApi.in_thread(name: :__stop_hook_watcher) do
    kq = Thread::Queue.new
    Thread.current[:__kill_queue] = kq
    kq.pop

    hooks = $__STOP_HOOKS
    unless hooks.empty?
      _log "Running stop hooks...", "stop-hooks"
      hooks.each_value { |b| b.call }
      hooks.clear
      _log "Stop hooks complete", "stop-hooks"
    end
  end
end
