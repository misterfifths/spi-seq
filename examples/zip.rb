use_bpm 111

require "~/spi-seq/core"
init_spi_seq

# Uncomment these if you want to use MIDI output
# use_player_defaults(midi: true, sync: :midi_clock)
# midi_clock_live_loop(port: "*")

# This is a variation on an example in the readme.

t = T(chord(:fs3, :major)).gate(0.5)

# Interleave the track with itself in reverse, with a shorter gate and shifted to the left.
t = t.zip(t.reverse.gate(0.25).shl)

# Repeat the track as-is twice, then twice shifted up a fifth
t = t * 2 + t.transpose(7) * 2

# Interleave the track with itself down a fifth
t = t.zip(t.transpose(-7))

tll :t, t


# And let's add a bass track with longer gates, down 2 octaves, and converting
# every 3rd slot to a rest, for some rhythm.
track_live_loop :bass, t.down.dropout(3).gate(0.9)
