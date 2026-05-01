use_bpm 111

require "~/spi-seq/core"
init_spi_seq

# Uncomment these if you want to use MIDI output
# use_player_defaults(midi: true, sync: :midi_clock)
# midi_clock_live_loop(port: "*")


melody_bits = [[:as5, :fs5, :gs5],
               [:fs5, :cs5, :ds5],
               [:as4, :cs5, :ds5],
               [:fs5, :cs5, :ds5]]

tll :melody do
  # Build a track that plays each group of notes from melody_bits, shuffled,
  # followed by 5 rests (so that each chunk is 8 slots long).
  # Since we used a block here, this track will change on every loop.
  melody_bits.map { |bit| Track.new(bit.shuffle + [:r] * 5) }.reduce(:+)
end

tll :melody_low do
  # Builds a similar track to :melody, but offset such that it doesn't play
  # notes until slot 5, and shifted down an octave. This builds a sort of call
  # and response between the two tracks.
  melody_bits.map { |bit| Track.new([:r] * 4 + bit.shuffle + [:r]).down }.reduce(:+)
end
