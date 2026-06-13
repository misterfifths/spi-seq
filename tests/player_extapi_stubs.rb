# frozen_string_literal: true

# Dummy implementations of enough external methods to simulate the workings of
# Player when using MIDI output. These track outgoing MIDI events in hashes that
# we can check. Sonic Pi's internal synthesis (e.g. `play` and `kill`) is not
# simulated, nor is the machinery for live loops. Also many of these functions
# are not completely compatible with their Sonic Pi counterparts in that they do
# not handle or even accept all of the possible arguments.
#
# There is only one global set of events; having multiple active players - much
# less threads - is a bad idea.
#
# Since these are applied to the External modules themselves, they will be used
# even if we're inside Sonic Pi. Because Sonic Pi uses a single Ruby context per
# launch, loading this module will break playback from spi-seq in Sonic Pi until
# it is restarted.

require_relative "../external/sync"
require_relative "../external/midi"

module TestMocks
  @events = []
  @delayed_blocks = []  # [[time, block]]
  @bpm = 60
  @bpm_mul = 1
  @vt = 0

  class << self
    attr_accessor :bpm, :bpm_mul
    attr_reader :vt

    # Returns a list of hashes for events that have occurred since the last
    # time this method was called, sorted by timestamp, then type, ascending.
    # By default, executes all delayed blocks and clears the queue.
    def drain_events(exec_delayed_blocks: true)
      if exec_delayed_blocks
        @delayed_blocks.each { |b| exec_delayed_block(b) }
        @delayed_blocks.clear
      end

      # Events may be out of order due to time warps.
      es = @events.sort! do |a, b|
        [a[:t], a[:type]] <=> [b[:t], b[:type]]
      end
      @events = []
      es
    end

    def add_event(**kwargs)
      @events << kwargs
    end

    def add_delayed_block(delay_secs, block)
      @delayed_blocks << [@vt + delay_secs, block]
      @delayed_blocks.sort! { |a, b| a[0] <=> b[0] }
    end

    # Executes all delayed blocks whose start time is <= vt
    private def exec_expired_delayed_blocks
      # These are sorted by start time, so they'll happen in order.
      executed_blocks = 0
      @delayed_blocks.each do |b|
        time, = *b
        break if time > @vt
        executed_blocks += 1
        exec_delayed_block(b)
      end

      @delayed_blocks = @delayed_blocks.drop(executed_blocks) if executed_blocks > 0
    end

    private def exec_delayed_block(b)
      time, block = *b

      # We probably won't be at the vt when we were supposed to call the block,
      # so pretend we are while we call it. There are probably edge cases where
      # this approach will go horribly wrong (e.g. if a delayed block sleeps or
      # registers its own delayed block, I imagine things will get weird), but
      # it suffices for now.
      actual_vt = @vt
      @vt = time
      block.call
      @vt = actual_vt
    end

    # Sets vt to t. If run_blocks is true, executes all delayed blocks whose
    # start time is <= t. Blocks are not executed based on the value of vt when
    # this function is called. If clear_blocks is true, all pending delayed
    # blocks are cleared, even if they did not execute.
    def set_vt(t, run_blocks: true, clear_blocks: false)
      @vt = t
      exec_expired_delayed_blocks if run_blocks
      @delayed_blocks.clear if clear_blocks
    end

    def reset_vt
      set_vt(0, run_blocks: false, clear_blocks: true)
    end
  end
end

module SpiSeq
  module External
    module Sync
      class << self
        def vt
          TestMocks.vt
        end

        def current_bpm
          TestMocks.bpm * TestMocks.bpm_mul
        end

        def with_bpm_mul(mul)
          old_mul = TestMocks.bpm_mul
          # Nested calls to this stack, so multiply the current multiple.
          TestMocks.bpm_mul *= mul
          yield
          TestMocks.bpm_mul = old_mul
        end

        def at(beats, &block)
          # Since the block may have side-effects, it's important that it not
          # execute until its scheduled time. Queue it up for later; we'll run
          # blocks we've stepped past in `sleep` and clear the whole queue in
          # `drain_events`.
          if beats == 0
            block.call
          elsif beats < 0
            raise RangeError, "the stub does not support delays into the past"
          else
            TestMocks.add_delayed_block(bt(beats), block)
          end
        end

        def sleep(beats)
          TestMocks.set_vt(TestMocks.vt + bt(beats), run_blocks: true)
        end

        def cue(name, *args, **kwargs)
          TestMocks.add_event(type: :cue, t: vt, name: name, args: args, kwargs: kwargs)
        end

        def sync(name)
          TestMocks.add_event(type: :sync, t: vt, name: name)
        end


        # We do not normally import these; these are only here for the tests.
        def use_bpm(bpm)
          TestMocks.bpm = bpm
        end

        def bt(beats = 1)
          beats * (60.0 / current_bpm)
        end
      end
    end

    module MIDI
      @midi_defaults = {}

      class << self
        # We do not import this normally; this stub is only here for the tests.
        def use_midi_defaults(port: nil, channel: nil)
          defaults = {}
          defaults[:port] = port unless port.nil?
          defaults[:channel] = channel unless channel.nil?
          @midi_defaults = defaults.freeze
        end

        def current_midi_defaults
          @midi_defaults
        end

        private def resolve_midi_dest(port, channel)
          defaults = current_midi_defaults || {}
          port = defaults[:port] || "*" if port.nil?
          channel = defaults[:channel] || "*" if channel.nil?
          [port, channel]
        end

        def midi(note, velocity: 127, sustain: 1.0, port: nil, channel: nil)
          # For consistency's sake, we'll turn this into separate on and off
          # events.
          midi_note_on(note, velocity: velocity, port: port, channel: channel)
          Sync.at(sustain) do
            midi_note_off(note, port: port, channel: channel)
          end
        end

        def midi_note_on(note, velocity: 127, port: nil, channel: nil)
          port, channel = resolve_midi_dest(port, channel)
          note = MIDINote.new(note)
          TestMocks.add_event(type: :midi_note_on, t: Sync.vt, note: note, vel: velocity, port: port, channel: channel)
        end

        def midi_note_off(note, port: nil, channel: nil)
          port, channel = resolve_midi_dest(port, channel)
          note = MIDINote.new(note)
          TestMocks.add_event(type: :midi_note_off, t: Sync.vt, note: note, port: port, channel: channel)
        end

        def midi_cc(number, val, port: nil, channel: nil)
          port, channel = resolve_midi_dest(port, channel)
          TestMocks.add_event(type: :midi_cc, t: Sync.vt, num: number, val: val, port: port, channel: channel)
        end
      end
    end
  end
end
