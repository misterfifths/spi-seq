#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/init"
require_relative "lib/track_helpers"
require_relative "../lib/spiseq/internal/random"
require_relative "../lib/spiseq/internal/utils"
require_relative "../lib/spiseq/math/curves"
require_relative "../lib/spiseq/tracks/track"

include SpiSeq::Math
include SpiSeq::Tracks

# Test Track's step manipulation methods.
# This is mostly things that deal with individual steps in the Track, rather
# than the track or slots as a whole.
class TrackStepTest < Test::Unit::TestCase
  include TrackHelpers

  def assert_mutate_steps(track, grid, &block)
    t = track.mutate_steps(&block)
    assert_grid t, grid
  end

  def test_mutate_each_step
    t = T[:a1, [:b2, :c3], :d4]

    assert_mutate_steps(t, [[:f9], [:f9], [:f9]]) { |_| :f9 }
    assert_mutate_steps(t, [[:f9], [:f9], [:f9]]) { |_, _| :f9 }
    assert_mutate_steps(t, [[:f9], [:f9], [:f9]]) { |_, _, _| :f9 }

    [nil, :r, :rest].each do |rest|
      assert_mutate_steps(t, [[:a1], [:b2], [:d4]]) { |s| (s.note == :c3) ? rest : s }
      assert_mutate_steps(t, [[], [:b2, :c3], [:d4]]) { |s| (s.note.pitch_class == :a) ? rest : s }
    end

    assert_mutate_steps(t, [[:f1], [:f2, :f3], [:f4]]) { |s| s.with_note(s.note.with_pitch_class(:f)) }

    assert_mutate_steps(t, [[:a1], [], [:d4]]) { |s, i| (i == 1) ? nil : s }

    # rubocop:disable Lint/FloatComparison
    assert_mutate_steps(t, [[:f9], [:b2, :c3], [:d4]]) { |s, _, pct| (pct == 0) ? [:f9] : s }
    assert_mutate_steps(t, [[:a1], [:f9], [:d4]]) { |s, _, pct| (pct == 0.5) ? [:f9] : s }
    assert_mutate_steps(t, [[:a1], [:b2, :c3], [:f9]]) { |s, _, pct| (pct == 1) ? [:f9] : s }
    # rubocop:enable Lint/FloatComparison

    # Returning more than one step from the block.
    assert_mutate_steps(t, [[:a1], [:f8, :f9], [:d4]]) { |s, i| (i == 1) ? [:f8, :f9] : s }
  end

  def assert_mutate_in_slot(track, i, grid, &block)
    t = track.mutate_steps_in_slot(i, &block)
    assert_grid t, grid
  end

  def test_mutate_steps_in_slot
    t = T[:a1, [:b2, :c3], :r]

    assert_mutate_in_slot(t, 0, [[:a2], [:b2, :c3], []]) { |s| s.shift_tone(12) }
    assert_mutate_in_slot(t, 1, [[:a1], [], []]) { |_| nil }
    assert_mutate_in_slot(t, 2, [[:a1], [:b2, :c3], []]) { |_| :f9 }  # block is never called

    # Returning more than one step
    assert_mutate_in_slot(t, 0, [[:a0, :a2], [:b2, :c3], []]) { |s| [s.shift_tone(12), s.shift_tone(-12)] }

    assert_raises { t.mutate_steps_in_slot(3) { |_| nil } }

    # Negative indexes
    assert_mutate_in_slot(t, -2, [[:a1], [:b3, :c4], []]) { |s| s.shift_tone(12) }
    assert_mutate_in_slot(t, -3, [[:a2], [:b2, :c3], []]) { |s| s.shift_tone(12) }
  end

  def assert_mutate_filled_slot(track, n, grid, &block)
    t = track.mutate_filled_slot(n, &block)
    assert_grid t, grid
  end

  def test_mutate_filled_slot
    t = T[:a1, :r, [:b2, :c3], :r]

    assert_mutate_filled_slot(t, 0, [[:a2], [], [:b2, :c3], []]) { |s| s.shift_tone(12) }
    assert_mutate_filled_slot(t, 1, [[:a1], [], [:f9], []]) { |_| :f9 }
    assert_raises { t.mutate_filled_slot(2) { |_| nil } }

    # Negative indexes
    assert_mutate_filled_slot(t, -1, [[:a1], [], [:f9], []]) { |_| :f9 }
    assert_mutate_filled_slot(t, -2, [[:a2], [], [:b2, :c3], []]) { |s| s.shift_tone(12) }
  end

  def assert_set_filled_slot(track, n, new_slot, grid)
    t = track.set_filled_slot(n, new_slot)
    assert_grid t, grid
  end

  def test_replace_filled_slot
    t = T[:a1, :r, [:b2, :c3], :r]

    assert_set_filled_slot t, 0, :a2, [[:a2], [], [:b2, :c3], []]
    assert_set_filled_slot t, 0, [:a2, :a3], [[:a2, :a3], [], [:b2, :c3], []]
    assert_set_filled_slot t, 0, [], [[], [], [:b2, :c3], []]
    assert_set_filled_slot t, 0, :r, [[], [], [:b2, :c3], []]

    assert_set_filled_slot t, 1, :f9, [[:a1], [], [:f9], []]

    assert_raises { t.set_filled_slot(2, []) }

    # Negative indexes
    assert_set_filled_slot t, -1, :a2, [[:a1], [], [:a2], []]
    assert_set_filled_slot t, -2, :f9, [[:f9], [], [:b2, :c3], []]
  end

  def test_with_gate
    assert_steps_attr T[:c4].gate(0.5), :gate, 0.5
    assert_steps_attr T[:c4, :d4].gate(0.5), :gate, 0.5
    assert_steps_attr T[:c4, [:d4, :e4]].gate(0.5), :gate, 0.5
    assert_steps_attr T[S(:f9, gate: 0.25)].gate(0.5), :gate, 0.5

    assert_steps_attr T[S(:f9, gate: 0.25), :e8].gate(2), :gate, 1
    assert_steps_attr T[S(:f9, gate: 0.25), :e8].gate(-2), :gate, 0
  end

  def test_scale_gate
    assert_grid T[:c4].scale_gate(0.5), [[S(:c4, gate: 0.5)]]
    assert_grid T[:c4, :d4].scale_gate(0.5), [[S(:c4, gate: 0.5)], [S(:d4, gate: 0.5)]]
    assert_grid T[:c4, [:d4, S(:e4, gate: 0.5)]].scale_gate(0.25), [[S(:c4, gate: 0.25)], [S(:d4, gate: 0.25), S(:e4, gate: 0.125)]]

    assert_grid T[S(:f9, gate: 0.25), [:d4, :e4]].scale_gate(2), [[S(:f9, gate: 0.5)], [:d4, :e4]]
    assert_grid T[:c4, S(:d4, gate: 0.5)].scale_gate(-1), [[S(:c4, gate: 0)], [S(:d4, gate: 0)]]
  end

  def test_with_vel
    assert_steps_attr T[:c4].vel(63), :vel, 63
    assert_steps_attr T[:c4, :d4].vel(63), :vel, 63
    assert_steps_attr T[:c4, [:d4, :e4]].vel(63), :vel, 63
    assert_steps_attr T[S(:f9, vel: 99)].vel(63), :vel, 63

    assert_steps_attr T[S(:f9, vel: 32), :e8].vel(256), :vel, 127
    assert_steps_attr T[S(:f9, vel: 32), :e8].vel(-127), :vel, 0

    # velf
    assert_steps_attr T[:c4].velf(0.5), :vel, 63
    assert_steps_attr T[:c4, :d4].velf(0.5), :vel, 63
    assert_steps_attr T[:c4, [:d4, :e4]].velf(0.5), :vel, 63
    assert_steps_attr T[S(:f9, vel: 99)].velf(0.5), :vel, 63

    assert_steps_attr T[S(:f9, vel: 32), :e8].velf(2), :vel, 127
    assert_steps_attr T[S(:f9, vel: 32), :e8].velf(-1), :vel, 0
  end

  def test_scale_vel
    assert_grid T[:c4].scale_vel(0.5), [[S(:c4, vel: 63)]]
    assert_grid T[:c4, :d4].scale_vel(0.5), [[S(:c4, vel: 63)], [S(:d4, vel: 63)]]
    assert_grid T[:c4, [:d4, S(:e4, vel: 63)]].scale_vel(0.25), [[S(:c4, vel: 31)], [S(:d4, vel: 31), S(:e4, vel: 15)]]

    assert_grid T[S(:f9, vel: 31), [:d4, :e4]].scale_vel(2), [[S(:f9, vel: 62)], [:d4, :e4]]
    assert_grid T[:c4, S(:d4, vel: 63)].scale_vel(-1), [[S(:c4, vel: 0)], [S(:d4, vel: 0)]]
  end

  def test_with_octave_shift_octave
    assert_grid T[:c4].oct(6), [[:c6]]
    assert_grid T[:c4, :d5].oct(5), [[:c5], [:d5]]
    assert_grid T[:c4, [:d5, :e6]].oct(3), [[:c3], [:d3, :e3]]

    assert_grid T[:c4].up(2), [[:c6]]
    assert_grid T[:c4].shift_octave(2), [[:c6]]
    assert_grid T[:c4, :d5].up(5), [[:c9], [:d10]]
    assert_grid T[:c4, [:d5, :e6]].down(3), [[:c1], [:d2, :e3]]
    assert_grid T[:c4, [:d5, :e6]].shift_octave(-3), [[:c1], [:d2, :e3]]
  end

  def test_rand_octave
    if in_sonic_pi?
      SpiSeq::External::Random.use_random_seed(1234)
      assert_grid T[:c4].roct, [[:c5]]
      assert_grid T[:c4, :d5].roct(p: 1), [[:c5], [:d6]]
      assert_grid T[:c4, [:d5, :e6]].roct(3, p: 1), [[:c6], [:d6, :e4]]
      assert_grid T[:c4, [:d5, :e6]].roct(0..2), [[:c4], [:d5, :e6]]
      assert_grid T[:c4, [:d5, :e6]].roct(-2..2), [[:c4], [:d6, :e6]]
    else
      srand 123456
      assert_grid T[:c4].roct, [[:c3]]
      assert_grid T[:c4, :d5].roct(p: 1), [[:c3], [:d4]]
      assert_grid T[:c4, [:d5, :e6]].roct(3, p: 1), [[:c1], [:d3, :e3]]
      assert_grid T[:c4, [:d5, :e6]].roct(0..2), [[:c4], [:d5, :e8]]
      assert_grid T[:c4, [:d5, :e6]].roct(-2..2), [[:c4], [:d3, :e5]]
    end
  end

  def test_shift_tone
    assert_grid T[:c4].transpose(2), [[:d4]]
    assert_grid T[:c4, :d5].transpose(5), [[:f4], [:g5]]
    assert_grid T[:c4, [:d5, :e6]].transpose(-3), [[:a3], [:b4, :cs6]]

    assert_grid T[:c4].semi_up, [[:cs4]]
    assert_grid T[:c4].semi_up(2), [[:d4]]
    assert_grid T[:d4].semi_down, [[:cs4]]
    assert_grid T[:d4].semi_down(2), [[:c4]]
  end

  def assert_sub_note(track, note, repl, grid)
    assert_grid track.sub_note(note, repl), grid
  end

  def test_sub_note
    t = T[:a1, [:b2, :b3], :c3]

    assert_sub_note t, :d, :e, [[:a1], [:b2, :b3], [:c3]]
    assert_sub_note t, :b, :c, [[:a1], [:c2, :c3], [:c3]]
    assert_sub_note t, :b2, :c, [[:a1], [:c2, :b3], [:c3]]
    assert_sub_note t, :b2, :c3, [[:a1], [:c3, :b3], [:c3]]
    assert_sub_note t, :b, :f9, [[:a1], [:f9], [:c3]]
    assert_sub_note t, :c3, :f8, [[:a1], [:b2, :b3], [:f8]]

    [nil, :r, :rest].each do |rest|
      assert_sub_note t, :d, rest, [[:a1], [:b2, :b3], [:c3]]
      assert_sub_note t, :b, rest, [[:a1], [], [:c3]]
      assert_sub_note t, :b2, rest, [[:a1], [:b3], [:c3]]
      assert_sub_note t, :c, rest, [[:a1], [:b2, :b3], []]
    end
  end

  def test_prob
    t = T[:c1, S(:c2, prob: 0.5), [S(:c3, prob: Prob.one_in(3)), :c4]]

    assert_steps_attr t.clear_prob, :prob, nil
    assert_steps_attr t.prob(Prob.every_other), :prob, Prob.every_other
    assert_steps_attr t.prob(0.5), :prob, Prob.chance(0.5)

    p = Prob.one_in(5)
    u = t.prob(p, overwrite: false)
    assert_grid u, [[S(:c1, prob: p)], [S(:c2, prob: 0.5)], [S(:c3, prob: Prob.one_in(3)), S(:c4, prob: p)]]
  end

  def test_fill
    t = T[:c1, [S(:c2, prob: 0.5), S(:c3, prob: Prob.fill)], S(:c4, prob: Prob.one_in(3))]

    assert_steps_attr t.fill, :prob, Prob.fill
    assert_grid t.fill(false), [[:c1], [S(:c2, prob: 0.5), :c3], [S(:c4, prob: Prob.one_in(3))]]
  end

  def test_with_accum_clear_accum
    t = T[:c1, S(:c2).accum(1), S(:c3, gate: 0.5).accum(12, max: 24, mode: :freeze, target: :vel)]

    u = t.accum(5, min: -5, max: 10, prob: Prob.every_other, mode: :reverse)
    assert_steps_attr u, :accum_delta, 5
    assert_steps_attr u, :accum_min, -5
    assert_steps_attr u, :accum_max, 10
    assert_steps_attr u, :accum_prob, Prob.every_other
    assert_steps_attr u, :accum_mode, :reverse
    assert_steps_attr u, :accum_target, :note

    v = t.clear_accum
    assert_steps_attr v, :accum_delta, 0
  end

  def assert_curve(track, curve_func, attr, attr_scale_factor = 1, integer = false, tol = 0.01)
    track.grid.each_with_index do |slot, idx|
      if idx == 0
        pct = 0.0
      elsif idx == track.length - 1
        pct = 1.0
      else
        pct = idx.to_f / (track.length - 1)
      end

      slot.each do |step|
        attr_val = step.send(attr)

        curve_val = SpiSeq::Internal::Utils.call_varargs(curve_func, pct, idx) * attr_scale_factor
        curve_val = curve_val.to_i if integer
        assert_in_delta attr_val, curve_val, tol, "expected #{step.inspect} #{attr} to be #{curve_val}, but got #{attr_val}, track: #{track.repr}"
      end
    end
  end

  def assert_gate_curve(t, curve_func)
    assert_curve t, curve_func, :gate
  end

  def test_with_gate_curve
    t = T[:c1, [S(:c2, gate: 0.5), S(:c3, gate: 0.25)], :c4]

    assert_gate_curve t.gate_curve(Curves::UpLinear), Curves::UpLinear
    assert_gate_curve t.gate_curve(Curves::UpDown3Sine), Curves::UpDown3Sine

    assert_gate_curve t.gate_curve(Curves::UpLinear, min: 0.5), Curves.scale(Curves::UpLinear, 0.5, 1)
    assert_gate_curve t.gate_curve(Curves::UpLinear, max: 0.75), Curves.scale(Curves::UpLinear, 0, 0.75)
    assert_gate_curve t.gate_curve(Curves::UpLinear, min: 0.5, max: 0.9), Curves.scale(Curves::UpLinear, 0.5, 0.9)
  end

  def assert_vel_curve(t, curve_func)
    assert_curve t, curve_func, :vel, 127, true
  end

  def test_with_vel_curve
    t = T[:c1, [S(:c2, vel: 63), S(:c3, vel: 31)], :c4]
    scaled_lin = ->(pct) { pct * 127 }
    raw_lin = ->(pct) { pct }

    assert_vel_curve t.vel_curve(scaled_lin), raw_lin
    assert_vel_curve t.vel_curve(Curves.scale(Curves::UpDown2Sine, 0, 127)), Curves::UpDown2Sine

    assert_vel_curve t.vel_curve(scaled_lin, max: 63), Curves.scale(raw_lin, 0, 0.5)
    assert_vel_curve t.vel_curve(scaled_lin, max: 95), Curves.scale(Curves::UpLinear, 0, 0.75)
    assert_vel_curve t.vel_curve(scaled_lin, min: 63, max: 114), Curves.scale(Curves::UpLinear, 0.5, 0.9)

    # velf
    assert_vel_curve t.velf_curve(raw_lin), raw_lin
    assert_vel_curve t.velf_curve(Curves::UpDown2Sine), Curves::UpDown2Sine

    assert_vel_curve t.velf_curve(raw_lin, max: 0.5), Curves.scale(raw_lin, 0, 0.5)
    assert_vel_curve t.velf_curve(raw_lin, max: 0.75), Curves.scale(Curves::UpLinear, 0, 0.75)
    assert_vel_curve t.velf_curve(raw_lin, min: 0.5, max: 0.9), Curves.scale(Curves::UpLinear, 0.5, 0.9)
  end

  def assert_fade(t, fade_in:, quad: false, min: 0, max: 1, start: 0)
    curve_name = :"fade_#{fade_in ? 'in' : 'out'}_#{quad ? 'quad' : 'linear'}"
    curve_args = fade_in ? [min, max, start] : [max, min, start]
    curve_func = Curves.send(curve_name, *curve_args)

    track_fn_name = :"fade_#{fade_in ? 'in' : 'out'}#{'_quad' if quad}"
    track_fn_args = fade_in ? [min, max] : [max, min]

    t = t.send(track_fn_name, *track_fn_args, start: start)
    assert_vel_curve t, curve_func
  end

  def test_fade_in_fade_out
    t = T[:c1, [S(:c2, vel: 63), S(:c3, vel: 31)], :c4, *[:d9] * 20]

    [true, false].each do |fade_in|
      [true, false].each do |quad|
        assert_fade t, fade_in: fade_in, quad: quad
        assert_fade t, fade_in: fade_in, quad: quad, max: 0.5
        assert_fade t, fade_in: fade_in, quad: quad, max: 0.5, start: 0.5
        assert_fade t, fade_in: fade_in, quad: quad, min: 0.25
        assert_fade t, fade_in: fade_in, quad: quad, min: 0.25, start: 0.25
        assert_fade t, fade_in: fade_in, quad: quad, min: 0.25, max: 0.9
        assert_fade t, fade_in: fade_in, quad: quad, min: 0.25, max: 0.9, start: 0.1
        assert_fade t, fade_in: fade_in, quad: quad, min: 0.25, max: 0.9, start: 1
        assert_fade t, fade_in: fade_in, quad: quad, min: 0.25, max: 0.9, start: 2
      end
    end
  end

  def test_taper_gate_taper_vel
    t = T[
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.75, vel: 63), :e1],
      [S(:c1, gate: 0.25), :e1],  # This begins a new run of c1; the previous one was not tied.
      [:f1, S(:c1, gate: 0.1)],  # This is a new run of c1 too; the previous lasted one slot.
      [:f1, :d1, S(:c1, gate: 0.25)]  # This c1 run does not loop into slot 0, but the d1 does.
    ]

    assert_grid t.taper_gate(0.5), [
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.5, vel: 63), :e1],
      [S(:c1, gate: 0.25), S(:e1, gate: 0.5)],
      [:f1, S(:c1, gate: 0.1)],
      [S(:f1, gate: 0.5), :d1, S(:c1, gate: 0.25)]
    ]
    assert_grid t.taper_gate(0.5, taper_final_tie: true), [
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.5, vel: 63), :e1],
      [S(:c1, gate: 0.25), S(:e1, gate: 0.5)],
      [:f1, S(:c1, gate: 0.1)],
      [S(:f1, gate: 0.5), S(:d1, gate: 0.5), S(:c1, gate: 0.25)]
    ]
    assert_grid t.taper_gate(0.5, taper_single: true), [
      [:c1, S(:d1, gate: 0.5)],
      [:c1],
      [S(:c1, gate: 0.5, vel: 63), :e1],
      [S(:c1, gate: 0.5), S(:e1, gate: 0.5)],
      [:f1, S(:c1, gate: 0.5)],
      [S(:f1, gate: 0.5), :d1, S(:c1, gate: 0.5)]
    ]

    assert_grid t.taper_vel(48), [
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.75, vel: 48), :e1],
      [S(:c1, gate: 0.25), S(:e1, vel: 48)],
      [:f1, S(:c1, gate: 0.1)],
      [S(:f1, vel: 48), :d1, S(:c1, gate: 0.25)]
    ]
    assert_grid t.taper_vel(48, taper_final_tie: true), [
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.75, vel: 48), :e1],
      [S(:c1, gate: 0.25), S(:e1, vel: 48)],
      [:f1, S(:c1, gate: 0.1)],
      [S(:f1, vel: 48), S(:d1, vel: 48), S(:c1, gate: 0.25)]
    ]
    assert_grid t.taper_vel(48, taper_single: true), [
      [:c1, S(:d1, vel: 48)],
      [:c1],
      [S(:c1, gate: 0.75, vel: 48), :e1],
      [S(:c1, gate: 0.25, vel: 48), S(:e1, vel: 48)],
      [:f1, S(:c1, gate: 0.1, vel: 48)],
      [S(:f1, vel: 48), :d1, S(:c1, gate: 0.25, vel: 48)]
    ]

    assert_grid t.taper_velf(0.25), [
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.75, vel: 31), :e1],
      [S(:c1, gate: 0.25), S(:e1, vel: 31)],
      [:f1, S(:c1, gate: 0.1)],
      [S(:f1, vel: 31), :d1, S(:c1, gate: 0.25)]
    ]
    assert_grid t.taper_velf(0.25, taper_final_tie: true), [
      [:c1, :d1],
      [:c1],
      [S(:c1, gate: 0.75, vel: 31), :e1],
      [S(:c1, gate: 0.25), S(:e1, vel: 31)],
      [:f1, S(:c1, gate: 0.1)],
      [S(:f1, vel: 31), S(:d1, vel: 31), S(:c1, gate: 0.25)]
    ]
    assert_grid t.taper_velf(0.25, taper_single: true), [
      [:c1, S(:d1, vel: 31)],
      [:c1],
      [S(:c1, gate: 0.75, vel: 31), :e1],
      [S(:c1, gate: 0.25, vel: 31), S(:e1, vel: 31)],
      [:f1, S(:c1, gate: 0.1, vel: 31)],
      [S(:f1, vel: 31), :d1, S(:c1, gate: 0.25, vel: 31)]
    ]
  end

  def test_snap_to_notes
    t = T[55, 60, 65, 70]

    assert_grid t.snap_to_notes([58]), [[58], [58], [58], [58]]
    assert_grid t.snap_to_notes([60, 68]), [[60], [60], [68], [68]]
    assert_grid t.snap_to_notes([50, 61, 68]), [[50], [61], [68], [68]]
  end

  def test_snap_to_scale
    t = T[:c4, :d3, :e2, :f1, :"g-1",
          :cs4, :eb4, :bs4]

    assert_grid t.snap_to_scale(:c, :major),
                [[:c4], [:d3], [:e2], [:f1], [:"g-1"],
                 [:d4], [:e4], [:c5]]  # The accidentals should snap upward.
  end

  def test_evolve
    t = T[S(:c1, gate: 0.5, vel: 63), :c2, S(:c3, gate: 0.1, vel: 10)]

    if in_sonic_pi?
      SpiSeq::External::Random.use_random_seed(1234)
      assert_grid t.evolve(tone_shifts: [-12, 12], octave_limit: 0..4, gate_delta: 0, velf_delta: 0, p: 1),
                  T[S(:c0, vel: 63, gate: 0.5), :c1, S(:c4, vel: 10, gate: 0.1)].grid
      assert_grid t.evolve(tone_shifts: [-7, 7], octave_limit: 0..4, gate_delta: 0, velf_delta: 0, p: 1),
                  T[S(:g1, vel: 63, gate: 0.5), :g2, S(:g3, vel: 10, gate: 0.1)].grid
      assert_grid t.evolve(tone_shifts: [0, 24, 48], octave_limit: 1..4, gate_delta: 0, velf_delta: 0, p: 1),
                  T[S(:c3, vel: 63, gate: 0.5), :c4, S(:c4, vel: 10, gate: 0.1)].grid

      assert_grid t.evolve(tone_shifts: 0, gate_delta: 0.5, gate_limit: 0.1..1, velf_delta: 0, p: 1),
                  T[S(:c1, vel: 63, gate: 0.86), S(:c2, gate: 0.9), S(:c3, vel: 10, gate: 0.1)].grid
      assert_grid t.evolve(tone_shifts: 0, gate_delta: 1, gate_limit: 0..1, velf_delta: 0, p: 1),
                  T[S(:c1, vel: 63, gate: 0), S(:c2, gate: 0.35), S(:c3, vel: 10, gate: 0)].grid

      assert_grid t.evolve(tone_shifts: 0, gate_delta: 0, velf_delta: 0.5, velf_limit: 0.1..1, p: 1),
                  T[S(:c1, vel: 26, gate: 0.5), S(:c2, vel: 108), S(:c3, vel: 12, gate: 0.1)].grid
      assert_grid t.evolve(tone_shifts: 0, gate_delta: 0, velf_delta: 0.3, velf_limit: 0.5..0.9, p: 1),
                  T[S(:c1, vel: 63, gate: 0.5), S(:c2, vel: 114), S(:c3, vel: 63, gate: 0.1)].grid
    else
      srand 1234
      assert_grid t.evolve(tone_shifts: [-12, 12], octave_limit: 0..4, gate_delta: 0, velf_delta: 0, p: 1),
                  [[S(:c0, vel: 63, gate: 0.5)], [:c1], [S(:c4, gate: 0.1, vel: 10)]]
      assert_grid t.evolve(tone_shifts: [-7, 7], octave_limit: 0..4, gate_delta: 0, velf_delta: 0, p: 1),
                  [[S(:g1, vel: 63, gate: 0.5)], [:g2], [S(:g3, gate: 0.1, vel: 10)]]
      assert_grid t.evolve(tone_shifts: [0, 24, 48], octave_limit: 1..4, gate_delta: 0, velf_delta: 0, p: 1),
                  [[S(:c1, vel: 63, gate: 0.5)], [:c2], [S(:c4, gate: 0.1, vel: 10)]]

      assert_grid t.evolve(tone_shifts: 0, gate_delta: 0.5, gate_limit: 0.1..1, velf_delta: 0, p: 1),
                  [[S(:c1, vel: 63, gate: 0.35)], [S(:c2, gate: 0.53)], [S(:c3, gate: 0.1, vel: 10)]]
      assert_grid t.evolve(tone_shifts: 0, gate_delta: 1, gate_limit: 0..1, velf_delta: 0, p: 1),
                  [[S(:c1, vel: 63, gate: 0)], [S(:c2, gate: 0.32)], [S(:c3, gate: 0.07, vel: 10)]]

      assert_grid t.evolve(tone_shifts: 0, gate_delta: 0, velf_delta: 0.5, velf_limit: 0.1..1, p: 1),
                  [[S(:c1, vel: 12, gate: 0.5)], [S(:c2, vel: 119)], [S(:c3, gate: 0.1, vel: 12)]]
      assert_grid t.evolve(tone_shifts: 0, gate_delta: 0, velf_delta: 0.3, velf_limit: 0.5..0.9, p: 1),
                  [[S(:c1, vel: 63, gate: 0.5)], [S(:c2, vel: 94)], [S(:c3, gate: 0.1, vel: 63)]]
    end
  end
end
