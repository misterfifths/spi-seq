# frozen_string_literal: true

# Dummy implementations of enough methods on ExtApi to simulate the workings of
# Player when using MIDI output. These track outgoing MIDI events in hashes that
# we can check. Sonic Pi's internal synthesis (e.g. `play` and `kill`) is not
# simulated, nor is the machinery for live loops. Also many of these functions
# are not completely compatible with their Sonic Pi counterparts in that they do
# not handle or even accept all of the possible arguments.
#
# There is only one global set of events; having multiple active players - much
# less threads - is a bad idea.
#
# These are not included in the ExtApiStubs module because they are not of
# practical use outside of the tests.
#
# Note that since these are applied to the ExtApi module itself, they will be
# used even if we're inside Sonic Pi. Because Sonic Pi uses a single Ruby
# context per launch, loading this module will break playback from spi-seq in
# Sonic Pi until it is restarted.

require_relative "../extapi"

module ExtApi
  @events = []
  @vt = 0
  @bpm = 60
  @bpm_mul = 1
  @midi_defaults = {}
  @queued_timewarps = []  # [[time, block]]

  class << self
    # Returns a list of hashes for events that have occurred since the last
    # time this method was called, sorted by timestamp, then type, ascending.
    # By default, executes all queued timewarp blocks and clears the queue.
    def drain_events(exec_timewarps: true)
      if exec_timewarps
        @queued_timewarps.each { |tw| exec_timewarp(tw) }
        @queued_timewarps.clear
      end

      # Events may be out of order due to time warps.
      es = @events.sort! do |a, b|
        [a[:t], a[:type]] <=> [b[:t], b[:type]]
      end
      @events = []
      es
    end

    # Note that we do not import this from Sonic Pi into ExtApi normally; this
    # stub is only here for the tests.
    def use_bpm(bpm)
      @bpm = bpm
    end

    def current_bpm
      @bpm * @bpm_mul
    end

    def with_bpm_mul(mul)
      old_mul = @bpm_mul
      # Nested calls to this stack, so multiply the current multiple.
      @bpm_mul *= mul
      yield
      @bpm_mul = old_mul
    end

    attr_reader :vt

    def reset_vt(clear_timewarps: true)
      @queued_timewarps.clear if clear_timewarps
      @vt = 0
    end

    def secs_per_beat(beats = 1)
      beats * (60.0 / current_bpm)
    end

    def time_warp(beats, &block)
      # Since the block may have side-effects, it's important that it not
      # execute until its scheduled time. Queue it up for later; we'll run
      # blocks we've stepped past in `sleep` and clear the whole queue in
      # `drain_events`.
      if beats == 0
        block.call
      elsif beats < 0
        raise RangeError, "the stub does not support time_warps into the past"
      else
        @queued_timewarps << [@vt + secs_per_beat(beats), block]
        @queued_timewarps.sort! { |a, b| a[0] <=> b[0] }
      end
    end

    private def exec_timewarp(tw)
      time, block = *tw

      # We probably won't be at the vt when we were supposed to call the block,
      # so pretend we are while we call it. There are probably edge cases where
      # this approach will go horribly wrong (e.g. if a timewarp block sleeps or
      # registers its own timewarps, I imagine things will get weird), but it
      # suffices for now.
      actual_vt = @vt
      @vt = time
      block.call
      @vt = actual_vt
    end

    def sleep(beats)
      @vt += secs_per_beat(beats)

      # Dequeue and execute any timewarp blocks whose time came while we slept.
      # These are sorted by start time, so they'll happen in order.
      executed_timewarps = 0
      @queued_timewarps.each do |tw|
        time, = *tw
        break if time > @vt
        executed_timewarps += 1
        exec_timewarp(tw)
      end

      @queued_timewarps = @queued_timewarps.drop(executed_timewarps) if executed_timewarps > 0
    end

    # Note that we do not import this from Sonic Pi into ExtApi normally; this
    # stub is only here for the tests.
    def use_midi_defaults(port: nil, channel: nil)
      @midi_defaults.clear
      @midi_defaults[:port] = port unless port.nil?
      @midi_defaults[:channel] = channel unless channel.nil?
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
      # For consistency's sake, we'll turn this into separate on and off events.
      midi_note_on(note, velocity: velocity, port: port, channel: channel)
      time_warp(sustain) do
        midi_note_off(note, port: port, channel: channel)
      end
    end

    def midi_note_on(note, velocity: 127, port: nil, channel: nil)
      port, channel = resolve_midi_dest(port, channel)
      note = MIDINote.new(note)
      @events << {type: :midi_note_on, t: vt, note: note, vel: velocity, port: port, channel: channel}
    end

    def midi_note_off(note, port: nil, channel: nil)
      port, channel = resolve_midi_dest(port, channel)
      note = MIDINote.new(note)
      @events << {type: :midi_note_off, t: vt, note: note, port: port, channel: channel}
    end

    def midi_cc(number, val, port: nil, channel: nil)
      port, channel = resolve_midi_dest(port, channel)
      @events << {type: :midi_cc, t: vt, num: number, val: val, port: port, channel: channel}
    end
  end
end
