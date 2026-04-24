# frozen_string_literal: true

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
  Peak = :peak
  Valley = :valley
  Random = :random
  Order = :order

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
  # applies before any spread. If direction is :order, notes it adds will appear
  # at the end of the result, before notes from the spread. Like spread,
  # extra_octaves will not add duplicate notes.
  def self.arpeggiate(notes, direction, spread: 0, extra_octaves: [])
    return [] if notes.empty?

    # NOTE: notes might be a Sonic Pi ring, which doesn't have everything from
    # Enumerable, so we need to call `to_a` on it. But it gets weirder - the
    # objects returned by `chord` are really tricky. It returns a ring wrapping
    # a SonicPi::Chord. Calling to_a on that ring just unwraps and returns the
    # Chord object. Chords are technically subclasses of Array, but they're
    # kind of broken - in-place mutations like `map!` and `sort!` don't modify
    # them! So we explicitly call to_a twice here.
    notes = notes.to_a.to_a.dup.map! { |n| MIDINote.new(n) }  # rubocop:disable Lint/RedundantTypeConversion
    orig_notes = notes.dup

    # TODO: where should this apply in relation to spread?
    extra_octaves.each do |octave_shift|
      orig_notes.each do |n|
        new_note = n.up(octave_shift)
        notes << new_note unless notes.include?(new_note)
      end
    end

    if spread > 0
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
    when Arp::Peak, Arp::Valley
      notes.sort!
      notes = notes.values_at(*peak_indexes(notes.length, direction))
    when Arp::Random
      notes.shuffle!
    when Arp::Order
      # nothing to do
    else
      raise "Unknown arpeggiator direction #{direction}"
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
      # TODO: drop the last note when it would repeat in a loop?
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

def arp(*args, **kwargs)
  Arp.arpeggiate(*args, **kwargs)
end
