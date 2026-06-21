# frozen_string_literal: true

module SpiSeq; module Internal; module Utils
  # Given a proc or lambda and a hash of keyword arguments, returns a new hash
  # containing only the members of the hash that are valid keyword arguments.
  # If the proc or lambda takes a double-star **kwargs argument, the hash is
  # not filtered.
  module_function def filter_kwargs_for_proc(proc, kwargs)
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

  # Calls a given proc or lambda with an appropriate subset of the provided
  # arguments. `arity` many of the positional arguments are passed, and only
  # the valid keyword arguments (as found by filter_kwargs_for_proc). Does not
  # raise if the proc/lambda takes more positional arguments than are
  # provided.
  module_function def call_varargs(proc, *args, **kwargs)
    args = args.take(proc.arity)
    kwargs = filter_kwargs_for_proc(proc, kwargs)
    proc.call(*args, **kwargs)
  end

  # Given a proc or lambda, returns an array:
  # [count of required positional args, count of optional required args,
  #  [required keyword name symbols], [optional keyword name symbols]]
  module_function def describe_args(proc)
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

  module_function def is_macos?
    RUBY_PLATFORM.include?("darwin")
  end
end; end; end
