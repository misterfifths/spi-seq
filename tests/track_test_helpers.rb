# frozen_string_literal: true

module TrackTestHelpers
  def equal_steps?(step, stepish, tol = 0.01)
    if stepish.is_a?(Step)
      return step.note == stepish.note &&
             ((step.gate - stepish.gate).abs < tol) &&
             step.vel == stepish.vel &&
             step.prob.to_s == stepish.prob.to_s  # TODO: this is a crappy way to test Prob equality
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

  def with_strict_merging
    use_track_defaults(strict_track_merging: true)
    yield
    use_track_defaults(strict_track_merging: false)
  end

  # Checks that, when `method` is called on a track and passed another track
  # with a different granularity and/or timescale, the correct behavior occurs.
  # Namely, the operation should only succeed when strict track merging is off,
  # and the result should have the granularity and timescale of the first track.
  # This method does not check the grid of the returned track; it only checks
  # for a correct granularity and timescale.
  def assert_merge_strictness(method, *args, **kwargs)
    t8_1 = T(:c1)
    t8_2 = T(:c2, timescale: 2)
    t16_1 = T(:c3, granularity: :sixteenth)
    t32_2 = T(:c4, granularity: :sixteenth, timescale: 2)

    # Strict merging is off by default. The result should have the granularity
    # and timescale of the receiver.
    assert_gt t8_1.send(method, t8_2, *args, **kwargs), NoteLength::Eighth, 1
    assert_gt t8_1.send(method, t16_1, *args, **kwargs), NoteLength::Eighth, 1
    assert_gt t16_1.send(method, t8_1, *args, **kwargs), NoteLength::Sixteenth, 1
    assert_gt t8_2.send(method, t16_1, *args, **kwargs), NoteLength::Eighth, 2
    assert_gt t16_1.send(method, t32_2, *args, **kwargs), NoteLength::Sixteenth, 1

    # Under strict merging, these should all fail.
    with_strict_merging do
      assert_raises { t8_1.send(method, t8_2, *args, **kwargs) }
      assert_raises { t8_1.send(method, t16_1, *args, **kwargs) }
      assert_raises { t8_2.send(method, t16_1, *args, **kwargs) }
      assert_raises { t16_1.send(method, t32_2, *args, **kwargs) }
    end
  end
end
