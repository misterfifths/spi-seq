# frozen_string_literal: true

begin
  Object.const_get("SonicPi::RuntimeMethods")

  # TODO: This is a sin, but is the only way I find to catch hitting the stop
  # button (or quitting) Sonic Pi. Trying to catch ThreadExit in a Sonic Pi
  # thread doesn't work for whatever reason.
  # See runtime.rb in the Sonic Pi source for what we're overriding here.
  # https://github.com/sonic-pi-net/sonic-pi/blob/e3e305164d9b5c4e29caceed9fb60666fc7cbbb1/app/server/ruby/lib/sonicpi/runtime.rb#L549
  module SonicPi
    module RuntimeMethods
      alias __orig_stop_jobs __stop_jobs
      def __stop_jobs
        __orig_stop_jobs

        if __any_stop_hooks?
          __info("Running stop hooks...")
          # We need to hop into a Sonic Pi thread context so its builtins will
          # work. __in_thread seems preferable but I couldn't get it to work,
          # so __spider_eval it is. It does seem to run the code in a relatively
          # fresh context though, since it's not a child thread of the sketch.
          # Global settings like `use_midi_logging` are lost.
          __clear_stop_hook_event
          __spider_eval("__run_stop_hooks")
          unless __wait_for_stop_hooks(timeout: 1)
            __info("Stop hooks timed out! Killing them...")
            __orig_stop_jobs
          end
        end
      end
    end
  end
rescue NameError  # rubocop:disable Lint/SuppressedException
end


$__STOP_HOOKS = []
$__STOP_HOOKS_QUEUE = Thread::Queue.new

# @!group Sonic Pi lifecycle utilities

# Registers a block to execute when Sonic Pi's execution is stopped or when
# quitting the application. Note that the work you do in the block should be
# very quick! The maximum total time allotted for all stop hooks to complete is
# 1 second.
#
# Also note that the code in the block is evaluated in a new context, so many
# global Sonic Pi settings (e.g. `use_midi_defaults`) will not be set.
#
# @return [void]
# @yield
def on_stop(&block)
  $__STOP_HOOKS << block
end

# @!endgroup

# Returns true if any hooks have been registered with `on_stop`.
# This is called from a non-Sonic Pi thread; things in ExtApi won't work.
# @private
def __any_stop_hooks?
  !$__STOP_HOOKS.empty?
end

# Resets the event used for detecting when all stop hooks have completed. Call
# this before `__run_stop_hooks` and `__wait_for_stop_hooks`.
# This is called from a non-Sonic Pi thread; things in ExtApi won't work.
# @private
def __clear_stop_hook_event
  $__STOP_HOOKS_QUEUE.clear
end

# Waits for all stop hooks (as triggered by `__run_stop_hooks`) to complete, or
# for the timeout to elapse. Returns true if the hooks completed before the
# timeout.
# This is called from a non-Sonic Pi thread; things in ExtApi won't work.
# @private
def __wait_for_stop_hooks(timeout: 1)
  !$__STOP_HOOKS_QUEUE.pop(timeout: timeout).nil?
end

# Runs all stop hooks, clears the list of hooks, and triggers the event that
# will wake a thread waiting on `__wait_for_stop_hooks`.
# This is called from a Sonic Pi thread.
# @private
def __run_stop_hooks
  $__STOP_HOOKS_QUEUE.clear
  $__STOP_HOOKS.each { |b| b.call }
  $__STOP_HOOKS.clear
  $__STOP_HOOKS_QUEUE << true
end
