# frozen_string_literal: true

require "forwardable"
require_relative "interval"
require_relative "midinote"


# TODO: support interval-ish notation to `degree`, add back Arp.arp_degrees


# @!group Music theory
# An alias for {Scale#initialize Scale.new}.
# @return [Scale]
def SC(*args, **kwargs)
  Scale.new(*args, **kwargs)
end
# @!endgroup


# A grouping of notes that represents some {#num_octaves number of octaves} of a
# {#name scale}, starting on a particular {#tonic root note}. Enumerable over
# its {#notes}, and has most of the read-only methods of Array.
#
# If you would like a scale that covers the full MIDI range, see {.full_scale}.
# Such a scale is useful for, e.g., {Track#scale}.
#
# Scales are immutable.
#
# Sonic Pi already provides a class called `Scale`, so this class is aliased to
# {Sc}. Alternatively, you can use the {SC} function as an alias for
# {#initialize Scale.new}.
class Scale
  include Enumerable
  extend Forwardable

  # The name of the scale, one of the keys in {SCALES}.
  # @return [Symbol]
  attr_reader :name

  # The root note of the scale.
  # @return [MIDINote]
  attr_reader :tonic

  # The number of octaves included in this instance.
  # @return [Integer]
  attr_reader :num_octaves

  # The notes of the scale held by this instance, consisting of {#num_octaves}
  # octaves along the scale starting at {#tonic}.
  # @return [Array<MIDINote>]
  attr_reader :notes

  # Whether the notes held by this instance are clamped to the MIDI range (0 -
  # 127).
  # @return [Boolean]
  attr_reader :clamp_to_midi

  # each gets us all of Enumerable. The others are common methods on Array that
  # aren't in Enumerable.
  def_delegators :@notes,
                 :each, :[], :slice, :length, :size, :last, :to_a, :to_ary,
                 :values_at, :empty?

  # A hash of the scales supported by this class. The keys of this hash are the
  # valid values to pass to {#initialize}.
  SCALES = lambda do
    # These scale definitions are taken from Overtone,
    # https://github.com/overtone/overtone

    ionian_sequence     = [2, 2, 1, 2, 2, 2, 1]
    hex_sequence        = [2, 2, 1, 2, 2, 3]
    pentatonic_sequence = [3, 2, 2, 3, 2]

    scales = {
      diatonic:           ionian_sequence,
      ionian:             ionian_sequence,
      major:              ionian_sequence,
      dorian:             ionian_sequence.rotate(1),
      phrygian:           ionian_sequence.rotate(2),
      lydian:             ionian_sequence.rotate(3),
      mixolydian:         ionian_sequence.rotate(4),
      aeolian:            ionian_sequence.rotate(5),
      minor:              ionian_sequence.rotate(5),
      locrian:            ionian_sequence.rotate(6),
      hex_major6:         hex_sequence,
      hex_dorian:         hex_sequence.rotate(1),
      hex_phrygian:       hex_sequence.rotate(2),
      hex_major7:         hex_sequence.rotate(3),
      hex_sus:            hex_sequence.rotate(4),
      hex_aeolian:        hex_sequence.rotate(5),
      minor_pentatonic:   pentatonic_sequence,
      yu:                 pentatonic_sequence,
      major_pentatonic:   pentatonic_sequence.rotate(1),
      gong:               pentatonic_sequence.rotate(1),
      egyptian:           pentatonic_sequence.rotate(2),
      shang:              pentatonic_sequence.rotate(2),
      jiao:               pentatonic_sequence.rotate(3),
      pentatonic:         pentatonic_sequence.rotate(4),  # historical match
      zhi:                pentatonic_sequence.rotate(4),
      ritusen:            pentatonic_sequence.rotate(4),
      whole_tone:         [2, 2, 2, 2, 2, 2],
      whole:              [2, 2, 2, 2, 2, 2],
      chromatic:          [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
      harmonic_minor:     [2, 1, 2, 2, 1, 3, 1],
      melodic_minor_asc:  [2, 1, 2, 2, 2, 2, 1],
      hungarian_minor:    [2, 1, 3, 1, 1, 3, 1],
      octatonic:          [2, 1, 2, 1, 2, 1, 2, 1],
      messiaen1:          [2, 2, 2, 2, 2, 2],
      messiaen2:          [1, 2, 1, 2, 1, 2, 1, 2],
      messiaen3:          [2, 1, 1, 2, 1, 1, 2, 1, 1],
      messiaen4:          [1, 1, 3, 1, 1, 1, 3, 1],
      messiaen5:          [1, 4, 1, 1, 4, 1],
      messiaen6:          [2, 2, 1, 1, 2, 2, 1, 1],
      messiaen7:          [1, 1, 1, 2, 1, 1, 1, 1, 2, 1],
      super_locrian:      [1, 2, 1, 2, 2, 2, 2],
      hirajoshi:          [2, 1, 4, 1, 4],
      kumoi:              [2, 1, 4, 2, 3],
      neapolitan_major:   [1, 2, 2, 2, 2, 2, 1],
      bartok:             [2, 2, 1, 2, 1, 2, 2],
      bhairav:            [1, 3, 1, 2, 1, 3, 1],
      locrian_major:      [2, 2, 1, 1, 2, 2, 2],
      ahirbhairav:        [1, 3, 1, 2, 2, 1, 2],
      enigmatic:          [1, 3, 2, 2, 2, 1, 1],
      neapolitan_minor:   [1, 2, 2, 2, 1, 3, 1],
      pelog:              [1, 2, 4, 1, 4],
      augmented2:         [1, 3, 1, 3, 1, 3],
      scriabin:           [1, 3, 3, 2, 3],
      harmonic_major:     [2, 2, 1, 2, 1, 3, 1],
      melodic_minor_desc: [2, 1, 2, 2, 1, 2, 2],
      romanian_minor:     [2, 1, 3, 1, 2, 1, 2],
      hindu:              [2, 2, 1, 2, 1, 2, 2],
      iwato:              [1, 4, 1, 4, 2],
      melodic_minor:      [2, 1, 2, 2, 2, 2, 1],
      diminished2:        [2, 1, 2, 1, 2, 1, 2, 1],
      marva:              [1, 3, 2, 1, 2, 2, 1],
      melodic_major:      [2, 2, 1, 2, 1, 2, 2],
      indian:             [4, 1, 2, 3, 2],
      spanish:            [1, 3, 1, 2, 1, 2, 2],
      prometheus:         [2, 2, 2, 5, 1],
      diminished:         [1, 2, 1, 2, 1, 2, 1, 2],
      todi:               [1, 2, 3, 1, 1, 3, 1],
      leading_whole:      [2, 2, 2, 2, 2, 1, 1],
      augmented:          [3, 1, 3, 1, 3, 1],
      purvi:              [1, 3, 2, 1, 1, 3, 1],
      chinese:            [4, 2, 1, 4, 1],
      lydian_minor:       [2, 2, 2, 1, 1, 2, 2]
    }

    {
      maj: :major,
      hex_maj6: :hex_major6,
      hex_maj7: :hex_major7,
      min_pentatonic: :minor_pentatonic,
      maj_pentatonic: :major_pentatonic,
      harmonic_min: :harmonic_minor,
      melodic_min_asc: :melodic_minor_asc,
      hungarian_min: :hungarian_minor,
      neapolitan_maj: :neapolitan_major,
      locrian_maj: :locrian_major,
      neapolitan_min: :neapolitan_minor,
      harmonic_maj: :harmonic_major,
      melodic_min_desc: :melodic_minor_desc,
      romanian_min: :romanian_minor,
      melodic_min: :melodic_minor,
      melodic_maj: :melodic_major,
      lydian_min: :lydian_minor
    }.each { |alias_name, name| scales[alias_name] = scales[name] }

    scales.each_value { |steps| steps.freeze }
    scales.freeze

    scales
  end.call


  # Creates a new Scale.
  #
  # `Scale.new` is aliased to {SC} for convenience.
  #
  # @param tonic [MIDINote, String, Symbol, Integer] The root note of the scale.
  #   A {MIDINote} or one of the values understood by {MIDINote.new}.
  # @param name [Symbol, String] The name of the scale to use, one of the keys
  #   of the {.SCALES} hash. This class understands all of the same scale names
  #   as Sonic Pi's `scale` function and more.
  # @param num_octaves [Integer] The resulting instance will have notes
  #   belonging to this many octaves of the scale.
  # @param clamp_to_midi [Boolean] If true, only notes in the MIDI range of 0 -
  #   127 will be included.
  def initialize(tonic, name, num_octaves: 1, clamp_to_midi: false)
    @tonic = MIDINote.new(tonic)
    @name = name.to_sym
    @num_octaves = num_octaves
    @clamp_to_midi = clamp_to_midi

    steps = SCALES[@name]
    raise ArgumentError, "unknown scale name #{name}" if steps.nil?

    @notes = [@tonic]
    @num_octaves.times do
      steps.each { |step| @notes << @notes[-1] + step }
    end

    @notes.reject! { |n| n < 0 || n > 127 } if @clamp_to_midi

    @notes.freeze
  end

  # Returns a Scale that covers the full set of MIDI notes (0-127) that belong
  # to the given scale with the given tonic.
  # @param tonic [String, Symbol] The pitch class for the root note of the
  #   scale, e.g. `:c`.
  # @param scale_name [Symbol, String] The name of the scale to use, one of the
  #   keys of the {.SCALES} hash.
  # @return [Scale]
  # @see Track#scale
  def self.full_scale(tonic, scale_name)
    @full_scale_cache ||= {}

    tonic = MIDINote.new(tonic)
    key = [tonic.pitch_class, scale_name.to_sym]
    scale = @full_scale_cache[key]
    return scale unless scale.nil?

    # Note 0 is c-1, and 127 is g9. So we need to start at octave -2 to ensure
    # we hit all possibilities for the scale, and do 12 total octaves to cover
    # the whole MIDI range.
    low_tonic = tonic.with_octave(-2)
    scale = new(low_tonic, scale_name, num_octaves: 12, clamp_to_midi: true)
    @full_scale_cache[key] = scale
    scale
  end


  # Returns the note on the scale that is the given number of steps away from
  # `relative_tonic`. Raises an ArgumentError if `relative_tonic` is not in the
  # scale or if the scale does not contain a note that is `steps` far away from
  # it.
  # @param relative_tonic [MIDINote, String, Symbol, Integer]
  # @param steps [Integer]
  # @return [MIDINote]
  def note_at_step(relative_tonic, steps)
    tonic_idx = @notes.index(relative_tonic)
    raise ArgumentError, "scale does not contain #{relative_tonic}" if tonic_idx.nil?

    i = tonic_idx + steps
    raise RangeError, "scale does not contain a note #{steps} steps from #{relative_tonic}" if i < 0 || i >= @notes.length
    @notes[i]
  end

  ROMAN_NUMS = {
    "i" => 1,
    "v" => 5,
    "x" => 10,
    "l" => 50,
    "c" => 100,
    "d" => 500,
    "m" => 1000
  }.freeze
  private_constant :ROMAN_NUMS

  private_class_method def self.roman_to_int(s)
    raise ArgumentError, "string must not be empty" if s.empty?

    # This is very lenient, but isn't worth thinking about too much.

    s = s.downcase
    res = 0
    i = 0
    loop do
      break if i >= s.length

      val = ROMAN_NUMS[s[i]]
      raise ArgumentError, "invalid Roman numeral string #{s}" if val.nil?
      if i < s.length - 1
        # Check if we're less than the next number (like "IX") and if so, add
        # the difference and skip past that character.
        next_val = ROMAN_NUMS[s[i + 1]]
        raise ArgumentError, "invalid Roman numeral string #{s}" if next_val.nil?

        if val < next_val
          res += next_val - val
          i += 2
          next
        end
      end

      res += val
      i += 1
    end

    res
  end

  # Parses a degree number, string, or symbol into its integer value and a
  # semitone shift. Returns [number, semitones].
  # @private
  def self.parse_degree(d)
    return [d.to_i, 0] if d.is_a?(Numeric)
    raise TypeError, "degree must be a number, symbol, or string" unless d.is_a?(String) || d.is_a?(Symbol)

    d = d.to_s.downcase
    mod = 0
    if d.start_with?("aa")
      mod = 2
      d = d[2..]
    elsif d.start_with?("dd")
      mod = -2
      d = d[2..]
    elsif d.start_with?("a")
      mod = 1
      d = d[1..]
    elsif d.start_with?("d")
      mod = -1
      d = d[1..]
    elsif d.start_with?("p")
      d = d[1..]
    end

    raise ArgumentError, "no number component to degree" if d.empty?

    begin
      num = Integer(d)
    rescue ArgumentError
      num = roman_to_int(d)
    end

    [num, mod]
  end

  # Returns the note in the scale that is `d` degrees from `relative_tonic`. If
  # `relative_tonic` is nil (the default), the tonic of the scale will be used
  # instead. Raises an ArgumentError if the scale does not contain
  # `relative_tonic`, or if `d` is a degree beyond the bounds of the scale.
  #
  # `d` may be an integer (a number of degrees), or a string or symbol. Those
  # take the form of a number (decimal digits or Roman numeral), optionally
  # prefixed by "a", "d", "aa", "dd", or "p" for augmented, diminished, doubly
  # augmented or diminished, or perfect (unchanged). Symbols and strings are
  # case-insensitive. For example, `:Aiv` is the augmented fourth degree.
  #
  # `d` may be a negative integer, which can be useful if `relative_tonic` is
  # not the tonic of the scale. A degree of -1 is taken to be one note below the
  # tonic on the scale.
  #
  # Note that, unlike Sonic Pi's `degree` function, this will only return notes
  # within the octave range of the scale on which it is called. See the class
  # method {.degree} for a less bounded version.
  #
  # @param d [Integer, Symbol, String]
  # @param relative_tonic [MIDINote, String, Symbol, Integer, nil]
  # @return [MIDINote]
  # @see .degree
  def degree(d, relative_tonic: nil)
    n, mod = Scale.parse_degree(d)

    raise RangeError, "degree 0 is undefined" if n == 0

    steps = n
    steps -= 1 if steps > 0
    note_at_step(relative_tonic || @tonic, steps) + mod
  end

  # Returns a note on a scale that is `d` degrees away from `tonic`. This is
  # equivalent to calling {#degree} on the result of {.full_scale}.
  #
  # This is analogous to Sonic Pi's `degree`, though note that it won't return
  # notes outside of the MIDI scale.
  #
  # @param d [Integer, Symbol, String] The requested degree. See {#degree} for
  #   details.
  # @param tonic [MIDINote, String, Symbol, Integer, nil] The root of the scale.
  #   May be a {MIDINote} or anything understood by {MIDINote.new}.
  # @param scale_name [Symbol, String] The name of the scale to use, one of the
  #   keys of the {.SCALES} hash. This class understands all of the same scale
  #   names as Sonic Pi's `scale` function and more.
  # @return [MIDINote]
  # @see .full_scale
  # @see #degree
  def self.degree(d, tonic, scale_name)
    scale = full_scale(tonic, scale_name)
    scale.degree(d, relative_tonic: tonic)
  end

  # Returns the number of steps on the scale between the given notes. Raises an
  # ArgumentError if either note is not in the scale.
  # @param relative_tonic [MIDINote, String, Symbol, Integer]
  # @param note [MIDINote, String, Symbol, Integer]
  # @return [Integer]
  def steps_between(relative_tonic, note)
    tonic_idx = @notes.index(relative_tonic)
    raise ArgumentError, "scale does not contain #{relative_tonic}" if tonic_idx.nil?

    note_idx = @notes.index(note)
    raise ArgumentError, "scale does not contain #{note}" if note_idx.nil?

    note_idx - tonic_idx
  end

  # Returns the number of degrees between the given note and `relative_tonic`.
  # If `relative_tonic` is nil (the default), the tonic of the scale will be
  # used instead. Raises an ArgumentError if the scale does not contain `note`
  # or `relative_tonic`.
  #
  # Note that the returned value may be negative if `relative_tonic` is not the
  # tonic of the scale, and `note` falls before it. The note one below the tonic
  # has degree -1.
  #
  # @param note [MIDINote, String, Symbol, Integer]
  # @param relative_tonic [MIDINote, String, Symbol, Integer, nil]
  # @return [Integer]
  def degree_of(note, relative_tonic: nil)
    degree = steps_between(relative_tonic || @tonic, note)
    degree += 1 if degree >= 0
    degree
  end


  # Snaps the given note upwards to the nearest note in this scale.
  # @param note [MIDINote, String, Symbol, Integer] The {MIDINote} to snap, or
  #   a value understood by {MIDINote.new}.
  # @return [MIDINote]
  # @see MIDINote#snap
  def snap(note)
    MIDINote.new(note).snap(self)
  end

  # A string representation of this Scale.
  # @return [String]
  def to_s
    clamp_str = @clamp_to_midi ? ", clamped" : ""
    "<Scale #{@tonic} #{@name}, #{@num_octaves} octaves#{clamp_str}>"
  end

  # A string of the Ruby code representation of this scale.
  # @return [String]
  def repr
    return "Scale.full_scale(:#{@tonic.pitch_class}, :#{@name})" if @tonic.octave == -2 && @num_octaves == 12 && @clamp_to_midi

    ctor_args = {}
    ctor_args[:num_octaves] = @num_octaves.to_s unless @num_octaves == 1
    ctor_args[:clamp_to_midi] = @clamp_to_midi.to_s if @clamp_to_midi

    res = "SC(#{@tonic.repr}, :#{@name}"
    unless ctor_args.empty?
      res += ", "
      res += ctor_args.map { |k, v| "#{k}: #{v}" }.join(", ")
    end
    "#{res})"
  end
end


# @!group Class aliases

# An alias for the {Scale} class since Sonic Pi already has a class with that
# name. See also {SC}, an alias for the initializer.
Sc = Scale

# @!endgroup
