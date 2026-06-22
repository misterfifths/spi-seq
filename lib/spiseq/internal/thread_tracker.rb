# frozen_string_literal: true

require "weakref"

module SpiSeq; module Internal; module ThreadTracker
  # @private
  module State
    @threads = {}
    class << self
      attr_accessor :threads
    end

    # Returns the Thread object associated with the the given name. If the
    # thread with that name is not running or has not been registered, returns
    # nil. This is part of the internal API because the returned Thread isn't a
    # strong reference, and there's no good way to turn a WeakRef into a strong
    # one. So all access to the result is racy and needs to catch RefError,
    # which is a pain. The public methods of ThreadTracker handle that.
    module_function def get_thread(thread_name)
      thread = State.threads[thread_name]
      return thread if !thread.nil? && thread.weakref_alive? && thread.alive?
      nil
    rescue RefError
      nil
    end
  end

  # Associate the thread with the given name. Overwrites an existing thread with
  # that name if there already is one.
  module_function def register(thread_name, thread)
    State.threads[thread_name] = WeakRef.new(thread)
  end

  # Returns true if a thread with the given name is registered and running.
  module_function def is_running?(thread_name)
    !State.get_thread(thread_name).nil?
  rescue RefError
    false
  end

  # Associates a value with the thread with the given name. The value can be
  # retrieved with var_get. When the thread exits, this value will no longer be
  # accessible. Does nothing if the named thread has exited or was not
  # registered.
  module_function def var_set(thread_name, var_name, value)
    State.get_thread(thread_name)&.thread_variable_set(var_name, value)
  rescue RefError
    # We lost a race with the WeakRef.
  end

  # Returns the value of a variable associated with the thread with the given
  # name, as set by var_set. Returns nil if there is no such variable associated
  # with the thread, or if the thread has exited or was never registered.
  module_function def var_get(thread_name, var_name)
    State.get_thread(thread_name)&.thread_variable_get(var_name)
  rescue RefError
    nil
  end
end; end; end
