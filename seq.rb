# I don't understand how to get a sane set of SonicPi functions in external
# scripts, so this is intended to be eval'd so we get access to the context that
# the sketch is running inside. Namely:
$spi ||= self


module NoteLength
  Whole = 4
  Half = 2
  Quarter = 1
  Eighth = 1/2.0
  Sixteenth = 1/4.0
  ThirtySecond = 1/8.0

  def self.stringify(length)
    case length
    when Whole
      "whole"
    when Half
      "half"
    when Quarter
      "quarter"
    when Eighth
      "eighth"
    when Sixteenth
      "sixteenth"
    when ThirtySecond
      "thirty-second"
    else
      "invalid (#{length})"
    end
  end
end


module NoteUtils
  # note is a symbol for a note (e.g. :fs3) or a MIDI note number. If octave is
  # given, it overrides the octave of the note (even if it is a note number).
  # If octave is not given and the note is a symbol without an octave (e.g. :c),
  # the result will be in octave 4.
  # Returns an array [note symbol, note number, octave number]
  def self.normalize(note, octave: nil)
    info = $spi.note_info(note, octave: octave)
    [info.midi_string.downcase.to_sym, info.midi_note, info.octave]
  end

  # Returns a normalized symbol for the given note (a symbol or MIDI note
  # number). Uses the same octave rules as normalize.
  def self.sym(note, octave: nil)
    normalize(note, octave: octave)[0]
  end

  # Returns the MIDI note number for the given note (a symbol or MIDI note
  # number). Uses the same octave rules as normalize.
  def self.number(note, octave: nil)
    normalize(note, octave: octave)[1]
  end

  # Returns the octave number for the given note (a symbol or MIDI note number).
  # Uses the same octave rules as normalize.
  def self.octave(note, octave: nil)
    normalize(note, octave: octave)[2]
  end

  # Returns a normalized symbol for the given note (a symbol or MIDI note
  # number), changing its octave to the given value. This is effectively an
  # alias for sym.
  def self.set_octave(note, octave)
    sym(note, octave)
  end

  # Returns a normalized symbol for the given note, with its octave shifted by
  # the given offset.
  def self.shift_octave(note, octave_shift)
    sym(note, octave: octave(note) + octave_shift)
  end

  # Returns a normalized symbol for the given note, shifted by the given number
  # of semitones. The octave parameter, if given, is applied when resolving the
  # note argument; the result will not be in the given octave if the tone shift
  # moves it outside of that octave.
  def self.shift_tone(note, semitone_shift, octave: nil)
    sym(number(note, octave: octave) + semitone_shift)
  end

  # Returns a normalized symbol for the given note, snapped to the closest value
  # in notes. notes must be an array of note representations (symbols or MIDI
  # note numbers). The octave parameter, if given, is used to resolve the note
  # parameter. It is not used to resolve notes in the notes array; you probably
  # want to give those explicit octaves.
  def snap(note, notes, octave: nil)
    # TODO: be more particular about rounding up or down?
    notes = notes.map { |n| number(n) }
    note = notes.number(note, octave: octave)
    winner = nil
    smallest_diff = 256
    notes.each do |n|
      diff = (n - note).abs
      if diff < smallest_diff
        smallest_diff = diff
        winner = n
      end
    end

    sym(winner)
  end

  # Returns a normalized symbol for the given note, snaped to the nearest note
  # in the given scale. root is the root note for the scale and must be a symbol
  # for a note without an octave (e.g. :c or :fs). scale is a symbol for one of
  # the scales known to Sonic Pi. The octave parameter, if given, is used to
  # resolve the note parameter. It has no effect on the scale.
  def snap_to_scale(note, root, scale, octave: nil)
    oct_0_root = (root.to_s + "0").to_sym
    snap(note, $spi.scale(oct_0_root, scale, num_octaves: 10), octave: octave)
  end
end


