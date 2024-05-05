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
    if !octave.nil? && note.is_a?(Numeric)
      # If we're overriding the octave of a numeric note, convert it to a symbol
      # first so that note_info actually respects the octave.
      note = sym(note)
    end

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
    sym(note, octave: octave)
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


class Prob
  # Use a custom trigger probability predicate. The callable must respond to
  # call and arity, and must have an arity of 2. It will be called with the
  # step and the cycle number, and should return true to trigger the step.
  def self.custom(callable)
    new(callable, "custom")
  end

  # Step will trigger with the given probability (0-1 inclusive).
  def self.chance(p)
    new(->(step, cycle) { $spi.rand < p }, "#{p.round(2)}")
  end

  # Step will trigger with a probablity of 1 in n.
  def self.one_in(n)
    new(->(step, cycle) { $spi.one_in(n) }, "one in #{n}")
  end

  # Step is guaranteed to trigger the xth cycle out of each set of y cycles. x
  # should be <= y. For example, x_of_y(3, 4) means that the Step will trigger
  # on the third of every four cycles.
  def self.x_of_y(x, y)
    new(->(step, cycle) { cycle % y == x - 1 }, "#{x}|#{y}")
  end

  # The inverse of x_of_y - the Step will trigger on every cycle except for the
  # xth out of every y cycles.
  def self.not_x_of_y(x, y)
    new(->(step, cycle) { cycle % y != x - 1 }, "!#{x}|#{y}")
  end

  # Step will trigger only on the first cycle.
  def self.first
    new(->(step, cycle) { cycle == 0 }, "first")
  end

  # Step will trigger on every cycle except the first.
  def self.not_first
    new(->(step, cycle) { cycle != 0 }, "!first")
  end

  # Evaluates the probability function for the given step in the given cycle of
  # the Track. Returns true if the step should trigger.
  def should_trigger?(step, cycle)
    res = @callable.call(step, cycle)
    $spi.puts("prob(#{step.inspect}, cycle=#{cycle}) = #{res}")
    res
  end

  def to_s
    @desc
  end

  def inspect
    "<Prob #{to_s}>"
  end


  private

  def initialize(callable, desc)
    if callable.respond_to?(:call) && callable.respond_to?(:arity) && callable.arity == 2
      @callable = callable
    else
      raise "Invalid probability predicate: must be a callable that takes 2 arguments"
    end

    @desc = desc
  end
end


# Immutable!
# TODO: legato?
# TODO: distinguish between 100% gate and a tie? is that even useful? want the
# full duration of the step, but want the note to retrigger on the next step?
# TODO: microtiming?
class Step
  attr_reader :note, :note_number, :octave, :vel, :gate, :prob

  # note can be a string, symbol, integer MIDI note. It is always normalized
  # to a lower-case symbol of the Sonic Pi note name.
  # vel is the MIDI velocity for the note, 0 - 127. It is only used when the
  # note is played via MIDI, obviously.
  # gate is the percentage of the duration of the step for which the note will
  # be triggered. The note will not be played with a gate of 0, and will be
  # tied to the following step (if any) with a gate of 1.
  # prob is the probability that the step will trigger. It should be either:
  # 1. nil - the Step will always trigger
  # 2. a number between 0 and 1 inclusive that represents the chance that the
  #    Step will trigger
  # 3. a callable predicate lambda/proc that takes two arguments, step and
  #    cycle. This will be wrapped in a Prob instance. If the predicate returns
  #    true, the step will trigger.
  # 4. an instance of Prob. See that class for some common cases.
  def initialize(note, vel: 127, gate: 1.0, prob: nil)
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

    if prob.nil?
      @prob = nil
    elsif prob.is_a?(Numeric)
      @prob = Prob.chance(prob)
    elsif prob.is_a?(Prob)
      @prob = prob
    else
      @prob = Prob.custom(prob)  # this will raise if this isn't an appropriate predicate
    end
  end

  def mutate(mutations)
    mutations = mutations.dup
    note = mutations.delete(:note) || @note
    [:vel, :gate, :prob].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

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

  def with_prob(new_prob)
    mutate(prob: new_prob)
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

  def should_trigger?(cycle)
    return true if @prob.nil?
    @prob.should_trigger?(self, cycle)
  end

  def inspect
    if @prob.nil?
      prob_desc = ""
    else
      prob_desc = " prob=#{@prob}"
    end
    "<Step #{@note}/#{@note_number} vel=#{@vel} gate=#{@gate}#{prob_desc}>"
  end
