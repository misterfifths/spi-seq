# frozen_string_literal: true

require "forwardable"
require_relative "sonic_pi"

module SpiSeq; module External; module Sync
  extend Forwardable
  extend self

  def_delegators "SpiSeq::External::SonicPi",
    :current_bpm, :with_bpm_mul,
    :vt, :sleep,
    :with_real_time,
    :live_loop,
    :in_thread, :at,
    :cue, :sync,
    :get_event
end; end; end
