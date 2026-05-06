# frozen_string_literal: true

require_relative "../extapi"

# @!group Sonic Pi lifecycle utilities

# Executes its block the first time this sketch runs, and whenever it is
# restarted after having been stopped. The block will not run if the sketch is
# simply restarted while already running. `key` is used to uniquely identify
# each cold-run block. If you need independent cold-run blocks, you should
# provide different keys for each call to this function.
# @param key [Symbol] A unique name for the handler.
# @return [void]
# @yield
def on_cold_run(key = :__default_cold_run, &block)
  ExtApi.in_thread(name: key) do
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
  $__ONE_TIME_INIT_KEYS ||= Set.new
  unless $__ONE_TIME_INIT_KEYS.include?(key)
    yield
    $__ONE_TIME_INIT_KEYS.add(key)
  end
end

$__STOP_HOOKS = []
$__STOP_HOOKS_QUEUE = Thread::Queue.new

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

# Given a proc and a hash of keyword arguments, returns a new hash containing
# only the members of the hash that are valid keyword arguments for the proc.
# If the proc takes a double-star **kwargs argument, the hash is not filtered.
# @private
def __filter_kwargs_for_proc(proc, kwargs)
  params = proc.parameters
  return {} if params.empty?

  # If there's a **kwargs param, just pass everything.
  return kwargs if params.last[0] == :keyrest

  # We want the key names from parameters that look like [:key, :keyname] or
  # [:keyreq, :keyname].
  key_args = params.filter { |p| [:key, :keyreq].member?(p[0]) }.map { |p| p[1] }
  kwargs.filter { |k, _| key_args.member?(k) }
end

# @private
module Clipboard
  # Copies the given string to the clipboard. Only supported on macOS.
  def self.copy(s)
    IO.popen("/usr/bin/pbcopy", "w") do |pipe|
      pipe.print(s)
      pipe.close_write
    end
  end

  # Returns the contents of the clipboard as a string. Only supported on macOS.
  def self.paste
    IO.popen("/usr/bin/pbpaste", "r") do |pipe|
      return pipe.read
    end
  end
end
