# frozen_string_literal: true

module SpiSeq; module Internal; module Utils
  # Returns an array containing elements of `enum` with unique returns from the
  # `key_getter` lambda. If two elements have the same key, `tie_breaker` is
  # called with both elements and the element it returns will be in the result
  # (the one it doesn't return is discarded).
  module_function def unique_by(enum, key_getter, tie_breaker)
    objs_by_key = {}
    enum.each do |obj|
      key = key_getter.call(obj)
      other = objs_by_key[key]
      objs_by_key[key] = other.nil? ? obj : tie_breaker.call(obj, other)
    end
    objs_by_key.values
  end

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
    key_args = params.filter { |p| %i[key keyreq].member?(p[0]) }.map { |p| p[1] }
    kwargs.filter { |k, _| key_args.member?(k) }
  end

  # Calls a given proc or lambda with an appropriate subset of the provided
  # arguments. `proc.arity` many of the positional arguments are passed, and
  # only the valid keyword arguments (as found by filter_kwargs_for_proc). Does
  # not raise if the proc/lambda takes more positional arguments than are
  # provided.
  module_function def call_varargs(proc, *args, **kwargs)
    # If there are optional arguments, arity is -n - 1, where n is the number of
    # mandatory arguments. We'll only try n many arguments in that case.
    arity = proc.arity
    arity = -(arity + 1) if arity < 0
    args = args.take(arity)
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

  module_function def is_macos? = RUBY_PLATFORM.include?("darwin")

  # A simplified version of Forwardable that defines module_functions rather
  # than plain methods. Extend a module with this and call
  # def_mod_func_delegators to define module_functions that delegate to the
  # given methods on the object. This is not as flexible as Forwardable! Namely
  # it assumes that this module is extending another module, and that the object
  # to which you are forwarding is the name of a constant.
  module ModuleFunctionForwardable
    private def def_mod_func_delegators(obj, *methods)
      methods.each do |m|
        module_eval <<-RUBY, __FILE__, __LINE__ + 1
          # module_function def f(...) = Target.f(...)
          module_function def #{m}(...) = #{obj}.#{m}(...)
        RUBY
      end
    end
  end
end; end; end
