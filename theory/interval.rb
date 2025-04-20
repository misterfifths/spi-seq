# frozen_string_literal: true

# TODO: inversion?

# An interval between two notes, represented both by its traditional number and
# quality, and its size (i.e. the number of semitones).
#
# Intervals are instances of Numeric, and their value is the number of semitones
# they represent. That means you can add Intervals directly to MIDINotes to
# obtain the note that is an interval away from another.
#
# Note that performing arithmetic on Intervals results in instances with a
# default quality (major/minor/perfect when possible, but diminished for 6
# semitones). For instance, adding 1 to a major 2nd results in a minor 3rd,
# not an augmented 2nd.
#
# Intervals that span more than one octave (i.e. those with a number > 8, or
# semitones > 12) are called compound. You can decompose such intervals into
# a number of octaves (`octave_span`) and the simple interval they represent on
# top of that number of octaves (`simple_interval`). When possible,
# simple_interval will have the same quality as the compound interval it belongs
# to.
#
# Intervals can be compared to:
# - Other Interval instances
# - Other numbers, which will be treated as a number of semitones.
# - Symbols or strings, which will be treated as abbreviated interval names.
class Interval < Numeric
  attr_accessor :number, :quality, :size, :octave_span, :simple_interval
  alias semitones size

  # semitones -> { quality -> number }
  # Order in the value hashes is significant; when making an Interval via
  # arithmetic or a size but no quality, the first quality is the one that will
  # be chosen for the new instance. E.g. `Interval.new(:P4) + 1` will yield a
  # diminished 5th, not an augmented 4th.
  SIZES_TO_NUMBERS = {
     0 => { perfect: 1, dim: 2 },
     1 => { minor:   2, aug: 1 },
     2 => { major:   2, dim: 3 },
     3 => { minor:   3, aug: 2 },
     4 => { major:   3, dim: 4 },
     5 => { perfect: 4, aug: 3 },
     6 => { dim:     5, aug: 4 },
     7 => { perfect: 5, dim: 6 },
     8 => { minor:   6, aug: 5 },
     9 => { major:   6, dim: 7 },
    10 => { minor:   7, aug: 6 },
    11 => { major:   7, dim: 8 },
    12 => { perfect: 8, aug: 7, dim: 9 }  # d9 is from compound territory
  }.freeze
  SIZES_TO_NUMBERS.each_value { |h| h.freeze }
  private_constant :SIZES_TO_NUMBERS

  # number -> { quality -> semitones }
  # The order of the value hashes is not significant.
  NUMBERS_TO_SIZES = {
    1 => {                     perfect:  0, aug:  1 },
    2 => { dim:  0, minor:  1, major:    2, aug:  3 },
    3 => { dim:  2, minor:  3, major:    4, aug:  5 },
    4 => { dim:  4,            perfect:  5, aug:  6 },
    5 => { dim:  6,            perfect:  7, aug:  8 },
    6 => { dim:  7, minor:  8, major:    9, aug: 10 },
    7 => { dim:  9, minor: 10, major:   11, aug: 12 },
    8 => { dim: 11,            perfect: 12, aug: 13 }  # A8 is compound
  }.freeze
  NUMBERS_TO_SIZES.each_value { |h| h.freeze }
  private_constant :NUMBERS_TO_SIZES

  QUALITY_PREFIXES = {
    major:   "M",
    minor:   "m",
    perfect: "P",
    aug:     "A",
    dim:     "d"
  }.freeze
  private_constant :QUALITY_PREFIXES

  PREFIX_TO_QUALITY = QUALITY_PREFIXES.invert.freeze
  private_constant :PREFIX_TO_QUALITY


  # Re-expresses a possibly complex interval number as a number of octaves and
  # the number of a simple interval on top of those octaves. Returns an array
  # [number of octaves, simple interval number]. For example, interval number 10
  # decomposes into [1, 3] since it is one octave and a third.
  private_class_method def self.decompose_number(num)
    num_octaves = num / 8
    sub_octave_num = num % 8

    # Exact octave multiples should map to an 8th (sub_octave_num = 8).
    # Otherwise, if the interval is more than one octave, we should bump the
    # number up one (because, e.g., a 9th is an 8th + a 2nd, not 8th + 1st).
    if sub_octave_num == 0
      sub_octave_num = 8
      num_octaves -= 1 if num_octaves > 0
    elsif num_octaves > 0
      sub_octave_num += 1
    end

    [num_octaves, sub_octave_num]
  end

  # Creates a new Interval. The arguments must be one of the following:
  # - A symbol or string, which is taken as the abbreviated name of an interval.
  # - The number: keyword argument, optionally with quality:. This returns an
  #   Interval with the given number and quality, or the default quality (major
  #   or perfect) for that interval number if quality is omitted.
  # - The size: keyword argument, optionally with quality:. size is the number
  #   of semitones for the interval, and quality specifies how that size should
  #   be interpreted (thus determining the interval number). If quality is
  #   omitted, a default is chosen (major/minor/perfect when possible, or
  #   diminished for a size of 6).
  #
  # It is an error to provide a keyword argument with a symbol/string, or to
  # provide both the number: and size: keyword arguments simultaneously.
  #
  # Interval abbreviations are a number preceded by d, m, M, P, or A for
  # diminished, minor, major, perfect and augmented, respectively.
  #
  # If given, quality must be one of :major, :minor, :perfect, :aug, or :dim.
  # Note that not every combination number/size and quality is valid - e.g.
  # there is no such thing as a major 5th interval.
  def self.new(*args, number: nil, size: nil, quality: nil)
    @name_cache ||= {}
    @size_cache ||= {}
    @number_cache ||= {}

    if !args.empty?
      raise ArgumentError, "expected at most one positional argument, an interval name" if args.length > 1
      raise ArgumentError, "no keyword arguments may be given with an interval name" if number || size || quality

      name = args[0].to_sym
      instance = @name_cache[name]
      return instance unless instance.nil?

      instance = from_sym(name)
    elsif !number.nil?
      raise ArgumentError, "the number and size arguments are mutually exclusive" unless size.nil?

      number = number.to_i
      raise ArgumentError, "interval number must be > 0" unless number > 0

      # Pick perfect/major if quality was omitted.
      if quality.nil?
        _, sub_octave_num = decompose_number(number)
        quality = case sub_octave_num
        when 1, 4, 5, 8
          :perfect
        else
          :major
        end
      end

      instance = @number_cache[[number, quality]]
      return instance unless instance.nil?

      instance = from_number(number, quality)
    elsif !size.nil?
      size = size.to_i

      instance = @size_cache[[size, quality]]
      return instance unless instance.nil?

      instance = super(size: size, quality: quality)

      # Cache here specifically for the nil quality case.
      @size_cache[[size, quality]] = instance if quality.nil?
    else
      raise ArgumentError, "one of number, size, or a positional argument must be given"
    end

    @name_cache[instance.to_sym] = instance
    @number_cache[[instance.number, instance.quality]] = instance
    @size_cache[[instance.size, instance.quality]] = instance

    instance
  end

  private_class_method def self.from_number(num, quality)
    num_octaves, sub_octave_num = decompose_number(num)

    intra_octave_semitones = NUMBERS_TO_SIZES[sub_octave_num][quality]
    raise ArgumentError, "invalid quality #{quality} for interval number #{num}" if intra_octave_semitones.nil?
    size = intra_octave_semitones + 12 * num_octaves

    new(size: size, quality: quality)
  end

  private_class_method def self.from_sym(sym)
    str = sym.to_s
    prefix = str[0]
    quality = PREFIX_TO_QUALITY[prefix]
    raise ArgumentError, "invalid interval quality #{prefix}" if quality.nil?
    num = str[1..].to_i

    from_number(num, quality)
  end

  def initialize(size:, quality: nil)
    super()

    @size = size.to_i
    raise ArgumentError, "interval size must be > 0" if @size < 0

    num_octaves = @size / 12
    intra_octave_semitones = @size % 12

    # Exact octave multiples should map to an 8th (intra_octave_semitones = 12)
    if @size > 0 && intra_octave_semitones == 0
      intra_octave_semitones = 12
      num_octaves -= 1 if num_octaves > 0
    end

    if quality.nil?
      # Take the quality from the first element in the SIZES_TO_NUMBERS hash.
      @quality, @number = SIZES_TO_NUMBERS[intra_octave_semitones].first
    else
      @quality = quality
      @number = SIZES_TO_NUMBERS[intra_octave_semitones][quality]
      raise ArgumentError, "an interval of #{size} semitones cannot have quality #{quality}" if number.nil?
    end

    @number += 7 * num_octaves
    @sym = :"#{QUALITY_PREFIXES[@quality]}#{number}"

    @octave_span = num_octaves + 1
    if @sym == :d9
      # d9 has an octave_span of 1, but we don't want it to be its own
      # simple_interval since its number is > 8. Generally we'd like
      # simple_interval to have the same quality as self, but we have to special
      # case this one.
      @simple_interval = Interval.new(:P8)
    elsif @octave_span == 1
      @simple_interval = self
    else
      @simple_interval = Interval.new(size: intra_octave_semitones, quality: @quality)
    end
  end

  # Returns a new interval with the same size but some variation (diminished,
  # minor, major/perfect, augmented) on the given number. For example, since
  # a perfect 5th and a diminished 6th are both 5 semitones,
  # Interval.new(:P5).as(6) will return a diminished 6.
  # Returns nil if this conversion is not possible.
  def as(number)
    return self if @number == number

    sizes_for_num = NUMBERS_TO_SIZES[number]

    # TODO: handle compound intervals more sanely
    raise ArgumentError, "expected a simple interval" if sizes_for_num.nil?

    new_qual, = sizes_for_num.find { |_, s| s == @size }
    return nil if new_qual.nil?
    Interval.new(number: number, quality: new_qual)
  end

  # Returns true if this interval can be expressed as some variation
  # (diminished, minor, major/perfect, augmented) on the given number. A
  # shortcut that checks if `as(number)` is not nil.
  def expressible_as(number)
    !as(number).nil?
  end

  # Returns true if this interval is compound, i.e. its number is greater than 8
  # or its size is greater than 12.
  def compound?
    # The two cases are really only necessary because d9 and A8 are weird
    # outliers; otherwise either would do.
    @number > 8 || @size > 12
  end

  def perfect?
    @quality == :perfect
  end

  def major?
    @quality == :major
  end

  def minor?
    @quality == :minor
  end

  def augmented?
    @quality == :aug
  end

  alias aug? augmented?

  def diminished?
    @quality == :dim
  end

  alias dim? diminished?


  ### Ruby magic methods and Numeric implementation

  def to_i
    @size
  end

  def to_f
    @size.to_f
  end

  private def delegate_comp(method, other)
    case other
    when Numeric
      @size.send(method, other.to_f)
    when Symbol, String
      begin
        @size.send(method, Interval.new(other))
      rescue ArgumentError
        false
      end
    else
      raise TypeError, "cannot compare an Interval to #{other.inspect}"
    end
  end

  def <(other)
    delegate_comp(:<, other)
  end

  def <=(other)
    delegate_comp(:<=, other)
  end

  def >(other)
    delegate_comp(:>, other)
  end

  def >=(other)
    delegate_comp(:>=, other)
  end

  def <=>(other)
    delegate_comp(:<=>, other)
  end

  def ==(other)
    delegate_comp(:==, other)
  end

  alias eql? ==

  def hash
    @sym.hash
  end

  def coerce(other)
    [Interval.new(size: other), self]
  end

  def +(other)
    Interval.new(size: @size + other.to_f)
  end

  def -(other)
    Interval.new(size: @size - other.to_f)
  end

  def *(other)
    Interval.new(size: @size * other.to_f)
  end

  def /(other)
    Interval.new(size: @size / other.to_f)
  end

  def to_s
    @sym.to_s
  end

  def inspect
    "<Interval #{@sym}, #{@size} semitones>"
  end

  def to_sym
    @sym
  end
end
