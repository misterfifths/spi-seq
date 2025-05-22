# frozen_string_literal: true

require_relative "extapi"
require_relative "trackbase"
require_relative "ccstep"
require_relative "theory/midinote"  # Only for `rest?`


# An alias for `CCTrack.new`.
def CCT(*args, **kwargs)
  CCTrack.new(*args, **kwargs)
end


# A CCTrack deals with a grid whose slots contain CCSteps. CCStep instances
# represent MIDI CC events, consisting of a CC number and a value. See the
# TrackBase documentation for details on grids, slots, and the basic inherited
# functionality.
class CCTrack < TrackBase
  ### Track construction helpers

  # Attempts to convert its argument to a CCStep. Conversion rules are:
  # - CCSteps are passed through verbatim.
  # - It is an error to pass a rest (as defined by `MIDINote.rest?`) to this
  #   function.
  def self.stepify(x)
    raise "A rest cannot be converted to a step" if MIDINote.rest?(x)

    case x
    when CCStep
      x
    else
      raise "Not a valid value for a CCStep: #{x.inspect}"
    end
  end

  # Given a slot (an array of CCSteps), returns a new slot with at most one
  # CCStep for each CC number. If multiple CCSteps in the input have the same
  # CC number, one with the highest `value` is chosen.
  def self.dedupe_slot(slot)
    steps_by_cc = {}
    yelled = false
    slot.each do |step|
      old_step_with_same_cc = steps_by_cc[step.cc]
      if old_step_with_same_cc.nil?
        steps_by_cc[step.cc] = step
      else
        unless yelled
          ExtApi.puts("warning: more than one step with CC #{step.cc} in the same slot! Picking one with the highest value!")
          yelled = true
        end
        steps_by_cc[step.cc] = step if old_step_with_same_cc.value < step.value
      end
    end

    steps_by_cc.values
  end

  private_class_method :dedupe_slot

  # Attempts to convert its argument to a grid slot (i.e. an array of CCSteps).
  # The returned array will be frozen. Conversion rules:
  # - Rests (see `MIDINote.rest?`) become an empty slot ([]).
  # - Single CCSteps become a slot containing just that CCStep.
  # - Array-like arguments are converted as follows:
  #   1. All rests are removed.
  #   2. All remaining elements are passed through `stepify`.
  #   3. If more than one of the resulting CCSteps has the same CC number, a
  #      warning is printed, and only the CCStep with the highest value is
  #      chosen.
  def self.slotify(x)
    return [].freeze if MIDINote.rest?(x)

    case x
    when CCStep
      [x].freeze
    # See the note in Track.slotify about these class selections.
    when ::Enumerable, SonicPi::Core::SPVector
      raw_slot = x.to_a.reject { |s| MIDINote.rest?(s) }.map { |s| stepify(s) }
      dedupe_slot(raw_slot).freeze
    else
      raise "Not a valid value for a slot: #{x.inspect}"
    end
  end

  # Attempts to convert its argument to a grid (a 2d array of CCSteps). The
  # returned array and all of its elements will be frozen. Conversion rules:
  # - A single rest (see `MIDINote.rest?`) becomes a grid with one rest ([[]]).
  # - A single CCStep becomes a grid with one slot containing that CCStep.
  # - Array-like arguments are converted by passing each element through
  #   `slotify`.
  def self.gridify(x)
    return [[].freeze].freeze if MIDINote.rest?(x)

    case x
    when CCStep
      [[x].freeze].freeze
    # See the note in Track.slotify about these class selections.
    when ::Enumerable, SonicPi::Core::SPVector
      x.to_a.map { |s| slotify(s) }.freeze
    else
      raise "Not a valid value for a grid: #{x.inspect}"
    end
  end
end
