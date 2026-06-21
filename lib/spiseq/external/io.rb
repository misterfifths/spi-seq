# frozen_string_literal: true

require_relative "sonic_pi"

module SpiSeq; module External; module IO
  module_function def puts(*args)
    if External.in_sonic_pi?
      SonicPi.puts(*args)
    else
      Kernel.puts(*args)
    end
  end
end; end; end
