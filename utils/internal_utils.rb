# frozen_string_literal: true

require_relative "../extapi"

# @private
module SpiSeq
  module Utils
    # Given a proc or lambda and a hash of keyword arguments, returns a new hash
    # containing only the members of the hash that are valid keyword arguments.
    # If the proc or lambda takes a double-star **kwargs argument, the hash is
    # not filtered.
    private_class_method def self.filter_kwargs_for_proc(proc, kwargs)
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
    def self.call_varargs(proc, *args, **kwargs)
      args = args.take(proc.arity)
      kwargs = filter_kwargs_for_proc(proc, kwargs)
      proc.call(*args, **kwargs)
    end

    # Given a proc or lambda, returns an array:
    # [count of required positional args, count of optional required args,
    #  [required keyword name symbols], [optional keyword name symbols]]
    def self.describe_args(proc)
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

    if Object.const_defined?("SonicPi::Core::SPVector")
      # 'Enumerable' resolves to SonicPi::RuntimeMethods::Enumerable from within
      # Sonic Pi, which e.g. Array does not have as a superclass. So we need to
      # use ::Enumerable to get the built-in class.
      #
      # SPVector is the parent class of most list-like things from Sonic Pi
      # (e.g. `ring`s and `ramp`s). It unfortunately does mix in Enumerable, so
      # we need to check for it specially. Since SPVectors are missing some
      # Enumerable/Array methods (e.g. `reject`), and have idiosyncratic
      # implementations of others, you should really call `arrayify` on anything
      # for which this method returns true!
      def self.enumerable?(e)
        e.is_a?(::Enumerable) || e.is_a?(SonicPi::Core::SPVector)
      end

      # A souped up version of `to_a` that tries very hard to unwrap Sonic Pi's
      # enumerable classes and actually return an Array.
      def self.arrayify(x)
        return x if x.is_a?(Array)
        # For certain values, like the return of `chord`, there is an outer
        # SPVector whose `to_a` returns an array subclass. That inner class is
        # broken when it comes to mutating methods, so let's unwrap it too.
        x = x.to_a
        return x if x.class == Array  # rubocop:disable Style/ClassEqualityComparison
        x.to_a
      end
    else
      def self.enumerable?(e)
        e.is_a?(Enumerable)
      end

      def self.arrayify(x)
        return x if x.is_a?(Array)
        x.to_a
      end
    end
  end

  module Clipboard
    # Copies the given string to the clipboard. Only supported on macOS.
    def self.copy(s)
      IO.popen("/usr/bin/pbcopy", "w") do |pipe|
        pipe.print(s)
        pipe.close_write
      end
    end

    # Returns the contents of the clipboard as a string. Only supported on
    # macOS.
    def self.paste
      IO.popen("/usr/bin/pbpaste", "r") do |pipe|
        return pipe.read
      end
    end
  end

  module Log
    def self.log(msg, channel = "spi-seq")
      s = "[#{channel}] #{msg}"
      if ExtApi.in_sonic_pi?
        ExtApi.puts(s)
      else
        puts(s)
      end
    end

    def self.warn(msg, channel = "spi-seq")
      log("warning: #{msg}", channel)
    end
  end

  module Random
    # This is compatible with Sonic Pi's, which always returns a float.
    def self.rand_f(max_or_range = 1)
      return ExtApi.rand(max_or_range) if ExtApi.in_sonic_pi?

      max_or_range = 0..max_or_range if max_or_range.is_a?(Numeric)
      max_or_range.min + Kernel.rand * max_or_range.max
    end

    def self.chance(p)
      rand_f < p
    end

    def self.one_in(n)
      # Sonic Pi offers this but it's easy enough to implement on top of rand.
      chance(1 / n.to_f)
    end
  end
end
