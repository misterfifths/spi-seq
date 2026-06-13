# frozen_string_literal: true

require_relative "midinote"

# @!group Music theory
# An alias for {Arp.arpeggiate}.
# @return [Array<MIDINote>]
def arp(*args, **kwargs)
  Arp.arpeggiate(*args, **kwargs)
end
# @!endgroup

# A simple arpeggiator. See {.arpeggiate} for details.
module Arp
  # An arpeggiation direction that returns notes in increasing order. For
  # example:
  #   arp([:c4, :e4, :d4], :up)
  #   # returns [:c4, :d4, :e4]
  Up = :up

  # An arpeggiation direction that returns notes in decreasing order. For
  # example:
  #   arp([:c4, :e4, :d4], :down)
  #   # returns [:e4, :d4, :c4]
  Down = :down

  # An arpeggiation direction that returns notes in increasing order, then in
  # reverse. The middle note is not repeated, nor is the final note. For
  # example:
  #   arp([:c4, :e4, :d4], :updown)
  #   # returns [:c4, :d4, :e4, :d4]
  UpDown = :updown

  # An arpeggiation direction that returns notes in the same order as {.UpDown},
  # but with each note doubled. The middle note is not repeated, nor is the
  # final note. For example:
  #   arp([:c4, :e4, :d4], :twouptwodown)
  #   # returns [:c4, :c4, :d4, :d4, :e4, :e4, :d4, :d4]
  TwoUpTwoDown = :twouptwodown

  # An arpeggiation direction that returns notes in alternating order, working
  # inward from opposite edges of the input. For example:
  #   arp([:a1, :b2, :c3, :d4, :e5], :alternin)
  #   # returns [:a1, :e5, :b2, :d4, :c3]
  AlternIn = :alternin

  # An arpeggiation direction that returns notes in alternating order, working
  # outward from the middle of the input. For example:
  #   arp([:a1, :b2, :c3, :d4, :e5], :alternout)
  #   # returns [:c3, :b2, :d4, :a1, :e5]
  AlternOut = :alternout

  # An arpeggiation direction that returns notes in alternating order, first
  # inward like {.AlternIn}, then outward like {.AlternOut}, but not repeating
  # the middle note. For example:
  #   arp([:a1, :b2, :c3, :d4, :e5], :alterninout)
  #   # returns [:a1, :e5, :b2, :d4, :c3, :b2, :d4, :a1, :e5]
  AlternInOut = :alterninout

  # An arpeggiation direction that returns notes in ascending order, but with
  # the highest note in every other position. The high note is not doubled at
  # the end. For example:
  #   arp([:c4, :e4, :d4, :c5], :pinky)
  #   # returns [:c4, :c5, :d4, :c5, :e4, :c5]
  Pinky = :pinky

  # An arpeggiation direction that returns notes in ascending order, but with
  # the lowest note in every other position. The low note is not doubled at the
  # beginning. For example:
  #   arp([:c4, :e4, :d4, :c5], :thumb)
  #   # returns [:d4, :c4, :e4, :c4, :c5, :c4]
  Thumb = :thumb

  # An arpeggiation direction that returns notes in an order that climbs to the
  # highest note and then descends. The notes are sorted ascending, then every
  # other note is chosen to walk toward the highest note, then the remaining
  # notes appear in descending order. For example:
  #   arp([:c1, :c3, :c2, :c4, :c5], :peak)
  #   # returns [:c1, :c3, :c5, :c4, :c2]
  Peak = :peak

  # An arpeggiation direction that returns notes in an order that descends from
  # the highest note and then ascends. The highest note appears first, then
  # every other note descending to the lowest, then the remaining notes in
  # ascending order. For example:
  #   arp([:c1, :c3, :c2, :c4, :c5], :valley)
  #   # returns [:c5, :c3, :c1, :c2, :c4]
  Valley = :valley

  # An arpeggiation direction that returns notes in a random order.
  Random = :random

  # An arpeggiation direction that does not reorder notes; they will be
  # returned as passed to {.arpeggiate}. This is not particularly useful on its
  # own, but may be together with `spread` or `extra_octaves`, which add extra
  # notes to the input.
  Order = :order

  # Returns an array of {MIDINote}s by arpeggiating the given array of notes.
  # See the documentation on the constants in this class for details on the
  # possible `direction`s.
  #
  # This method is aliased to {arp} for convenience.
  #
  # If `spread` is > 0, the result will have a note added an octave above each
  # of the the `spread` lowest notes. If this operation creates duplicate notes
  # (e.g. `spread`=1 with `[:e3, :e4]`, which would result in two E4s), the
  # duplicates will not be added to the result. In the {.Order :order}
  # direction, the notes from the `spread` will appear at the end, in order from
  # lowest to highest.
  #
  # If `extra_octaves` is specified, the result will contain copies of the notes
  # in the `notes` array shifted by each offset in `extra_octaves`. This
  # addition applies before any `spread`. If the direction is {.Order :order},
  # notes added this way will appear at the end of the result, before notes from
  # the `spread`. Like `spread`, `extra_octaves` will not add duplicate notes.
  #
  # @example
  #   arp([:a1, :b1], :down, extra_octaves: [-1, 2])
  #   # The notes from [:a1, :b1], shifted down an octave and up 2 octaves,
  #   # are added before applying the direction Arp::Down
  #   # returns [:b3, :a3, :b1, :a1, :b0, :a0]
  #
  # @example
  #   arp([:b1, :a1, :c1, :d1], :up, spread: 3)
  #   # Before applying the direction Arp::Up, the three lowest notes
  #   # (:c1, :d1, :a1) are added to the pool, shifted up an octave.
  #   # returns [:c1, :d1, :a1, :b1, :c2, :d2, :a2]
  #
  # @param notes [Array<MIDINote, Symbol, String, Integer>] The notes to
  #   arpeggiate; an array of {MIDINote}s or any value accepted by
  #   {MIDINote.new}.
  # @param direction [Symbol] One of the direction symbols defined on Arp, e.g.
  #   {.Pinky :pinky} or {.UpDown :updown}. You can pass the symbol directly
  #   rather than referencing the constant on this module.
  # @param spread [Integer] Adds notes an octave above some number of the lowest
  #   notes in the result. See above for details.
  # @param extra_octaves [Array<Integer>] Adds a copy of the incoming notes
  #   shifted by some number of octaves before arpeggiating. See above for
  #   details.
  # @return [Array<MIDINote>] The arpeggiated notes.
  # @see Track.arp
  def self.arpeggiate(notes, direction, spread: 0, extra_octaves: [])
    # See the note in SpiSeq::Utils.enumerable? about arrayify.
    notes = SpiSeq::Utils.arrayify(notes).map { |n| MIDINote.new(n) }
    return [] if notes.empty?

    orig_notes = notes.dup

    extra_octaves.each do |octave_shift|
      orig_notes.each do |n|
        new_note = n.up(octave_shift)
        notes << new_note unless notes.include?(new_note)
      end
    end

    if spread > 0
      # Take at most spread lowest notes and add a note an octave up. Do not
      # duplicate notes, and do not effect the sorting of the original array.
      # Notes added from spread go at the end, in case we're playing in order.
      # Notes added from a spread are eligible to be spread themselves.
      sorted_notes = notes.sort
      i = 0
      while spread > 0 && i < sorted_notes.length
        new_note = sorted_notes[i].up
        i += 1
        next if notes.include?(new_note)

        notes << new_note
        sorted_notes << new_note
        sorted_notes.sort!
        spread -= 1
      end
    end

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
      notes.pop if notes.length > 1 && notes[0] == notes[-1]  # cycle cleanly
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
    when Arp::Peak, Arp::Valley
      notes.sort!
      notes = notes.values_at(*peak_indexes(notes.length, direction))
    when Arp::Random
      notes.shuffle!
    when Arp::Order
      # nothing to do
    else
      raise ArgumentError, "Unknown arpeggiator direction #{direction}"
    end

    notes
  end


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

      idxs
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

      idxs
    when Arp::AlternInOut
      in_idxs = altern_indexes(length, Arp::AlternIn)
      out_idxs = altern_indexes(length, Arp::AlternOut)
      in_idxs + out_idxs.drop(1)
    end
  end

  private_class_method :altern_indexes

  def self.peak_indexes(length, direction)
    return [] if length == 0
    return [0] if length == 1

    case direction
    when Arp::Peak
      # Climb up to the maximum with even indexes, then descend with the odds.
      rising_idxs = []
      falling_idxs = []
      0.upto(length - 1) do |i|
        if i.even?
          rising_idxs << i
        else
          falling_idxs << i
        end
      end

      rising_idxs + falling_idxs.reverse
    when Arp::Valley
      # Descend from the maximum then ascend, with alternating indexes going
      # into the descension and ascension.
      falling_idxs = []
      rising_idxs = []
      (length - 1).downto(0) do |i|
        if length.even?
          if i.odd?
            falling_idxs << i
          else
            rising_idxs << i
          end
        elsif i.odd?
          rising_idxs << i
        else
          falling_idxs << i
        end
      end

      falling_idxs + rising_idxs.reverse
    end
  end

  private_class_method :peak_indexes
end
