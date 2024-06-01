# I don't understand how to get a sane set of SonicPi functions in external
# scripts, so this is intended to be eval'd so we get access to the context that
# the sketch is running inside. Namely:
$spi ||= self


class NoteLength
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
      raise "Invalid note length symbol #{sym}"
    end
  end

  Whole = new(:whole)
  Half = new(:half)
  Quarter = new(:quarter)
  Eighth = new(:eighth)
  Sixteenth = new(:sixteenth)
  ThirtySecond = new(:thirty_second)
  SixtyFourth = new(:sixty_fourth)

  def self.from_length(f)
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
      raise "Invalid note length #{f}"
    end
  end

  # Attempts to convert the given value to a NoteLength. It may be:
  # - A NoteLength, in which case it is returned verbatim
  # - A symbol, which is fed to the constructor of the class
  # - A number, which is fed to from_length.
  # Any other type, invalid numbers, or invalid symbols are an error.
  def self.normalize(x)
    if x.is_a?(NoteLength)
      x
    elsif x.is_a?(Symbol)
      new(x)
    elsif x.is_a?(Numeric)
      from_length(x)
    else
      raise "Invalid note length value #{x}; must be a symbol, number, or NoteLength"
    end
  end

  # Returns a NoteLength with half the duration of this one. E.g., halving a
  # quarter note length returns an eighth. It is an error to attempt to halve
  # a sixty-fourth note.
  def halve
    raise "No supported note length shorter than #{self}" if @next_shorter.nil?
    NoteLength.new(@next_shorter)
  end

  # Returns a NoteLength with double the duration of this one. E.g., doubling a
  # quarter note length returns a half. It is an error to attempt to double a
  # whole note.
  def double
    raise "No supported note length longer than #{self}" if @next_longer.nil?
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
    @sym == other.sym
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
    return (@log2 - other_note_length.log2).abs
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
    "<NoteLength #{to_s}>"
  end


  protected

  attr_reader :sym, :log2
end


# TODO: note class?
module NoteUtils
  NOTE_REGEX = /^(?<pitch_class>[a-g][sbf]?)(?<octave>\d*)$/i

  # note is a symbol for a note (e.g. :fs3) or a MIDI note number. If octave is
  # given, it overrides the octave of the note (even if it is a note number).
  # If octave is not given and the note is a symbol without an octave (e.g. :c),
  # the result will be in octave 4.
  # Sharps and flats are normalized into sharps. The returned symbol is in lower
  # case and is guaranteed to have an explicit octave number.
  # Returns an array [note symbol, note number, octave number]
  def self.normalize(note, octave: nil)
    # Always go to a number first, so that sharps and flats collapse.
    note = $spi.note(note)

    # If we're overriding the octave, convert back to a symbol so that note_info
    # actually respects the octave.
    note = sym(note) if !octave.nil?

    info = $spi.note_info(note, octave: octave)
    [info.midi_string.downcase.to_sym, info.midi_note, info.octave]
  end

  # Returns a normalized symbol for the given note (a symbol or MIDI note
  # number). Uses the same octave rules as normalize.
  def self.sym(note, octave: nil)
    normalize(note, octave: octave)[0]
  end

  # Returns the symbol for the note's pitch class (e.g. :c for Cs in all
  # octaves). note may be a symbol or MIDI note number.
  def self.pitch_class(note)
    match = NOTE_REGEX.match(sym(note).to_s)
    raise "Invalid note symbol #{note}" if match.nil?  # should never happen
    match[:pitch_class].to_sym  # we normalized before the match, so this will be lowercase
  end

  # Returns the MIDI note number for the given note (a symbol or MIDI note
  # number). Uses the same octave rules as normalize.
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

  # Returns the octave number for the given note (a symbol or MIDI note number).
  # Uses the same octave rules as normalize.
  def self.octave(note, octave: nil)
    normalize(note, octave: octave)[2]
  end

  # Returns a normalized symbol for the given note (a symbol or MIDI note
  # number), changing its octave to the given value. This is effectively an
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
  # in notes. notes must be an array of note representations (symbols or MIDI
  # note numbers). The octave parameter, if given, is used to resolve the note
  # parameter. It is not used to resolve notes in the notes array; you probably
  # want to give those explicit octaves.
  def self.snap(note, notes, octave: nil)
    # TODO: be more particular about rounding up or down?
    notes = notes.map { |n| number(n) }
    note = notes.number(note, octave: octave)
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

  # Returns a normalized symbol for the given note, snapped to the nearest note
  # in the given scale. root is the root note for the scale and must be a symbol
  # for a note without an octave (e.g. :c or :fs). scale is a symbol for one of
  # the scales known to Sonic Pi. The octave parameter, if given, is used to
  # resolve the note parameter. It has no effect on the scale.
  def self.snap_to_scale(note, root, scale, octave: nil)
    oct_0_root = (root.to_s + "0").to_sym
    snap(note, $spi.scale(oct_0_root, scale, num_octaves: 10), octave: octave)
  end

  # Returns true if the given note represents a rest.
  def self.rest?(note)
    note.nil? || note == :r || note == :rest
  end
end


class Prob
  # Use a custom trigger probability predicate. The predicate must respond to
  # call and arity, and must have an arity between 0 and 3 inclusive. It will be
  # called with arguments based on its arity:
  # - Arity 1: will be called with the cycle number
  # - Arity 2: will be called with the cycle number and the Step.
  # - Arity 3: will be called with the cycle number, the Step, and an array of
  #   Steps that were played in the slot immediately prior to the current one.
  # The predicate should return true if the Step should trigger.
  def self.custom(callable)
    new(callable, "custom")
  end

  # Step will trigger with the given probability (0-1 inclusive).
  def self.chance(p)
    new(->{ $spi.rand < p }, "#{p.round(2)}")
  end

  # Step will trigger with a probablity of 1 in n.
  def self.one_in(n)
    new(->{ $spi.one_in(n) }, "one in #{n}")
  end

  # Step is guaranteed to trigger the xth cycle out of each set of y cycles. x
  # should be <= y. For example, x_of_y(3, 4) means that the Step will trigger
  # on the third of every four cycles.
  def self.x_of_y(x, y)
    new(->(cycle) { cycle % y == x - 1 }, "#{x}|#{y}")
  end

  # The inverse of x_of_y - the Step will trigger on every cycle except for the
  # xth out of every y cycles.
  def self.not_x_of_y(x, y)
    new(->(cycle) { cycle % y != x - 1 }, "!#{x}|#{y}")
  end

  # Step will trigger only on the first cycle.
  def self.first
    new(->(cycle) { cycle == 0 }, "first")
  end

  # Step will trigger on every cycle except the first.
  def self.not_first
    new(->(cycle) { cycle != 0 }, "!first")
  end

  # Step will trigger if any step triggered in the previously played slot.
  def self.pre
    new(->(cycle, step, prev_steps) { prev_steps.length != 0 }, "pre" )
  end

  # Step will trigger if no step triggered in the previously played slot.
  def self.not_pre
    new(->(cycle, step, prev_steps) { prev_steps.length == 0 }, "!pre" )
  end

  # Step will trigger if a step triggered in the previously played slot with the
  # same note as this step.
  def self.pre_same_note
    pred = lambda do |cycle, step, prev_steps|
      prev_steps.any? { |prev_step| prev_step.note == step.note }
    end
    new(pred, "pre same note")
  end

  # Step will trigger only if none of the steps that triggered in the previously
  # played slot had the same note as this step.
  def self.not_pre_same_note
    pred = lambda do |cycle, step, prev_steps|
      prev_steps.all? { |prev_step| prev_step.note != step.note }
    end
    new(pred, "!pre same note")
  end

  # Evaluates the probability function for the given step in the given cycle of
  # the Track. Returns true if the step should trigger.
  def should_trigger?(cycle, step, prev_steps)
    case @callable.arity
    when 0
      res = @callable.call
    when 1
      res = @callable.call(cycle)
    when 2
      res = @callable.call(cycle, step)
    when 3
      res = @callable.call(cycle, step, prev_steps)
    end

    # $spi.puts("prob(#{step.inspect}, cycle=#{cycle}) = #{res}")
    res
  end

  def to_s
    @desc
  end

  def inspect
    "<Prob #{to_s}>"
  end


  private

  def initialize(callable, desc)
    if callable.respond_to?(:call) && callable.respond_to?(:arity) && callable.arity <= 3
      @callable = callable
    else
      raise "Invalid probability predicate: must be a callable that takes <= 3 arguments"
    end

    @desc = desc
  end
