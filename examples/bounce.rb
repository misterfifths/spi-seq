use_bpm 111

require "~/spi-seq/core"

# Uncomment these if you want to use MIDI output
# use_player_defaults(midi: true, sync: :midi_clock)
# midi_clock_live_loop(port: "*")

set_volume! 1  # Only necessary with built-in synthesis

# We'll call this in each cycle of the live loop to get the notes we should
# play for that cycle.
def notes_for_cycle(cycle)
  voicings = [:open, :open2, :open3, :open2]
  voicing = voicings[cycle % voicings.length]
  # This is spi-seq's Chord class, which supports all the chord names that
  # Sonic Pi's `chord` does, but also has voicing options.
  C(:ds3, :min7, voicing)
end

tll :t do |cycle:|
  notes = notes_for_cycle(cycle)
  thumb = Track.arp(notes, :thumb).gate(0.5)
  pinky = Track.arp(notes, :pinky).down.gate(0.75)

  (thumb | pinky) * 4
end
