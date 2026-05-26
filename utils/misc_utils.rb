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
  $__ONE_TIME_INIT_KEYS ||= Set.new
  unless $__ONE_TIME_INIT_KEYS.include?(key)
    yield
    $__ONE_TIME_INIT_KEYS.add(key)
  end
end

# Given a proc or lambda and a hash of keyword arguments, returns a new hash
# containing only the members of the hash that are valid keyword arguments.
# If the proc or lambda takes a double-star **kwargs argument, the hash is not
# filtered.
# @private
def __filter_kwargs_for_proc(proc, kwargs)
  return kwargs if kwargs.empty?

  params = proc.parameters
  return {} if params.empty?

  # If there's a **kwargs param, just pass everything.
  return kwargs if params.last[0] == :keyrest

  # We want the key names from parameters that look like [:key, :keyname] or
  # [:keyreq, :keyname].
  key_args = params.filter { |p| [:key, :keyreq].member?(p[0]) }.map { |p| p[1] }
  kwargs.filter { |k, _| key_args.member?(k) }
end

# Given a proc or lambda, returns the count of its required positional arguments
# and the names of its required keyword arguments.
# @private
def __describe_args(proc)
  req_pos_args = 0
  opt_pos_args = 0
  req_keywords = []
  opt_keywords = []
  proc.parameters.each do |type, name|
    case type
    when :req
      req_pos_args += 1
    when :opt
      opt_pos_args += 1
    when :keyreq
      req_keywords << name
    when :key
      opt_keywords << name
    end
  end

  [req_pos_args, opt_pos_args, req_keywords, opt_keywords]
end

# Calls a given proc or lambda with an appropriate subset of the provided
# arguments. `arity` many of the positional arguments are passed, and only
# the valid keyword arguments (as found by __filter_kwargs_for_proc). Does not
# raise if the proc/lambda takes more positional arguments than are provided.
# @private
def __call_varargs(proc, *args, **kwargs)
  args = args.take(proc.arity)
  kwargs = __filter_kwargs_for_proc(proc, kwargs)
  proc.call(*args, **kwargs)
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