end


# Immutable!
# TODO: legato?
# TODO: microtiming?
class Step
  attr_reader :note, :note_number, :octave, :vel, :gate, :prob

  # note can be a string, symbol, integer MIDI note. It is always normalized
  # to a lower-case symbol of the Sonic Pi note name, and flats are converted to
  # sharps. If you need to compare against a Step's note, make sure you use such
  # a normalized symbol, or use the has_note? method.
  # vel is the MIDI velocity for the note, 0 - 127. It is only used when the
  # note is played via MIDI, obviously.
  # gate is the percentage of the duration of the step for which the note will
  # be triggered. The note will not be played with a gate of 0, and will be
  # tied to the following step (if any) with a gate of 1.
  # prob is the probability that the step will trigger. It should be either:
  # 1. nil - the Step will always trigger
  # 2. a number between 0 and 1 inclusive that represents the chance that the
  #    Step will trigger
  # 3. a callable predicate lambda/proc that takes the arguments described by
  #    Prob.custom. If the predicate returns true, the step will trigger.
  # 4. an instance of Prob. See that class for some common cases.
  def initialize(note, vel: 127, gate: 1.0, prob: nil)
    @note, @note_number, @octave = NoteUtils.normalize(note)

    @vel = vel.to_i
    if @vel < 0
      @vel = 0
    elsif @vel > 127
      @vel = 127
    end

    # TODO: quantize this?
    @gate = gate.to_f
    if @gate < 0.0
      @gate = 0.0
    elsif @gate > 1.0
      @gate = 1.0
    end

    if prob.nil?
      @prob = nil
    elsif prob.is_a?(Numeric)
      @prob = Prob.chance(prob)
    elsif prob.is_a?(Prob)
      @prob = prob
    else
      @prob = Prob.custom(prob)  # this will raise if this isn't an appropriate predicate
    end
  end

  def mutate(mutations)
    mutations = mutations.dup
    note = mutations.delete(:note) || @note
    [:vel, :gate, :prob].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Step.new(note, **mutations)
  end

  def with_note(new_note)
    mutate(note: new_note)
  end

  def with_vel(new_vel)
    mutate(vel: new_vel)
  end

  def with_gate(new_gate)
    mutate(gate: new_gate)
  end

  def with_prob(new_prob)
    mutate(prob: new_prob)
  end

  def with_octave(new_octave)
    with_note(NoteUtils.set_octave(@note, new_octave))
  end

  def shift_octave(shift)
    with_note(NoteUtils.shift_octave(@note, shift))
  end

  # Adjusts the note by the given number of semitones.
  def shift_tone(shift)
    with_note(NoteUtils.shift_tone(@note, shift))
  end

  def tied?
    @gate == 1.0
  end

  # Returns whether this Step has the given note, which may be a MIDI note
  # number, a string, or a symbol. You can compare directly against the note
  # attribute if you use a normalized note symbol (lowercase, with sharps
  # converted to flats). Otherwise, this function makes sure to do the
  # normalization for you.
  def has_note?(n)
    @note == NoteUtils.sym(n)
  end

  def should_trigger?(cycle, prev_steps)
    return true if @prob.nil?
    @prob.should_trigger?(cycle, self, prev_steps)
  end

  def inspect
    if @prob.nil?
      prob_desc = ""
    else
      prob_desc = " prob=#{@prob}"
    end
    "<Step #{@note}/#{@note_number} vel=#{@vel} gate=#{@gate}#{prob_desc}>"
  end
end

def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


