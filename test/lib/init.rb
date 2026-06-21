# frozen_string_literal: true

begin
  require "simplecov"

  root_dir = File.expand_path("#{File.dirname(__FILE__)}/../..")

  SimpleCov.start do
    root(root_dir)

    track_files "lib/**/*.rb"

    add_group "tracks", "lib/spiseq/tracks"
    add_group "playback", "lib/spiseq/playback"
    add_group "theory", "lib/spiseq/theory/"
    add_group "utils", "lib/spiseq/utils/"
    add_group "math", "lib/spiseq/math/"
    add_group "tests", "test/"
    add_group "external", "lib/spiseq/external/"
    add_group "internal", "lib/spiseq/internal/"

    # These are basically Sonic Pi-only.
    add_filter "lib/spiseq/utils/midi.rb"
    add_filter "lib/spiseq/utils/lifecycle.rb"

    # We don't use the module import files in the tests.
    add_filter "lib/spiseq.rb"
    add_filter "lib/spiseq/math.rb"
    add_filter "lib/spiseq/playback.rb"
    add_filter "lib/spiseq/theory.rb"
    add_filter "lib/spiseq/tracks.rb"
    add_filter "lib/spiseq/utils.rb"
  end
rescue LoadError
  require_relative "../../lib/spiseq/internal/log"
  SpiSeq::Internal::Log.warn("coverage is unavailable")
end

require "test/unit"
require_relative "externals"

def in_sonic_pi?
  SpiSeq::External.in_sonic_pi?
end
