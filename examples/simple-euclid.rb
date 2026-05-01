use_bpm 111

require "~/spi-seq/core"
init_spi_seq

# Uncomment these if you want to use MIDI output
# use_player_defaults(midi: true, sync: :midi_clock)
# midi_clock_live_loop(port: "*")

set_volume! 0.5  # Only needed with internal synthesis

notes = chord(:ds3, :minor)

t = Track.euclid(notes[1], 5, 16).gate(0.75)
u = Track.euclid(notes[2], 7, 16).gate(0.5)
v = Track.euclid(notes[3], 11, 16).gate(0.25)

tll :t, t
tll :u, u
tll :v, v


# On top of the short pulses of the Euclidean tracks, play the notes of the
# chord up a fifth, held quite a bit longer (whole notes).
long = T(notes, granularity: :whole).transpose(7).mirror.gate(0.9)
tll :long, long
