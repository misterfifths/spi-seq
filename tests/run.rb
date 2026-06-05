#!/usr/bin/env ruby
# frozen_string_literal: true

# test_helper should be required first so coverage catches other requires.
require_relative "test_helper"
require_relative "../extapi"
require_relative "../utils/internal_utils"

BASE_DIR = File.expand_path("#{File.dirname(__FILE__)}/..")
TEST_DIR = File.join(BASE_DIR, "tests")

unless ExtApi.in_sonic_pi?
  SpiSeq::Log.silence!
  exit Test::Unit::AutoRunner.run(true, TEST_DIR)
end


# To run the tests from inside Sonic Pi, require this file, then call
# `run_tests("path/to/output.log")`. E.g.:
#
# require "~/spi-seq/tests/run"
# run_tests("~/spi-seq-tests.log")
#
# Note that since Sonic Pi maintains a single persistent Ruby context per
# launch, if you edit a test or any Ruby file you will have to quit and reopen
# Sonic Pi for the the changes to take effect.
#
# Also note that some tests may overwrite the implementations of Sonic Pi
# methods and thus break playback from spi-seq. You will need to restart Sonic
# Pi after running the tests to return to a usable environment.

def run_tests(output_path)
  require "test/unit/collector/dir"
  require "test/unit/ui/console/testrunner"

  collector = Test::Unit::Collector::Dir.new
  suite = collector.collect(TEST_DIR)
  SpiSeq::Log.log("Found #{suite.tests.count} test case classes")

  buggy_test_classes = [TrackLiveLoopTest, MutableLiveLoopTest]
  subsuites_to_remove = []
  suite.tests.each do |subsuite|
    first_case = subsuite.tests.first
    if buggy_test_classes.include?(first_case.class)
      subsuites_to_remove << subsuite
      SpiSeq::Log.log("Skipping #{first_case.class}: known to be buggy in Sonic Pi")
    end
  end
  subsuites_to_remove.each { |subsuite| suite.delete(subsuite) }

  SpiSeq::Log.with_silence do
    Test::Unit::UI::Console::TestRunner.run(suite, {
      use_color: false,
      progress_style: :mark,
      output: File.open(File.expand_path(output_path), "w")
    })
  end

  if suite.passed?
    SpiSeq::Log.log("Tests passed!")
  else
    SpiSeq::Log.log("There were test failures; see the log")
  end
end
