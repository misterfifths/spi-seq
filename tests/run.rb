#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"

require_relative "test_extapi"
require_relative "test_midinote"
require_relative "test_arp"
require_relative "test_step"
require_relative "test_ccstep"
require_relative "test_track_init"
require_relative "test_track_basics"
require_relative "test_track_grid"
require_relative "test_track_step"
require_relative "test_track_regrain"
require_relative "test_trackrecorder"
require_relative "test_cctrack"
require_relative "test_chord"
require_relative "test_chordvoicing"
require_relative "test_euclid"
require_relative "test_interval"
require_relative "test_notelength"
require_relative "test_scale"
require_relative "test_ccplayer"
require_relative "test_player"
require_relative "test_track_live_loop"
require_relative "test_mutable_live_loop"
require_relative "test_prob"
require_relative "test_accum"

if ExtApi.in_sonic_pi?
  # To run the tests from inside Sonic Pi, call `init_spi_seq`, then require
  # this file, then call `run_tests("path/to/output.log")`. E.g.:
  #
  # require "~/spi-seq/core"
  # init_spi_seq
  # require "~/spi-seq/tests/run"
  # run_tests("~/spi-seq-tests.log")
  #
  # Note that since Sonic Pi maintains a single persistent Ruby context per
  # launch, if you edit a test or any Ruby file you will have to quit and reopen
  # Sonic Pi for the the changes to take effect.
  #
  # Also note that some tests may overwrite the implementations of Sonic Pi
  # methods and thus break playback from spi-seq. Do not expect the Sonic Pi
  # environment to be particularly usable after running the tests until you
  # restart.

  def run_tests(output_path)
    require "test/unit/collector/descendant"
    require "test/unit/ui/console/testrunner"

    collector = Test::Unit::Collector::Descendant.new
    suite = collector.collect("spi-seq")
    log("Found #{suite.tests.count} test case classes")

    Test::Unit::UI::Console::TestRunner.run(suite, {
      use_color: false,
      progress_style: :mark,
      output: File.open(File.expand_path(output_path), "w")
    })
  end
end
