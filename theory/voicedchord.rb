# frozen_string_literal: true

require "forwardable"
require_relative "chord"
require_relative "interval"
require_relative "midinote"


# A Chord that has been voiced on a particular root note in a particular style
# and inversion. Most easily created with the `voice` method on a Chord.
# Enumerable over its MIDINotes.
#
# Voicing styles apply after the chord's intervals are inverted.
class VoicedChord
  include Enumerable
  extend Forwardable

  attr_reader :chord, :root, :inversion, :voicing, :notes

  # each gets us all of Enumerable. The others are common methods on Array that
  # aren't in Enumerable.
  def_delegators :@notes, :each, :[], :slice, :length, :size, :last, :to_a, :to_ary, :values_at


  # TODO: double voicings that go up an octave

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
    %i[double_root]             => :voice_double_root,
    %i[double_bass]             => :voice_double_bass,
    %i[double_third double_three
       double_3 double3]        => ->(intervals, root) { voice_double_interval_num(intervals, root, 3) },
    %i[double_fifth double_five
       double_5 double5]        => ->(intervals, root) { voice_double_interval_num(intervals, root, 5) },
    %i[open]                    => :voice_open,
    %i[open2]                   => :voice_open2,
    %i[open3]                   => :voice_open3
  }.freeze
  private_constant :VOICING_DEFS

  # Blow VOICING_DEFS up into a 1-d map from names.
  VOICINGS = {}  # rubocop:disable Style/MutableConstant
  VOICING_DEFS.each do |names, val|
    names.each { |name| VOICINGS[name] = val }
  end
  VOICINGS.freeze

  # TODO: use expressible_as instead? what about the P1?
  SHELL_INTERVALS = [:P1, :d3, :m3, :M3, :A3, :d7, :m7, :M7, :A7].map { |i| Interval.new(i) }
  SHELL_INTERVALS.freeze
  private_constant :SHELL_INTERVALS


  # Creates a new VoicedChord instance for the given chord on a root note. The
  # voicing argument must be the name of a voicing style, as found in the keys
  # of the VOICINGS hash. inversion specifies how to invert the chord's
  # intervals before applying the voicing.
  def initialize(chord, root, voicing = :closed, inversion: 0)
    @chord = chord
    @root = MIDINote.new(root)
    @inversion = inversion
    @voicing = voicing.to_sym

    # Inversions apply before voicing.
    raise ArgumentError, "inversion must be >= 0" unless @inversion >= 0
    raise ArgumentError, "chord only has #{chord.intervals.length - 1} inversions" if @inversion >= chord.intervals.length
    if @inversion > 0
      intervals = chord.intervals.dup
      shifted_intervals = intervals.shift(@inversion).map! { |i| i + 12 }
      intervals += shifted_intervals

      # Inversion may have duplicated an interval.
      intervals.sort!
      intervals.uniq!
    else
      intervals = @chord.intervals
    end

    voice_val = VOICINGS[@voicing]
    raise ArgumentError, "unknown voicing #{voicing}" if voice_val.nil?
    @notes = case voice_val
    when Symbol
      VoicedChord.method(voice_val).call(intervals, @root)
    else
      voice_val.call(intervals, @root)
    end
    @notes.sort!
    @notes.uniq!
    @notes.freeze
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

  # Doubles the root note, an octave down.
  private_class_method def self.voice_double_root(intervals, root)
    notes = voice_closed(intervals, root)
    notes.append(root - 12) if notes.include?(root)
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles the lowest note in the closed voicing, an octave down. Note that
  # this will be equivalent to doubling the root note unless there's an
  # inversion.
  private_class_method def self.voice_double_bass(intervals, root)
    notes = voice_closed(intervals, root)
    notes.append(notes[0] - 12)
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles the note corresponding to the given interval number (in any
  # alteration), an octave down. Equivalent to a closed voicing if there is no
  # such interval in the chord.
  private_class_method def self.voice_double_interval_num(intervals, root, doubled_num)
    notes = []
    intervals.each do |i|
      notes << root + i
      notes << root + i - 12 if i.expressible_as(doubled_num)
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
