use_bpm 111

require "~/spi-seq/core"
init_spi_seq

# Uncomment these if you want to use MIDI output
# use_player_defaults(midi: true, sync: :midi_clock)
# midi_clock_live_loop(port: "*")


# This is adapted from the code for the song "F00F Redux" by Full Empty,
# https://soundcloud.com/full-empty-214000746/f00f-redux


# Make a track that arpeggiates a g3 min7 chord such that the lowest note (the
# g3) repeats after each other note.
t = Track.arp(chord(:g3, :minor7), :thumb, granularity: :eighth)

# Adjust the gate of all steps - give :g3s 0.1 and all other notes 0.75
t = t.mutate_each_step { |step| step.note == :g3 ? step.with_gate(0.1) : step.with_gate(0.75) }

# Now we're going to build a track by strategically replacing the g3 in t with
# other notes.
subs = chord(:a3, :minor7) + [:a4, :c4]
subbed_track = t * 2
subs.each { |note| subbed_track += t.sub_note(:g3, note) * 2 }

tll :t, subbed_track
