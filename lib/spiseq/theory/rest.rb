# frozen_string_literal: true

module SpiSeq; module Theory
  # Returns true if the given value represents a rest. nil, `:r`, and `:rest`
  # are considered rests.
  # @param val [Object]
  # @return [Boolean]
  module_function def rest?(val)
    return true if val.nil?
    return false unless val.is_a?(Symbol)
    %i[r rest].include?(val)
  end
end; end
