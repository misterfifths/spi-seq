# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.start
rescue LoadError  # rubocop:disable Lint/SuppressedException
end

require "test/unit"
