# frozen_string_literal: true

require_relative "sonic_pi"
require_relative "../internal/utils"

module SpiSeq; module External; module Sync
  extend Internal::Utils::ModuleFunctionForwardable

  def_mod_func_delegators "SpiSeq::External::SonicPi",
    :current_bpm, :with_bpm_mul,
    :vt, :sleep,
    :with_real_time,
    :live_loop,
    :in_thread, :at,
    :cue, :sync,
    :get_event
end; end; end
