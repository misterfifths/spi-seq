# frozen_string_literal: true

require_relative "internal_utils"

# @!group Music theory
# An alias for {Interval.new}.
# @param (see Interval.new)
# @return [Interval]
def I(name = nil, number: nil, size: nil, quality: nil)
  Interval.new(name, number: number, size: size, quality: quality)
end
# @!endgroup


# An interval between two notes, represented both by its traditional {#number}
# and {#quality}, and its {#size} (i.e. the number of semitones).
#
# Intervals are instances of Numeric, and their value is the number of semitones
# they represent. That means you can add Intervals directly to {MIDINote}s to
# obtain the note that is an interval away from another.
#
# Performing arithmetic on Intervals results in instances with a default quality
# (major/minor/perfect when possible, but diminished for 6 semitones). For
# instance, adding 1 to a major 2nd results in a minor 3rd, not an augmented
# 2nd.
#
# Intervals that span more than one octave (i.e. those with a number > 8, or
# semitones > 12) are called compound. You can decompose such intervals into
# a number of octaves ({#octave_span}) and the simple interval they represent on
# top of that number of octaves ({#simple_interval}). When possible,
# `simple_interval` will have the same quality as the compound interval it
# belongs to. As a special case, intervals that are a multiple of an octave
# (e.g. P8 or A7) will have a `simple_interval` of P1, even if they are not
# technically compound.
#
# Intervals can be compared to:
# - Other Interval instances
# - Other numbers, which will be treated as a number of semitones.
# - Symbols or strings, which will be treated as abbreviated interval names.
class Interval < Numeric
  # The traditional number for this interval.
  # @return [Integer]
  attr_reader :number

  # The quality of this interval.
  # @return [:perfect, :major, :minor, :aug, :dim]
  attr_reader :quality

  # The number of semitones represented by this interval.
  # @return [Integer]
  attr_reader :size
  alias semitones size

  # The number of octaves this interval spans. Intervals that span more than one
  # octave are compound.
  # @return [Integer]
  attr_reader :octave_span

  # If this interval spans more than one octave, this is the interval that
  # remains after those octaves. E.g. for a M10 interval, which is 16 semitones,
  # this value is a M3, accounting for the 4 additional semitones after the
  # octave. If this interval is not compound this is just `self`, except for
  # P8 and A7 for which this is P1.
  # @return [Interval]
  attr_reader :simple_interval

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
    num_octaves = (num - 1) / 7
    simple_num = 1 + (num - 1) % 7

    # Take octave+P1 to (octave-1)+P8 (unless it's actually just a P1).
    if simple_num == 1 && num > 1
      simple_num = 8
      num_octaves -= 1
    end

    [num_octaves, simple_num]
  end

  # Creates a new Interval. The arguments must be one of the following:
  # - A symbol or string, which is taken as the abbreviated name of an interval.
  # - The `number` keyword argument, optionally with `quality`. This returns
  #   an Interval with the given number and quality, or the default quality
  #   (major or perfect) for that interval number if quality is omitted.
  # - The `size` keyword argument, optionally with `quality`. `size` is the
  #   number of semitones for the interval, and `quality` specifies how that
  #   size should be interpreted (thus determining the interval number). If
  #   `quality` is omitted, a default is chosen (major/minor/perfect when
  #   possible, or diminished for a size of 6).
  #
  # It is an error to provide a keyword argument with a symbol/string, or to
  # provide both the `number` and `size` keyword arguments simultaneously.
  #
  # Interval abbreviations are a number preceded by d, m, M, P, or A for
  # diminished, minor, major, perfect and augmented, respectively.
  #
  # If given, quality must be one of `:major`, `:minor`, `:perfect`, `:aug`, or
  # `:dim`. Of course, not every combination number/size and quality is valid -
  # e.g. there is no such thing as a major 5th interval. This method will raise
  # if given an invalid quality.
  #
  # This method is aliased to {I} for convenience.
  #
  # @param name [Symbol, String, nil] The abbreviated name of an interval.
  #   Optional; you may use some combination of keyword arguments instead.
  # @param number [Integer, nil]
  # @param size [Integer, nil]
  # @param quality [:perfect, :major, :minor, :aug, :dim, nil]
  # @return [Interval]
  def self.new(name = nil, number: nil, size: nil, quality: nil)
    @name_cache ||= {}
    @size_cache ||= {}
    @number_cache ||= {}

    if !name.nil?
      raise ArgumentError, "no keyword arguments may be given with an interval name" if number || size || quality
      raise TypeError, "the interval name must be a symbol or string" unless name.is_a?(Symbol) || name.is_a?(String)

      name = name.to_sym
      instance = @name_cache[name]
      return instance unless instance.nil?

      instance = from_sym(name)
    elsif !number.nil?
      raise ArgumentError, "the number and size arguments are mutually exclusive" unless size.nil?

      number = number.to_i
      raise RangeError, "interval number must be > 0" unless number > 0

      instance = @number_cache[[number, quality]]
      return instance unless instance.nil?

      # If the given quality is what we would pick for this number given a nil
      # quality, cache against nil too.
      _, simple_num = decompose_number(number)
      quality_if_nil = case simple_num
      when 1, 4, 5, 8
        :perfect
      else
        :major
      end
      cache_against_nil_quality = quality.nil? || quality == quality_if_nil

      instance = from_number(number, quality || quality_if_nil)

      @number_cache[[number, nil]] = instance if cache_against_nil_quality
    elsif !size.nil?
      size = size.to_i

      instance = @size_cache[[size, quality]]
      return instance unless instance.nil?

      # If the given quality is what we would pick for this size given a nil
      # quality, cache against nil too.
      intra_octave_semitones = size % 12
      quality_if_nil, = SIZES_TO_NUMBERS[intra_octave_semitones].first
      cache_against_nil_quality = quality.nil? || quality == quality_if_nil

      instance = super(size: size, quality: quality || quality_if_nil)

      @size_cache[[size, nil]] = instance if cache_against_nil_quality
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

    quals_to_sizes = NUMBERS_TO_SIZES[sub_octave_num]
    intra_octave_semitones = quals_to_sizes[quality]
    raise ArgumentError, "invalid quality #{quality} for interval number #{num} - must be one of #{quals_to_sizes.keys.inspect}" if intra_octave_semitones.nil?
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

  private def initialize(size:, quality:)
    super()

    @size = size.to_i
    raise RangeError, "interval size must be >= 0" if @size < 0

    num_octaves = @size / 12
    intra_octave_semitones = @size % 12

    # Exact octave multiples should map to an 8th (intra_octave_semitones = 12)
    if @size > 0 && intra_octave_semitones == 0
      intra_octave_semitones = 12
      num_octaves -= 1 if num_octaves > 0
    end

    @quality = quality
    quals_to_numbers = SIZES_TO_NUMBERS[intra_octave_semitones]
    @number = quals_to_numbers[quality]
    raise ArgumentError, "an interval of #{size} semitones cannot have quality #{quality} - must be one of #{quals_to_numbers.keys.inspect}" if number.nil?

    @number += 7 * num_octaves
    @sym = :"#{QUALITY_PREFIXES[@quality]}#{number}"

    # Not adjusted for P8 like num_octaves above
    @octave_span = 1 + @size / 12
    @simple_interval = if size > 0 && (size % 12) == 0
      # Exact multiples of an octave are funny. P8 & A7 are simple (number < 8);
      # d9 is technically compound though it's the same size. We want all of
      # them to have a simple_interval of a first so that they'll be considered
      # with things like shell chord voicing. So this is an unfortunate special
      # case where intervals with `simple?` true are not their own
      # simple_interval, and the qualities might not match.
      Interval.new(:P1)
    elsif num_octaves == 0
      self
    else
      Interval.new(size: intra_octave_semitones, quality: @quality)
    end
  end

  # Returns all possible names for an interval of this {#size}.
  # @return [Array<Symbol>]
  def names
    return @names unless @names.nil?

    # We give P8 & multiples a simple interval of P1 and one more octave span,
    # so undo that. We want the number of 7ths we need to add, and an index into
    # SIZES_TO_NUMBERS.
    if simple_interval.to_sym == :P1 && size > 0
      simple_interval_size = 12
      octaves = octave_span - 2
    else
      simple_interval_size = simple_interval.size
      octaves = octave_span - 1
    end

    @names = SIZES_TO_NUMBERS[simple_interval_size].map do |other_quality, other_number|
      new_num = octaves * 7 + other_number
      qual_prefix = QUALITY_PREFIXES[other_quality]
      :"#{qual_prefix}#{new_num}"
    end
    @names.freeze
    @names
  end

  # Returns a new interval with the same {#size} but as some quality of the
  # given `number`. For example, since a perfect 5th and a diminished 6th are
  # both 5 semitones, `Interval.new(:P5).as(6)` will return a diminished 6.
  # Returns nil if this conversion is not possible.
  # @param number [Integer]
  # @return [Interval, nil]
  def as(number)
    return self if @number == number

    names.each do |name|
      next if name == @sym
      other_num = name.to_s[1..].to_i
      return Interval.new(name) if number == other_num
    end

    nil
  end

  # Returns true if this interval can be expressed as some quality of `number`.
  # A shortcut that checks if `as(number)` is not nil.
  # @param number [Integer]
  # @return [Boolean]
  # @see #as
  def expressible_as(number)
    !as(number).nil?
  end

  # Returns true if this interval is compound, i.e. its {#number} is greater
  # than 8 or its {#size} is greater than 12.
  # @return [Boolean]
  def compound?
    # The two cases are really only necessary because d9 and A8 are weird
    # outliers; otherwise either would do.
    @number > 8 || @size > 12
  end

  # Returns true if this interval has perfect {#quality}.
  # @return [Boolean]
  def perfect?
    @quality == :perfect
  end

  # Returns true if this interval has major {#quality}.
  # @return [Boolean]
  def major?
    @quality == :major
  end

  # Returns true if this interval has minor {#quality}.
  # @return [Boolean]
  def minor?
    @quality == :minor
  end

  # Returns true if this interval has augmented {#quality}.
  # @return [Boolean]
  def augmented?
    @quality == :aug
  end

  alias aug? augmented?

  # Returns true if this interval has diminished {#quality}.
  # @return [Boolean]
  def diminished?
    @quality == :dim
  end

  alias dim? diminished?


  ### Ruby magic methods and Numeric implementation

  # Returns the interval's {#size}.
  # @return [Integer]
  def to_i
    @size
  end

  # Returns the interval's {#size} as a floating point number.
  # @return [Float]
  def to_f
    @size.to_f
  end

  # @private
  def <=>(other)
    case other
    when Numeric
      @size <=> other.to_i
    when Symbol, String
      # Equality fast paths
      return 0 if other.is_a?(Symbol) && @sym == other
      return 0 if other.is_a?(String) && @sym.to_s == other

      begin
        @size <=> Interval.new(other).size
      rescue StandardError
        nil
      end
    end
  end

  alias eql? ==

  # @private
  def hash
    @size.hash
  end

  # @private
  def coerce(other)
    [Interval.new(size: other), self]
  end

  # Returns a new Interval by adding `other` many semitones to this one's
  # {#size}.
  # @param other [Integer]
  # @return [Interval]
  def +(other)
    Interval.new(size: @size + other.to_f)
  end

  # Returns a new Interval by subtracting `other` many semitones from this one's
  # {#size}.
  # @param other [Integer]
  # @return [Interval]
  def -(other)
    Interval.new(size: @size - other.to_f)
  end

  # Returns a new Interval by multiplying this one's {#size} by `other`.
  # @param other [Integer]
  # @return [Interval]
  def *(other)
    Interval.new(size: @size * other.to_f)
  end

  # Returns a new Interval by dividing this one's {#size} by `other`.
  # @param other [Integer]
  # @return [Interval]
  def /(other)
    Interval.new(size: @size / other.to_f)
  end

  # The string representation of this interval, in the abbreviated format
  # described by {.new}.
  # @return [String]
  def to_s
    @sym.to_s
  end

  # @private
  def inspect
    return @inspect_s unless @inspect_s.nil?

    other_names = names.dup
    other_names.delete(@sym)
    other_names = other_names.join(", ")
    @inspect_s = "<Interval #{@sym} (aka #{other_names}), #{@size} semitones>"
    @inspect_s
  end

  # A symbol representation of this interval, in the abbreviated format
  # described by {.new}.
  # @return [Symbol]
  def to_sym
    @sym
  end
end


# Some overrides so comparison works when a string or symbol is on the left.
# We don't need to do anything about Numeric; that already works via coercion.
# @private
module SpiSeq
  module MonkeyPatches
    module IntervalComparison
      SpiSeq::Utils.define_reverse_comparison_ops(self, Interval)
    end
  end
end

# @private
class Symbol
  prepend SpiSeq::MonkeyPatches::IntervalComparison
end

# @private
class String
  prepend SpiSeq::MonkeyPatches::IntervalComparison
end
