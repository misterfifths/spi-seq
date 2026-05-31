# frozen_string_literal: true

require "forwardable"
require_relative "chord"
require_relative "interval"
require_relative "midinote"
require_relative "scale"

# @!group Music theory

# (see Chord.voiced)
def C(root, name, voicing = :closed, num_octaves: 1, invert: 0)
  Chord.voiced(root, name, voicing, num_octaves: num_octaves, invert: invert)
end

# @!endgroup

# This documentation should live in chord.rb, but I couldn't convince yard to
# parse that file first.

# A grouping of Intervals that represents a chord.
#
# Sonic Pi already provides a class called `Chord`, so this class is aliased to
# {Ch}.
#
# Enumerable over its {#intervals}, and has most of the read-only methods of
# Array. The intervals are always sorted ascending and will never contain
# duplicates, even if a mutation might produce one.
#
# Note that this class only represents the intervals; it does not track a root
# note or inversions. Instances can be concretely expressed (i.e., converted to
# actual {MIDINote}s) on a particular root note with {#voice}, {.voiced} or the
# {C} helper function. Inversions also happen at voice-time.
#
# **Chord objects are immutable.** The various mutation methods it provides
# (e.g. {#flat}, {#sus4}, {#add}) return new Chord instances with different
# intervals.
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
       double_root_down
       double_bass
       double_bass_down]        => ->(intervals, root) { voice_double_bass(intervals, root, -12) },
    %i[double_root_up
       double_bass_up]          => ->(intervals, root) { voice_double_bass(intervals, root, 12) },
    %i[double_third double_three
       double_3 double3
       double_third_down
       double_three_down
       double_3_down
       double3_down
       double3down]             => ->(intervals, root) { voice_double_interval(intervals, root, %i[m3 M3], -12) },
    %i[double_third_up
       double_three_up
       double_3_up double3_up
       double3up]               => ->(intervals, root) { voice_double_interval(intervals, root, %i[m3 M3], 12) },
    %i[double_fifth double_five
       double_5 double5
       double_fifth_down
       double_five_down
       double_5_down
       double5_down
       double5down]             => ->(intervals, root) { voice_double_interval(intervals, root, [:P5], -12) },
    %i[double_fifth_up
       double_five_up
       double_5_up double5_up
       double5up]               => ->(intervals, root) { voice_double_interval(intervals, root, [:P5], 12) },
    %i[double_seventh
       double_seven double_7
       double7
       double_seventh_down
       double_seven_down
       double_7_down
       double7_down
       double7down]             => ->(intervals, root) { voice_double_interval(intervals, root, %i[m7 M7], -12) },
    %i[double_seventh_up
       double_seven_up
       double_7_up double7_up
       double7up]               => ->(intervals, root) { voice_double_interval(intervals, root, %i[m7 M7], 12) },
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
  private_constant :VOICINGS

  # The names of all voicing styles supported by this class. These are the valid
  # values to pass to {.voice}.
  #
  # Valid voicing styles:
  # - `closed`: The simplest voicing: uses the intervals in the chord as-is.
  # - `rootless`: The same as closed voicing, but omits the root note. If the
  #   only interval in the chord is the root, this voicing will return an empty
  #   array.
  # - `shell`: Only the root, thirds, and seventh intervals (in any octave) are
  #   included. If none of those intervals are present in the chord, this
  #   voicing will return an empty array.
  # - `drop2`: Applies a closed voicing, then drops the 2nd highest note in the
  #   result an octave.
  # - `drop3`: Same as drop2, but drops the third highest note.
  # - `drop4`: Same as drop2, but only drops the 4th highest note.
  # - `drop23`: Combines drop2 and drop3.
  # - `drop24`: Combines drop2 and drop4.
  # - `drop34`: Combines drop3 and drop4.
  # - `double_bass`: Applies a closed voicing, then adds a note that is an
  #   octave below the lowest note in the result.
  # - `double_bass_up`: Like double_bass, but adds the new note an octave up.
  # - `double3`: Applies a closed voicing, then adds a note an octave below any
  #   major or minor 3rd (in all octaves).
  # - `double3_up`: Same as double 3, but adds the new note an octave up.
  # - `double5`: Same as double3, but looks for perfect fifths in the chord.
  # - `double5_up`: Same as double3_up, but looks for perfect fifths in the
  #   chord.
  # - `double7`: Same as double3, but looks for major or minor 7ths in the
  #   chord.
  # - `double7_up`: Same as double3_up, but looks for major or minor 7ths in
  #   the chord.
  # - `open`: Applies a closed voicing, then raises the second-lowest note an
  #   octave.
  # - `open2`: Applies a closed voicing, then raises the lowest note an octave
  #   and lowers the third lowest note an octave.
  # - `open3`: Applies a closed voicing, then lowers the second-lowest note an
  #   octave.
  #
  # Note that there are aliases for many of the above styles; print this array
  # to see all possible names.
  #
  # @return [Array<Symbol>]
  VOICING_STYLES = VOICINGS.keys.to_a.freeze


  SHELL_INTERVALS = [:P1, :m3, :M3, :m7, :M7].map { |i| Interval.new(i) }
  SHELL_INTERVALS.freeze
  private_constant :SHELL_INTERVALS


  # @!group Voicing

  # Returns an array of {MIDINote}s that express a named chord on the given
  # root note, using a particular voicing style and inversion. A shortcut for
  # creating a {Chord} and immediately {Chord#voice voicing} it.
  # @param root [MIDINote, String, Symbol, Integer] The root note of the chord.
  #   May be a {MIDINote} or anything understood by {MIDINote.new}.
  # @param name [Symbol, String] The name of the chord, a value accepted by
  #   {Chord.new}.
  # @param voicing [Symbol, String] The voicing style to use, a value accepted
  #   by {Chord#voice}.
  # @param num_octaves [Integer] How many octaves of the chord to express. This
  #   many copies of the chord's intervals will be added, each an octave higher,
  #   before inverting and voicing.
  # @param invert [Integer] The number of inversions to apply to the chord
  #   before voicing it.
  # @return [Array<MIDINote>]
  # @see Chord.new
  # @see Chord#voice
  def self.voiced(root, name, voicing = :closed, num_octaves: 1, invert: 0)
    new(name).voice(root, voicing, num_octaves: num_octaves, invert: invert)
  end

  # Voices the chord. That is, converts the {#intervals} to concrete notes,
  # after potentially applying an inversion and a voicing technique.
  #
  # You can create and voice a chord in one shot using {.voiced} or the {C}
  # helper function.
  #
  # @param root [MIDINote, String, Symbol, Integer] The root note upon which to
  #   voice the chord. Must be a {MIDINote} or something understood by
  #   {MIDINote.new}.
  # @param voicing [Symbol] The voicing style to use. Valid values are listed in
  #   the {.VOICING_STYLES} array.
  # @param num_octaves [Integer] How many octaves of the chord to express. This
  #   many copies of the chord's intervals will be added, each an octave higher,
  #   before inverting and voicing. Note that combining this with inversion is
  #   likely to result in duplicate intervals, which will not result in
  #   duplicate notes in the output.
  # @param invert [Integer] How many times to invert the chord's intervals
  #   before applying the `voicing`.
  # @return [Array<MIDINote>]
  # @see C
  # @see .voiced
  def voice(root, voicing = :closed, num_octaves: 1, invert: 0)
    raise RangeError, "inversion must be >= 0" unless invert >= 0

    root = MIDINote.new(root)

    intervals = []
    num_octaves.times do |octave|
      @intervals.each do |interval|
        intervals << interval + 12 * octave
      end
    end
    intervals.sort!
    intervals.uniq!

    # Inversions apply before voicing.
    raise RangeError, "chord only has #{intervals.length - 1} inversions" if invert >= intervals.length

    if invert > 0
      shifted_intervals = intervals.shift(invert).map! { |i| i + 12 }
      intervals += shifted_intervals

      # Inversion may have duplicated an interval.
      intervals.sort!
      intervals.uniq!
    end

    voice_val = VOICINGS[voicing]
    raise ArgumentError, "unknown voicing #{voicing}" if voice_val.nil?
    notes = case voice_val
    when Symbol
      Chord.method(voice_val).call(intervals, root)
    else
      voice_val.call(intervals, root)
    end
    notes.sort!
    notes.uniq!
    notes
  end

  # Returns a set of notes for a chord of the given degree on a scale. The root
  # note of the chord is the note at degree `d` on the scale starting at
  # `tonic`. From there, subsequent thirds (major or minor) on the scale are
  # added.
  #
  # This process ends when `number_of_notes` notes have been accumulated, or
  # when the next third is not on the scale. So, on non-diatonic scales (e.g.
  # pentatonic), which are not built on thirds, this function has limited
  # utility. For example, it is not possible to build a chord on the second
  # degree of C major pentatonic; the root is D, but there is no third after
  # D on the scale.
  #
  # This is equivalent to Sonic Pi's `chord_degree` on diatonic scales, though
  # it does add `voicing`.
  #
  # @example
  #   Chord.degree(:i, :a3, :major)  # [:a3, :cs4, :e4, :gs4] - A3 maj7
  #   Chord.degree(:ii, :a3, :major, 5)  # [:b3, :d4, :fs4, :a4, :cs5] - B3 min9
  #   Chord.degree(:vii, :g4, :major, 3)  # [:fs5, :a5, :c6] - F#5 dim
  #
  #   Chord.degree(:v, :c4, :major, 3, :drop2)  # [:b3, :g4, :d5] - G4 maj, drop2 voicing
  #
  #   # Probably best avoided on non-diatonic scales:
  #   Chord.degree(2, :c4, :major_pentatonic, 5)  # [:d4]; see above
  #
  # @param d [Integer, String, Symbol] The chord degree. May be an integer or
  #   a Roman numeral string or symbol (e.g. `:ii` or "ix"). Must be > 0.
  # @param tonic [MIDINote, String, Symbol, Integer] The root note of the scale.
  #   May be a {MIDINote} or any value understood by {MIDINote.new}.
  # @param scale_name [Symbol, String] The name of the scale to use, one of the
  #   values in {Scale.SCALE_NAMES}. Most of the scale name recognized by Sonic
  #   Pi's `scale` function are supported, and some others.
  # @param number_of_notes [Integer] The number of notes from the chord to
  #   return. This function will never return notes outside of the MIDI range
  #   (0 - 127), or notes that are not on the scale, so the result may contain
  #   fewer than this many elements.
  # @param voicing [Symbol] The voicing style to use. Valid values are listed in
  #   the {.VOICING_STYLES} array
  # @param invert [Integer] How many times to invert the chord's intervals
  #   before applying the `voicing`. This must be < `number_of_notes`.
  # @return [Array<MIDINote>]
  # @see #voice
  # @see Scale.degree
  def self.degree(d, tonic, scale_name, number_of_notes = 4, voicing = :closed, invert: 0)
    raise RangeError, "chord only has #{number_of_notes - 1} inversions" if invert >= number_of_notes

    # Scale#degree accepts degrees like :aii, but we can accept only non-
    # prefixed numbers so that we wind up with root note that is actually on the
    # scale.
    n, mod = Scale.parse_degree(d)
    raise ArgumentError, "invalid degree #{d}" if mod != 0
    raise RangeError, "degree must be > 0" if n <= 0

    scale = Scale.full_scale(tonic, scale_name)
    root = scale.degree(d, relative_tonic: tonic)

    # Select subsequent 3rds (major or minor), until we hit one that is not on
    # the scale. Note that outside of diatonic scales this behavior differs
    # quite a bit from Sonic Pi, which just selects every other note on the
    # scale. Our behavior seems more sensible.
    maj3 = Interval.new(:M3)
    min3 = Interval.new(:m3)
    notes = [root]
    intervals = [Interval.new(:P1)]
    (number_of_notes - 1).times do
      n = notes[-1] + maj3
      if scale.include?(n)
        notes << n
        intervals << intervals[-1] + maj3
      else
        n = notes[-1] + min3
        break unless scale.include?(n)
        notes << n
        intervals << intervals[-1] + min3
      end
    end

    # A slightly silly round-trip between notes & intervals, but this lets us
    # piggyback on chord voicing.
    chord = Chord.new(intervals)

    # Note that since we may have wound up with fewer notes than
    # `number_of_notes`, `invert` may now be > notes.length. Quite the edge
    # case; I'm just going to take it down to the minimum.
    invert = intervals.length - 1 if invert >= intervals.length
    chord.voice(root, voicing, invert: invert)
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

  # Only the root, thirds, and sevenths (in any octave) are voiced.
  private_class_method def self.voice_shell(intervals, root)
    notes = []
    intervals.each do |i|
      notes << root + i if SHELL_INTERVALS.include?(i.simple_interval)
    end
    notes
  end

  # Lowers the nth highest notes (from drops) an octave.
  private_class_method def self.voice_drop(intervals, root, *drops)
    notes = voice_closed(intervals, root)
    drops.each do |idx|
      next if idx > notes.length
      notes[-idx] -= 12
    end
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles the lowest note in the closed voicing, offset by the given number of
  # semitones.
  private_class_method def self.voice_double_bass(intervals, root, shift)
    notes = voice_closed(intervals, root)
    notes.append(notes[0] + shift)
    notes.sort!
    notes.uniq!
    notes
  end

  # Doubles all notes corresponding to the given intervals (double_ints), offset
  # by the given number of semitones. Equivalent to a closed voicing if none of
  # the target intervals are in the chord.
  private_class_method def self.voice_double_interval(intervals, root, double_ints, shift)
    double_ints = double_ints.map { |i| Interval.new(i) }

    notes = []
    intervals.each do |i|
      notes << root + i
      notes << root + i + shift if double_ints.include?(i.simple_interval)
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