# Immutable!
# TODO: probability & electron-style x/y? or even a predicate function
# TODO: legato?
class Step
  attr_reader :note, :note_number, :octave, :vel, :gate

  # note can be a string, symbol, integer MIDI note. It is always normalized
  # to a lower-case symbol of the Sonic Pi note name.
  # vel is the MIDI velocity for the note, 0 - 127. It is only used when the
  # note is played via MIDI, obviously.
  # gate is the percentage of the duration of the step for which the note will
  # be triggered. The note will not be played with a gate of 0, and will be
  # tied to the following step (if any) with a gate of 1.
  def initialize(note, vel: 127, gate: 1.0)
    @note, @note_number, @octave = NoteUtils::normalize(note)

    @vel = vel.to_i
    if @vel < 0
      @vel = 0
    elsif @vel > 127
      @vel = 127
    end

    @gate = gate.to_f
    if @gate < 0.0
      @gate = 0.0
    elsif @gate > 1.0
      @gate = 1.0
    end
  end

  def mutate(mutations)
    mutations = mutations.clone
    note = mutations.delete(:note) || @note
    mutations[:vel] = @vel unless mutations.has_key?(:vel)
    mutations[:gate] = @gate unless mutations.has_key?(:gate)
    Step.new(note, **mutations)
  end

  def with_note(new_note)
    mutate(note: new_note)
  end

  def with_vel(new_vel)
    mutate(vel: new_vel)
  end

  def with_gate(new_gate)
    mutate(gate: new_gate)
  end

  def with_octave(new_octave)
    with_note(NoteUtils::set_octave(@note, new_octave))
  end

  def shift_octave(shift)
    with_note(NoteUtils::shift_octave(@note, shift))
  end

  # Adjusts the note by the given number of semitones.
  def shift_tone(shift)
    with_note(NoteUtils::shift_tone(@note, shift))
  end

  def tied?
    @gate == 1.0
  end

  def inspect
    "<Step #{@note}/#{@note_number} vel=#{@vel} gate=#{gate}>"
  end
end

def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


# TODO: make mutable? seems tricky. plus would probably need to make a Grid
# class (or at least a bunch of Track methods) to make manipulation ergonomic.
# TODO: does timescale belong here? really only effects the Player, but this
# feels like a convenient play for it (& to mutate it)
class Track
  attr_reader :granularity, :grid, :timescale

  # grid is an array of arrays.
  # each element of grid is a "slot" and represents the state for a duration the
  # length of the granularity.
  # each slot is an array of Steps, which may be empty to represent a rest.
  # that is, each slot is filled with zero or more Steps.
  # the length of grid is the number of slots in this Track, and the
  # duration of this Track in beats is granularity * grid.length.

  # timescale is the speed at which this track plays, relative to the global
  # bpm. a timescale of 2 means this track plays at twice the global bpm, e.g.

  # Constructs a monophonic track with the given Steps. steps must be an array,
  # each element of which is either a Step object or nil to represent a rest.
  # Each Step or rest lasts for the granularity.
  def self.mono(steps, granularity: NoteLength::Quarter, timescale: 1)
    steps = steps.map do |s|
      if s.nil?
        []
      else
        [s]
      end
    end

    poly(steps, granularity: granularity, timescale: timescale)
  end

  # Constructs a polyphonic track with the given grid. grid must be an array,
  # each element of which is itself an array of Steps, which may be empty to
  # represent a rest. Each element of grid represents the Steps that should be
  # active for a time period of the granularity. That is, the duration of the
  # Track in beats is the granularity * grid.length.
  def self.poly(grid, granularity: NoteLength::Quarter, timescale: 1)
    new(grid: grid, granularity: granularity, timescale: timescale)
  end

  def num_slots
    @grid.length
  end

  # Returns an array: [newly triggered Steps, continued (tied) Steps, newly ended Steps]
  # Wraps the index if it exceeds the number of slots in the grid.
  # TODO: clarify the i == 0 behavior, or maybe add a `first` flag here too
  def steps_at_slot(i)
    prev_steps = @grid[(i - 1) % num_slots]
    cur_steps = @grid[i % num_slots]

    new_steps = []
    tied_steps = []
    ended_steps = []

    # distinguish between tied notes and newly started ones
    if i == 0
      # special case: if i *as passed, before a mod* was zero, do not consider
      # ties. all steps are new at the index 0.
      new_steps = cur_steps  # TODO: probably clone this if we go mutable
    else
      cur_steps.each do |step|
        # were we just playing this note as a tie?
        is_tie = prev_steps.one? { |prev_step| prev_step.tied? && prev_step.note == step.note }
        if is_tie
          tied_steps << step
        else
          new_steps << step
        end
      end
    end

    # find notes from the last index that have ended.
    # special case: if i *as passed, before a mod* was zero, do not wrap here
    # either; nothing was playing before index 0, so nothing has ended.
    # TODO: maybe if the note didn't have a full gate, it shouldn't go in
    # ended_steps?
    if i != 0
      prev_steps.each do |prev_step|
        # any note we were playing that is not tied has ended
        continues = tied_steps.one? { |step| step.note == prev_step.note }
        ended_steps << prev_step if !continues
      end
    end

    # TODO: for each new step, also find its total duration so we can play it
    # with `play`? what about notes that continue indefinitely though?
    [new_steps, tied_steps, ended_steps]
  end

  def inspect
    res = "Track slots=#{num_slots} granularity=#{NoteLength::stringify(granularity)}/#{granularity} timescale=#{timescale} grid:\n"
    @grid.each_with_index do |slot, i|
      res += "slot #{i} @ t=#{i * granularity}\n"
      slot.each { |step| res += "  #{step.inspect}\n" }
    end
    res
  end


  private

  def initialize(grid:, granularity:, timescale:)
    # TODO: normalize grid to make sure any given slot doesn't contain multiple
    # Steps for the same note?

    # Do a kinda-deep frozen clone of grid (no need to clone the Steps, but do
    # clone the array itself and the slot arrays). Frozen so the version we
    # expose through the attr_reader is immutable.
    # TODO: revisit this if we go mutable, obvs
    @grid = grid.map { |slot| slot.clone.freeze }.freeze
    @granularity = granularity
    @timescale = timescale
  end
