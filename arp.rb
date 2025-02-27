require_relative "midinote"

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

  # Returns an array of MIDINotes by arpeggiating the given array of notes.
  # direction should be one of the constants in the Arp module.
  # If spread is n > 0, the result will have a note added an octave above each
  # of the the n lowest notes. If the spread creates duplicate notes (e.g.
  # spread=1 with [:e3, :e4], which would result in two :e4s), the duplicates
  # will not be added to the result. If an arp with a spread > 0 is played in
  # Arp::Order direction, the notes from the spread will appear at the end, in
  # order from lowest to highest.
  # If extra_octaves is specified, the result will contain copies of the notes
  # in the notes array shifted by each offset in extra_octaves. extra_octaves
  # applies before any spread. Notes it adds will appear at the end of the
  # result, before notes from the spread.
  def self.arpeggiate(notes, direction, spread: 0, extra_octaves: [])
    orig_notes = notes
    # NOTE: notes might be a Sonic Pi ring, which doesn't have everything from
    # Enumerable, so we need to call `to_a` on it. But it gets weirder - the
    # objects returned by `chord` are really tricky. It returns a ring wrapping
    # a SonicPi::Chord. Calling to_a on that ring just unwraps and returns the
    # Chord object. Chords are technically subclasses of Array, but they're
    # kind of broken - in-place mutations like `map!` and `sort!` don't modify
    # them! So we explicitly call to_a twice here.
    notes = notes.to_a.to_a.dup.map! { |n| MIDINote.new(n) }

    # TODO: where should this apply in relation to spread?
    extra_octaves.each do |octave_shift|
      orig_notes.each do |n|
        notes << n.up(octave_shift)
      end
    end

    if spread > 0 && notes.length > 0
      # take the spread lowest notes and add a note an octave up. do not
      # duplicate notes, and do not effect the sorting of the original array.
      # notes added from spread go at the end, in case we're playing in order.
      sorted_notes = notes.sort
      # TODO: spread should take into account notes added from itself
      spread = [spread, sorted_notes.length].min
      spread.times do |i|
        new_note = sorted_notes[i].up
        notes << new_note unless notes.include?(new_note)
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
    when Arp::Order
      # nothing to do
    else
      raise "Unknown arpeggiator direction #{direction}"
    end

    notes
  end

  # Arpeggiate the given degrees of the tonic note in the given scale.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, spread: 0, extra_octaves: [])
    notes = degrees.map { |d| ExtApi.degree(d, tonic, scale) }
    arpeggiate(notes, direction, spread: spread, extra_octaves: extra_octaves)
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

  private_class_method :altern_indexes
end

def arp(*args, **kwargs)
  Arp.arpeggiate(*args, **kwargs)
end
