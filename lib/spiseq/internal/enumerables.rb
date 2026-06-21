# frozen_string_literal: true

require_relative "../external/enumerables"

module SpiSeq; module Internal; module Enumerables
  # Detects builtin Enumerables and some of Sonic Pi's.
  module_function def enumerable?(e)
    External::Enumerables.enumerable?(e)
  end

  # Souped up `to_a` that tries very hard to unwrap Sonic Pi's enumerables.
  module_function def arrayify(x)
    External::Enumerables.arrayify(x)
  end
end; end; end
