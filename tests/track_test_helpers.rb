# frozen_string_literal: true

module TrackTestHelpers
  def equal_steps?(step, stepish)
    if stepish.is_a?(Step)
      return false unless step.note == stepish.note
      return false unless step.gate == stepish.gate
      return false unless step.vel == stepish.vel
      return false unless step.prob.equal?(stepish.prob)
    else  # something MIDINote-ish
      return false unless step.note == stepish
      return false unless step.tied?
      return false unless step.vel == 127
      return false unless step.prob.nil?
    end

    true
  end

  def assert_grid(track, slots)
    assert_equal track.length, slots.length

    track.grid.each_with_index do |slot, slot_idx|
      target_slot = slots[slot_idx]
      assert_equal slot.length, target_slot.length

      # Step order is not significant and may be changed by the initializer, so
      # we need to check each target step against all steps in the track's slot.
      candidates = slot.dup
      target_slot.each_with_index do |step, i|
        winning_idx = candidates.index { |candstep| equal_steps?(candstep, step) }
        refute_nil winning_idx, "no Step in slot #{i} matched #{step.inspect}"
        candidates.delete_at(winning_idx)
      end
    end
  end

  def assert_gt(track, granularity, timescale)
    assert_equal track.granularity, granularity
    assert_equal track.timescale, timescale
  end
end
