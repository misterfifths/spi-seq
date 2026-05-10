# frozen_string_literal: true

require "forwardable"
require_relative "chord"
require_relative "interval"
require_relative "midinote"

class Chord
  VOICING_DEFS = {
    %i[closed]                  => :voice_closed,
    %i[rootless]                => :voice_rootless,
    %i[shell]                   => :voice_shell,
    %i[drop_two drop_2 drop2]   => ->(intervals, root) { voice_drop(intervals, root, 2) },
    %i[drop_three drop_3 drop3] => ->(intervals, root) { voice_drop(intervals, root, 3) },
    %i[drop_two_three drop_2_3
       drop23]                  => ->(intervals, root) { voice_drop(intervals, root, 2, 3) },
    %i[drop_two_four drop_2_4
       drop24]                  => ->(intervals, root) { voice_drop(intervals, root, 2, 4) },
    %i[drop_three_four drop_3_4
       drop34]                  => ->(intervals, root) { voice_drop(intervals, root, 3, 4) },
    %i[drop_four drop_4 drop4]  => ->(intervals, root) { voice_drop(intervals, root, 4) },
    %i[double_root
       double_root_down]        => ->(intervals, root) { voice_double_root(intervals, root, -12) },
    %i[double_root_up]          => ->(intervals, root) { voice_double_root(intervals, root, 12) },
    %i[double_bass
       double_bass_down]        => ->(intervals, root) { voice_double_bass(intervals, root, -12) },
    %i[double_bass_up]          => ->(intervals, root) { voice_double_bass(intervals, root, 12) },
    %i[double_third double_three
       double_3 double3
       double_third_down
       double_three_down
       double_3_down
       double3_down]            => ->(intervals, root) { voice_double_interval_num(intervals, root, 3, -12) },
    %i[double_third_up
       double_three_up
       double_3_up double3_up]  => ->(intervals, root) { voice_double_interval_num(intervals, root, 3, 12) },
    %i[double_fifth double_five
       double_5 double5
       double_fifth_down
       double_five_down
       double_5_down
       double5_down]            => ->(intervals, root) { voice_double_interval_num(intervals, root, 5, -12) },
    %i[double_fifth_up
       double_five_up
       double_5_up double5_up]  => ->(intervals, root) { voice_double_interval_num(intervals, root, 5, 12) },
    %i[open]                    => :voice_open,
    %i[open2]                   => :voice_open2,
    %i[open3]                   => :voice_open3
  }.freeze
  private_constant :VOICING_DEFS

  # Blow VOICING_DEFS up into a 1-d map from names.

  # A hash of the voicing styles supported by this class. The keys of this hash
  # are the valid values to pass to {.voice}.
  #
  # Valid voicing styles:
  # - `:closed`: The simplest voicing: uses the intervals in the chord as-is.
  # - `:rootless`: The same as closed voicing, but omits the root note.
  # - `:shell`: Only the root, thirds, and seventh intervals are included.
  # - `:drop2`: Applies a closed voicing, then drops the 2nd highest note in the
  #   result an octave.
  # - `:drop3`: Same as drop2, but drops the third highest note.
  # - `:drop23`: Combines drop2 and drop3.
  # - `:drop24`: drop2, and also drops the 4th highest note.
  # - `:drop34`: drop3, and also drops the 4th highest note.
  # - `:drop4`: Like drop2, but only drops the 4th highest note.
  # - `:double_root`: Applies a closed voicing, then adds a note that is an
  #   octave below the root note.
  # - `:double_root_up`: Like double_root, but adds the root note an octave up.
  # - `:double_bass`: Applies a closed voicing, then adds a note that is an
  #   octave below the lowest note in the result. This will be identical to
  #   double_root unless there is an inversion.
  # - `:double_bass_up`: Like double_bass, but adds the new note an octave up.
  # - `:double3`: Applies a closed voicing, then, if there is a third in the
  #   chord, adds a note that is an octave below that.
  # - `:double3_up`: Same as double 3, but adds the new note an octave up.
  # - `:double5`: Same as double3, but looks for a fifth in the chord.
  # - `:double5_up`: Same as double3_up, but looks for a fifth in the chord.
  # - `:open`: Applies a closed voicing, then raises the second-lowest note an
  #   octave.
  # - `:open2`: Applies a closed voicing, then raises the lowest note an octave
  #   and lowers the third lowest note an octave.
  # - `:open3`: Applies a closed voicing, then lowers the second-lowest note an
  #   octave.
  #
  # (Note that there are aliases for many of the above styles; print the result
  # of `Chord::VOICINGS.keys` to see all possible names.)
  VOICINGS = {}  # rubocop:disable Style/MutableConstant
  VOICING_DEFS.each do |names, val|
    names.each { |name| VOICINGS[name] = val }
  end
  VOICINGS.freeze

  # TODO: use expressible_as instead? what about the P1?
  SHELL_INTERVALS = [:P1, :d3, :m3, :M3, :A3, :d7, :m7, :M7, :A7].map { |i| Interval.new(i) }
  SHELL_INTERVALS.freeze
  private_constant :SHELL_INTERVALS

  # @private
  def self.voice(chord, root, voicing = :closed, inversion: 0)
    root = MIDINote.new(root)

    # Inversions apply before voicing.
    raise RangeError, "inversion must be >= 0" unless inversion >= 0
    raise RangeError, "chord only has #{chord.intervals.length - 1} inversions" if inversion >= chord.intervals.length
    if inversion > 0
      intervals = chord.intervals.dup
      shifted_intervals = intervals.shift(inversion).map! { |i| i + 12 }
      intervals += shifted_intervals

      # Inversion may have duplicated an interval.
      intervals.sort!
      intervals.uniq!
    else
      intervals = chord.intervals
    end

    voice_val = VOICINGS[voicing]
    raise ArgumentError, "unknown voicing #{voicing}" if voice_val.nil?
    notes = case voice_val
    when Symbol
      method(voice_val).call(intervals, root)
    else
      voice_val.call(intervals, root)
    end
    notes.sort!
    notes.uniq!
    notes
  end


  # These voicing methods receive an array of Intervals which will be uniq'd and
  # sorted low to high. They should return an array of MIDINotes that are also
  # uniq'd and sorted.
  #
  # Voicings are applied after inversion of the intervals.

  # Straight voicing of the intervals in order on the root.
  private_class_method def self.voice_closed(intervals, root)
    intervals.map { |i| root + i }
  end

  # Closed voicing without the root.
  private_class_method def self.voice_rootless(intervals, root)
    notes = []
    intervals.each do |i|
      notes << root + i unless i == :P1
    end
    notes
  end

  # Only the root, thirds, and sevenths are voiced.
  private_class_method def self.voice_shell(intervals, root)
    notes = []
    intervals.each do |i|
      notes << root + i if SHELL_INTERVALS.include?(i)
    end
    notes
  end

  # Lowers the nth highest notes (from drops) an octave.
  private_class_method def self.voice_drop(intervals, root, *drops)
    notes = voice_closed(intervals, root)
    drops.each do |idx|
      next if idx > notes.length  # TODO: should this be an error?
      notes[-idx] -= 12
    end
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles the root note, offset by the given number of semitones.
  private_class_method def self.voice_double_root(intervals, root, shift)
    notes = voice_closed(intervals, root)
    notes.append(root + shift) if notes.include?(root)
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles the lowest note in the closed voicing, offset by the given number of
  # semitones. Note that this will be equivalent to doubling the root note
  # unless there's an inversion.
  private_class_method def self.voice_double_bass(intervals, root, shift)
    notes = voice_closed(intervals, root)
    notes.append(notes[0] + shift)
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles the note corresponding to the given interval number (in any
  # alteration), offset by the given number of semitones. Equivalent to a closed
  # voicing if there is no such interval in the chord.
  private_class_method def self.voice_double_interval_num(intervals, root, doubled_num, shift)
    notes = []
    intervals.each do |i|
      notes << root + i
      notes << root + i + shift if i.expressible_as(doubled_num)
    end
    notes.sort!
    notes.uniq!
    notes
  end

  # Raise the 2nd lowest note an octave. Does nothing if there is only one note.
  private_class_method def self.voice_open(intervals, root)
    notes = voice_closed(intervals, root)
    notes[1] += 12 if notes.length >= 2
    notes.sort!
    notes.uniq!
    notes
  end

  # Raise the lowest note an octave and lower the third lowest note an octave.
  # If there is only one note, only it is lowered.
  private_class_method def self.voice_open2(intervals, root)
    notes = voice_closed(intervals, root)
    notes[0] += 12
    notes[2] -= 12 if notes.length >= 3
    notes.sort!
    notes.uniq!
    notes
  end

  # Lower the 2nd lowest note an octave. Does nothing if there is only one note.
  private_class_method def self.voice_open3(intervals, root)
    notes = voice_closed(intervals, root)
    notes[1] -= 12 if notes.length >= 2
    notes.sort!
    notes.uniq!
    notes
  end
end
