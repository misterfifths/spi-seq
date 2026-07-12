# frozen_string_literal: true

require_relative "rest"
require_relative "scale"
require_relative "../internal/comparison_utils"

module SpiSeq; module Theory
  # Represents a note, particularly the sort understood by MIDI devices.
  #
  # You should not need to manually make instances of MIDINote very often.
  # Classes that use them, like {Track} and {Step}, will automatically convert
  # numbers, symbols, or strings to MIDINotes automatically. If you do need to
  # make one though, {.new} is aliased to {N}.
  #
  # **MIDINotes are immutable**. The mutation methods provided here, like
  # {#with_pitch_class}, return new MIDINotes that have all the same attributes
  # as the receiver, with just the described change.
  #
  # Despite the name, this class can represent notes outside the MIDI range (C-1
  # to G9, note numbers 0 - 127). However such notes cannot be played on MIDI
  # devices, so they aren't particularly relevant. That use case should be
  # considered deprecated.
  #
  # For consistency, the string and symbol representation of MIDINote instances
  # (`to_s` and `to_sym`) are normalized to naturals (when possible) or sharps.
  # For example, `N(:bf3).to_sym` is `:as3`. All variations of a note compare
  # equal to one another, however, so `N(:as3) == :bf3` is true.
  #
  # This class derives from Numeric, so you can directly pass instances of it to
  # Sonic Pi methods like `play` and `midi`. You can also perform arithmetic on
  # them, and compare instances directly to numbers, symbols, strings, or other
  # MIDINotes. For example, these statements are all true:
  #   N(61) == 61
  #   N(61) == :cs4
  #   N(:cs4) == "db4"
  #   N(:c5) == 72
  #   N(:c5) - 1 == :b4
  #   N(:c4) + 12 == N(:c5)
  #   N(:c5) > :c4
  #   :bf3 == N(:as3)
  #   N(:Bs3) == :c4
  class MIDINote < Numeric
    NOTE_REGEX = /^(?<pitch_class>[a-g](?:s|b|f|ss|bb|ff)?)(?<octave>-?\d+)?$/i
    private_constant :NOTE_REGEX

    # Order is significant, both in the subarrays and the array as a whole. The
    # pitch classes must be in ascending order starting with C. And within each
    # pitch class array, the first element is the canonical representation of
    # that class (e.g. :db will be normalized to :cs because :cs is the first
    # element of the corresponding array).
    PITCH_CLASSES = [%i[c bs dbb dff],
                     %i[cs db df bss],
                     %i[d css ebb eff],
                     %i[ds eb ef fbb fff],
                     %i[e fb ff dss],
                     %i[f es gbb gff],
                     %i[fs gb gf ess],
                     %i[g fss abb aff],
                     %i[gs ab af],
                     %i[a gss bbb bff],
                     %i[as bb bf cbb cff],
                     %i[b cb cf ass]].freeze
    PITCH_CLASSES.each { |classes| classes.freeze }
    private_constant :PITCH_CLASSES

    # The default octave for note symbols/strings without one.
    DEFAULT_OCTAVE = 4
    private_constant :DEFAULT_OCTAVE

    # The symbol for the pitch class of the note (e.g. `:c` for C notes in any
    # octave). This will always be lower-case, and accidentals are normalized to
    # a natural (when possible) or a sharp.
    # @return [Symbol]
    attr_reader :pitch_class

    # The MIDI number for the note (e.g. C4 is 60). This may not be in the MIDI
    # range of 0 - 127.
    # @return [Integer]
    attr_reader :number
    alias to_i number
    alias to_int number

    # The octave number for the note (e.g. 2 for C2). This may be negative, and
    # may not be in the MIDI range.
    # @return [Integer]
    attr_reader :octave

    # Creates a new MIDINote instance from the given value, which must be either
    # a MIDI note number, a string, a symbol, or a MIDINote instance (in which
    # case the argument is returned as-is). Floating point arguments are
    # truncated.
    #
    # This method is aliased to {N} for convenience.
    #
    # Acceptable strings and symbols are of the form "(pitch class)(octave)".
    # The pitch class is "a" - "g", with an optional suffix of "b" or "f" for
    # flats or "s" for sharps. Double flats and sharps are permitted. The octave
    # is an integer. Case is ignored, but will be standardized to lower for
    # {MIDINote#pitch_class}, {MIDINote#to_s}, and {MIDINote#to_sym}.
    # Accidentals are normalized to a natural (when possible) or a single sharp.
    # For example, `"Cs3"`, `:df4`, `:bss2`, `:g9`, and `"c-1"` are all valid
    # arguments.
    #
    # The octave number may be omitted on strings and symbols; the default is
    # octave 4.
    #
    # @param note [MIDINote, String, Symbol, Integer]
    # @return [MIDINote]
    def self.new(note)
      return note if note.is_a?(MIDINote)
      raise TypeError, "Cannot convert a rest to a MIDINote" if Theory.rest?(note)

      @note_cache ||= {}

      # Attempt a raw cache lookup.
      note = note.to_i if note.is_a?(Numeric)
      instance = @note_cache[note]
      return instance unless instance.nil?

      # No dice; canonicalize the key a bit.
      cache_key = case note
      when String
        note.downcase
      when Symbol
        note.to_s.downcase
      end

      if cache_key != note
        instance = @note_cache[cache_key]
        unless instance.nil?
          # `note` must be a new representation of a value we already know
          # about; we should update the cache.
          @note_cache[note] = instance
          return instance
        end
      end

      # We've got to make a new instance.
      instance = super
      @note_cache[note] = instance
      @note_cache[cache_key] = instance unless cache_key.nil?
      @note_cache[instance.to_i] = instance
      @note_cache[instance.to_s] = instance

      instance.names.each do |name|
        @note_cache[name] = instance
        @note_cache[name.to_s] = instance
      end

      instance
    end

    private def initialize(note)
      super()

      case note
      when Numeric
        @number = note.to_i
        @octave = (@number / 12) - 1
        @pitch_class = PITCH_CLASSES[@number % 12][0]
        @sym = :"#{@pitch_class}#{@octave}"
      when Symbol, String
        match = NOTE_REGEX.match(note.to_s.downcase)
        raise ArgumentError, "Invalid note name #{note}" if match.nil?

        @octave = match[:octave].nil? ? DEFAULT_OCTAVE : match[:octave].to_i
        @pitch_class = match[:pitch_class].to_sym

        # Check for octave boundary crossings: c flats will normalize to a note
        # an octave down (e.g. cb4 -> b3) and b sharps will go up (e.g. bss2 ->
        # cs3).
        @octave -= 1 if %i[cb cf cbb cff].include?(@pitch_class)
        @octave += 1 if %i[bs bss].include?(@pitch_class)

        cls_idx = PITCH_CLASSES.find_index { |classes| classes.include?(@pitch_class) }
        @pitch_class = PITCH_CLASSES[cls_idx][0]  # normalize
        @number = 12 + @octave * 12 + cls_idx  # 12 is c0
        @sym = :"#{@pitch_class}#{@octave}"
      else
        raise TypeError, "Invalid note value #{note}"
      end
    end

    # Returns a new note with the same pitch class but the given octave.
    # @param new_octave [Integer]
    # @return [MIDINote]
    def with_octave(new_octave)
      return self if new_octave == @octave
      MIDINote.new(:"#{@pitch_class}#{new_octave}")
    end

    # Returns a new note with the same pitch class but with its octave shifted
    # up by the given amount.
    # @param shift [Integer]
    # @return [MIDINote]
    def shift_octave(shift)
      return self if shift == 0
      with_octave(@octave + shift)
    end

    # Returns a new note with the same pitch class but with its octave shifted
    # up by the given amount.
    # @param octave_shift [Integer]
    # @return [MIDINote]
    def up(octave_shift = 1) = shift_octave(octave_shift)

    # Returns a new note with the same pitch class but with its octave shifted
    # down by the given amount.
    # @param octave_shift [Integer]
    # @return [MIDINote]
    def down(octave_shift = 1) = shift_octave(-octave_shift)

    # Returns a new note that is `shift` many semitones away.
    # @param shift [Integer]
    # @return [MIDINote]
    def transpose(shift)
      return self if shift == 0
      MIDINote.new(@number + shift)
    end
    alias shift_tone transpose
    alias t transpose

    # Returns a new note in the same octave but with the given pitch class,
    # which should be a string or symbol of the sort accepted by {.new}.
    #
    # After normalization of flats and sharps, this will actually change the
    # reported octave number if you provide a pitch class of `:cb`/`:cf` (one
    # octave down) or `:bs` (one octave up). For example,
    #
    #   N(:c4).with_pitch_class(:cb)  # would give :cb4, but that's normalized to :b3
    #
    # @param cls [Symbol, String]
    # @return [MIDINote]
    def with_pitch_class(cls) = MIDINote.new(:"#{cls}#{@octave}")

    # Returns true if `other` matches this note. That is:
    # - `other` has an explicit octave (or is a MIDI number) and refers to the
    #   same note as this one. E.g. `:cs2` matches `:cs2` and `:db2`. 67 matches
    #   `:g4`.
    # - Or, `other` is missing an octave and has the same pitch class as this
    #   note. E.g. `:c2` and `:c4` both match `:c`. `:cs` matches `:cs3`,
    #   `:db2`, and `:db`.
    # @param other [MIDINote, Symbol, String, Integer]
    # @return [Boolean]
    def match?(other)
      return false if Theory.rest?(other)
      return self == other if MIDINote.has_octave?(other)
      @pitch_class == MIDINote.new(other).pitch_class
    end

    # Returns a new note snapped to the closest value in `notes`. If this note
    # falls evenly between two candidates in `notes`, the higher note is chosen.
    # @param notes [Array<MIDINote, Symbol, String, Integer>] The array of
    #   notes to which this note can snap. Must consist of values understood by
    #   {.new}.
    # @return [MIDINote]
    # @see Scale#snap
    def snap(notes)
      notes = notes.map { |n| MIDINote.new(n) }
      winner = nil
      smallest_diff = 256
      notes.each do |n|
        diff = (n.number - @number).abs
        if winner.nil? || diff < smallest_diff
          smallest_diff = diff
          winner = n
        elsif diff == smallest_diff && n.number > winner.number
          # Prefer the upper note in the case of an equal distance.
          winner = n
        end
      end

      winner
    end

    # Returns a new note, snapped upward to the nearest note in the given scale.
    # @param tonic [Symbol, String] The root note of the scale used for
    #   snapping. Must be a pitch class (e.g. `:c` or `:fs`).
    # @param scale_name [Symbol] The name of the scale used for snapping. Must
    #   be one of the scales known to the {Scale} class.
    # @return [MIDINote]
    def snap_to_scale(tonic, scale_name) = snap(Scale.full_scale(tonic, scale_name))

    # Returns all possible names for an note with this {#number}.
    # @return [Array<Symbol>]
    def names
      return @names unless @names.nil?

      @names = []
      PITCH_CLASSES[@number % 12].each do |cls|
        octave = @octave
        octave += 1 if %i[cb cf cbb cff].include?(cls)
        octave -= 1 if %i[bs bss].include?(cls)
        @names << :"#{cls}#{octave}"
        @names << :"#{cls}" if octave == DEFAULT_OCTAVE
      end
      @names.freeze
      @names
    end


    ### Ruby magic methods and Numeric implementation

    # Returns {#number} as a floating point number.
    # @return [Float]
    def to_f = @number.to_f

    # @private
    def <=>(other)
      case other
      when Numeric
        @number <=> other.to_i
      when Symbol, String
        # Equality fast paths
        return 0 if other.is_a?(Symbol) && @sym == other
        return 0 if other.is_a?(String) && @sym.to_s == other

        begin
          @number <=> MIDINote.new(other).number
        rescue StandardError
          nil
        end
      end
    end
    alias eql? ==

    # @private
    def hash = @sym.hash

    # @private
    def coerce(other) = [MIDINote.new(other), self]

    # Returns a new MIDINote by adding `other` many semitones to this one.
    # @param other [Integer]
    # @return [MIDINote]
    def +(other) = transpose(other.to_i)

    # Returns a new MIDINote by subtracting `other` many semitones from this
    # one.
    # @param other [Integer]
    # @return [MIDINote]
    def -(other) = transpose(-other.to_i)

    # Returns a new MIDINote by multiplying this note's {#number} by `other`.
    # @param other [Integer]
    # @return [MIDINote]
    def *(other) = MIDINote.new(@number * other.to_i)

    # Returns a new MIDINote by dividing this note's {#number} by `other`.
    # @param other [Integer]
    # @return [MIDINote]
    def /(other) = MIDINote.new(@number / other.to_i)

    # Returns the symbol for this note, which consists of its {#pitch_class} and
    # #{octave}. It is always lower case, and accidentals are normalized to
    # a natural (when possible) or a sharp.
    # @return [Symbol]
    def to_sym = @sym

    # The string version of this MIDINote, normalized as per {#to_sym}.
    # @return [String]
    def to_s = @sym.to_s
    alias to_str to_s

    # @private
    def inspect = ":#{@sym}"

    # Returns a Ruby representation of this note.
    # @param short [Boolean] If true, the returned string will just be the
    #   symbol for the note name and will not include a call to {N}. In this
    #   case, the returned string will not evaluate to an instance of MIDINote.
    # @return [String]
    def repr(short: false)
      return ":#{@sym}" if short
      "N(:#{@sym})"
    end


    ### Misc. class methods

    # Returns true if the given value (a MIDINote or something understood by
    # {.new}) has an explicit octave. Always returns true for MIDI note numbers
    # and MIDINote objects. Returns true for note symbols or strings that end in
    # a number, e.g. `:cs4`.
    # @param note [MIDINote, String, Symbol, Integer]
    # @return [Boolean]
    def self.has_octave?(note)
      return true if note.is_a?(Numeric) || note.is_a?(MIDINote)

      match = NOTE_REGEX.match(note.to_s)
      raise ArgumentError, "Invalid note symbol #{note}" if match.nil?
      !match[:octave].nil?
    end
  end

  # @!group Music theory

  # An alias for {MIDINote.new}.
  # @return [MIDINote]
  module_function def N(...) = MIDINote.new(...)

  # @!endgroup
end; end


# Patch comparisons so they work when a string or symbol is on the left.
# We don't need to do anything about Numeric; that already works via coercion.
SpiSeq::Internal::ComparisonUtils.monkey_patch_reverse_comparisons(Symbol, SpiSeq::Theory::MIDINote)
SpiSeq::Internal::ComparisonUtils.monkey_patch_reverse_comparisons(String, SpiSeq::Theory::MIDINote)
