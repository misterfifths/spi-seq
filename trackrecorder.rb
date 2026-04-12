# frozen_string_literal: true

require_relative "track"
require_relative "step"
require_relative "theory/notelength"
require_relative "theory/midinote"
require_relative "extapi"
require_relative "utils/live_loop_utils"

module TrackRecorder
  # TODO: probably this is overkill? can just do (a - b) < 0.01 or something?
  private_class_method def self.lt_threshold(val, threshold, digits = 2)
    (val.to_f.round(digits) - threshold.to_f.round(digits)).round(digits) < 0
  end

  # Return a description of the total length in steps for a duration in seconds,
  # given the seconds that a slot occupies. The return is a two-element array,
  # the first element of which is an integer number of tied steps, and the
  # second of which is the floating point gate for the final step after the
  # ties. If the duration maps entirely to ties, the second element is 0. If it
  # maps to a single step that is not a tie, the first element is 0. E.g., a
  # return of [15, 0.1] means the duration occupies 15 tied steps followed by
  # one step with a gate of 0.1. A return of [10, 0.0] means the duration
  # occupies exactly 10 tied steps. And [0, 0.5] means the duration occupies one
  # step with a gate of 0.5.
  #
  # If there is at least one tie and the final step would have a gate less than
  # min_gate, it is ignored, and the second element of the return will be 0.
  # However, if the duration only maps to one step, and that step's gate would
  # be less than min_gate, this function returns [0, min_gate]. E.g., if the
  # return would be [15, 0.01], but min_gate is 0.1, the function will return
  # [15, 0] instead. But if the return would be just [0, 0.01] and the min_gate
  # is 0.1, the function will return [0, 0.1]. This ensures that very short
  # durations are not lost entirely. This function only returns [0, 0.0] if the
  # duration is 0.
  #
  # If quantize is true, the second element of the return will be rounded up to
  # the nearest multiple of min_gate.
  private_class_method def self.gates_for_duration(duration, secs_per_slot,
                                                   min_gate: 0.1, quantize: true)
    return [0, 0.0] if duration == 0

    total_gate = duration.to_f / secs_per_slot
    tied_steps = 0
    final_gate = 0.0

    if lt_threshold(total_gate, 1.0)
      tied_steps = 0
      final_gate = total_gate

      # Only going to be one slot, so round up if we need to.
      final_gate = min_gate if lt_threshold(final_gate, min_gate)
    else
      # If we happened to be very close to the threshold for 1.0, but not quite,
      # round up.
      total_gate = 1.0 if total_gate < 1.0

      tied_steps = total_gate.to_i
      final_gate = total_gate - total_gate.to_i

      # If the gate in the final step would be too small, drop it.
      final_gate = 0.0 if lt_threshold(final_gate, min_gate)
    end

    final_gate = (final_gate / min_gate).round * min_gate if quantize

    [tied_steps, final_gate]
  end

  # Add Steps to an array of slots for a note being played for the given period.
  # The elements of slots must be arrays (they will be appended to), and slots
  # itself must be long enough to hold the steps that the note event maps to.
  # This function considers the slots to begin at time 0, so start_time and
  # end_time should be relative to that.
  #
  # min_gate and quantize_gates control the behavior of the internal
  # gates_for_duration call; see its documentation for details.
  private_class_method def self.add_note_to_slots(slots, secs_per_slot, note,
                                                  start_time, end_time, velocity,
                                                  min_gate: 0.1, quantize_gates: true)
    # This will snap notes that began >= halfway through a slot to the next one.
    start_slot = (start_time.to_f / secs_per_slot).round

    # And since we snapped, the note doesn't actually start at start_time
    # anymore; it starts at the beginning of that step.
    start_time = secs_per_slot * start_slot
    duration = end_time - start_time

    tied_steps, final_gate = gates_for_duration(duration, secs_per_slot,
                                                min_gate: min_gate, quantize: quantize_gates)

    if tied_steps > 0
      tied_step = Step.new(note, vel: velocity)
      tied_steps.times do |i|
        slots[start_slot + i] << tied_step
      end
    end

    if final_gate > 0
      slots[start_slot + tied_steps] << Step.new(note, vel: velocity, gate: final_gate)
    end
  end

  # Convert a timeline of note events to a Track.
  #
  # The timeline is an array of four-element arrays, the elements of which are:
  # [0] the note, which may a MIDINote or anything convertible to one
  # [1] the start time of the note in seconds
  # [2] the end time of the note in seconds
  # [3] the MIDI velocity of the note (an integer between 0 and 127 inclusive)
  #
  # The duration of the resulting track is determined by the start_time and
  # end_time arguments. If they are provided, they specify the time at which
  # the recording of the timeline began and ended. All events in the timeline
  # must fall between those times. If either is nil, that endpoint is determined
  # from the events in the timeline. I.e., if start_time is nil, the start time
  # of the first event in the timeline is used. Likewise if end_time is nil, the
  # greatest end time among all the events in the timeline is used.
  #
  # bpm is the beats per minute at which the track is to be played back, and
  # granularity is the slot granularity for the resulting Track. Together these
  # two determine the duration of a slot in the track, and thus control how to
  # map between seconds in the timeline and steps in the track. Granularity can
  # be a NoteLength instance or any of the values accepted by NoteLength.new.
  # If bpm is nil, the current Sonic Pi BPM is used.
  #
  # min_gate specifies the minimum gate for translated events; if an event in
  # the timeline would last for less than min_gate, its duration is rounded up
  # to min_gate instead. Also, if an event translates to a sequence of tied
  # steps followed by one step with a partial gate, that final step will be
  # dropped if its gate is less than min_gate. If quantize_gates is true, all
  # gates are rounded up to the nearest multiple of min_gate.
  #
  # If ignore_vel is true, the velocities in the timeline will be ignored and
  # they will all be set to 127 in the resulting track.
  def self.timeline_to_track(timeline,
                             bpm: nil, granularity: NoteLength::Eighth,
                             start_time: nil, end_time: nil,
                             min_gate: 0.1, quantize_gates: true,
                             ignore_vel: false)
    bpm = ExtApi.current_bpm if bpm.nil?
    granularity = NoteLength.new(granularity)
    beats_per_sec = bpm * (1 / 60.0)
    secs_per_beat = 1.0 / beats_per_sec
    secs_per_slot = secs_per_beat * granularity.to_f

    trim_start = start_time.nil?
    trim_end = end_time.nil?
    start_time = timeline.min_by { |entry| entry[1] }[1] if trim_start
    end_time = timeline.max_by { |entry| entry[2] }[2] if trim_end
    duration = end_time - start_time

    total_track_gate = gates_for_duration(duration, secs_per_slot,
                                          min_gate: min_gate, quantize: quantize_gates)
    num_slots = total_track_gate[0] + total_track_gate[1].ceil

    slots = Array.new(num_slots) { [] }

    timeline.each do |entry|
      note = entry[0]

      note_start = entry[1] - start_time
      note_start = 0 if note_start < 0
      note_end = entry[2] - start_time
      note_end = end_time if note_end > end_time
      velocity = ignore_vel ? 127 : entry[3]

      add_note_to_slots(slots, secs_per_slot,
                        note, note_start, note_end, velocity,
                        min_gate: min_gate, quantize_gates: quantize_gates)
    end

    t = Track.new(slots, granularity: granularity)

    # I imagine, with rounding error, it's possible that we still wind up with
    # rests at either end of the track if one of the endpoints is nil. Trim the
    # final track just in case.
    t = t.ltrim if trim_start
    t = t.rtrim if trim_end

    t
  end

  # Records a timeline of note events, suitable for use with timeline_to_track.
  #
  # Recording is stopped and started by a MIDI CC (control_cc) on cc_port and
  # cc_channel, either of which may be wildcards. The value of the CC message is
  # ignored.
  #
  # MIDI notes from the given port and channel (which may also be wildcards) are
  # recorded in the timeline. Any notes that are still on when recording is
  # stopped by the control_cc are treated as if they ended at the same time that
  # the CC was received.
  #
  # This method blocks the calling thread until recording is stopped via the CC.
  # It must be called in a real-time context, i.e. in a thread that has called
  # use_real_time, or in a with_real_time block.
  #
  # The return is a three-element array [start time, end time, timeline], where
  # the timeline is as described in timeline_to_track.
  private_class_method def self.record_timeline(control_cc:, cc_port:, cc_channel:,
                                                port:, channel:)
    recording = false
    start_time = 0
    end_time = 0
    timeline = []
    in_progress_timeline_events = {}  # by note

    event_re = %r{^/midi:(?<port>[^:]+):(?<channel>\d+)/(?<event>.+)$}
    event_glob = "/midi:*/{control_change,note_on,note_off}"
    loop do
      note_or_cc, vel_or_cc_val = ExtApi.sync(event_glob)

      # get_event is undocumented, but it gives back a CueEvent object for the
      # most recent thing you sync'd to, given the argument you passed to sync.
      # The path property on that object is the string for the event.
      cue_event = ExtApi.get_event(event_glob)
      cue_name = cue_event.path

      # cue_event.time.to_f is also an option
      cue_time = ExtApi.vt

      re_match = event_re.match(cue_name)
      next if re_match.nil?

      cue_port = re_match[:port]
      cue_channel = re_match[:channel].to_i
      cue_event = re_match[:event]

      if cue_event == "control_change"
        next if note_or_cc != control_cc
        next if cc_port != "*" && cue_port != cc_port
        next if cc_channel != "*" && cue_channel != cc_channel

        if recording
          ExtApi.puts("ending recording @ #{cue_time}")

          recording = false
          end_time = cue_time
          break
        else
          ExtApi.puts("starting recording @ #{cue_time}")

          recording = true
          start_time = cue_time
        end
      elsif %w[note_on note_off].include?(cue_event)
        next unless recording
        next if port != "*" && cue_port != port
        next if channel != "*" && cue_channel != channel

        note = MIDINote.new(note_or_cc)
        vel = vel_or_cc_val

        active_event = in_progress_timeline_events[note]

        if cue_event == "note_on"
          if active_event.nil?
            in_progress_timeline_events[note] = [note, cue_time, -1, vel]
          else
            ExtApi.puts("got a note on for #{note}, but it's already on")
          end
        elsif active_event.nil?
          ExtApi.puts("got a note off for #{note}, but we didn't see it come on")
        else
          active_event[2] = cue_time
          timeline << active_event
          in_progress_timeline_events.delete(note)
        end
      end
    end

    # Clean up any lingering events by giving them the end time of the whole
    # recording.
    in_progress_timeline_events.each_value do |te|
      te[2] = end_time
      timeline << te
    end

    [start_time, end_time, timeline]
  end

  # Records incoming MIDI notes on a given port and channel (either of which
  # may be wildcards) and creates a Track by quantizing those notes to a grid.
  #
  # Recording is stopped and started by a MIDI CC (the cc argument) on cc_port
  # and cc_channel, either of which may be wildcards. The value of the CC
  # message is ignored.
  #
  # Any notes that are still on when recording is stopped by the CC are treated
  # as if they ended at the same time that the CC was received.
  #
  # If any of the CC port/channel or the port/channel for notes is nil, the
  # default is used, or a wildcard if no default is set. Set the default CC
  # options for spi-seq with use_cc_control_defaults, and the defaults for MIDI
  # notes with Sonic Pi's built-in use_midi_defaults.
  #
  # bpm is the beats per minute at which the track is to be played back, and
  # granularity is the slot granularity for the resulting track. Together these
  # two determine the duration of a slot in the track, and thus control how to
  # map between wall-clock seconds and steps in the track. Granularity can be a
  # NoteLength instance or any of the values accepted by NoteLength.new. If bpm
  # is nil, the current Sonic Pi BPM is used.
  #
  # By default, the track will last for the duration that recording was enabled
  # via the CC; if there was silence at the beginning or end of recording, there
  # will be rests on either end of the resulting track. If true, trim_start and
  # trim_end will remove those rests from the corresponding ends of the track.
  #
  # min_gate specifies the minimum gate for single notes in the track; if a
  # recorded MIDI event would translate to a single step with a gate less than
  # min_gate, its duration is rounded up to min_gate instead. Also, if an event
  # translates to a sequence of tied steps followed by one step with a partial
  # gate, that final step will be dropped if its gate is less than min_gate. If
  # quantize_gates is true, all gates are rounded up to the nearest multiple of
  # min_gate.
  #
  # If ignore_vel is true, the recorded velocity of notes will be ignored and
  # they will all be set to 127 in the resulting track.
  def self.record(cc:, cc_port: nil, cc_channel: nil,
                  port: nil, channel: nil,
                  bpm: nil, granularity: NoteLength::Eighth,
                  trim_start: false, trim_end: false,
                  min_gate: 0.1, quantize_gates: true,
                  ignore_vel: false)
    cc_port, cc_channel = __resolve_cc_port_and_channel(cc_port, cc_channel)
    port, channel = __resolve_midi_port_and_channel(port, channel)

    start_time = end_time = timeline = nil
    ExtApi.with_real_time do
      start_time, end_time, timeline = record_timeline(control_cc: cc, cc_port: cc_port, cc_channel: cc_channel,
                                                       port: port, channel: channel)
    end

    start_time = nil if trim_start
    end_time = nil if trim_end

    # TODO: guard against an empty track when trimming

    timeline_to_track(timeline,
                      start_time: start_time, end_time: end_time,
                      bpm: bpm, granularity: granularity,
                      min_gate: min_gate, quantize_gates: quantize_gates,
                      ignore_vel: ignore_vel)
  end
end
