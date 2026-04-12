# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.start do
    # Not including utils/ here since that's almost entirely Sonic Pi stuff.
    track_files "{math/,theory/,}*.rb"
    add_filter "core.rb"
    add_filter "track_live_loop.rb"
    add_filter "playerbase.rb"
    add_filter "player.rb"
  end
rescue LoadError  # rubocop:disable Lint/SuppressedException
end

require "test/unit"
