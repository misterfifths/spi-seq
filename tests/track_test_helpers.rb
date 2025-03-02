# frozen_string_literal: true

module TrackTestHelpers
  def equal_steps?(step, stepish)
    if stepish.is_a?(Step)
      return step.note == stepish.note &&
             step.gate == stepish.gate &&
             step.vel == stepish.vel &&
             step.prob.equal?(stepish.prob)
    end

    # something MIDINote-ish
    step.note == stepish &&
      step.tied? &&
      step.vel == 127 &&
      step.prob.nil?
  end

  def assert_grid(track, slots)
    assert_equal track.length, slots.length, "grid length mismatch between #{track.repr} and #{slots.inspect}"

    track.grid.each_with_index do |slot, slot_idx|
      target_slot = slots[slot_idx]
      assert_equal slot.length, target_slot.length, "slot #{slot_idx} length mismatch: expected #{slot.inspect}, got #{target_slot.inspect}, track: #{track.repr}"

      # Step order is not significant and may be changed by the initializer, so
      # we need to check each target step against all steps in the track's slot.
      candidates = slot.dup
      target_slot.each do |step|
        winning_idx = candidates.index { |candstep| equal_steps?(candstep, step) }
        refute_nil winning_idx, "no Step in slot #{slot_idx} matched #{step.inspect}, track: #{track.repr}"
        candidates.delete_at(winning_idx)
      end
    end
  end

  def assert_gt(track, granularity, timescale)
    assert_equal track.granularity, granularity
    assert_equal track.timescale, timescale
  end
end