module Arp
  Up = :up
  Down = :down
  UpDown = :updown
  TwoUpTwoDown = :twouptwodown
  AlternIn = :alternin
  AlternOut = :alternout
  AlternInOut = :alterninout
  Pinky = :pinky
  Thumb = :thumb
  Random = :random
  Order = :order

  # See https://www.reddit.com/r/musictheory/comments/1clent8/names_for_common_arpeggio_patterns
  module DegreePatterns
    OneThreeFive = [1, 3, 5]
    OneThreeFiveThree = [1, 3, 5, 3]
    Alberti = [1, 5, 3, 5]
    AlbertiFirstInv = [3, 8, 5, 8]
    AlbertiSecondInv = [5, 10, 8, 10]
    AlbertiSeventh = [1, 7, 3, 7]
    OpenPosition = [1, 5, 10]
    OneOctave = [1, 3, 5, 8]
    OneOctaveFirstInv = [3, 5, 8, 10]
    OneOctaveSecondInv = [5, 8, 10, 12]
    TwoOctaveBroken = [1, 5, 3, 8, 5, 10, 8, 12, 10, 15]
  end

  # TODO: extra_octaves is definitely not what octave spread does on the oxi
  # spread n - for the n lowest notes, add a note an octave up, wrapping around
  # as needed. the oxi tops out at 7 note polyphony

  def self.arpeggiate(notes, direction, extra_octaves: [])
    orig_notes = notes
    notes = notes.to_a.dup  # to_a because this might be a SonicPi ring

    extra_octaves.each do |octave_shift|
      orig_notes.each do |n|
        notes << NoteUtils.shift_octave(n, octave_shift)
      end
    end

    # need to deal with note numbers internally; we'll be sorting
    notes.map! { |n| NoteUtils.number(n) }

    case direction
    when Arp::Up
      notes.sort!
    when Arp::Down
      notes.sort!.reverse!
    when Arp::UpDown
      notes.sort!
      notes += notes.reverse.drop(1)  # don't repeat the middle note
      notes.pop  # cycle cleanly without repeating the final note either
    when Arp::TwoUpTwoDown
      notes.sort!
      notes += notes.reverse.drop(1)
      notes.pop
      notes = notes.zip(notes).flatten
    when Arp::AlternIn, Arp::AlternOut, Arp::AlternInOut
      notes.sort!
      notes = notes.values_at(*altern_indexes(notes.length, direction))
    when Arp::Pinky
      # play the highest note after each (but don't double at end)
      notes.sort!
      highest = notes.pop
      notes = notes.zip([highest].cycle).flatten
    when Arp::Thumb
      # play the lowest note after each (but don't double at beginning)
      notes.sort!
      lowest = notes.shift
      notes = notes.zip([lowest].cycle).flatten
    when Arp::Random
      notes.shuffle!
    # nothing to do for Arp::Order
    end

    notes.map! { |n| NoteUtils.sym(n) }
  end

  # Arpeggiate the given degrees of the tonic note in the given scale.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, extra_octaves: [])
    notes = degrees.map { |d| $spi.degree(d, tonic, scale) }
    arpeggiate(notes, direction, extra_octaves: extra_octaves)
  end


  private

  def self.altern_indexes(length, direction)
    # in: work in toward the center from the edges, alternating low and high
    # notes, starting each alternation with the low note.
    # 0 1 2 3 4 5 -> 0 5 1 4 2 3
    # 0 1 2 3 4 -> 0 4 1 3 2
    # 0 1 2 3 -> 0 3 1 2
    # 0 1 2 -> 0 2 1
    # 0 1 -> 0 1

    # out: work outward from the center (rounding up when even-length),
    # alternating low and high notes, starting each alternation with the lower
    # note.
    # 0 1 2 3 4 5 -> 3 2 4 1 5 0
    # 0 1 2 3 4 -> 2 1 3 0 4
    # 0 1 2 3 -> 2 1 3 0
    # 0 1 2 -> 1 0 2
    # 0 1 -> 1 0

    # in-out: in, then out, but not repeating the middle note

    return [] if length == 0
    return [0] if length == 1

    case direction
    when Arp::AlternIn
      low_idx = 0
      high_idx = length - 1
      idxs = []
      while low_idx <= high_idx
        idxs << low_idx
        break if low_idx == high_idx
        idxs << high_idx
        low_idx += 1
        high_idx -= 1
      end

      return idxs
    when Arp::AlternOut
      center_idx = length.odd? ? (length - 1) / 2 : length / 2
      idxs = [center_idx]
      low_idx = center_idx - 1
      high_idx = center_idx + 1
      while low_idx >= 0 || high_idx < length
        idxs << low_idx if low_idx >= 0
        idxs << high_idx if high_idx < length
        low_idx -= 1
        high_idx += 1
      end

      return idxs
    when Arp::AlternInOut
      # TODO: drop the last note when it would repeat in a loop?
      in_idxs = altern_indexes(length, Arp::AlternIn)
      out_idxs = altern_indexes(length, Arp::AlternOut)
      return in_idxs + out_idxs.drop(1)
    end
  end
end