end

def S(*args, **kwargs)
  Step.new(*args, **kwargs)
end


module Arp
  Up = :up
  Down = :down
  UpDown = :updown
  TwoUpTwoDown = :twouptwodown
  Pinky = :pinky
  Thumb = :thumb
  Order = :order

  def self.arpeggiate(notes, direction, extra_octaves: [])
    orig_notes = notes
    notes = notes.to_a.dup  # to_a because this might be a SonicPi ring

    extra_octaves.each do |octave_shift|
      orig_notes.each do |n|
        notes << NoteUtils::shift_octave(n, octave_shift)
      end
    end

    # need to deal with note numbers internally; we'll be sorting
    notes = notes.map { |n| NoteUtils::number(n) }

    case direction
    when Arp::Up
      notes.sort!
    when Arp::Down
      notes.sort!.reverse!
    when Arp::UpDown
      notes.sort!
      notes += notes.reverse.drop(1)  # don't repeat the middle note
      notes.pop  # cycle cleanly without repeating the final note either
    when Arp::TwoUpTwoDown
      notes.sort!
      notes += notes.reverse.drop(1)
      notes.pop
      notes = notes.zip(notes).flatten
    when Arp::Pinky
      # play the highest note after each (but don't double at end)
      notes.sort!
      highest = notes.pop
      notes = notes.zip([highest].cycle).flatten
    when Arp::Thumb
      # play the lowest note after each (but don't double at beginning)
      notes.sort!
      lowest = notes.shift
      notes = notes.zip([lowest].cycle).flatten
    # nothing to do for Arp::Order
    end

    notes.map! { |n| NoteUtils::sym(n) }
  end
end


