# frozen_string_literal: true

module SpiSeq; module Theory
  # Represents a traditional note length (e.g. quarter, eighth, whole, etc.) and
  # its duration as a fraction of a beat.
  #
  # You will most often use a note length when constructing tracks, as their
  # {Tracks::TrackBase#granularity granularity}. It is unlikely that you will
  # need to interact with this class directly though. When using a track
  # constructor, you can pass any value that {.new} accepts; you don't need to
  # use the constants defined on this class.
  class NoteLength
    include Comparable

    ALIASES = {
      thirtysecond: :thirty_second,
      sixtyfourth: :sixty_fourth
    }.freeze
    private_constant :ALIASES

    # Create a new NoteLength representing the given length. The argument may
    # be:
    # - Another NoteLength object, which is returned as-is.
    # - A symbol for the name of a length, e.g. `:whole`, `:quarter`, or
    #   `:thirty_second`.
    # - A number that represents the fraction of a beat for the note length,
    #   e.g. 0.5 for eighth notes, or 4 for whole notes.
    # @param length [NoteLength, Symbol, Number]
    # @return [NoteLength]
    def self.new(length)
      return length if length.is_a?(NoteLength)

      length = ALIASES.fetch(length, length)

      @cache ||= {}
      instance = @cache[length]
      return instance unless instance.nil?

      # Every possible value other than symbols will be cached (and symbols are
      # only uncached until we make the constants below), so anything else is an
      # error here.

      raise ArgumentError, "Invalid note length #{length}" unless length.is_a?(Symbol)

      instance = super

      @cache[length] = instance
      @cache[instance.to_sym] = instance
      @cache[instance.to_f] = instance
      @cache[instance.to_f.to_i] = instance if instance.to_f == instance.to_f.to_i  # rubocop:disable Lint/FloatComparison

      instance
    end

    private def initialize(sym)
      @sym = sym

      case sym
      when :whole
        @float_val = 4.0
        @log2 = 2
        @desc = "whole"
        @next_longer = nil
        @next_shorter = :half
      when :half
        @float_val = 2.0
        @log2 = 1
        @desc = "half"
        @next_longer = :whole
        @next_shorter = :quarter
      when :quarter
        @float_val = 1.0
        @log2 = 0
        @desc = "quarter"
        @next_longer = :half
        @next_shorter = :eighth
      when :eighth
        @float_val = 1/2.0
        @log2 = -1
        @desc = "eighth"
        @next_longer = :quarter
        @next_shorter = :sixteenth
      when :sixteenth
        @float_val = 1/4.0
        @log2 = -2
        @desc = "sixteenth"
        @next_longer = :eighth
        @next_shorter = :thirty_second
      when :thirty_second
        @sym = :thirty_second
        @float_val = 1/8.0
        @log2 = -3
        @desc = "thirty-second"
        @next_longer = :sixteenth
        @next_shorter = :sixty_fourth
      when :sixty_fourth
        @sym = :sixty_fourth
        @float_val = 1/16.0
        @log2 = -4
        @desc = "sixty-fourth"
        @next_longer = :thirty_second
        @next_shorter = nil
      else
        raise ArgumentError, "Invalid note length symbol #{sym}"
      end
    end

    # Returns a NoteLength with half the duration of this one. E.g., halving a
    # quarter note length returns an eighth. It is an error to attempt to halve
    # a sixty-fourth note length.
    # @return [NoteLength]
    def halve
      raise ArgumentError, "No supported note length shorter than #{self}" if @next_shorter.nil?
      NoteLength.new(@next_shorter)
    end

    # Returns a NoteLength with double the duration of this one. E.g., doubling
    # a quarter note length returns a half. It is an error to attempt to double
    # a whole note length.
    # @return [NoteLength]
    def double
      raise ArgumentError, "No supported note length longer than #{self}" if @next_longer.nil?
      NoteLength.new(@next_longer)
    end

    # @private
    def <=>(other)
      case other
      when NoteLength, Numeric
        @float_val <=> other.to_f
      when Symbol
        # Equality fast path
        return 0 if @sym == other

        begin
          @float_val <=> NoteLength.new(other).to_f
        rescue StandardError
          nil
        end
      end
    end
    alias eql? ==

    # @private
    def hash = @sym.hash

    # Returns how many "steps" there are between this length and the given one.
    # Each halving or doubling represents one step. So, for instance, there are
    # two steps between a quarter and a sixteenth, since it requires two
    # halvings to get between the two.
    # @param other_note_length [NoteLength]
    # @return [Integer]
    def steps_to(other_note_length) = (@log2 - other_note_length.log2).abs

    # The fraction of a beat represented by this length. For instance, returns
    # 0.5 for {.Eighth} and 4 for {.Whole}.
    # @return [Number]
    def to_f = @float_val
    alias length to_f

    # Returns a symbol representing the note length, e.g. `:whole` or
    # `:quarter`.
    # @return [Symbol]
    def to_sym = @sym

    # Returns a human-readable description of the NoteLength.
    # @return [String]
    def to_s = "#{@desc}/#{@float_val}"
    alias to_str to_s

    # (see #to_s)
    def inspect = "<NoteLength #{self}>"

    # Returns a representation of the NoteLength as Ruby code.
    # @return [String]
    def repr = ":#{@sym}"


    # Creating these constants has the side-effect of priming the cache so that
    # the initializer doesn't have to worry about creating instances from
    # anything other than symbols.

    # Whole-note length: 4 beats.
    Whole = new(:whole)
    # Half-note length: 2 beats.
    Half = new(:half)
    # Quarter-note length: 1 beat.
    Quarter = new(:quarter)
    # Eighth-note length: half a beat.
    Eighth = new(:eighth)
    # Sixteenth-note length: a quarter of a beat.
    Sixteenth = new(:sixteenth)
    # Thirty-second-note length: an eighth of a beat.
    ThirtySecond = new(:thirty_second)
    # Sixty-fourth-note length: a sixteenth of a beat.
    SixtyFourth = new(:sixty_fourth)


    protected

    attr_reader :log2
  end
end; end