# A Track is mostly a "grid" of Steps together with a granularity. The grid is a
# 2d array, each element of which is a "slot". A slot contains some number
# (possibly 0) of Steps. Those are the Steps that should trigger (subject to
# their probabilities) when that slot is played. The order of Steps within a
# slot is not significant. There should not be more than one Step with the same
# note in a given slot; if there is, one with the longest gate will be used.
# Each slot represents the Steps for a timespan equal to the Track's
# granularity, which is some fraction of a beat (e.g. 1/4 for sixteenth note
# granularity). An empty slot represents a rest for the same duration. Thus the
# length of a Track in beats is the granularity multiplied by the number of
# slots in the grid.
# Tracks also have a timescale, which is the speed at which this track will play
# relative to the global bpm. A timescale of 2 means that this track will play
# at twice the global bpm, e.g., and 0.5 means half-speed.
# TODO: make mutable? seems tricky. plus would probably need to make a Grid
# class (or at least a bunch of Track methods) to make manipulation ergonomic.
# TODO: does timescale belong here? really only effects the Player, so it could
# live there, but this feels like a convenient place for it (& to mutate it)
class Track
  attr_reader :granularity, :grid, :timescale


  ### Basic constructors

  # Constructs a track with the given array, each element of which represents
  # a step or a rest. The elements will be played one at a time, in the given
  # order, each for a duration equal to the granularity (in other words, each
  # element of steps defines a slot with a single step). The elements of steps
  # must each be either:
  # - a Step object,
  # - a MIDI note number or symbol, which will be converted to a Step with the
  #   default arguments, or
  # - nil, :r, or :rest to represent a rest.
  def self.mono(steps, granularity: NoteLength::Eighth, timescale: 1)
    grid = steps.map { |s| s.nil? ? [] : [s] }
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a track with the given grid. grid is a two-dimensional array,
  # each element of which is a "slot". A slot is an array, each element of which
  # represents the steps to play simultaneously for a duration of the
  # granularity. A slot may be empty to represent a rest. Non-empty slots must
  # contain some number of
  # - Step objects,
  # - MIDI note numbers or symbols, which will be converted to Steps with the
  #   default arguments, or
  # - nil, :r, or :rest to represent a rest (though this is generally
  #   unnecessary and you should just use an empty array instead)
  def self.poly(grid, granularity: NoteLength::Eighth, timescale: 1)
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs an empty track that rests for the given number of slots.
  def self.rest(num_slots, granularity: NoteLength::Eighth, timescale: 1)
    grid = [[]] * num_slots
    new(grid: grid, granularity: granularity, timescale: 1)
  end


  ### More interesting constructors

  # Constructs a track that arpeggiates the given notes. extra_octaves is an
  # array of octave shifts. The arpeggiation will include all the notes from the
  # note array in addition to copies of them with the given octave shifts.
  # TODO: incorporate euclidean rhythm
  def self.arp(notes, direction = Arp::Up, extra_octaves: [], granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arpeggiate(notes, direction, extra_octaves: extra_octaves)
    grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a track that arpeggiates the given degrees of the tonic note in
  # the given scale. Other arguments are as specified in arp.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, extra_octaves: [], granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    notes = Arp.arp_degrees(tonic, degrees, direction, scale: scale, extra_octaves: extra_octaves)
    grid = notes.map { |n| [Step.new(n, vel: vel, gate: gate)] }
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  # Constructs a mono track that plays the given notes in a Euclidean rhythm.
  # The length of the rhythm is slots, and the number of hits to play over those
  # slots is pulses. notes should be an array of note numbers or symbols, or a
  # single note number or symbol.
  # The cycle_notes parameter controls how the notes array is used when placing
  # notes in the track. If it is true, each time there is a hit in the rhythm,
  # the next note from the notes array is used (wrapping around if needed). For
  # example, when spreading [:c3, :d3] over 3 pulses and 4 slots, the result
  # will be a track with the following steps:
  #   :c3, rest, :d3, :c3
  # If cycle_notes is false, when there is a hit in the rhythm, the note at the
  # corresponding index of that hit in the notes array is used (wrapping around
  # as needed). Using the same spread as above with cycle_notes false would
  # result in:
  #   :c3, rest, :c3, :d3
  # The third note is :c3 because the hit index, 2, corresponds :c3 in the notes
  # array (modulo the length of the array).
  def self.euclid(notes, pulses, slots, invert: false, rotate: 0, cycle_notes: true, granularity: NoteLength::Eighth, gate: 1, vel: 127, timescale: 1)
    if notes.is_a?(Numeric) || notes.is_a?(Symbol) || notes.is_a?(String)
      notes = [notes]
    end

    hits = $spi.spread(pulses, slots).to_a
    hits.rotate!(rotate) if rotate != 0
    hits.map! { |hit| !hit } if invert

    note_idx = 0
    grid = hits.map.with_index do |hit, i|
      if hit
        if cycle_notes
          note = notes[note_idx % notes.length]
          note_idx += 1
        else
          note = notes[i % notes.length]
        end

        [Step.new(note, vel: vel, gate: gate)]
      else
        []
      end
    end

    new(grid: grid, granularity: granularity, timescale: timescale)
  end


  ### Properties

  def num_slots
    @grid.length
  end

  def beat_length
    num_slots * @granularity.to_f
  end


  ### Playback support

  # Returns an array of arrays of Steps representing the state of playback at
  # step i in the given cycle, assuming that the steps in prev_steps were the
  # Steps played in the most recently evaluated slot. The array has the
  # following elements:
  #   [newly triggered Steps, continued (tied) Steps, newly ended Steps]
  # Step probabilities are evaluated, and steps that should not trigger are not
  # returned.
  # Note that the returned array of ended steps does not strictly contain steps
  # that ended exactly at the beginning of this step. It also contains steps
  # that ended between this step and the previous one - i.e. steps with gates
  # less than 1.
  # Wraps the slot index if it exceeds the number of slots in the grid.
  # prev_steps is an array of the Steps that were active in the most recently
  # played slot. prev_steps should be nil or empty when playback is beginning.
  # cycle is the number of times the Track has played in its entirety (used to
  # evaluate Step trigger probabilities).
  # Intended to be called iteratively, incrementing i and the cycle, and feeding
  # back playing and tied steps from the return value as prev_steps.
  def steps_at_slot(i, prev_steps:, cycle:)
    new_steps = []
    tied_steps = []
    ended_steps = []

    prev_steps ||= []
    cur_steps = @grid[i % num_slots].filter { |step| step.should_trigger?(cycle, prev_steps) }

    # distinguish between tied notes and newly started ones
    cur_steps.each do |step|
      # were we just playing this note as a tie?
      is_tie = prev_steps.one? { |prev_step| prev_step.tied? && prev_step.note == step.note }
      if is_tie
        tied_steps << step
      else
        new_steps << step
      end
    end

    # find notes from the last slot that have ended.
    prev_steps.each do |prev_step|
      # any note we were playing that is not tied has ended
      note_continues = tied_steps.one? { |tie| tie.note == prev_step.note }
      ended_steps << prev_step if !note_continues
    end

    [new_steps, tied_steps, ended_steps]
  end


  ### Etc.

  def inspect
    res = "Track slots=#{num_slots} granularity=#{granularity} timescale=#{timescale} grid:\n"
    @grid.each_with_index do |slot, i|
      res += "slot #{i} @ t=#{i * granularity.to_f}\n"
      slot.each { |step| res += "  #{step.inspect}\n" }
    end
    res
  end


  ### Mutators

  ## Granularity manipulations

  # Creates a new Track with double the granularity and number of slots. The
  # length of each Step is doubled to keep the Track sounding roughly the same,
  # which may entail turning a single step into multiple tied ones. For example,
  # expanding a 5-slot Track with 8th-note granularity will result in an 10-slot
  # Track with 16th-note granularity. A Step that had a gate of 90% would become
  # two Steps in back-to-back slots, one a tie and the following with 80% gate.
  def expand
    raise "Cannot expand past 64th-note granularity" if @granularity == NoteLength::SixtyFourth

    # Gameplan: each slot in the grid will expand to two slots. Consider each
    # slot individually. Each Step in that slot may expand to either one Step,
    # or two Steps in each of the new slots. Find the "total gate" for each Step
    # by multiplying its current gate by 2. If it is greater than one, the Step
    # becomes two Steps: one a tie, and the other with gate of total_gate - 1.
    # If the total gate is less than 1, the Step remains as one (longer) step in
    # the first of the new slots.

    def expand_step(step)
      step1_prob = step.prob
      total_gate = step.gate * 2.0
      if total_gate > 1  # TODO: tolerance?
        # If we expanded into two steps, only the second gets the probability.
        # (This is just the Oxi's behavior; it only arguably makes sense.)
        step1_prob = nil
        step2 = step.with_gate(total_gate - 1)
        total_gate = 1
      else
        step2 = nil
      end

      step1 = step.mutate(gate: total_gate, prob: step1_prob)

      [step1, step2]
    end

    new_grid = []
    @grid.each do |slot|
      new_slots = [[], []]
      slot.each do |step|
        step1, step2 = expand_step(step)
        new_slots[0] << step1
        new_slots[1] << step2 unless step2.nil?
      end

      new_grid.concat(new_slots)
    end

    mutate(grid: new_grid, granularity: @granularity.halve)
  end

  # Creates a new Track with half the granularity and number of slots. Steps and
  # tied steps have their lengths halved to keep the track sounding roughly the
  # same. For example, condensing a 10-slot Track with 8th-note granularity will
  # result in a 5-slot Track with quarter-note granularity. Say the Track
  # contained two Steps in back-to-back slots for the same note, the first a tie
  # and the second with a gate of 80. That sequence of Steps would become one
  # Step in one slot in the new track, with a gate of 90.
  # Note that this operation is potentially significantly more lossy than
  # expand. Steps with short gates and those starting on off-beats may be
  # completely absent from the result.
  def condense
    raise "Cannot condense past whole-note granularity" if @granularity == NoteLength::Whole

    # Gameplan: each pair of slots in the grid will collapse into one slot in a
    # new grid. In each pair, find the total gate of any given Step by checking
    # if it is tied to a Step with the same note in the following slot. Divide
    # that total gate by 2 and make a new step. Repeat, condensing all the steps
    # from the pair of slots into shorter steps in one slot.

    # Condense two Steps for the same note into one. The Steps are passed in-
    # order as they appear in the Track. One or the other may be nil, but not
    # both. May return nil if the steps condense to nothing.
    def condense_steps(step1, step2)
      # The Oxi seems to discard anything that begins on the second slot when
      # condensing.
      return nil if step1.nil?

      if step2.nil?
        total_gate = step1.gate / 2.0
      else
        total_gate = (step1.gate + step2.gate) / 2.0
      end

      # The probability and velocity of the second step is discarded; the first
      # step wins. (Again, just Oxi behavior.)
      step1.with_gate(total_gate)
    end

    # Condense the Steps from one or two slots into one new slot. The second
    # slot will be nil for the last slot in a Track with an odd number of slots.
    def condense_slots(slot1, slot2 = nil)
      steps_by_note = Hash.new { |h, k| h[k] = [nil, nil] }
      slot1.each { |step| steps_by_note[step.note][0] = step }
      slot2.each { |step| steps_by_note[step.note][1] = step } unless slot2.nil?

      new_slot = []
      steps_by_note.each do |_, steps|
        condensed_step = condense_steps(*steps)
        new_slot << condensed_step unless condensed_step.nil?
      end

      new_slot
    end

    new_grid = []
    @grid.each_slice(2) do |slot_chunk|
      new_grid << condense_slots(*slot_chunk)
    end

    mutate(grid: new_grid, granularity: @granularity.double)
  end

  # Calls expand or condense the appropriate number of times to return a new
  # Track with the given granularity.
  def regranularize(new_granularity)
    return self if @granularity == new_granularity

    # NOTE: this is obviously very silly, but the alternative would be making
    # expand and condense way more complicated, which is not worth it.

    steps = @granularity.steps_to(new_granularity)
    new_track = self
    steps.times do
      new_track = new_granularity < @granularity ? new_track.expand : new_track.condense
    end

    new_track
  end

  alias regrain regranularize

  ## Grid-level mutations

  def with_rate(rate)
    mutate(timescale: rate)
  end

  alias rate with_rate

  # Returns a new track with the given granularity. Does not effect the timing
  # of any Steps; to change granularity while attempting to keep the track
  # sounding roughly the same, use condense, expand, or regranularize.
  def with_granularity(granularity)
    mutate(granularity: granularity)
  end

  def append(other_track)
    assert_compatible_track(other_track)
    mutate(grid: @grid + other_track.grid)
  end

  alias concat append
  alias add append
  alias + append

  # Create a new Track that merges the Steps in corresponding slots of from this
  # track and other_track. The length of the resulting track is the maximum
  # length of the two tracks.
  def merge(other_track)
    assert_compatible_track(other_track)

    if num_slots > other_track.num_slots
      longer_track = self
      shorter_track = other_track
    else
      longer_track = other_track
      shorter_track = self
    end

    new_grid = longer_track.mutable_grid_dup
    shorter_track.grid.each_with_index { |slot, i| new_grid[i].concat(slot) }

    mutate(grid: new_grid)
  end

  alias | merge

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. cycle controls the behavior if other_track is shorter than this
  # track. When cycle is false, blank slots (rests) will be interleaved once
  # those of other_track are exhausted. If cycle is true, the slots of
  # other_track will be looped as needed. For instance, consider zipping
  # together two sequences with Steps [:a1, :b1, :c1, :d1] and [:e5, :f5].
  # When cycle is false, the resulting Track will contain slots with the
  # following steps:
  #    :a1 :e5 :b1 :f5 :c1 rest :d1 rest
  # When cycle is true, the same operation will result in slots
  #    :a1 :e5 :b1 :f5 :c1 :e5 :d1 :f5
  def zip(other_track, cycle: true)
    assert_compatible_track(other_track)

    other_grid = other_track.grid
    if cycle
      other_grid = other_grid.cycle
    else
      # In the case of a length mismatch, fill in with empty slots.
      repeating_rests = [[]].cycle
      other_grid = other_grid.chain(repeating_rests)
    end

    new_grid = @grid.zip(other_grid).flatten(1)

    mutate(grid: new_grid)
  end

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. Unlike zip, this function does not alternate between 1 slot of
  # each track. Instead, group_size many slots of this track appear
  # consecutively, followed by other_group_size slots of other_track, then
  # group_size many slots of this track, and so on. cycle controls the behavior
  # when the other track has fewer groups than this one. It behaves as described
  # in zip. pad_short_groups controls the behavior when a group size does not
  # evenly divide the number of slots in its corresponding track. If it is true,
  # rests are added to the final chunk of slots so that it has the group size.
  # For instance, consider gzipping together a track with slots with the steps
  #     :a1 :b1 :c1 :d1
  # and one with slots with steps
  #     :e2 :f2
  # If group_size is 3 and other_group_size is 1, and pad_short_groups is false,
  # the result will be
  #     :a1 :b1 :c1 :e2 :d1 :f2
  # But if pad_short_groups is true, the second group of slots from the first
  # track will be padded with two rests so that it has a length equal to its
  # group size. The result then would be
  #    :a1 :b1 :c1 :e2 :d1 rest rest :f2
  # Note that pad_short_groups applies to both groups from this track and
  # other_track.
  def grouped_zip(other_track, group_size, other_group_size, cycle: true, pad_short_groups: false)
    assert_compatible_track(other_track)

    a_chunks = @grid.each_slice(group_size).to_a
    b_chunks = other_track.grid.each_slice(other_group_size).to_a

    if pad_short_groups
      if a_chunks.last.length < group_size
        a_chunks[-1] += [[]] * (group_size - a_chunks.last.length)
      end

      if b_chunks.last.length < other_group_size
        b_chunks[-1] += [[]] * (other_group_size - b_chunks.last.length)
      end
    end

    if cycle
      b_chunks = b_chunks.cycle
    else
      # In the case of a length mismatch, fill in with groups of
      # other_group_size many empty slots.
      repeating_empty_chunks = [[[]] * other_group_size].cycle
      b_chunks = b_chunks.chain(repeating_empty_chunks)
    end
    new_grid = a_chunks.zip(b_chunks).flatten(2)

    mutate(grid: new_grid)
  end

  alias gzip grouped_zip

  def repeat(n)
    mutate(grid: @grid * n)
  end

  alias * repeat

  # Returns a new track that repeats the slots of this track for n slots.
  def cycle_to_length(n)
    mutate(grid: @grid.cycle.take(n))
  end

  # Returns a new track with all empty slots (rests) removed.
  def compact
    mutate(grid: @grid.reject { |slot| slot == [] })
  end

  def reverse
    mutate(grid: @grid.reverse)
  end

  alias rev reverse
  alias bw reverse

  # Returns a new Track that will play the grid forwards and then backwards,
  # repeating the slot in the middle.
  def mirror
    mutate(grid: @grid + @grid.reverse)
  end

  # Returns a new Track that will play the grid forwards and then backwards,
  # without repeating the slot in the middle.
  def reflect
    mutate(grid: @grid + @grid.reverse.drop(1))
  end

  alias bnf reflect

  # Returns a new Track with the slots in the grid shuffled.
  def shuffle
    mutate(grid: @grid.shuffle)
  end

  # Returns a new Track with the slots in the grid rotated to the right by the
  # given amount. The track duration is maintained; slots will be wrapped around
  # to the beginning of the grid as needed.
  def rotate(rightward_shift = 1)
    mutate(grid: @grid.rotate(rightward_shift))
  end

  alias right rotate
  alias rshift rotate
  alias shr rotate

  def left(leftward_shift = 1)
    rotate(-leftward_shift)
  end

  alias lshift left
  alias shl left

  # Returns a new Track by adding num_rests many empty slots (rests) to the
  # beginning of the track.
  def left_pad(num_rests = 1)
    mutate(grid: [[]] * num_rests + @grid)
  end

  alias lpad left_pad

  # Returns a new Track by adding num_rests many empty slots (rests) to the end
  # of the track.
  def right_pad(num_rests = 1)
    mutate(grid: @grid + [[]] * num_rests)
  end

  alias rpad right_pad

  # Returns a new Track by adding num_rests many empty slots (rests) after each
  # existing slot.
  def space(num_rests)
    new_grid = []
    @grid.each do |slot|
      new_grid << slot
      new_grid.concat([[]] * num_rests)
    end

    mutate(grid: new_grid)
  end

  # Returns a new Track with the first n slots removed.
  def drop(n = 1)
    mutate(grid: @grid.drop(n))
  end

  # Returns a new Track consisting of only the first n slots of this track.
  def take(n)
    mutate(grid: @grid.take(n))
  end

  # Returns a new Track consisting of only the selected slots of this track.
  # Takes the same arguments as Array#slice (aka []): a single integer index, an
  # index and a length, or a range.
  def slice(*args)
    s = @grid.slice(*args)
    s = [s] if s.length == 0 || !s[0].is_a?(Array)
    mutate(grid: s)
  end

  alias [] slice

  # Returns a new Track consisting of n random slots from this track's grid. The
  # relative order of the chosen slots is not maintained.
  def sample(n)
    # TODO: does this use spi's rng?
    # TODO: more useful if it does maintain order? could sample an array of
    # indexes instead, sort the result, and use those to choose slots.
    mutate(grid: @grid.sample(n))
  end

  # Returns a new Track with all Steps in every nth slot removed. The duration
  # of the Track does not change; the emptied slots simply become rests.
  def drop_every(n)
    # e.g., drop every 3:
    # keep  | 0 1 - 3 4 - 6 7 - 9
    # drop  |     2     5     8
    # i % 3 | 0 1 2 0 1 2 0 1 2 0
    new_grid = @grid.map.with_index do |slot, i|
      i % n == n - 1 ? [] : slot
    end

    mutate(grid: new_grid)
  end

  alias dropout drop_every

  # Return a new Track by, with probability p, removing all Steps in any given
  # slot.
  def rand_dropout(p)
    new_grid = @grid.map { |slot| $spi.rand < p ? [] : slot }
    mutate(grid: new_grid)
  end

  alias rdropout rand_dropout


  ## Step-level mutations

  # Return a new Track, replacing each Step in this track with the result of the
  # given block. The block may return:
  # - A Step, which will replace the step yielded to the block
  # - nil, :r, or :rest, which will remove the step yielded to the block
  # - An array of Steps, which will all be added in place of the yielded step to
  #   the corresponding slot of the yielded step.
  def mutate_each_step
    mutate_each_step_with_pct { |step, _| yield step }
  end

  # Functionally the same as mutate_each_step, except the block is called with
  # two arguments: the Step, and the percentage through the Track that the slot
  # the Step belongs to represents. For instance, Steps in the first slot of the
  # track will have percent 0, steps in the middle slot (in a Track with an odd
  # number of slots) will have percent 0.5, and steps in the final slot will
  # have percent 1.0.
  def mutate_each_step_with_pct
    new_grid = @grid.map.with_index do |slot, i|
      pct = i.to_f / (num_slots - 1)
      new_slot = []
      slot.each do |step|
        new_step = yield step, pct
        if NoteUtils.rest?(new_step)
          next
        elsif new_step.is_a?(Step)
          new_slot << new_step
        else
          new_slot.concat(new_step)
        end
      end

      new_slot
    end

    mutate(grid: new_grid)
  end

  def with_gate(new_gate)
    mutate_each_step { |step| step.with_gate(new_gate) }
  end

  alias gate with_gate

  def scale_gate(factor)
    mutate_each_step { |step| step.with_gate(step.gate * factor) }
  end

  # Returns a new track where each Step's gate is replaced with the result of
  # curve_func. curve_func will be called with one parameter, a percentage
  # through the track (0-1), and should return a floating point value 0-1 that
  # will be used for all Steps in the slot at that percentage.
  # TODO: add a library of useful curve functions for this
  def with_gate_curve(curve_func)
    raise "Curve function must be a callable that takes one argument" unless curve_func.respond_to?(:call) && curve_func.arity == 1
    mutate_each_step_with_pct { |step, pct| step.with_gate(curve_func.call(pct)) }
  end

  alias gate_curve with_gate_curve

  def with_vel(new_vel)
    mutate_each_step { |step| step.with_vel(new_vel) }
  end

  alias vel with_vel

  def scale_vel(factor)
    mutate_each_step { |step| step.with_vel(step.vel * factor) }
  end

  # Returns a new track where each Step's velocity is replaced with the result
  # of curve_func. curve_func will be called with one parameter, a percentage
  # through the track (0-1), and should return a velocity to use for all Steps
  # in the slot at that percentage. The value returned by curve_func should be
  # either:
  # - If zero_to_one is true, a floating point number 0 - 1 that will be scaled
  #   to a velocity value between 0 and 127, inclusive.
  # - If zero_to_one is false, an integer between 0 and 127, inclusive.
  def with_vel_curve(curve_func, zero_to_one: true)
    raise "Curve function must be a callable that takes one argument" unless curve_func.respond_to?(:call) && curve_func.arity == 1
    mutate_each_step_with_pct do |step, pct|
      vel = curve_func.call(pct)
      vel *= 127 if zero_to_one
      step.with_vel(vel)
    end
  end

  alias vel_curve with_vel_curve

  def with_octave(new_octave)
    mutate_each_step { |step| step.with_octave(new_octave) }
  end

  alias octave with_octave
  alias oct octave

  def shift_octave(shift)
    mutate_each_step { |step| step.shift_octave(shift) }
  end

  def up(octave_shift = 1)
    shift_octave(octave_shift)
  end

  def down(octave_shift = 1)
    shift_octave(-octave_shift)
  end

  # Return a new track that, with probability p, shifts the octave of each Step
  # by a random value in the given range. If range is an integer,
  # [-range, range] is used.
  def rand_octave(range = 1, p: 0.5)
    mutate_each_step do |step|
      next step unless $spi.rand < p

      # We've already decided to shift, so ignore random 0 values. Not using
      # rand_i here since it's exclusive. rand is too, but we're rounding.
      shift = 0
      while shift == 0
        if range.is_a?(Range)
          shift = $spi.rand(range).round
        else
          shift = $spi.rand(-range..range).round
        end
      end

      step.shift_octave(shift)
    end
  end

  alias roct rand_octave

  def shift_tone(shift)
    mutate_each_step { |step| step.shift_tone(shift) }
  end

  alias tone shift_tone
  alias transpose shift_tone

  def semi_up(tone_shift = 1)
    shift_tone(tone_shift)
  end

  alias sup semi_up

  def semi_down(tone_shift = 1)
    shift_tone(-tone_shift)
  end

  alias sdown semi_down

  # Return a new track by, for each Step, adding additional Steps with notes
  # that are the given number of semitones away from the original. offsets
  # should be an array of integer semitones. It defaults to [-12, 12] - i.e.,
  # an octave up and down. The new Steps share the velocity, gate, and
  # probability of the Step from which they were offset. If only is provided,
  # it should be a note (number, string, or symbol) or an array of notes, and
  # only steps with those notes will be harmonized.
  def harmonize(*offsets, only: nil)
    only = [only] unless only.nil? || only.is_a?(Array)
    offsets = [-12, 12] if offsets.empty?
    mutate_each_step do |step|
      new_steps = [step]
      if only.nil? || only.include?(step.note)
        offsets.each { |offset| new_steps << step.shift_tone(offset) }
      end
      new_steps
    end
  end

  # Return a new track in which each Step has its note snapped to the nearest
  # note among the given array, which should consist of MIDI note numbers or
  # symbols.
  def snap_to_notes(notes)
    mutate_each_step { |step| step.with_note(NoteUtils.snap(step.note, notes)) }
  end

  # Return a new track in which each Step has its note snapped to the nearest
  # note in the given scale starting at the given root note. root should be a
  # MIDI note number of symbol, and scale should be one of the scale names known
  # to Sonic Pi.
  def snap_to_scale(root, scale)
    mutate_each_step { |step| step.with_note(NoteUtils.snap_to_scale(step.note, root, scale)) }
  end

  # Returns a new track where each Step with note orig is replaced with a Step
  # that has note repl but is otherwise identical. If orig has an explicit
  # octave (or is a MIDI note number), only Steps with that exact note are
  # effected. If orig does not have an explicit octave, repl must not either. In
  # that case, all Steps with the same pitch class as orig have their notes
  # changed to repl, in the same octave as the original step. For instance,
  # sub_note(:c, :e) on a Track with steps [:c4, :d2, :c3] would result in a
  # track with steps [:e4, :d2, :e3].
  # repl may be nil, :r, or :rest to remove Steps that match orig.
  def sub_note(orig, repl)
    has_octave = NoteUtils.has_octave?(orig)
    repl_is_rest = NoteUtils.rest?(repl)
    if has_octave
      orig = NoteUtils.sym(orig)
    else
      if !repl_is_rest && NoteUtils.has_octave?(repl)
        raise "Replacement notes cannot have an octave if the origial note doesn't"
      end
      orig = NoteUtils.pitch_class(orig)
    end

    mutate_each_step do |step|
      if has_octave && step.note == orig
        repl_is_rest ? nil : step.with_note(repl)
      elsif !has_octave && NoteUtils.pitch_class(step.note) == orig
        repl_is_rest ? nil : step.with_note(NoteUtils.sym(repl, octave: step.octave))
      else
        step
      end
    end
  end


  protected

  # Does a deep dup of the grid, returning a version where the grid itself and
  # each slot is mutable.
  def mutable_grid_dup
    @grid.map { |slot| slot.dup }
  end


  private

  def initialize(grid:, granularity:, timescale:)
    # Do a deep frozen clone of grid, while making sure no slot has more than
    # one Step with the same note, and converting nils/rest symbols into empty
    # slots and integers/symbols into Steps. Freeze the whole thing recursively
    # so the version we expose through the attr_reader is immutable.
    @grid = grid.map.with_index do |slot, i|
      steps_by_note = {}
      slot.each do |step|
        next if NoteUtils.rest?(step)
        step = Step.new(step) unless step.is_a?(Step)

        old_step_with_same_note = steps_by_note[step.note]
        if old_step_with_same_note.nil?
          steps_by_note[step.note] = step
        else
          $spi.puts("warning: more than one Step with note #{step.note} in slot #{i}! Picking one with the longest gate!")
          steps_by_note[step.note] = step if old_step_with_same_note.gate < step.gate
        end
      end

      steps_by_note.values.freeze
    end
    @grid.freeze

    @granularity = NoteLength.normalize(granularity)
    @timescale = timescale
  end

  def mutate(mutations)
    mutations = mutations.dup
    [:grid, :granularity, :timescale].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Track.new(**mutations)
  end

  # TODO: do automatic granularity adjustment when possible?
  def assert_compatible_track(other_track)
    if @granularity != other_track.granularity
      raise "Granularity mismatch: #{@granularity} != #{other_track.granularity}"
    end

    if @timescale != other_track.timescale
      raise "Timescale mismatch: #{@timescale} != #{other_track.timescale}"
    end
  end
end


def use_player_defaults(midi:)
  $spi.set(:__player_defaults, { midi: midi })
end


# TODO: playhead direction - mostly just a matter of how we move the slot index
# in play, but also need to consider what "cycle" means in some of the weirder
# cases like a drunk walk.
# TODO: probably special-case Steps with a 0 gate
# TODO: swing?
class Player
  attr_reader :midi, :track, :cycle, :channel, :port

  def initialize(track, midi: nil, channel: nil, port: nil, debug: false)
    @track = track

    @midi = resolve_midi_arg(midi)
    @channel = channel
    @port = port
    @midi_spi_kwargs = {}
    @midi_spi_kwargs[:channel] = channel unless channel.nil?
    @midi_spi_kwargs[:port] = port unless port.nil?

    @debug = debug
    @active_synth_nodes = {}  # note symbols -> synth nodes. unused when playing midi
    @active_midi_notes = Set.new  # active midi note symbols. unused when playing built-in synths

    stop
  end

  def stop
    end_all_steps
    @prev_steps = nil
    @cycle = 0
  end

  # Plays one cycle of the track
  def play
    $spi.with_bpm_mul(@track.timescale) do
      @track.num_slots.times do |i|
        play_slot(i)

        # Sleep until it's time for the next slot
        $spi.sleep(@track.granularity.to_f)
      end
    end

    @cycle += 1
  end

  # Sleeps for the duration of the track. Cycle count and tie tracking are not
  # effected. All currently playing Steps are stopped.
  # TODO: do we want to increment cycle count here? kinda depends on what this
  # is philosophically - is it a muted play, or just a way to stall until we
  # start playing for the first time? if it's a muted play, it should just be an
  # argument to play. The only thing I can think of that would be screwed up is
  # Steps with a 'first' probability.
  def sleep
    end_all_steps
    $spi.with_bpm_mul(@track.timescale) do
      $spi.sleep(@track.beat_length)
    end
  end


  private

  def resolve_midi_arg(midi)
    defaults = $spi.get(:__player_defaults) || {}
    midi = defaults[:midi] || false if midi.nil?
    return midi
  end

  def play_slot(i)
    new_steps, tied_steps, ended_steps = @track.steps_at_slot(i, prev_steps: @prev_steps, cycle: @cycle)

    if @debug
      $spi.puts "@ slot=#{i} cycle=#{@cycle}"
      $spi.puts "new steps: #{new_steps}"
      $spi.puts "tied steps: #{tied_steps}"
      $spi.puts "ended steps: #{ended_steps}"
    end

    # Turn off or kill ended steps
    ended_steps.each { |step| end_step(step) }

    # Schedule ends for continued steps that end before the next slot.
    # Note that we don't need to do this for new steps - those are either:
    # - of some specific length less than the granularity (i.e., not tied), in
    #   which case we provide the length to the sustain or duration argument
    #   when playing the note; or
    # - tied, and so of indeterminant length since it may continue in the next
    #   played slot. In this case we start the note with an indefinite time
    #   (midi_note_on, e.g.), and terminate it (midi_note_off or kill) later
    #   when it either (a) ends at the beginning of a step (the end_step call
    #   above), or (b) ends between steps (i.e., a tie ending with a step with
    #   gate < 1.0), in which case we schedule its end at the appropriate time
    #   here.
    tied_steps.each do |step|
      schedule_end_for_step_with_partial_gate(step) unless step.tied?
    end

    # Start new steps
    new_steps.each { |step| start_step(step) }

    # Update prev_steps for the next round
    @prev_steps = tied_steps + new_steps
  end

  def end_step(step)
    # Stop the MIDI note or kill the synth node. Note that we may have already
    # ended the step if it didn't have a full gate, in which case it will not
    # be in active_midi_notes or active_synth_nodes. Do nothing in that case.
    if @midi
      $spi.midi_note_off(step.note, **@midi_spi_kwargs) unless @active_midi_notes.delete(step.note).nil?
    else
      node = @active_synth_nodes.delete(step.note)
      $spi.kill(node) if !node.nil?
    end
  end

  def schedule_end_for_step_with_partial_gate(step)
    $spi.time_warp(step.gate * @track.granularity.to_f) do
      $spi.puts "killing #{step.inspect} @ t=#{$spi.vt}" if @debug
      end_step(step)
    end
  end

  def end_all_steps
    if @midi
      @active_midi_notes.each { |n| $spi.midi_note_off(n, **@midi_spi_kwargs) }
      @active_midi_notes.clear
    else
      @active_synth_nodes.each { |_, node| $spi.kill(node) }
      @active_synth_nodes.clear
    end
  end

  def start_step(step)
    if step.tied?
      # Step has indeterminate duration; it may be continued in the next played
      # slot. Start it and we'll kill it later when it ends in play_slot.
      if @midi
        $spi.midi_note_on(step.note, velocity: step.vel, **@midi_spi_kwargs)
      else
        # TODO: there's no good way to just have a synth note go forever and
        # eventually gracefully kick it into release. Luckily I'm really only
        # using this for previewing stuff away from my real synth...
        # For now just having ties go for 100 * the length of the whole track.
        # Obviously that's ridiculous.
        node = $spi.play(step.note, duration: @track.beat_length * 100, attack: 0, decay: 0, release: 0)
      end
    else
      # Step has a known duration, so we can specify it now and don't have to
      # kill it later.
      if @midi
        $spi.midi(step.note, velocity: step.vel, sustain: step.gate * @track.granularity.to_f, **@midi_spi_kwargs)
      else
        # TODO: there's no real reason to keep track of these synth nodes,
        # right? They'll get cleaned up in play_slot, but also spuriously
        # killed. Probably not an issue?
        node = $spi.play(step.note, duration: step.gate * @track.granularity.to_f, attack: 0, decay: 0, release: 0)
      end
    end

    if @midi
      @active_midi_notes << step.note
    else
      @active_synth_nodes[step.note] = node
    end
  end
end


# Create a live_loop that plays the given track. Takes the same arguments as
# cc_mutable_live_loop, with the exception that cc may be nil (the default), in
# which case the live_loop is not mutable by CCs.
# The live_loop responds to muting by calling sleep on the track for muted
# iterations, rather than play.
# If send_cycle_cues is true, immediately before the live_loop plays a cycle of
# the track, it sends a cue with the name <loop_name>_cycle and a single value,
# the number of the cycle iteration that's about to play. Cycle cues are not
# sent while the track is muted.
# A block may be provided, in which case it is called before each cycle is
# played. The block may take 0 - 3 arguments, which are as follows:
# - 1st argument: muted - whether the track is currently muted
# - 2nd argument: the upcoming cycle number of the player
# - 3rd argument: the normal optional live_loop argument
# If the block returns a value, it is fed back in the next iteration as the
# third argument.
# Note that the internal block that plays the track will sleep, so a user-
# provided block does not need to sleep or sync, unlike normal live_loop blocks.
# If it does sync or sleep, it may cause delays between cycles of the track.
def track_live_loop(loop_name, track, start_muted: false, midi: nil, player_port: nil, player_channel: nil, cc: nil, cc_port: nil, cc_channel: nil, send_cycle_cues: true, debug: false, **kwargs, &block)
  raise "Block must take 0 - 3 arguments" if !block.nil? && block.arity > 3

  player = Player.new(track, midi: midi, debug: debug, port: player_port, channel: player_channel)
  cycle_cue_sym = (loop_name.to_s + "_cycle").to_sym

  wrapped_block = lambda do |muted, arg|
    res = nil
    unless block.nil?
      if block.arity == 3
        res = block.call(muted, player.cycle, arg)
      elsif block.arity == 2
        block.call(muted, player.cycle)
      elsif block.arity == 1
        block.call(muted)
      else
        block.call
      end
    end

    if muted
      player.sleep
    else
      $spi.cue(cycle_cue_sym, player.cycle) if send_cycle_cues
      player.play
    end

    res
  end

  if cc.nil?
    mutable_live_loop(loop_name, start_muted: start_muted, **kwargs, &wrapped_block)
  else
    cc_mutable_live_loop(loop_name, start_muted: start_muted, cc: cc, port: cc_port, channel: cc_channel, **kwargs, &wrapped_block)
  end
end
