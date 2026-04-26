# frozen_string_literal: true

begin
  require "simplecov"

  root_dir = File.expand_path("#{File.dirname(__FILE__)}/..")

  SimpleCov.start do
    root(root_dir)

    # Not including utils/ here since that's almost entirely Sonic Pi stuff.
    track_files "{math/,theory/,}*.rb"
    add_group("core") { |f| File.dirname(f.filename) == root_dir }
    add_group "theory", "theory/"
    add_group "math", "math/"
    add_group "tests", "tests/"
    add_filter "utils/"
    add_filter "core.rb"
    add_filter "track_live_loop.rb"
  end
rescue LoadError  # rubocop:disable Lint/SuppressedException
end

require "test/unit"
