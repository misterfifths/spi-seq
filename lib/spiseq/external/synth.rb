# frozen_string_literal: true

require "forwardable"
require_relative "sonic_pi"

module SpiSeq; module External; module Synth
  extend Forwardable
  extend self

  def_delegators "SpiSeq::External::SonicPi", :play, :kill
end; end; end
