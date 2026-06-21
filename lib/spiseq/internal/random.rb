# frozen_string_literal: true

require_relative "../external/random"

module SpiSeq; module Internal; module Random
  # This is compatible with Sonic Pi's, which always returns a float.
  module_function def rand_f(max_or_range = 1)
    External::Random.rand_f(max_or_range)
  end

  module_function def chance(p)
    rand_f < p
  end

  module_function def one_in(n)
    # Sonic Pi offers this but it's easy enough to implement on top of rand.
    chance(1 / n.to_f)
  end
end; end; end
