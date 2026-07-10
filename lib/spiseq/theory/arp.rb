# frozen_string_literal: true

require_relative "midinote"
require_relative "../internal/enumerables"

module SpiSeq; module Theory
  # A simple arpeggiator. See {.arpeggiate} for details.
  module Arp
    # The actual arpeggiation functions. Passed an array of MIDINotes, which
    # they may alter. Spread and octave additions have already been applied.
    # `arpeggiate` calls these via name lookup in ARPEGGIATORS.
    # @private
    module Arpeggiators
      # Names (as passed to `arpeggiate`) to methods.
      ALIASES = {
        %i[up]                                   => :up,
        %i[down]                                 => :down,
        %i[updown up_down]                       => :up_down,
        %i[twouptwodown two_up_two_down
           2up2down doubleupdown double_up_down] => :two_up_two_down,
        %i[alternin altern_in in]                => :altern_in,
        %i[alternout altern_out out]             => :altern_out,
        %i[alterninout altern_in_out inout]      => :altern_in_out,
        %i[pinky]                                => :pinky,
        %i[thumb]                                => :thumb,
        %i[peak]                                 => :peak,
        %i[valley]                               => :valley,
        %i[random rand rnd shuffle]              => :random,
        %i[order]                                => :order
      }.flat_map do |names, meth|
        names.map { |name| [name, meth] }
      end.to_h.freeze

      module_function def up(notes)
        notes.sort!
      end

      module_function def down(notes)
        notes.sort! { |a, b| b <=> a }
      end

      module_function def up_down(notes)
        notes.sort!
        notes += notes.reverse.drop(1)  # don't repeat the middle note
        notes.pop  # cycle cleanly without repeating the final note either
        notes
      end

      module_function def two_up_two_down(notes)
        up_down(notes).flat_map { |n| [n, n] }
      end

      module_function def altern_in(notes)
        # Work in toward the center from the edges, alternating low and high
        # notes, starting each alternation with the low note.
        # 0 1 2 3 4 5 -> 0 5 1 4 2 3
        # 0 1 2 3 4 -> 0 4 1 3 2
        # 0 1 2 3 -> 0 3 1 2
        # 0 1 2 -> 0 2 1
        # 0 1 -> 0 1
        length = notes.length
        return notes if length <= 1

        notes.sort!

        low_idx = 0
        high_idx = length - 1
        res = []
        while low_idx <= high_idx
          res << notes[low_idx]
          break if low_idx == high_idx
          res << notes[high_idx]
          low_idx += 1
          high_idx -= 1
        end

        res
      end

      module_function def altern_out(notes)
        # Work outward from the center (rounding up when even-length),
        # alternating low and high notes, starting each alternation with the
        # lower note.
        # 0 1 2 3 4 5 -> 3 2 4 1 5 0
        # 0 1 2 3 4 -> 2 1 3 0 4
        # 0 1 2 3 -> 2 1 3 0
        # 0 1 2 -> 1 0 2
        # 0 1 -> 1 0
        length = notes.length
        return notes if length <= 1

        notes.sort!

        center_idx = length.odd? ? (length - 1) / 2 : length / 2
        res = [notes[center_idx]]
        low_idx = center_idx - 1
        high_idx = center_idx + 1
        while low_idx >= 0 || high_idx < length
          res << notes[low_idx] if low_idx >= 0
          res << notes[high_idx] if high_idx < length
          low_idx -= 1
          high_idx += 1
        end

        res
      end

      module_function def altern_in_out(notes)
        # In, then out, but not repeating the middle or final note
        res = altern_in(notes) + altern_out(notes).drop(1)
        res.pop if res.length > 1 && res[0] == res[-1]  # cycle cleanly
        res
      end

      module_function def pinky(notes)
        # play the highest note after each (but don't double at end)
        notes.sort!
        highest = notes.pop
        notes.flat_map { |n| [n, highest] }
      end

      module_function def thumb(notes)
        # play the lowest note after each (but don't double at beginning)
        notes.sort!
        lowest = notes.shift
        notes.flat_map { |n| [n, lowest] }
      end

      module_function def peak(notes)
        # Climb up to the maximum with even indexes, then descend with the odds.
        length = notes.length
        return notes if length <= 1

        notes.sort!

        rising = []
        falling = []
        0.upto(length - 1) do |i|
          if i.even?
            rising << notes[i]
          else
            falling.unshift(notes[i])
          end
        end

        rising + falling
      end

      module_function def valley(notes)
        # Descend from the maximum then ascend, with alternating indexes going
        # into the descension and ascension.
        length = notes.length
        return notes if length <= 1

        notes.sort!

        falling = []
        rising = []
        (length - 1).downto(0) do |i|
          if length.even?
            if i.odd?
              falling << notes[i]
            else
              rising.unshift(notes[i])
            end
          elsif i.odd?
            rising.unshift(notes[i])
          else
            falling << notes[i]
          end
        end

        falling + rising
      end

      module_function def random(notes)
        notes.shuffle!
      end

      module_function def order(notes)
        notes
      end
    end
    private_constant :Arpeggiators

    # All arpeggiation directions supported by {.arpeggiate}.
    #
    # Valid directions are:
    #
    # `:up` returns notes in increasing order.
    #
    #   arp([:c4, :e4, :d4], :up)
    #   # returns [:c4, :d4, :e4]
    #
    # `:down` returns notes in decreasing order.
    #
    #   arp([:c4, :e4, :d4], :down)
    #   # returns [:e4, :d4, :c4]
    #
    # `:updown` returns notes in increasing order, then in reverse. The middle
    # note is not repeated, nor is the final note.
    #
    #   arp([:c4, :e4, :d4], :updown)
    #   # returns [:c4, :d4, :e4, :d4]
    #
    # `:twouptwodown` returns notes in the same order as `:updown`, but with
    # each note doubled. The middle note is not repeated, nor is the final note.
    #
    #   arp([:c4, :e4, :d4], :twouptwodown)
    #   # returns [:c4, :c4, :d4, :d4, :e4, :e4, :d4, :d4]
    #
    # `:alternin` returns notes in alternating order, working inward from
    # opposite edges of the input.
    #
    #   arp([:a1, :b2, :c3, :d4, :e5], :alternin)
    #   # returns [:a1, :e5, :b2, :d4, :c3]
    #
    # `:alternout` returns notes in alternating order, working outward from the
    # middle of the input.
    #
    #   arp([:a1, :b2, :c3, :d4, :e5], :alternout)
    #   # returns [:c3, :b2, :d4, :a1, :e5]
    #
    # `:alterninout` returns notes in alternating order, first inward like
    # `:alternin`, then outward like `:alternout`, but not repeating the middle
    # note.
    #
    #   arp([:a1, :b2, :c3, :d4, :e5], :alterninout)
    #   # returns [:a1, :e5, :b2, :d4, :c3, :b2, :d4, :a1, :e5]
    #
    # `:peak` returns notes in an order that climbs to the highest note and then
    # descends. The notes are sorted ascending, then every other note is chosen
    # to walk toward the highest note, then the remaining notes appear in
    # descending order.
    #
    #   arp([:c1, :c3, :c2, :c4, :c5], :peak)
    #   # returns [:c1, :c3, :c5, :c4, :c2]
    #
    # `:valley` returns notes in an order that descends from the highest note
    # and then ascends. The highest note appears first, then every other note
    # descending to the lowest, then the remaining notes in ascending order.
    #
    #   arp([:c1, :c3, :c2, :c4, :c5], :valley)
    #   # returns [:c5, :c3, :c1, :c2, :c4]
    #
    # `:pinky` returns notes in ascending order, but with the highest note in
    # every other position. The high note is not doubled at the end.
    #
    #   arp([:c4, :e4, :d4, :c5], :pinky)
    #   # returns [:c4, :c5, :d4, :c5, :e4, :c5]
    #
    # `:thumb` returns notes in ascending order, but with the lowest note in
    # every other position. The low note is not doubled at the beginning.
    #
    #   arp([:c4, :e4, :d4, :c5], :thumb)
    #   # returns [:d4, :c4, :e4, :c4, :c5, :c4]
    #
    # `:random` returns notes in a random order.
    #
    # `:order` does not reorder notes; they will be returned as passed to
    # {.arpeggiate}. This is not particularly useful on its own, but may be
    # together with `spread` or `extra_octaves`, which add extra notes to the
    # input.
    #
    # There are aliases for many of the above names; print this array to see all
    # possible values.
    #
    # @return [Array<Symbol>]
    ARP_DIRECTIONS = Arpeggiators::ALIASES.keys.freeze


    # Returns an array of {MIDINote}s by arpeggiating the given array of notes.
    # See {DIRECTIONS} for details on the possible values for `direction`.
    #
    # If `spread` is > 0, the result will have a note added an octave above each
    # of the the `spread` lowest notes. If this operation creates duplicate
    # notes (e.g. `spread`=1 with `[:e3, :e4]`, which would result in two E4s),
    # the duplicates will not be added to the result. In the `:order` direction,
    # the notes from the `spread` will appear at the end, in order from lowest
    # to highest.
    #
    # If `extra_octaves` is specified, the result will contain copies of the
    # notes in the `notes` array shifted by each offset in `extra_octaves`. This
    # addition applies before any `spread`. If the direction is `:order`, notes
    # added this way will appear at the end of the result, before notes from the
    # `spread`. Like `spread`, `extra_octaves` will not add duplicate notes.
    #
    # This method is aliased to {Theory.arp} for convenience.
    #
    # @example
    #   arp([:a1, :b1], :down, extra_octaves: [-1, 2])
    #   # The notes from [:a1, :b1], shifted down an octave and up 2 octaves,
    #   # are added before applying the direction :down
    #   # returns [:b3, :a3, :b1, :a1, :b0, :a0]
    #
    # @example
    #   arp([:b1, :a1, :c1, :d1], :up, spread: 3)
    #   # Before applying the direction :up, the three lowest notes
    #   # (:c1, :d1, :a1) are added to the pool, shifted up an octave.
    #   # returns [:c1, :d1, :a1, :b1, :c2, :d2, :a2]
    #
    # @param notes [Array<MIDINote, Symbol, String, Integer>] The notes to
    #   arpeggiate; an array of {MIDINote}s or any value accepted by
    #   {MIDINote.new}.
    # @param direction [Symbol, String] One of the direction names defined in
    #   {DIRECTIONS}, e.g. `:pinky` or `:updown`.
    # @param spread [Integer] Adds notes an octave above some number of the
    #   lowest notes in the result. See above for details.
    # @param extra_octaves [Array<Integer>] Adds a copy of the incoming notes
    #   shifted by some number of octaves before arpeggiating. See above for
    #   details.
    # @return [Array<MIDINote>] The arpeggiated notes.
    # @see Tracks::Track.arp
    module_function def arpeggiate(notes, direction, spread: 0, extra_octaves: [])
      arp_method_name = Arpeggiators::ALIASES[direction.to_sym]
      raise ArgumentError, "unknown arpeggiator direction #{direction}" if arp_method_name.nil?
      arpeggiator = Arpeggiators.method(arp_method_name)

      # See the note in enumerable? about arrayify.
      notes = Internal::Enumerables.arrayify(notes).map { |n| MIDINote.new(n) }
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

      arpeggiator.call(notes)
    end
  end

  # @!group Music theory

  # (see Arp.arpeggiate)
  # An alias for {Arp.arpeggiate}.
  module_function def arp(notes, direction, spread: 0, extra_octaves: [])
    Arp.arpeggiate(notes, direction, spread:, extra_octaves:)
  end
end; end
