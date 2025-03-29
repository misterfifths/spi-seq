# frozen_string_literal: true

require_relative "extapi"


# An alias for MIDINote.new.
def N(note)
  MIDINote.new(note)
end


# Represents information about a note.
# - to_sym: A normalized symbol for the note. It will be in lower-case, with all
#   accidentals standardized to sharps. It will always include an octave number.
# - pitch_class: A symbol for the pitch class of the note (e.g. :c for C notes
#   in any octave), normalized in the same manner as `to_sym`.
# - number: The MIDI note number for the note. Note that this may not be an
#   integer (e.g. if there's a cent tuning in effect). In that case, `to_sym`
#   and `pitch_class` will correspond to the floor of `number`. If you need an
#   integer MIDI note value, use the to_i method.
# - octave: The octave for the note.
#
# Note that since this class derives from Numeric, you can directly pass
# instances of it to Sonic Pi methods like `play` and `midi`. You can also
# perform arithmetic on them, and compare instances directly to other numbers,
# symbols, or strings. For example,
#    MIDINote.new(61) == 61 == :cs4 == "db4"
#    MIDINote.new(:c4) + 12 == :c5 == 72
class MIDINote < Numeric
  # See https://github.com/sonic-pi-net/sonic-pi/blob/714d33316620d46d6815e554f17c5a76e4967471/app/server/ruby/lib/sonicpi/note.rb#L65
  NOTE_REGEX = /^:?(?<pitch_class>[a-g][sbf]?)(?<octave>-?\d*)$/i.freeze
  NOTE_NAMES = [[:c, :bs], [:cs, :db, :df], [:d], [:ds, :eb, :ef], [:e, :fb, :ff], [:f, :es],
                [:fs, :gb, :gf], [:g], [:gs, :ab, :af], [:a], [:as, :bb, :bf], [:b, :cb, :cf]].freeze
  NOTE_NAMES.each { |names| names.freeze }

  attr_reader :pitch_class, :number, :octave

  # Creates a new MIDINote instance from the given value, which must be either a
  # MIDI note number, a string, a symbol, or a MIDINote instance (in which case
  # the argument is returned as-is).
  def self.new(note)
    return note if note.is_a?(MIDINote)
    raise "Cannot convert a rest to a MIDINote" if rest?(note)

    @note_cache ||= {}

    # Attempt a raw cache lookup.
    instance = @note_cache[note]
    return instance unless instance.nil?

    # No dice; canonicalize the key a bit.
    cache_key = case note
    when String
      note.downcase
    when Symbol
      note.to_s.downcase
    when Numeric
      note.to_f
    else
      note
    end

    instance = @note_cache[cache_key]
    unless instance.nil?
      # `note` must be a new representation of a value we already know about; we
      # should update the cache.
      @note_cache[note] = instance
      return instance
    end

    # We've got to make a new instance.
    instance = super
    @note_cache[note] = instance
    @note_cache[cache_key] = instance
    @note_cache[instance.to_f] = instance

    # It's only safe to cache against instance.to_s if the note number is an
    # integer. If it was a float, it is not the canonical representation of that
    # note symbol, and we should only cache it against instance.to_f (which will
    # also be the cache_key in that case).
    if instance.number.is_a?(Integer)
      @note_cache[instance.to_s] = instance
    end

    instance
  end

  def initialize(note)
    super()

    case note
    when Numeric
      # The argument may be a float. Keep it as-is in @number, but be sure to
      # use to_i when using it as a MIDI note number.
      @number = note
      @octave = (note.to_i / 12) - 1
      @pitch_class = NOTE_NAMES[note.to_i % 12][0]
      @sym = :"#{@pitch_class}#{@octave}"
    when Symbol, String
      match = NOTE_REGEX.match(note.to_s.downcase)
      raise "Invalid note name #{note}" if match.nil?

      @octave = match[:octave].empty? ? 4 : match[:octave].to_i
      @pitch_class = match[:pitch_class].to_sym

      # Check for octave boundary crossings: cb (down an octave) and bs (up)
      @octave -= 1 if [:cb, :cf].include?(@pitch_class)
      @octave += 1 if @pitch_class == :bs

      name_idx = NOTE_NAMES.find_index { |names| names.include?(@pitch_class) }
      @pitch_class = NOTE_NAMES[name_idx][0]  # normalize
      @number = 12 + @octave * 12 + name_idx  # 12 is c0
      @sym = :"#{@pitch_class}#{@octave}"
    else
      raise "Invalid note value #{note}"
    end
  end

  # Returns a new note with the same pitch class but the given octave.
  def with_octave(new_octave)
    return self if new_octave == @octave
    MIDINote.new(:"#{@pitch_class}#{new_octave}")
  end

  # Returns a new note with the same pitch class but with its octave shifted up
  # by the given amount.
  def shift_octave(shift)
    return self if shift == 0
    with_octave(@octave + shift)
  end

  # Returns a new note with the same pitch class but with its octave shifted up
  # by the given amount.
  def up(octave_shift = 1)
    shift_octave(octave_shift)
  end

  # Returns a new note with the same pitch class but with its octave shifted
  # down by the given amount.
  def down(octave_shift = 1)
    shift_octave(-octave_shift)
  end

  # Returns a new note that is shift many semitones away.
  def shift_tone(shift)
    return self if shift == 0
    MIDINote.new(@number + shift)
  end

  alias transpose shift_tone

  # Returns a new note in the same octave but with the given pitch class.
  def with_pitch_class(cls)
    MIDINote.new(:"#{cls}#{@octave}")
  end

  # Returns true if other matches this note. That is:
  # - other has an explicit octave (or is a MIDI number) and refers to the same
  #   note. E.g. :cs2 matches :cs2 and :db2. 67 matches :g4.
  # - other is missing an octave and has the same pitch class. E.g. :c2 and :c4
  #   match :c. :cs matches :cs3, :db2, and :db.
  def match?(other)
    return false if MIDINote.rest?(other)
    return self == other if MIDINote.has_octave?(other)
    @pitch_class == MIDINote.new(other).pitch_class
  end

  # Returns a new note snapped to the closest value in notes. notes must be an
  # array of note representations (symbols, strings, MIDI note numbers, or
  # MIDINotes).
  def snap(notes)
    # TODO: be more particular about rounding up or down?
    notes = notes.map { |n| MIDINote.new(n) }
    winner = nil
    smallest_diff = 256
    notes.each do |n|
      diff = (n.number - @number).abs
      if diff < smallest_diff
        smallest_diff = diff
        winner = n
      end
    end

    winner
  end

  # Returns the full set of MIDINotes (in the MIDI range 0-127) that belong to
  # the given scale with the given tonic.
  def self.full_scale(tonic, scale_name)
    @scale_cache ||= {}

    tonic = MIDINote.new(tonic)
    key = [tonic.to_sym, scale_name.to_sym]
    scale = @scale_cache[key]
    return scale unless scale.nil?

    # Note 0 is c-1, and 127 is g9, so if we do 11 octaves from -1, we'll cover
    # the whole MIDI range.
    low_tonic = tonic.with_octave(-1)
    scale = ExtApi.scale(low_tonic, scale_name, num_octaves: 11).to_a.reject { |n| n < 0 || n > 127 }
    scale.map! { |n| MIDINote.new(n) }
    @scale_cache[key] = scale
    scale
  end

  # Returns a new note, snapped to the nearest note in the given scale. tonic is
  # the root note for the scale and must be a symbol or string for a note
  # without an octave (e.g. :c or :fs). scale is a symbol for one of the scales
  # known to Sonic Pi.
  def snap_to_scale(tonic, scale_name)
    snap(MIDINote.full_scale(tonic, scale_name))
  end


  ### Auto-harmonize

  # Returns a sort of degree number for the note in the given scale with the
  # given tonic. The result is an integer, which may be positive or negative,
  # representing how many degrees the note is away from the tonic.
  # Returns nil if the note is not in the scale.
  private def degree_number(tonic, scale_name)
    scale = MIDINote.full_scale(tonic, scale_name)
    note_index = scale.index(note)
    return nil if note_index.nil?
    note_index - scale.index(MIDINote.new(tonic))
  end

  # Returns the note that is num many degrees away from the tonic in the given
  # scale. num may be positive or negative.
  def self.my_degree(num, tonic, scale_name)
    scale = full_scale(tonic, scale_name)
    tonic_index = scale.index(MIDINote.new(tonic))
    scale[tonic_index + num]
  end

  private_class_method :my_degree

  # Returns an array of note symbols that represent a 4-part harmony for the
  # give note in the given scale and tonic. position must be 0, 1, or 2, and
  # determines which of the three possible harmonies is returned. The returned
  # array will be sorted from low to high, and the given note itself will be
  # the final element of the array. If note is not in the scale, returns a
  # single-element array containing just note.
  # This is based on an article by Neil Bickford:
  # https://www.gathering4gardner.org/g4g14gift/G4G14-NeilBickford-AlgorithmsForMusicalHarmonization.pdf
  # which in turn references a paper by Donald Knuth.
  def harmonize(tonic, scale_name, position: 0)
    n = degree_number(tonic, scale_name)
    return [self] if n.nil?

    degrees = case position
    when 0
      [n - 11, n - 4, n - 2, n]
    when 1
      [n - 7, n - 5, n - 3, n]
    when 2
      [n - 9, n - 5, n - 2, n]
    else
      raise "position must be between 0-2 inclusive"
    end

    # Avoid tritones
    degrees[0] -= 2 if degrees[0] % 7 == 6

    degrees.map { |d| MIDINote.my_degree(d, tonic, scale_name) }
  end


  ### Ruby magic methods and Numeric implementation

  def to_i
    @number.to_i
  end

  def to_f
    @number.to_f
  end

  def <(other)
    return @number < other.to_f if other.is_a?(Numeric)
    @number < MIDINote.new(other).number
  end

  def <=(other)
    return @number <= other.to_f if other.is_a?(Numeric)
    @number <= MIDINote.new(other).number
  end

  def >(other)
    return @number > other.to_f if other.is_a?(Numeric)
    @number > MIDINote.new(other).number
  end

  def >=(other)
    return @number >= other.to_f if other.is_a?(Numeric)
    @number >= MIDINote.new(other).number
  end

  def <=>(other)
    return @number <=> other.to_f if other.is_a?(Numeric)
    @number <=> MIDINote.new(other).number
  end

  def ==(other)
    return false if MIDINote.rest?(other)
    return @number == other.to_f if other.is_a?(Numeric)  # rubocop:disable Lint/FloatComparison
    # The symbol and string checks are just fast paths. :c4 and :C4 are still
    # equal, e.g., so we have to normalize if they don't match.
    return true if other.is_a?(Symbol) && @sym == other
    return true if other.is_a?(String) && @sym.to_s == other
    @sym == MIDINote.new(other).to_sym
  end

  alias eql? ==

  def hash
    @sym.hash
  end

  def coerce(other)
    [MIDINote.new(other), self]
  end

  def +(other)
    shift_tone(other.to_f)
  end

  def -(other)
    shift_tone(-other.to_f)
  end

  def *(other)
    MIDINote.new(@number * other.to_f)
  end

  def /(other)
    MIDINote.new(@number / other.to_f)
  end

  def to_sym
    @sym
  end

  def to_s
    @sym.to_s
  end

  def inspect
    ":#{@sym}"
  end

  def repr
    ":#{@sym}"
  end


  ### Misc. class methods

  # Returns true if the given note value (number, string, symbol, or MIDINote)
  # has an explicit octave. Always returns true for MIDI note numbers and
  # MIDINote objects. Returns true for note symbols or strings that end in a
  # number, e.g. :cs4.
  def self.has_octave?(note)
    return true if note.is_a?(Numeric) || note.is_a?(MIDINote)

    match = NOTE_REGEX.match(note.to_s)
    raise "Invalid note symbol #{note}" if match.nil?
    !match[:octave].empty?
  end

  # Returns true if the given value represents a rest. nil, :r, and :rest are
  # considered rests.
  def self.rest?(val)
    val.nil? || val == :r || val == :rest
  end
end
