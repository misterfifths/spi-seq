# frozen_string_literal: true

begin
  require "simplecov"

  root_dir = File.expand_path("#{File.dirname(__FILE__)}/..")

  SimpleCov.start do
    root(root_dir)

    track_files "{math/,theory/,utils/}*.rb"
    add_group("core") { |f| File.dirname(f.filename) == root_dir }
    add_group "theory", "theory/"
    add_group "utils", "utils/"
    add_group "math", "math/"
    add_group "tests", "tests/"
    add_filter "core.rb"
    # Most of utils/ is not very testable since it's very niche Sonic Pi stuff.
    add_filter "utils/midi_utils.rb"
    add_filter "utils/misc_utils.rb"
    add_filter "utils/stop_hooks.rb"
  end
rescue LoadError  # rubocop:disable Lint/SuppressedException
end

require "test/unit"
