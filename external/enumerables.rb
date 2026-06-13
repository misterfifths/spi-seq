# frozen_string_literal: true

require_relative "sonic_pi"

module SpiSeq
  module External
    module Enumerables
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
        return true if e.is_a?(::Enumerable)
        return true if External.in_sonic_pi? && e.is_a?(::SonicPi::Core::SPVector)
        false
      end

      # A souped up version of `to_a` that tries very hard to unwrap Sonic Pi's
      # enumerable classes and actually return an Array.
      def self.arrayify(x)
        return x if x.is_a?(Array)
        x = x.to_a

        return x unless External.in_sonic_pi?

        # For certain values, like the return of `chord`, there is an outer
        # SPVector whose `to_a` returns an array subclass. That inner class is
        # broken when it comes to mutating methods, so let's unwrap it too.
        return x if x.class == Array  # rubocop:disable Style/ClassEqualityComparison
        x.to_a
      end
    end
  end
end
