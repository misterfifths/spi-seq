# frozen_string_literal: true

require_relative "../../lib/spiseq/internal/utils"
require_relative "../../lib/spiseq/theory/notelength"
require_relative "../../lib/spiseq/theory/scale"
require_relative "../../lib/spiseq/tracks"

module TrackHelpers
  def assert_grid(track, slots)
    assert_equal track.length, slots.length, "grid length mismatch between #{track.repr} and #{slots.inspect}"

    i = 0
    track.grid.zip(slots) do |actual_slot, expected_slotish|
      assert_equal expected_slotish.length, actual_slot.length, "slot #{i} length mismatch: expected #{expected_slotish.inspect}, got #{actual_slot.inspect}, track: #{track.repr}"
      expected_slotish.each do |stepish|
        step = stepish.is_a?(SpiSeq::Tracks::Step) ? stepish : SpiSeq::Tracks::Step.new(stepish)
        assert actual_slot.include?(step), "no Step in slot #{i} matched #{step.inspect}, track: #{track.repr}"
      end
      i += 1
    end
  end

  def assert_gt(track, granularity, timescale, scale: nil)
    granularity = SpiSeq::Theory::NoteLength.new(granularity)
    assert_equal track.granularity, granularity
    assert_equal track.timescale, timescale

    if track.is_a?(Track)
      if scale.nil?
        assert_nil track.scale
      else
        assert_same track.scale, scale
      end
    end
  end

  def each_step(track, &block)
    track.grid.each do |slot|
      slot.each do |step|
        SpiSeq::Internal::Utils.call_varargs(block, step, slot)
      end
    end
  end

  def assert_steps_attr(track, attr_name, value, tol = 0.01)
    each_step(track) do |step|
      actual = step.send(attr_name)
      if actual.is_a?(Float) || value.is_a?(Float)
        assert_in_delta actual, value, tol, "expected #{step.inspect} #{attr_name} to be #{value.inspect}, but got #{actual}"
      else
        assert_equal actual, value, "expected #{step.inspect} #{attr_name} to be #{value.inspect}, but got #{actual}"
      end
    end
  end

  # Checks that, when `method` is called on a track and passed another track
  # with a different granularity and/or timescale, the correct behavior occurs.
  # Namely, the result should have the granularity and timescale of the first
  # track. This method does not check the grid of the returned track; it only
  # checks for a correct granularity and timescale.
  def assert_merge_gt(method, *, **)
    t8_1 = T[:c1]
    c_maj = SpiSeq::Theory::Scale.full_scale(:c, :major)
    t8_1_cmajor = T[:c1, scale: c_maj]
    t8_2 = T[:c2, timescale: 2]
    t16_1 = T[:c3, granularity: :sixteenth]
    t32_2 = T[:c4, granularity: :thirty_second, timescale: 2]

    assert_gt t8_1.send(method, t8_1_cmajor, *, **), :eighth, 1
    assert_gt t8_1_cmajor.send(method, t8_1, *, **), :eighth, 1, scale: c_maj
    assert_gt t8_1.send(method, t8_2, *, **), :eighth, 1
    assert_gt t8_1.send(method, t16_1, *, **), :eighth, 1
    assert_gt t16_1.send(method, t8_1, *, **), :sixteenth, 1
    assert_gt t8_2.send(method, t16_1, *, **), :eighth, 2
    assert_gt t16_1.send(method, t32_2, *, **), :sixteenth, 1
  end

  # Asserts that the given track round-trips to an equivalent one if its repr
  # is evaluated.
  def assert_repr(t)
    # Testing different groupings to make sure syntax errors don't sneak in.
    [nil, 8, 4, 1].each do |group|
      roundtrip = eval(t.repr(group:))  # rubocop:disable Security/Eval
      assert_gt roundtrip, t.granularity, t.timescale, scale: t.is_a?(SpiSeq::Tracks::Track) ? t.scale : nil
      assert_grid roundtrip, t.grid
    end
  end
end
