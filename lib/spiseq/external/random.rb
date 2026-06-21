# frozen_string_literal: true

require_relative "sonic_pi"

module SpiSeq; module External; module Random
  # Intended to be compatible with Sonic Pi's, which always returns a float.
  module_function def rand_f(max_or_range = 1)
    if External.in_sonic_pi?
      SonicPi.rand(max_or_range)
    else
      max_or_range = 0..max_or_range if max_or_range.is_a?(Numeric)
      max_or_range.min + Kernel.rand * max_or_range.max
    end
  end
end; end; end
