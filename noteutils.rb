$spi ||= self

module NoteUtils
  # See https://github.com/sonic-pi-net/sonic-pi/blob/714d33316620d46d6815e554f17c5a76e4967471/app/server/ruby/lib/sonicpi/note.rb#L65
  NOTE_REGEX = /^:?(?<pitch_class>[a-g][sbf]?)(?<octave>-?\d*)$/i

  # note is a symbol or string for a note (e.g. :fs3), or a MIDI note number. If
  # octave is given, it overrides the octave of the note (even if it is a note
  # number). If octave is not given and the note is a symbol or string without
  # an octave (e.g. :c), the result will be in octave 4. Sharps and flats are
  # standardized into sharps.
  # Returns an array [note symbol, note number, octave number]. The returned
  # symbol is in lower case and is guaranteed to have an explicit octave number.
  def self.normalize(note, octave: nil)
    # note_info leaves pitch classes in symbols alone, so we always need to go
    # to a number first so that sharps and flats are normalized. Note that this
    # step is the one that enforces the default octave of 4 on symbols without
    # an explicit octave. We will replace the octave if needed in the note_info
    # call below.
    note = $spi.note(note)

    # note_info ignores its octave argument when the note is a number, so if we
    # want to override the octave we need to go back to a symbol/string first.
    # We could just call sym, but that would recurse and do some needless work,
    # so we use note_info directly here since we don't care about the details of
    # the name we get back, so long as it represents the note.
    if !octave.nil?
      info = $spi.note_info(note)
      note = info.midi_string
    end

    info = $spi.note_info(note, octave: octave)

    # Make sure flats are converted to sharps.
    pc = pitch_class_from_sym(info.midi_string.downcase.to_sym)
    note_sym = sharpify(pc, info.octave)

    [note_sym, info.midi_note, info.octave]
  end

  # Returns a normalized symbol for the given note (a symbol, string, or MIDI
  # note number). Uses the same octave rules as normalize.
  def self.sym(note, octave: nil)
    normalize(note, octave: octave)[0]
  end

  # Returns the symbol for the note's pitch class (e.g. :c for Cs in all
  # octaves). note may be a symbol, string, or MIDI note number. The returned
  # symbol will be in lowercase.
  def self.pitch_class(note)
    pitch_class_from_sym(sym(note))
  end

  # Returns the MIDI note number for the given note (a symbol, string, or MIDI
  # note number). Uses the same octave rules as normalize.
  def self.number(note, octave: nil)
    normalize(note, octave: octave)[1]
  end

  # Returns true if the given note has an explicit octave. Always returns true
  # for MIDI note numbers. Returns true for note symbols or strings that end in
  # a number, e.g. :cs4.
  def self.has_octave?(note)
    return true if note.is_a?(Numeric)
    match = NOTE_REGEX.match(note.to_s)
    raise "Invalid note symbol #{note}" if match.nil?
    !match[:octave].empty?
  end

  # Returns the octave number for the given note (a symbol, string, or MIDI note
  # number). Uses the same octave rules as normalize.
  def self.octave(note, octave: nil)
    normalize(note, octave: octave)[2]
  end

  # Returns a normalized symbol for the given note (a symbol, string, or MIDI
  # note number), changing its octave to the given value. This is effectively an
  # alias for sym.
  def self.set_octave(note, octave)
    sym(note, octave: octave)
  end

  # Returns a normalized symbol for the given note, with its octave shifted by
  # the given offset.
  def self.shift_octave(note, octave_shift)
    sym(note, octave: octave(note) + octave_shift)
  end

  # Returns a normalized symbol for the given note, shifted by the given number
  # of semitones. The octave parameter, if given, is applied when resolving the
  # note argument; the result will not be in the given octave if the tone shift
  # moves it outside of that octave.
  def self.shift_tone(note, semitone_shift, octave: nil)
    sym(number(note, octave: octave) + semitone_shift)
  end

  # Returns a normalized symbol for the given note, snapped to the closest value
  # in notes. notes must be an array of note representations (symbols, strings,
  # or MIDI note numbers). The octave parameter, if given, is used to resolve
  # the note parameter. It is not used to resolve notes in the notes array; you
  # probably want to give those explicit octaves.
  def self.snap(note, notes, octave: nil)
    # TODO: be more particular about rounding up or down?
    notes = notes.map { |n| number(n) }
    note = number(note, octave: octave)
    winner = nil
    smallest_diff = 256
    notes.each do |n|
      diff = (n - note).abs
      if diff < smallest_diff
        smallest_diff = diff
        winner = n
      end
    end

    sym(winner)
  end

  # Given a tonic and a scale name, returns an array with two elements:
  # - the full set of integer MIDI notes (0-127) that belong to the scale
  # - the index in the array where the tonic can be found
  def self.full_scale_and_tonic_idx(tonic, name)
    @__full_scales_cache ||= {}

    key = [tonic, name]
    val = @__full_scales_cache[key]

    if val.nil?
      # Note 0 is c-1, and 127 is g9, so if we do 11 octaves from -1, we'll
      # cover the whole MIDI range.
      low_tonic = (pitch_class(tonic).to_s + "-1").to_sym
      full_scale = $spi.scale(low_tonic, name, num_octaves: 11).to_a.reject { |n| n < 0 || n > 127 }
      tonic_index = full_scale.index(number(tonic))
      val = [full_scale, tonic_index]
      @__full_scales_cache[key] = val
    end

    val
  end

  private_class_method :full_scale_and_tonic_idx

  # Returns the full set of integer MIDI notes (0-127) that belong to the given
  # scale with the given tonic.
  def self.full_scale(tonic, scale_name)
    return full_scale_and_tonic_idx(tonic, scale_name)[0]
  end

  # Returns a normalized symbol for the given note, snapped to the nearest note
  # in the given scale. root is the root note for the scale and must be a symbol
  # or string for a note without an octave (e.g. :c or :fs). scale is a symbol
  # for one of the scales known to Sonic Pi. The octave parameter, if given, is
  # used to resolve the note parameter. It has no effect on the scale.
  def self.snap_to_scale(note, root, scale, octave: nil)
    snap(note, full_scale(root, scale), octave: octave)
  end

  # Returns a sort of degree number for the given note in the given scale with
  # the given tonic. The result is an integer, which may be positive or
  # negative, representing how many degrees the note is away from the tonic.
  # Returns nil if the note is not in the scale.
  def self.degree_number(note, scale_tonic, scale_name)
    sc, tonic_index = full_scale_and_tonic_idx(scale_tonic, scale_name)
    note_index = sc.index(number(note))
    return nil if note_index.nil?
    note_index - tonic_index
  end

  private_class_method :degree_number

  # Returns the symbol for a note that is num many degrees away from the tonic
  # in the given scale. num may be positive or negative.
  def self.my_degree(num, scale_tonic, scale_name)
    sc, tonic_idx = full_scale_and_tonic_idx(scale_tonic, scale_name)
    sym(sc[tonic_idx + num])
  end

  private_class_method :my_degree

  # Returns an array of note symbols that represent a 4-part harmony for the
  # give note in the given scale and tonic. position must be 0, 1, or 2, and
  # determines which of the three possible harmonies is returned. The returned
  # array will be sorted from low to high, and the given note itself will be
  # the final element of the array. If note is not in the scale, returns a
  # single-element array containing just note.
  # This is based on an article by Neil Bickford (https://www.gathering4gardner.org/g4g14gift/G4G14-NeilBickford-AlgorithmsForMusicalHarmonization.pdf)
  # which in turn references a paper by Donald Knuth.
  def self.harmonize(note, scale_tonic, scale_name, position: 0)
    n = degree_number(note, scale_tonic, scale_name)
    return [sym(note)] if n.nil?

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

    degrees.map { |d| my_degree(d, scale_tonic, scale_name) }
  end

  # Returns true if the given value represents a rest. nil, :r, and :rest are
  # considered rests.
  def self.rest?(val)
    val.nil? || val == :r || val == :rest
  end

  # Returns true if the two values refer to the same note, or are both rests.
  def self.equal_notes?(a, b)
    (rest?(a) && rest?(b)) || (sym(a) == sym(b))
  end

  # Returns true if the two values match one another. Two values match if:
  # - Both are a rest. E.g. :r matches :rest and nil.
  # - Both have an explicit octave (or are a MIDI number) and refer to the same
  #   note. E.g. :cs2 matches :cs2 and :db2. 67 matches :g4.
  # - Either (or both) is missing an octave, and the two have the same pitch
  #   class. E.g. :c2 and :c4 match :c. :cs matches :cs3, :db2, and :db.
  def self.match?(a, b)
    return true if rest?(a) && rest?(b)

    a_has_octave = has_octave?(a)
    b_has_octave = has_octave?(b)
    if (a_has_octave && b_has_octave) || (!a_has_octave && !b_has_octave)
      # If they both have an octave, or both don't, compare symbols directly. If
      # both don't have an octave, this will collapse them to the same default.
      return sym(a) == sym(b)
    end

    pitch_class(a) == pitch_class(b)
  end

  # Returns a symbol for the pitch class of an already normalized note symbol.
  # Broken out from pitch_class to avoid recursion in normalize.
  def self.pitch_class_from_sym(note_sym)
    match = NOTE_REGEX.match(note_sym.to_s)
    raise "Invalid note symbol #{note}" if match.nil?  # should never happen
    match[:pitch_class].to_sym  # we normalized before the match, so this will be lowercase
  end

  private_class_method :pitch_class_from_sym

  # note_info converts some notes to sharps and others to flats. This converts
  # everything to a sharp. pitch_class should be a lower- case normalized pitch
  # class symbol (e.g. :eb).
  def self.sharpify(pitch_class, octave)
    # Not trying to be exhaustive here; these are just the notes for which
    # note_info returns flats.
    if pitch_class == :eb
      pitch_class = :ds
    elsif pitch_class == :ab
      pitch_class = :gs
    elsif pitch_class == :bb
      pitch_class = :as
    end

    (pitch_class.to_s + octave.to_s).to_sym
  end

  private_class_method :sharpify
end
