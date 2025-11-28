# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.start do
    # Not including utils/ here since that's almost entirely Sonic Pi stuff.
    track_files "{math/,theory/,}*.rb"
  end
rescue LoadError  # rubocop:disable Lint/SuppressedException
end

require "test/unit"
