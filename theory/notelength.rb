# frozen_string_literal: true

class NoteLength
  # Create a new NoteLength representing the given length, which may be:
  # - Another NoteLength object, which is returned as-is.
  # - A symbol for the name of a length, e.g. :whole or :thirty_second.
  # - A number that represents the fraction of a beat for the note length, e.g.
  #   0.5 for eighth notes, or 4 for whole notes.
  def self.new(length, *aliases)
    return length if length.is_a?(NoteLength)

    @cache ||= {}

    instance = @cache[length]
    return instance unless instance.nil?

    instance = case length
    when Symbol
      super(length)
    when Numeric
      from_number(length)
    else
      raise TypeError, "Invalid note length #{f}"
    end

    @cache[length] = instance
    @cache[instance.to_sym] = instance
    @cache[instance.to_f] = instance
    aliases.each { |a| @cache[a] = instance }

    instance
  end

  def self.from_number(f)
    case f
    when 4.0
      Whole
    when 2.0
      Half
    when 1.0
      Quarter
    when 1/2.0
      Eighth
    when 1/4.0
      Sixteenth
    when 1/8.0
      ThirtySecond
    when 1/16.0
      SixtyFourth
    else
      raise RangeError, "Invalid note length #{f}"
    end
  end
  private_class_method :from_number

  def initialize(sym)
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
    when :thirty_second, :thirtysecond
      @sym = :thirty_second
      @float_val = 1/8.0
      @log2 = -3
      @desc = "thirty-second"
      @next_longer = :sixteenth
      @next_shorter = :sixty_fourth
    when :sixty_fourth, :sixtyfourth
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
  # a sixty-fourth note.
  def halve
    raise ArgumentError, "No supported note length shorter than #{self}" if @next_shorter.nil?
    NoteLength.new(@next_shorter)
  end

  # Returns a NoteLength with double the duration of this one. E.g., doubling a
  # quarter note length returns a half. It is an error to attempt to double a
  # whole note.
  def double
    raise ArgumentError, "No supported note length longer than #{self}" if @next_longer.nil?
    NoteLength.new(@next_longer)
  end

  def <(other)
    @float_val < other.to_f
  end

  def <=(other)
    @float_val <= other.to_f
  end

  def >(other)
    @float_val > other.to_f
  end

  def >=(other)
    @float_val >= other.to_f
  end

  def ==(other)
    @sym == other.to_sym
  end

  alias eql? ==

  def hash
    @sym.hash
  end

  # Returns how many "steps" there are between this length and the given one.
  # Each halving or doubling represents one step. So, for instance, there are
  # two steps between a quarter and a sixteenth, since it requires two halvings
  # to get between the two.
  def steps_to(other_note_length)
    (@log2 - other_note_length.log2).abs
  end

  def length
    @float_val
  end

  def to_f
    @float_val
  end

  def to_sym
    @sym
  end

  def to_s
    "#{@desc}/#{@float_val}"
  end

  def inspect
    "<NoteLength #{self}>"
  end

  def repr
    ":#{@sym}"
  end


  Whole = new(:whole)
  Half = new(:half)
  Quarter = new(:quarter)
  Eighth = new(:eighth)
  Sixteenth = new(:sixteenth)
  ThirtySecond = new(:thirty_second, :thirtysecond)
  SixtyFourth = new(:sixty_fourth, :sixtyfourth)


  protected

  attr_reader :log2
end
