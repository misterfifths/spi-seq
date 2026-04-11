# frozen_string_literal: true

require_relative "../extapi"

# Runs the given block the first time the script runs, and whenever it is
# restarted after having been stopped. thread_name is the name used for the
# internal thread this relies on. If you need independent cold-run blocks, you
# should provide different names for each call to this function.
def on_cold_run(thread_name = :__default_cold_run, &block)
  ExtApi.in_thread(name: thread_name) do
    block.call

    # spin to keep this thread alive until the script is manually stopped
    loop { ExtApi.sleep(100) }
  end
end

# Executes its block exactly once per run of Sonic Pi. The key argument, if
# provided, disambiguates different blocks; if you need independent one-time
# initializers, you should provide different keys for each call to this
# function.
def one_time_init(key = :default)
  # rubocop:disable Style/GlobalVars
  $__ONE_TIME_INIT_KEYS ||= Set.new
  unless $__ONE_TIME_INIT_KEYS.include?(key)
    yield
    $__ONE_TIME_INIT_KEYS.add(key)
  end
  # rubocop:enable Style/GlobalVars
end

# Given a proc and a hash of keyword arguments, returns a new hash containing
# only the members of the hash that are valid keyword arguments for the proc.
# If the proc takes a double-star **kwargs argument, the hash is not filtered.
def filter_kwargs_for_proc(proc, kwargs)
  params = proc.parameters
  return {} if params.empty?

  # If there's a **kwargs param, just pass everything.
  return kwargs if params.last[0] == :keyrest

  # We want the key names from parameters that look like [:key, :keyname] or
  # [:keyreq, :keyname].
  key_args = params.filter { |p| [:key, :keyreq].member?(p[0]) }.map { |p| p[1] }
  kwargs.filter { |k, _| key_args.member?(k) }
end

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
