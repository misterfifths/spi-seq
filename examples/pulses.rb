use_bpm 110

require "~/spi-seq/core"

# Uncomment these if you want to use MIDI output
# use_player_defaults(midi: true, sync: :midi_clock)
# midi_clock_live_loop(port: "*")


# Build up a track that repeats the chords from pulse_chain 16 times each
pulse_chain = [[:fs3],
               [:fs3, :as3],
               [:fs3, :as3, :ds4]]
pulses = pulse_chain.map { |ns| T[ns] * 16 }.reduce(:+)

# Turn every 5th, then 3nd, then 5th, ... slot into a rest
pulses = pulses.dropout(5, 3)

# Apply a curve to the gates of the steps. UpDown2Sine goes from 0->1->0->1
# along a sine curve.
pulses = pulses.gate_curve(Curves::UpDown2Sine, min: 0.2, max: 0.5)
tll :pulses, pulses


# Make a new track that has [:fs2, :ds2] in every slot where the pulses track
# has a rest, and a rest everywhere pulses has steps.
# If you are using MIDI, you could send this to a different synth with the port
# and channel arguments.
pulse_gap_bass = pulses.mutate_slots { |slot| slot.empty? ? [:fs2, :ds2] : [] }.gate(0.1)
tll :p2, pulse_gap_bass
