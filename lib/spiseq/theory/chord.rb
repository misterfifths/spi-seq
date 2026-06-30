# frozen_string_literal: true

require "forwardable"
require_relative "chord_voicing"
require_relative "interval"
require_relative "../internal/enumerables"

module SpiSeq; module Theory
  # A grouping of Intervals that represents a chord.
  #
  # Sonic Pi already provides a class called `Chord`, so this class is aliased
  # to {Ch}.
  #
  # Enumerable over its {#intervals}, and has most of the read-only methods of
  # Array. The intervals are always sorted ascending and will never contain
  # duplicates, even if a mutation might produce one.
  #
  # This class only represents intervals; it does not track a root note or
  # inversions. Instances can be concretely expressed (i.e., converted to actual
  # {MIDINote}s) on a particular root note with {#voice}, {.voiced} or the {C}
  # helper function. Inversions also happen at voice-time.
  #
  # **Chord objects are immutable.** The various mutation methods it provides
  # (e.g. {#flat}, {#sus4}, {#add}) return new Chord instances with different
  # intervals.
  class Chord
    include Enumerable
    extend Forwardable

    # The {Interval}s this chord represents. These will always be sorted
    # ascending by {Interval#size size} and will contain no duplicates.
    # @return [Array<Interval>]
    attr_reader :intervals

    # each gets us all of Enumerable. The others are common methods on Array
    # that aren't in Enumerable.
    def_delegators :@intervals,
                   :each, :[], :slice, :length, :size, :last, :to_a, :to_ary,
                   :values_at, :empty?, :each_index, :fetch, :index, :rindex,
                   :==, :eql?, :hash


    # Names to symbols for class methods, or 0-argument lambdas.
    ABBREVS = {
      %i[major   maj   M]       => :major_triad,
      %i[major6  maj6  M6 6]    => :major_sixth,
      %i[major7  maj7  M7]      => :major_seventh,
      %i[major9  maj9  M9]      => :major_ninth,
      %i[major11 maj11 M11]     => :major_eleventh,
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

      %i[halfdim halfdim7]      => :halfdim_seventh,
      %i[halfdim9]              => :halfdim_ninth,
      %i[halfdim11]             => :halfdim_eleventh,
      %i[halfdim13]             => :halfdim_thirteenth,

      %i[dom v]                 => :dom_triad,
      %i[dom_parallel dom_par
         dompar]                => :dom_parallel,
      %i[dom7 v7 7]             => :dom_seventh,
      %i[dom9 v9 9]             => :dom_ninth,
      %i[dom11 v11 11]          => :dom_eleventh,
      %i[dom13 v13 13]          => :dom_thirteenth,

      %i[fifth P5 5 power]      => :fifth,
      %i[power2]                => -> { Chord.fifth(2) },


      # Rather inconsistent names from Sonic Pi

      %i[1]                     => -> { Chord.new([:P1]) },

      %i[add2]                  => -> { Chord.major_triad.add(2) },
      %i[add4]                  => -> { Chord.major_triad.add(4) },
      %i[add9]                  => -> { Chord.major_triad.add(9) },
      %i[add11]                 => -> { Chord.major_triad.add(11) },
      %i[add13]                 => -> { Chord.major_triad.add(13) },
      %i[sus2]                  => -> { Chord.major_triad.sus2 },
      %i[sus4]                  => -> { Chord.major_triad.sus4 },
      %i[6*9]                   => -> { Chord.major_sixth.add(9) },

      %i[madd2]                 => -> { Chord.minor_triad.add(2) },
      %i[madd4]                 => -> { Chord.minor_triad.add(4) },
      %i[madd9]                 => -> { Chord.minor_triad.add(9) },
      %i[madd11]                => -> { Chord.minor_triad.add(11) },
      %i[madd13]                => -> { Chord.minor_triad.add(13) },
      %i[m+5]                   => -> { Chord.minor_triad.sharp5 },
      %i[m6*9]                  => -> { Chord.minor_sixth.add(9) },
      %i[m7+5]                  => -> { Chord.minor_seventh.sharp5 },
      %i[m7-5 m7b5]             => -> { Chord.minor_seventh.flat5 },  # AKA halfdim_seventh
      %i[m7+5-9]                => -> { Chord.minor_seventh.sharp5.add(:m9) },
      %i[m7-9]                  => -> { Chord.minor_seventh.add(:m9) },
      %i[m7+9]                  => :minor_ninth,
      %i[9sus4]                 => -> { Chord.minor_ninth.sus4 },
      %i[m11+]                  => -> { Chord.minor_eleventh.sharp(11) },

      %i[7-5]                   => -> { Chord.dom_seventh.flat5 },
      %i[7-9]                   => -> { Chord.dom_seventh.add(:m9) },
      %i[7-10]                  => -> { Chord.dom_seventh.add(:m10) },
      %i[7-11]                  => -> { Chord.dom_seventh.add(:d11) },
      %i[7-13]                  => -> { Chord.dom_seventh.add(:m13) },
      %i[7+5]                   => -> { Chord.dom_seventh.sharp5 },  # AKA aug_seventh
      %i[7+5-9]                 => -> { Chord.dom_seventh.sharp5.add(:m9) },
      %i[7sus2]                 => -> { Chord.dom_seventh.sus2 },
      %i[7sus4]                 => -> { Chord.dom_seventh.sus4 },
      %i[11+]                   => -> { Chord.dom_eleventh.sharp(11) },

      %i[augmented a]           => :aug_triad,

      %i[diminished i]          => :dim_triad,
      %i[diminished7 i7]        => :dim_seventh,

      %i[halfdiminished]        => :halfdim_seventh,

      # I have no idea what these are supposed to be.
      %i[9+5]                   => -> { Chord.new(%i[P1 m7 m9]) },
      %i[m9+5]                  => -> { Chord.new(%i[P1 m7 M9]) }
    }.flat_map do |names, val|
      names.map { |name| [name, val] }
    end.to_h.freeze
    private_constant :ABBREVS

    # All chord names supported by this class. The keys of this hash are valid
    # values to pass to {Chord.new}.
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
    # And some abbreviations from Sonic Pi:
    # `1`, `add2`, `add4`, `add9`, `add11`, `add13`, `sus2`, `sus4`, `6*9`,
    # `madd2`, `madd4`, `madd9`, `madd11`, `madd13`, `m+5`, `m6*9`, `m7+5`,
    # `m7+5-9`, `m7-9`, `9sus4`, `m11`, `7-9`, `7-10`, `7-11`, `7-13`, `7+5-9`,
    # `7sus2`, `7sus4`, `11`, `9+5`, `m9+5`
    #
    # There are aliases for many of the above names; print this array to see all
    # possible names. This class understands all of the same chord names as
    # Sonic Pi's `chord` function and more.
    #
    # @return [Array<Symbol>]
    CHORD_NAMES = ABBREVS.keys.freeze


    # @!group Initialization

    # Creates a new Chord. The argument may be one of two things:
    # 1. An abbreviated name of a chord (Symbol or String) as found in the
    #    {.CHORD_NAMES} array. This class understands all of the same chord
    #    names as Sonic Pi's `chord` function and more.
    # 2. An array of {Interval}s, symbols, strings, or numbers that represent
    #    the intervals that define the chord. Non-Interval values must be things
    #    understood by {Interval.new}; they will be passed to it for conversion.
    #    Such an array must have at least one element.
    #
    # To create and immediately {#voice voice} a chord, you can use {.voiced} or
    # the {C} helper function.
    #
    # You can also create Chords using the class methods named after common
    # chords, such as {.major_triad} or {.dom_ninth}.
    #
    # @param intervals_or_name [Symbol, String, Array<Interval, Symbol, String,
    #   Integer>]
    # @return [Chord]
    def self.new(intervals_or_name)
      if intervals_or_name.is_a?(Symbol) || intervals_or_name.is_a?(String)
        abbrev_val = ABBREVS[intervals_or_name.to_sym]
        raise ArgumentError, "unknown chord name #{intervals_or_name}" if abbrev_val.nil?

        return method(abbrev_val).call if abbrev_val.is_a?(Symbol)
        return abbrev_val.call
      end

      super
    end

    private def initialize(intervals)
      # See the note in Utils::enumerable? about arrayify.
      @intervals = Internal::Enumerables.arrayify(intervals).dup.map! do |i|
        case i
        when Interval
          i
        when Numeric
          Interval.new(number: i)
        else
          Interval.new(i)
        end
      end

      raise ArgumentError, "a Chord must have at least one interval" if @intervals.empty?

      @intervals.sort!
      @intervals.uniq!
      @intervals.freeze
    end


    # @!group Manipulating intervals

    # Returns a new Chord with the given interval(s) added. The argument must
    # be:
    # 1. An {Interval}.
    # 2. Another Chord, whose intervals will all be added.
    # 3. A symbol or string, which is taken as an abbreviated name of an
    #    {Interval}. See {Interval.new} for details on abbreviated interval
    #    names.
    # 4. A number, which is taken as the number of a major or perfect
    #    {Interval}.
    # 5. An enumerable of Intervals, symbols, strings, or numbers, each element
    #    of which will be treated as in cases 2 - 5.
    # @param other
    # @return [Chord]
    def append(other)
      if Internal::Enumerables.enumerable?(other)
        other = Internal::Enumerables.arrayify(other)  # see note in enumerable?
      else
        other = [other]
      end

      Chord.new(@intervals + other)
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
    # Raises an ArgumentError if the chord does not contain the given interval,
    # or if the interval to remove is the only one in the chord.
    #
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

    # Returns a new chord with the (major or minor) third replaced with a
    # perfect fourth. Raises an ArgumentError if the chord has no third, or if
    # it has both a major and a minor third.
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

    # Returns a new chord with the (major or minor) third replaced with a
    # perfect fourth, and an added major ninth. Raises an ArgumentError if the
    # chord has no third, or if it has both a major and a minor third.
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

    # Returns a new Chord with the given interval flattened (i.e., lowered by
    # one semitone). The argument must be one of:
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

    # Returns a new Chord with the perfect fifth flattened to a diminished
    # fifth. Raises an ArgumentError if the chord does not contain a perfect
    # fifth.
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

    # Returns a new Chord with the perfect fifth sharpened to an augmented
    # fifth. Raises an ArgumentError if the chord does not contain a perfect
    # fifth.
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


    # Returns fifth or "power" chord (P1 and P5) spanning the given number of
    # octaves.
    # @param octaves [Integer]
    # @return [Chord]
    def self.fifth(octaves = 1)
      p1 = Interval.new(:P1)
      p5 = Interval.new(:P5)
      intervals = []
      octaves.times do |i|
        intervals << p1 + 12 * i
        intervals << p5 + 12 * i
      end
      new(intervals)
    end

    # @!endgroup


    # Returns a string representation of the chord.
    # @return [String]
    # @private
    def to_s
      int_names = @intervals.join(" ")
      "<Chord #{int_names}>"
    end
    alias to_str to_s
    alias inspect to_s
  end


  # @!group Class aliases

  # An alias for the {Chord} class since Sonic Pi already has a class with that
  # name. See also {C}, a helper that creates and immediately voices a chord.
  Ch = Chord

  # @!endgroup
end; end
