# frozen_string_literal: true

require_relative "sonic_pi"

module SpiSeq; module External; module IO
  module_function def puts(*)
    if External.in_sonic_pi?
      SonicPi.puts(*)
    else
      Kernel.puts(*)
    end
  end
end; end; end