# A Track is mostly a "grid" of Steps together with a granularity. The grid is a
# 2d array, each element of which is a "slot". A slot contains some number
# (possibly 0) of Steps. Those are the Steps that should trigger (subject to
# their probabilities) when that slot is played. Each slot represents the Steps
# for a timespan equal to the Track's granularity, which is some fraction of a
# beat (e.g. 1/4 for sixteenth note granularity). Thus the length of a Track in
# beats is the granularity multiplied by the number of slots in the grid.
# Tracks also have a timescale, which is the speed at which this track will play
# relative to the global bpm. A timescale of 2 means that this track will play
# at twice the global bpm, e.g., and 0.5 means half-speed.
# TODO: make mutable? seems tricky. plus would probably need to make a Grid
# class (or at least a bunch of Track methods) to make manipulation ergonomic.
# TODO: does timescale belong here? really only effects the Player, so it could
# live there, but this feels like a convenient place for it (& to mutate it)
class Track
  attr_reader :granularity, :grid, :timescale


  ### Basic constructors

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

  # Constructs an empty sequence that lasts for the given number of steps.
  def self.rest(num_steps, granularity: NoteLength::Quarter, timescale: 1)
    grid = [[]] * num_steps
    new(grid: grid, granularity: granularity, timescale: 1)
  end


  ### More interesting constructors

  # Constructs a mono track that arpeggiates the given notes. extra_octaves is
  # an array of octave shifts. The arpeggiation will include all the notes from
  # the note array in addition to copies of them with the given octave shifts.
  def self.arp(notes, direction = Arp::Up, extra_octaves: [], granularity: NoteLength::Quarter, gate: 1, vel: 127, timescale: 1)
    notes = Arp::arpeggiate(notes, direction, extra_octaves: extra_octaves)
    steps = notes.map { |n| Step.new(n, vel: vel, gate: gate) }
    mono(steps, granularity: granularity, timescale: timescale)
  end


  ### Properties

  def num_slots
    @grid.length
  end


  ### Playback support

  # Returns an array: [newly triggered Steps, continued (tied) Steps, newly ended Steps]
  # Wraps the slot index if it exceeds the number of slots in the grid.
  # prev_steps is an array of the Steps that were active in the most recently
  # played slot. prev_steps should be nil or empty when playback is beginning.
  # cycle is the number of times the Track has played in its entirety (used to
  # handle Step probability).
  # Intended to be called iteratively, increasing i and feeding back playing
  # steps from the return value as prev_steps.
  def steps_at_slot(i, prev_steps:, cycle:)
    new_steps = []
    tied_steps = []
    ended_steps = []

    cur_steps = @grid[i % num_slots].filter { |step| step.should_trigger?(cycle) }
    prev_steps ||= []

    # distinguish between tied notes and newly started ones
    cur_steps.each do |step|
      # were we just playing this note as a tie?
      is_tie = prev_steps.one? { |prev_step| prev_step.tied? && prev_step.note == step.note }
      if is_tie
        tied_steps << step
      else
        new_steps << step
      end
    end

    # find notes from the last slot that have ended.
    prev_steps.each do |prev_step|
      # any note we were playing that is not tied has ended
      note_continues = tied_steps.one? { |step| step.note == prev_step.note }
      ended_steps << prev_step if !note_continues
    end

    [new_steps, tied_steps, ended_steps]
  end


  ### Etc.

  def inspect
    res = "Track slots=#{num_slots} granularity=#{NoteLength::stringify(granularity)}/#{granularity} timescale=#{timescale} grid:\n"
    @grid.each_with_index do |slot, i|
      res += "slot #{i} @ t=#{i * granularity}\n"
      slot.each { |step| res += "  #{step.inspect}\n" }
    end
    res
  end


  ### Mutators

  ## Grid-level mutations

  # TODO:
  # - destructive granularity changes (compress/expand)
  #   see what the oxi does about gates here
  # - nondestructive granularity changes (x2 & /2)
  # - global gate & velocity changes / scaling

  def with_rate(rate)
    mutate(timescale: @timescale * rate)
  end

  alias rate with_rate

  def append(other_track)
    assert_compatible_track(other_track)
    mutate(grid: @grid + other_track.grid)
  end

  alias concat append
  alias add append
  alias + append

  def merge(other_track)
    assert_compatible_track(other_track)
    new_grid_length = [num_slots, other_track.num_slots].max
    new_grid = []
    new_grid_length.times { |_| new_grid << [] }

    @grid.each_with_index { |slot, i| new_grid[i].concat(slot) }
    other_track.grid.each_with_index { |slot, i| new_grid[i].concat(slot) }

    mutate(grid: new_grid)
  end

  alias | merge

  def zip(other_track, cycle: false)
    assert_compatible_track(other_track)
    other_grid = other_track.grid
    other_grid = other_grid.cycle if cycle
    new_grid = @grid.zip(other_grid).flatten(1)

    # convert any nils that might have happened from a length mismatch into
    # rests.
    new_grid.map! { |slot| slot.nil? ? [] : slot } unless cycle

    mutate(grid: new_grid)
  end

  def repeat(n)
    mutate(grid: @grid * n)
  end

  alias * repeat

  def reverse
    mutate(grid: @grid.reverse)
  end

  alias rev reverse
  alias bw reverse

  def mirror
    mutate(grid: @grid + @grid.reverse)
  end

  def reflect
    mutate(grid: @grid + @grid.reverse.drop(1))
  end

  alias bnf reflect

  def shuffle
    mutate(grid: @grid.shuffle)
  end

  def rotate(rightward_shift = 1)
    mutate(grid: @grid.rotate(rightward_shift))
  end

  alias right rotate
  alias rshift rotate
  alias shr rotate

  def left(leftward_shift = 1)
    rotate(-leftward_shift)
  end

  alias lshift left
  alias shl rotate

  def drop(n)
    mutate(grid: @grid.drop(n))
  end

  def take(n)
    mutate(grid: @grid.take(n))
  end

  def slice(*args)
    mutate(grid: @grid.slice(*args))
  end

  alias [] slice

  def sample(n)
    mutate(grid: @grid.sample(n))
  end

  # Drops all Steps in every nth slot. The duration of the Track does not
  # change; the dropped slots simply become rests.
  def drop_every(n)
    # # e.g., drop every 3:
    # # keep  | 0 1 - 3 4 - 6 7 - 9
    # # drop  |     2     5     8
    # # i % 3 | 0 1 2 0 1 2 0 1 2 0
    new_grid = @grid.map.with_index do |slot, i|
      if i % n == n - 1
        []
      else
        slot
      end
    end

    mutate(grid: new_grid)
  end

  alias dropout drop_every


  ## Step-level mutations

  def mutate_each_step
    new_grid = @grid.map do |slot|
      slot.map do |step|
        yield step
      end
    end

    mutate(grid: new_grid)
  end

  def with_octave(new_octave)
    mutate_each_step { |step| step.with_octave(new_octave) }
  end

  alias octave with_octave
  alias oct octave

  def shift_octave(shift)
    mutate_each_step { |step| step.shift_octave(new_octave) }
  end

  def up(octave_shift = 1)
    shift_octave(octave_shift)
  end

  def down(octave_shift = 1)
    shift_octave(-octave_shift)
  end

  def shift_tone(shift)
    mutate_each_step { |step| step.shift_tone(shift) }
  end

  alias tone shift_tone

  def semi_up(tone_shift = 1)
    shift_tone(tone_shift)
  end

  alias sup semi_up

  def semi_down(tone_shift = 1)
    shift_tone(-tone_shift)
  end

  alias sdown semi_down


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

  def mutate(mutations)
    mutations = mutations.dup
    [:grid, :granularity, :timescale].each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    Track.new(**mutations)
  end

  # TODO: do automatic granularity adjustment when possible?
  def assert_compatible_track(other_track)
    if @granularity != other_track.granularity
      raise "Granularity mismatch: #{NoteLength::stringify(@granularity)} != #{NoteLength::stringify(other_track.granularity)}"
    end

    if @timescale != other_track.timescale
      raise "Timescale mismatch: #{@timescale} != #{other_track.timescale}"
    end
  end
end


# TODO: playhead direction - just a matter of how we move the slot index in play, i think
# TODO: probably special-case Steps with a 0 gate
class Player
  attr_reader :midi, :track

  def initialize(track, midi: false)
    @track = track
    @midi = midi
    @active_synth_nodes = Hash.new  # note symbols -> synth nodes. unused when playing midi
    @active_midi_notes = Set.new  # active midi note symbols. unused when playing built-in synths

    stop
  end

  def stop
    end_all_steps
    @prev_steps = nil
    @cycle = 0
  end

  # Plays one cycle of the track
  def play
    $spi.with_bpm($spi.current_bpm * track.timescale) do
      @track.num_slots.times do |i|
        play_slot(i)

        # Sleep until it's time for the next slot
        $spi.sleep(@track.granularity)
      end
    end

    @cycle += 1
  end


  private

  def play_slot(i)
    new_steps, tied_steps, ended_steps = @track.steps_at_slot(i, prev_steps: @prev_steps, cycle: @cycle)

    $spi.puts "@ slot=#{i} cycle=#{@cycle}"
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

    # Update prev_steps for the next round
    @prev_steps = tied_steps + new_steps
  end

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
