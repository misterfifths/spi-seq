# frozen_string_literal: true

require "forwardable"
require_relative "interval"
require_relative "chordvoicing"

# @!group Music theory

# (see Chord.voiced)
def C(root, name, voicing = :closed, invert: 0)
  Chord.voiced(root, name, voicing, invert: invert)
end

# @!endgroup


# A grouping of Intervals that represents a chord.
#
# Sonic Pi already provides a class called `Chord`, so this class is aliased to
# {Ch}.
#
# Enumerable over its {#intervals}, and has most of the read-only methods of
# Array.
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
  include Enumerable
  extend Forwardable

  # The {Interval}s this chord represents. These will always be sorted ascending
  # by {Interval#size size} and will contain no duplicates.
  # @return [Array<Interval>]
  attr_reader :intervals

  # each gets us all of Enumerable. The others are common methods on Array that
  # aren't in Enumerable.
  def_delegators :@intervals,
                 :each, :[], :slice, :length, :size, :last, :to_a, :to_ary,
                 :values_at, :empty?


  ABBREV_DEFS = {
    %i[major   maj   M]       => :major_triad,
    %i[major6  maj6  M6 6]    => :major_sixth,
    %i[major7  maj7  M7]      => :major_seventh,
    %i[major9  maj9  M9]      => :major_ninth,
    %i[major11 maj11 M11 11]  => :major_eleventh,
    %i[major13 maj13 M13]     => :major_thirteenth,

    %i[minor   min   m]       => :minor_triad,
    %i[minor6  min6  m6]      => :minor_sixth,
    %i[minor7  min7  m7]      => :minor_seventh,
    %i[minor9  min9  m9]      => :minor_ninth,
    %i[minor11 min11 m11]     => :minor_eleventh,
    %i[minor13 min13 m13]     => :minor_thirteenth,

    %i[minor_major7 min_maj7
       mM7 m/M7]              => :minor_major_seventh,
    %i[minor_major9 min_maj9
       mM9 m/M9]              => :minor_major_ninth,
    %i[minor_major11
       min_maj11 mM11 m/M11]  => :minor_major_eleventh,
    %i[minor_major13
       min_maj13 mM13 m/M13]  => :minor_major_thirteenth,

    %i[aug +5 +]              => :aug_triad,
    %i[aug6 +6 ger6 ger+6]    => :aug_sixth,
    %i[fr6 fr+6]              => -> { Chord.aug_sixth(:fr) },
    %i[it6 it+6]              => -> { Chord.aug_sixth(:it) },
    %i[aug7 +7]               => :aug_seventh,
    %i[aug9 +9]               => :aug_ninth,
    %i[aug11 +11]             => :aug_eleventh,
    %i[aug13 +13]             => :aug_thirteenth,

    %i[aug_major7 aug_maj7
       augM7 +M7]             => :aug_major_seventh,
    %i[aug_major9 aug_maj9
       augM9 +M9]             => :aug_major_ninth,
    %i[aug_major11 aug_maj11
       augM11 +M11]           => :aug_major_eleventh,
    %i[aug_major13 aug_maj13
       augM13 +M13]           => :aug_major_thirteenth,

    %i[dim -5]                => :dim_triad,
    %i[dim7 -7]               => :dim_seventh,
    %i[dim9 -9]               => :dim_ninth,
    %i[dim11 -11]             => :dim_eleventh,
    %i[dim13 -13]             => :dim_thirteenth,

    %i[halfdim halfdim7
       m7b5 m7-5]             => :halfdim_seventh,
    %i[halfdim9]              => :halfdim_ninth,
    %i[halfdim11]             => :halfdim_eleventh,
    %i[halfdim13]             => :halfdim_thirteenth,

    %i[dom v]                 => :dom_triad,
    %i[dom_parallel dom_par
       dompar]                => :dom_parallel,
    %i[dom7 v7 7]             => :dom_seventh,
    %i[dom9 v9 9]             => :dom_ninth,
    %i[dom11 v11]             => :dom_eleventh,
    %i[dom13 v13 13]          => :dom_thirteenth,

    %i[fifth P5 5 power]      => :fifth,
    %i[power2]                => -> { Chord.fifth(2) }
  }.freeze
  ABBREV_DEFS.each_key { |names| names.freeze }
  private_constant :ABBREV_DEFS

  # Blow ABBREV_DEFS up into a 1-d map from names.

  # A hash of the chord names supported by this class. The keys of this hash
  # are valid values to pass to {#initialize}.
  #
  # Valid chord names:
  # - `maj`: Major triad
  # - `maj6`: Major 6th
  # - `maj7`: Major 7th
  # - `maj9`: Major 9th
  # - `maj11`: Major 11th
  # - `maj13`: Major 13th
  # - `min`: Minor triad
  # - `min6`: Minor 6th
  # - `min7`: Minor 7th
  # - `min9`: Minor 9th
  # - `min11`: Minor 11th
  # - `min13`: Minor 13th
  # - `mM7`: Minor/major 7th
  # - `mM9`: Minor/major 9th
  # - `mM11`: Minor/major 11th
  # - `mM13`: Minor/major 13th
  # - `aug`: Augmented triad
  # - `aug6`: Augmented 6th (German)
  # - `fr6`: Augmented 6th (French)
  # - `it6`: Augmented 6th (Italian)
  # - `aug7`: Augmented 7th
  # - `aug9`: Augmented 9th
  # - `aug11`: Augmented 11th
  # - `aug13`: Augmented 13th
  # - `augM7`: Augmented major 7th
  # - `augM9`: Augmented major 9th
  # - `augM11`: Augmented major 11th
  # - `augM13`: Augmented major 13th
  # - `dim`: Diminished triad
  # - `dim7`: Diminished 7th
  # - `dim9`: Diminished 9th
  # - `dim11`: Diminished 11th
  # - `dim13`: Diminished 13th
  # - `halfdim7`: Half-diminished 7th
  # - `halfdim9`: Half-diminished 9th
  # - `halfdim11`: Half-diminished 11th
  # - `halfdim13`: Half-diminished 13th
  # - `dom`: Dominant triad
  # - `dompar`: Dominant parallel triad
  # - `dom7`: Dominant 7th
  # - `dom9`: Dominant 9th
  # - `dom11`: Dominant 11th
  # - `dom13`: Dominant 13th
  # - `power`: Power chord (root + fifth)
  # - `power2`: Power chord spanning two octaves
  #
  # Note that there are aliases for many of the above names; print the result
  # of `Chord::ABBREVS.keys` to see all possible names. This class understands
  # all of the same chord names as Sonic Pi's `chord` function and more.
  ABBREVS = {}  # rubocop:disable Style/MutableConstant
  ABBREV_DEFS.each do |names, val|
    names.each { |name| ABBREVS[name] = val }
  end
  ABBREVS.freeze


  # @!group Initialization

  # Creates a new Chord. The argument may be one of two things:
  # 1. An abbreviated name of a chord (Symbol or String) as found in the keys of
  #    the {.ABBREVS} hash. This class understands all of the same chord names
  #    as Sonic Pi's `chord` function and more.
  # 2. An array of {Interval}s, symbols, strings, or numbers that represent the
  #    intervals that define the chord. Non-Interval values must be things
  #    understood by {Interval.new}; they will be passed to it for conversion.
  #
  # To create and immediately {#voice voice} a chord, you can use {.voiced} or
  # the {C} helper function.
  #
  # Note that you can also create Chords using the class methods named after
  # common chords, such as {.major_triad} or {.dom_ninth}.
  # @param intervals_or_name [Symbol, String, Array<Interval, Symbol, String,
  #   Integer>]
  # @return [Chord]
  def self.new(intervals_or_name)
    if intervals_or_name.is_a?(Symbol) || intervals_or_name.is_a?(String)
      abbrev_val = ABBREVS[intervals_or_name.to_sym]
      raise ArgumentError, "unknown chord name #{intervals_or_name}" if abbrev_val.nil?

      return method(abbrev_val).call if abbrev_val.is_a?(Symbol)
      abbrev_val.call
    end

    super
  end

  private def initialize(intervals)
    @intervals = intervals.to_a.dup.map! do |i|
      case i
      when Interval
        i
      when Numeric
        Interval.new(number: i)
      else
        Interval.new(i)
      end
    end
    @intervals.sort!
    @intervals.uniq!
    @intervals.freeze
  end


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
  # @param invert [Integer] The number of inversions to apply to the chord
  #   before voicing it.
  # @return [Array<MIDINote>]
  # @see Chord.new
  # @see Chord#voice
  def self.voiced(root, name, voicing = :closed, invert: 0)
    new(name).voice(root, voicing, invert: invert)
  end


  # @!group Manipulating intervals

  # Returns a new Chord with the given interval(s) added. The argument must be:
  # 1. An {Interval}.
  # 2. Another Chord, whose intervals will all be added.
  # 3. A symbol or string, which is taken as an abbreviated name of an
  #    {Interval}. See {Interval.new} for details on abbreviated interval names.
  # 4. A number, which is taken as the number of a major or perfect {Interval}.
  # 5. An enumerable of Intervals, symbols, strings, or numbers, each element of
  #    which will be treated as in cases 2 - 5.
  # @param other
  # @return [Chord]
  def append(other)
    if other.is_a?(Chord)
      other = other.intervals
    elsif !other.is_a?(Enumerable)
      other = [other]
    end

    new_intervals = other.map do |i|
      case i
      when Interval
        i
      when Numeric
        Interval.new(number: i)
      else
        Interval.new(i)
      end
    end

    Chord.new(@intervals + new_intervals)
  end

  alias add append
  alias add_intervals append
  alias concat append
  alias + append


  # Returns a new Chord with the given interval removed. The argument must be
  # one of:
  # 1. An {Interval} instance.
  # 2. A String or Symbol, which must be the abbreviated name of an Interval.
  # 3. A number, which is taken as the number of a major or perfect Interval.
  #
  # Raises an ArgumentError if the chord does not contain the given interval.
  # @param interval [Interval, String, Symbol, Integer]
  # @return [Chord]
  def remove(interval)
    interval = Interval.new(number: interval) if interval.is_a?(Numeric) && !interval.is_a?(Interval)
    i = @intervals.find_index(interval)
    raise ArgumentError, "chord does not have a #{interval} interval" if i.nil?
    new_intervals = @intervals.dup
    new_intervals.delete_at(i)
    Chord.new(new_intervals)
  end

  alias without remove


  # Returns a new chord with the (major or minor) third replaced by the given
  # interval. Raises an ArgumentError if the chord has no third, or if it has
  # both a major and a minor third.
  # @param replacement [Interval, String, Symbol, Integer] The replacement
  #   {Interval}, or a value understood by {Interval.new}.
  # @return [Chord]
  private def suspend(replacement)
    maj3_idx = @intervals.find_index(:M3)
    min3_idx = @intervals.find_index(:m3)

    raise ArgumentError, "suspension is ill-defined with both a major and minor third" if maj3_idx && min3_idx
    raise ArgumentError, "chord has no major or minor third" if maj3_idx.nil? && min3_idx.nil?

    i = maj3_idx || min3_idx
    new_intervals = @intervals.dup
    new_intervals[i] = replacement
    Chord.new(new_intervals)
  end

  # Returns a new chord with the (major or minor) third replaced with a perfect
  # fourth. Raises an ArgumentError if the chord has no third, or if it has
  # both a major and a minor third.
  # @return [Chord]
  def sus4
    suspend(:P4)
  end

  alias sus sus4

  # Returns a new chord with the (major or minor) third replaced with a major
  # second. Raises an ArgumentError if the chord has no third, or if it has
  # both a major and a minor third.
  # @return [Chord]
  def sus2
    suspend(:M2)
  end

  # Returns a new chord with the (major or minor) third replaced with a major
  # fourth, and an added major ninth. Raises an ArgumentError if the chord has
  # no third, or if it has both a major and a minor third.
  # @return [Chord]
  def sus9
    sus4 + :M9
  end


  # Returns a new chord with the given interval adjusted by delta many
  # semitones. The interval may be an Interval, symbol, string, or number with
  # the usual rules. Raises an ArgumentError if the chord does not contain a
  # matching interval.
  private def with_altered_interval(interval, delta)
    interval = Interval.new(number: interval) if interval.is_a?(Numeric) && !interval.is_a?(Interval)
    i = @intervals.find_index(interval)
    raise ArgumentError, "chord does not have a #{interval} interval" if i.nil?
    new_intervals = @intervals.dup
    new_intervals[i] += delta
    Chord.new(new_intervals)
  end

  # Returns a new Chord with the given interval flattened (i.e., lowered by one
  # semitone). The argument must be one of:
  # 1. An Interval instance.
  # 2. A String or Symbol, which must be the abbreviated name of an Interval.
  # 3. A number, which is taken as the number of a major or perfect Interval.
  #
  # Raises an ArgumentError if the chord does not contain the given interval.
  #
  # @param interval [Interval, String, Symbol, Integer]
  # @return [Chord]
  def flat(interval)
    with_altered_interval(interval, -1)
  end

  # Returns a new Chord with the given interval sharpened (i.e., raised by one
  # semitone). The argument must be one of:
  # 1. An Interval instance.
  # 2. A String or Symbol, which must be the abbreviated name of an Interval.
  # 3. A number, which is taken as the number of a major or perfect Interval.
  #
  # Raises an ArgumentError if the chord does not contain the given interval.
  #
  # @param interval [Interval, String, Symbol, Integer]
  # @return [Chord]
  def sharp(interval)
    with_altered_interval(interval, 1)
  end

  # Returns a new Chord with the major third flattened to a minor. Raises an
  # ArgumentError if the chord does not contain a major third.
  # @return [Chord]
  def flat_three
    flat(3)
  end

  alias flat3 flat_three

  # Returns a new Chord with the perfect fifth flattened to a diminished fifth.
  # Raises an ArgumentError if the chord does not contain a perfect fifth.
  # @return [Chord]
  def flat_five
    flat(5)
  end

  alias flat5 flat_five

  # Returns a new Chord with the major ninth flattened to a minor. Raises an
  # ArgumentError if the chord does not contain a major ninth.
  # @return [Chord]
  def flat_nine
    flat(9)
  end

  alias flat9 flat_nine

  # Returns a new Chord with the major third sharpened to an augmented third.
  # Raises an ArgumentError if the chord does not contain a major third.
  # @return [Chord]
  def sharp_three
    sharp(3)
  end

  alias sharp3 sharp_three

  # Returns a new Chord with the perfect fifth sharpened to an augmented fifth.
  # Raises an ArgumentError if the chord does not contain a perfect fifth.
  # @return [Chord]
  def sharp_five
    sharp(5)
  end

  alias sharp5 sharp_five

  # Returns a new Chord with the major ninth sharpened to an augmented ninth.
  # Raises an ArgumentError if the chord does not contain a major ninth.
  # @return [Chord]
  def sharp_nine
    sharp(9)
  end

  alias sharp9 sharp_nine


  # @!group Common chords

  # Returns a major triad chord.
  # @return [Chord]
  def self.major_triad
    new(%i[P1 M3 P5])
  end

  # Returns a major 6th chord.
  # @return [Chord]
  def self.major_sixth
    major_triad + :M6
  end

  # Returns a major 7th chord.
  # @return [Chord]
  def self.major_seventh
    major_triad + :M7
  end

  # Returns a major 9th chord.
  # @return [Chord]
  def self.major_ninth
    major_seventh + :M9
  end

  # Returns a major 11th chord.
  # @return [Chord]
  def self.major_eleventh
    major_ninth + :P11
  end

  # Returns a major 13th chord.
  # @return [Chord]
  def self.major_thirteenth
    major_eleventh + :M13
  end


  # Returns a minor triad chord.
  # @return [Chord]
  def self.minor_triad
    new(%i[P1 m3 P5])
  end

  # Returns a minor 6th chord.
  # @return [Chord]
  def self.minor_sixth
    minor_triad + :M6
  end

  # Returns a minor 7th chord.
  # @return [Chord]
  def self.minor_seventh
    minor_triad + :m7
  end

  # Returns a minor 9th chord.
  # @return [Chord]
  def self.minor_ninth
    minor_seventh + :M9
  end

  # Returns a minor 11th chord.
  # @return [Chord]
  def self.minor_eleventh
    minor_ninth + :P11
  end

  # Returns a minor 13th chord.
  # @return [Chord]
  def self.minor_thirteenth
    minor_eleventh + :M13
  end


  # Returns a minor/major 7th chord.
  # @return [Chord]
  def self.minor_major_seventh
    major_seventh.flat_three
  end

  # Returns a minor/major 9th chord.
  # @return [Chord]
  def self.minor_major_ninth
    major_ninth.flat_three
  end

  # Returns a minor/major 11th chord.
  # @return [Chord]
  def self.minor_major_eleventh
    major_eleventh.flat_three
  end

  # Returns a minor/major 13th chord.
  # @return [Chord]
  def self.minor_major_thirteenth
    major_thirteenth.flat_three
  end


  # Returns an augmented triad chord.
  # @return [Chord]
  def self.aug_triad
    new(%i[P1 M3 A5])
  end

  # Returns an augmented sixth chord.
  # @param variation [:ger, :fr, :it] The desired variation of the 6th, either
  #   German, French, or Italian.
  # @return [Chord]
  def self.aug_sixth(variation = :ger)
    case variation
    when :ger
      new(%i[P1 M3 P5 A6])
    when :fr
      new(%i[P1 M3 d5 A6])
    when :it
      new(%i[P1 M3 A6])
    else
      raise ArgumentError, "unknown augmented 6th variation"
    end
  end

  # Returns an augmented 7th chord.
  # @return [Chord]
  def self.aug_seventh
    aug_triad + :m7
  end

  # Returns an augmented 9th chord.
  # @return [Chord]
  def self.aug_ninth
    aug_seventh + :M9
  end

  # Returns an augmented 11th chord.
  # @return [Chord]
  def self.aug_eleventh
    aug_ninth + :P11
  end

  # Returns an augmented 13th chord.
  # @return [Chord]
  def self.aug_thirteenth
    aug_eleventh + :M13
  end


  # Returns an augmented major 7th chord.
  # @return [Chord]
  def self.aug_major_seventh
    major_seventh.sharp_five
  end

  # Returns an augmented major 9th chord.
  # @return [Chord]
  def self.aug_major_ninth
    major_ninth.sharp_five
  end

  # Returns an augmented major 11th chord.
  # @return [Chord]
  def self.aug_major_eleventh
    major_eleventh.sharp_five
  end

  # Returns an augmented major 13th chord.
  # @return [Chord]
  def self.aug_major_thirteenth
    major_thirteenth.sharp_five
  end


  # Returns a diminished triad chord.
  # @return [Chord]
  def self.dim_triad
    new(%i[P1 m3 d5])
  end

  # Returns a diminished 6th chord.
  # @return [Chord]
  def self.dim_sixth
    dim_triad + :m6
  end

  # Returns a diminished 7th chord.
  # @return [Chord]
  def self.dim_seventh
    dim_triad + :d7
  end

  # Returns a diminished 9th chord.
  # @return [Chord]
  def self.dim_ninth
    dim_seventh + :M9
  end

  # Returns a diminished 11th chord.
  # @return [Chord]
  def self.dim_eleventh
    dim_ninth + :P11
  end

  # Returns a diminished 13th chord.
  # @return [Chord]
  def self.dim_thirteenth
    dim_eleventh + :M13
  end


  # Returns a half-diminished seventh chord.
  # @return [Chord]
  def self.halfdim_seventh
    minor_seventh.flat_five
  end

  # Returns a half-diminished 9th chord.
  # @return [Chord]
  def self.halfdim_ninth
    minor_ninth.flat_five
  end

  # Returns a half-diminished 11th chord.
  # @return [Chord]
  def self.halfdim_eleventh
    minor_eleventh.flat_five
  end

  # Returns a half-diminished 13th chord.
  # @return [Chord]
  def self.halfdim_thirteenth
    minor_thirteenth.flat_five
  end


  # Returns a dominant triad chord.
  # @return [Chord]
  def self.dom_triad
    major_triad
  end

  # Returns a dominant parallel triad chord.
  # @return [Chord]
  def self.dom_parallel
    dom_triad.flat_three
  end

  # Returns a dominant 7th chord.
  # @return [Chord]
  def self.dom_seventh
    dom_triad + :m7
  end

  # Returns a dominant 9th chord.
  # @return [Chord]
  def self.dom_ninth
    dom_seventh + :M9
  end

  # Returns a dominant 11th chord.
  # @return [Chord]
  def self.dom_eleventh
    dom_ninth + :P11
  end

  # Returns a dominant 13th chord.
  # @return [Chord]
  def self.dom_thirteenth
    dom_eleventh + :M13
  end


  # Returns fifth or "power" chord spanning the given number of octaves.
  # @param count [Integer]
  # @return [Chord]
  def self.fifth(count = 1)
    intervals = [:P1]
    count.times { |i| intervals.append(Interval.new(size: 7 * (i + 1))) }
    new(intervals)
  end


  # Returns a string representation of the chord.
  # @return [String]
  # @private
  def to_s
    "<Chord #{@intervals}>"
  end
end


# An alias for the {Chord} class since Sonic Pi already has a class with that
# name.
Ch = Chord
