# frozen_string_literal: true

require_relative "sonic_pi"
require_relative "../internal/utils"

module SpiSeq; module External; module Synth
  extend Internal::Utils::ModuleFunctionForwardable

  def_mod_func_delegators "SpiSeq::External::SonicPi", :play, :kill
end; end; end
