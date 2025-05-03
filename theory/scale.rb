# frozen_string_literal: true

require "forwardable"
require_relative "midinote"
require_relative "interval"


# Creates a new scale with the given name, starting on the given tonic, and
# spanning a certain number of octaves. Shortcut for Scale.new.
def SC(tonic, name, num_octaves: 1)
  Scale.new(tonic, name, num_octaves: num_octaves)
end


# A grouping of notes that represents some number of octaves of a scale,
# starting on a particular root note. Enumerable over its notes.
class Scale
  include Enumerable
  extend Forwardable

  attr_reader :name, :tonic, :num_octaves, :notes, :clamp_to_midi

  # each gets us all of Enumerable. The others are common methods on Array that
  # aren't in Enumerable.
  def_delegators :@notes, :each, :[], :slice, :length, :size, :last, :to_a, :to_ary, :values_at


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
    }.freeze

    scales.each_value { |steps| steps.freeze }

    scales
  end.call


  # Creates a new Scale with the given name, starting on the given tonic. The
  # scale will span `num_octaves` many octaves. If `clamp_to_midi` is true,
  # only notes in the MIDI range of 0 - 127 will be included in the Scale.
  #
  # Known scale names can be found as the keys in the SCALES hash.
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
  def self.full_scale(tonic, scale_name)
    @full_scale_cache ||= {}

    tonic = MIDINote.new(tonic)
    key = [tonic.pitch_class, scale_name.to_sym]
    scale = @full_scale_cache[key]
    return scale unless scale.nil?

    # Note 0 is c-1, and 127 is g9, so if we do 11 octaves from -1, we'll cover
    # the whole MIDI range.
    low_tonic = tonic.with_octave(-1)
    new(low_tonic, scale_name, num_octaves: 11, clamp_to_midi: true)
  end


  # Returns the note on the scale that is the given number of steps away from
  # `relative_tonic`. Raises an ArgumentError if `relative_tonic` is not in the
  # scale or if the scale does not contain a note that is `steps` far away from
  # it.
  def note_at_step(relative_tonic, steps)
    tonic_idx = @notes.index(relative_tonic)
    raise ArgumentError, "scale does not contain #{relative_tonic}" if tonic_idx.nil?

    i = tonic_idx + steps
    raise ArgumentError, "scale does not contain a note #{n} steps from #{relative_tonic}" if i < 0 || i >= @notes.length
    @notes[i]
  end

  # Returns the note in the scale that is `n` degrees from `relative_tonic`. If
  # `relative_tonic` is nil (the default), the tonic of the scale will be used
  # instead. Raises an ArgumentError if the scale does not contain
  # `relative_tonic`, or if `n` is a degree beyond the bounds of the scale.
  #
  # `n` may be negative, which can be useful if `relative_tonic` is not the
  # tonic of the scale. A degree of -1 is taken to be one note below the tonic
  # on the scale.
  def degree(n, relative_tonic: nil)
    raise ArgumentError, "degree 0 is undefined" if n == 0

    steps = n
    steps -= 1 if steps > 0
    note_at_step(relative_tonic || @tonic, steps)
  end

  # Returns the number of steps on the scale between the given notes. Raises an
  # ArgumentError if either note is not in the scale.
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
  def degree_of(note, relative_tonic: nil)
    degree = steps_between(relative_tonic || @tonic, note)
    degree += 1 if degree >= 0
    degree
  end


  # Returns a new note, snapped upward to the nearest note in this scale. `note`
  # must be a note representation of some sort (symbol, string, a MIDI note
  # number, or a MIDINote).
  def snap(note)
    MIDINote.new(note).snap(self)
  end


  def to_s
    clamp_str = @clamp_to_midi ? ", clamped" : ""
    "<Scale #{@tonic} #{@name}, #{@num_octaves} octaves#{clamp_str}>"
  end
end


# SonicPi has a Scale class which takes precedence in the environment.
Sc = Scale