end


class Player
  attr_reader :midi, :track

  def initialize(track, midi: false)
    @track = track
    @midi = midi
    @active_synth_nodes = Hash.new  # note symbols -> synth nodes. unused when playing midi
    @active_midi_notes = Set.new  # active midi note symbols. unused when playing built-in synths
  end

  # Plays one cycle of the track.
  def play(first:, ending:)
    if first
      # TODO: this is tricky. could argue that the first call to play on a
      # Player should be the only one where first is set, and we should hide it
      # from the user. or provide a stop/reset method?
      @active_synth_nodes.clear
      @active_midi_notes.clear
    end

    $spi.with_bpm($spi.current_bpm * track.timescale) do
      @track.num_slots.times do |i|
        # only feed steps_at_slot an actual 0 if this is the first play of this
        # track - we don't want ties and ended notes on the first step.
        # otherwise feed it num_slots (which will wrap around to 0), so that we
        # get ends and ties.
        i = @track.num_slots if i == 0 and !first
        new_steps, tied_steps, ended_steps = @track.steps_at_slot(i)

        if i % @track.num_slots == 0
          if first
            slot_desc = "0 (first)"
          else
            slot_desc = "0 (looped)"
          end
        else
          slot_desc = i.to_s
        end
        $spi.puts "@ slot=#{slot_desc}"
        $spi.puts "new steps: #{new_steps}"
        $spi.puts "tied steps: #{tied_steps}"
        $spi.puts "ended steps: #{ended_steps}"


        # Turn off or kill ended notes
        ended_steps.each { |step| end_step(step) }

        # Schedule ends for continued notes that end before the next slot
        tied_steps.each do |step|
          schedule_end_for_step_with_partial_gate(step) unless step.tied?
        end

        # Start new notes
        new_steps.each { |step| start_step(step) }

        # Sleep until it's time for the next slot
        $spi.sleep(@track.granularity)
      end

      if ending
        $spi.puts "ending; killing residual steps"
        end_all_steps
      end
    end
  end


  private

  def end_step(step)
    # Stop the MIDI note or kill the synth node. Note that we may have already
    # ended the step if it didn't have a full gate, in which case it will not
    # be in active_midi_notes or active_synth_nodes. Do nothing in that case.
    if @midi
      $spi.midi_note_off(step.note) unless @active_midi_notes.delete(step.note).nil?
    else
      node = @active_synth_nodes.delete(step.note)
      $spi.kill(node) if !node.nil?
    end
  end

  def schedule_end_for_step_with_partial_gate(step)
    $spi.time_warp(step.gate * @track.granularity) do
      $spi.puts "killing #{step.inspect} @ t=#{$spi.vt}"
      end_step(step)
    end
  end

  def end_all_steps
    if @midi
      @active_midi_notes.each { |n| $spi.midi_note_off(n) }
      @active_midi_notes.clear
    else
      @active_synth_nodes.each { |note, node| $spi.kill(node) }
      @active_synth_nodes.clear
    end
  end

  def start_step(step)
    if step.tied?
      if @midi
        $spi.midi_note_on(step.note, velocity: step.vel)
      else
        # TODO: there's no good way to just have a synth note go forever and
        # eventually gracefully kick it into release. Luckily I'm really only
        # using this for previewing stuff away from my real synth...
        # For now just having ties go for 100 * the length of the whole track.
        # Obviously that's ridiculous.
        node = $spi.play(step.note, duration: @track.granularity * @track.num_slots * 100, attack: 0, decay: 0, release: 0)
      end
    else
      if @midi
        $spi.midi(step.note, sustain: step.gate * @track.granularity)
      else
        node = $spi.play(step.note, duration: step.gate * @track.granularity, attack: 0, decay: 0, release: 0)
      end
    end

    if @midi
      @active_midi_notes << step.note
    else
      @active_synth_nodes[step.note] = node
    end
  end
end
