# frozen_string_literal: true

require_relative "cctrack"
require_relative "extapi"
require_relative "math/curves"
require_relative "prob"
require_relative "step"
require_relative "theory/arp"
require_relative "theory/midinote"
require_relative "theory/notelength"
require_relative "theory/scale"
require_relative "trackbase"


# An alias for Track.new.
def T(*args, **kwargs)
  Track.new(*args, **kwargs)
end


# A Track deals with a grid whose slots contain Steps. Step instances represent
# MIDI notes and their properties (e.g. gate and velocity). See the TrackBase
# documentation for details on grids, slots, and the basic inherited
# functionality.
#
# In addition to the basic mutation methods from TrackBase, Track contains
# functionality tailored to deal with Steps - e.g. note-based manipulation, or
# global gate/velocity adjustment.
#
# A Track may have a global scale assigned, which should be an instance of Scale
# (you probably want one from the `full_scale` method). If such a scale is
# provided, all the notes in the track are quantized to that scale before being
# played. Note that that operation is non-destructive; a Track with a scale can
# contain Steps with notes that are not on the scale, and they will be snapped
# to the scale just in time for playback. Also note that the snapping operation
# may result in duplicate notes within one slot (e.g. a C# and a D on a C major
# scale will both result in a D). In that case, the Step with the longest gate
# is played.
class Track < TrackBase
  attr_reader :scale


  ### Basic constructors

  # Constructs a Track with the given "gridish" definition. `gridish` will be
  # converted into a proper grid, an array of "slots". A slot is itself an
  # array of Steps, which all trigger simultaneously for a duration of the
  # granularity. A slot may be empty to represent a rest.
  #
  # `gridish` is converted to a grid in the following way:
  # - A single MIDI note (symbol, string, number or MIDINote instance) becomes
  #   grid with one slot containing a single Step created with that note and the
  #   default arguments to `Step.new`.
  # - A single Step becomes a grid with one slot containing just that Step.
  # - A single rest (see `MIDINote.rest?`) becomes a grid with one empty slot.
  # - Each element of an array-like value is converted to a slot. Conversion
  #   rules for each child element:
  #   1. Rests become empty slots.
  #   2. Single Steps become slots containing just that Step.
  #   3. Single MIDI notes become slots containing a single Step created with
  #      that note and the default arguments to `Step.new`.
  #   4. Each element of an array-like child is converted into an array of
  #      Steps using rules analogous to the above, except that rests are
  #      ignored.
  #
  # If, after all the above conversions, there is more than one Step with the
  # same note in the same slot, a warning is printed, and only the Step with the
  # longest gate is chosen.
  #
  # The resulting grid must have at least one slot.
  #
  # In the end, gridish should do what you expect. For example:
  # - Pass a single note to get a one-slot track with just that note.
  # - Pass a 1d array of notes or Steps to get a mono track where each element
  #   becomes its own slot.
  # - Pass a 2d array of notes or Steps to get a poly track where each subarray
  #   represents the contents of a slot.
  # - Pass an array with some mixure of solitary notes/steps and arrays to
  #   easily express a track with some slots that contain multiple Steps and
  #   some that only contain one. E.g. if `gridish` is [:a1, [:b2, :c3], :d4],
  #   the result will be a Track with three slots, :a1 in the first, :b2 + :c3
  #   in the second, and :d4 in the third.
  def initialize(gridish, granularity: NoteLength::Eighth, scale: nil, timescale: 1)
    # Track itself does basically nothing with the scale; it's all handled by
    # the Player.
    @scale = scale

    super(gridish, granularity: granularity, timescale: timescale)
  end


  ### More interesting constructors

  # Constructs a Track that arpeggiates the given notes. See the `Arp` class
  # for possible values of the `direction` parameter, and the meaning of the
  # `spread` and `extra_octaves` arguments.
  #
  # If `pulses` and `length` are given, the arpeggiated notes are spread in a
  # Euclidean rhythm. The track will repeat the Euclidean pattern (while cycling
  # through the arpeggiated notes) however many times is needed to ensure that
  # all the notes are played and that the track loops cleanly, unless
  # `full_cycle` is false. The `rotate` parameter controls rotation of the
  # Euclidean pattern.
  def self.arp(notes, direction = Arp::Up, spread: 0, extra_octaves: [], pulses: nil, length: nil, rotate: 0, full_cycle: true, granularity: NoteLength::Eighth, timescale: 1)
    notes = Arp.arpeggiate(notes, direction, spread: spread, extra_octaves: extra_octaves)
    if pulses.nil?
      grid = notes.map { |n| [Step.new(n)] }
      new(grid, granularity: granularity, timescale: timescale)
    else
      raise "pulses and length must both be nil or both be integers" if length.nil?
      euclid(notes, pulses, length, rotate: rotate, full_cycle: full_cycle, granularity: granularity, timescale: timescale)
    end
  end

  # Constructs a track that arpeggiates the given degrees of the tonic note in
  # the given scale. Other arguments are as specified in arp.
  def self.arp_degrees(tonic, degrees, direction = Arp::Order, scale: :major, spread: 0, extra_octaves: [], pulses: nil, length: nil, granularity: NoteLength::Eighth, timescale: 1)
    notes = Arp.arp_degrees(tonic, degrees, direction, scale: scale, spread: spread, extra_octaves: extra_octaves)
    if pulses.nil?
      grid = notes.map { |n| [Step.new(n)] }
      new(grid, granularity: granularity, timescale: timescale)
    else
      raise "pulses and length must both be nil or both be integers" if length.nil?
      euclid(notes, pulses, length, full_cycle: true, granularity: granularity, timescale: timescale)
    end
  end

  # Construct an isorhythmic Track. See https://en.wikipedia.org/wiki/Isorhythm.
  # To use classical terms, `gates` defines the talea and `notes` the color.
  #
  # `gates` is an array of numbers which defines the rhythm over which `notes`
  # will be played. The numbers in `gates` will become the gates of the Steps in
  # the track. The values in `gates` may also be booleans - true will be
  # interpreted as a gate of 1 and false a gate of 0.
  #
  # Within `gates`, there are "runs". A run is a series of gates that would
  # define a tied sequence of steps (or single untied steps). For instance, a
  # gates array of [1, 0.5, 0.25, 1] defines 3 runs: the first two steps would
  # be tied together, then a standalone step with gate 0.25, and a final step
  # with gate 1. (Note that trailing tied steps are considered to end at the end
  # end of the array.)
  #
  # Each run in `gates` will be assigned the same note from the `notes` array.
  # Subsequent runs will be assigned the next note, cycling as needed if the
  # number of runs outnumbers the number of notes.
  #
  # The entire pattern of notes over the rhythm defined by `gates` will be
  # repeated as many times as needed so that the resulting track uses all the
  # elements of `notes` and cycles cleanly.
  #
  # This method has much in common with `euclid`, except that a "hit" can last
  # more than one slot.
  #
  # For example:
  # isorhythm([:a1, :b2, :c3], [1, 0.5, 0, 0.25]) would result in a track with
  # slots
  #   [:a1, S(:a1, gate: 0.5), :r, S(:b2, gate: 0.25),
  #    :c3, S(:c3, gate: 0.5), :r, S(:a1, gate: 0.25),
  #    :b2, S(:b2, gate: 0.5), :r, S(:c3, gate: 0.25)]
  # The `gates` array represents 2 runs, and you can see that each of those runs
  # was assigned the same note from `notes`. In the final track, the rhythm
  # defined by `gates` was repeated three times while cycling through `notes`,
  # so that every note was used and the track ends on the final note of `notes`.
  def self.isorhythm(notes, gates, granularity: NoteLength::Eighth, timescale: 1)
    # Gameplan:
    # This is a variation on `euclid` above, really, with the added complication
    # that a "hit" can last more than one slot.
    # Calculate the number of distinct notes that the `gates` array specifies.
    # That is: find the number of runs, a run being a sequence of tied notes.
    # Ties at the end of `gates` are considered ended even if they would
    # continue in a loop. As with `euclid` above, call that number p.
    # We are spreading n = notes.length notes over those p hits, and we want to
    # cleanly cycle while using all the notes. As per the calculation in
    # `euclid`, that will take exactly lcm(p, n) / p cycles.

    # We're going to leverage the existing run manipulation machinery on Track
    # by building a rhythm track with the proper gates but all C4s. We'll then
    # repeat that track, fixing up the notes as we go along.
    hit_grid = gates.map do |g|
      case g
      when 0, false
        []
      when true
        Step.new(:c4)
      else
        Step.new(:c4, gate: g)
      end
    end
    hit_track = Track.new(hit_grid, granularity: granularity, timescale: timescale)

    # TODO: make these methods public so we don't have to call them with send.
    run_count = 0
    hit_track.send(:each_run) { |_, _| run_count += 1 }

    needed_cycles = run_count.lcm(notes.length) / run_count

    # Now build up the track by mutating hit_track, needed_cycle times.
    track = nil
    note_idx = 0
    needed_cycles.times do
      this_track = hit_track.send(:mutate_runs) do |_, orig_steps|
        # Replace each note in the run with the proper note at note_idx. Aside
        # from the note, the Steps in hit_track already have the correct
        # properties.
        new_steps = orig_steps.map do |step|
          step.with_note(notes[note_idx])
        end

        note_idx = (note_idx + 1) % notes.length

        new_steps
      end

      if track.nil?
        track = this_track
      else
        track += this_track
      end
    end

    track
  end

  # An alias for `isorhythm`.
  def self.iso(*args, **kwargs)
    isorhythm(*args, **kwargs)
  end


  ### Mutators

  ## Granularity manipulations

  # Creates a new Track with double the granularity and number of slots. The
  # length of each Step is doubled to keep the Track sounding roughly the same,
  # which may entail turning a single step into multiple tied ones. For example,
  # expanding a 5-slot Track with 8th-note granularity will result in an 10-slot
  # Track with 16th-note granularity. A Step that had a gate of 90% would become
  # two Steps in back-to-back slots, one a tie and the following with 80% gate.
  def expand
    raise "Cannot expand past 64th-note granularity" if @granularity == NoteLength::SixtyFourth

    # Gameplan: each slot in the grid will expand to two slots. Consider each
    # slot individually. Each Step in that slot may expand to either one Step,
    # or two Steps in each of the new slots. Find the "total gate" for each Step
    # by multiplying its current gate by 2. If it is greater than one, the Step
    # becomes two Steps: one a tie, and the other with gate of total_gate - 1.
    # If the total gate is less than 1, the Step remains as one (longer) step in
    # the first of the new slots.

    def expand_step(step)
      step1_prob = step.prob
      total_gate = step.gate * 2.0
      if total_gate > 1  # TODO: tolerance?
        # If we expanded into two steps, only the second gets the probability.
        # (This is just the Oxi's behavior; it only arguably makes sense.)
        step1_prob = nil
        step2 = step.with_gate(total_gate - 1)
        total_gate = 1
      else
        step2 = nil
      end

      step1 = step.with_gate(total_gate).with_prob(step1_prob)

      [step1, step2]
    end

    new_grid = []
    @grid.each do |slot|
      new_slots = [[], []]
      slot.each do |step|
        step1, step2 = expand_step(step)
        new_slots[0] << step1
        new_slots[1] << step2 unless step2.nil?
      end

      new_grid.concat(new_slots)
    end

    mutate(grid: new_grid, granularity: @granularity.halve)
  end

  # Creates a new Track with half the granularity and number of slots. Steps and
  # tied Steps have their lengths halved to keep the track sounding roughly the
  # same. For example, condensing a 10-slot Track with 8th-note granularity will
  # result in a 5-slot Track with quarter-note granularity. Say the Track
  # contained two Steps in back-to-back slots for the same note, the first a tie
  # and the second with a gate of 80. That sequence of Steps would become one
  # Step in one slot in the new track, with a gate of 90.
  # Note that this operation is potentially significantly more lossy than
  # expand. Steps with short gates and those starting on off-beats may be
  # completely absent from the result.
  def condense
    raise "Cannot condense past whole-note granularity" if @granularity == NoteLength::Whole

    # Gameplan: each pair of slots in the grid will collapse into one slot in a
    # new grid. In each pair, find the total gate of any given Step by checking
    # if it is tied to a Step with the same note in the following slot. Divide
    # that total gate by 2 and make a new step. Repeat, condensing all the steps
    # from the pair of slots into shorter steps in one slot.

    # Condense two Steps for the same note into one. The Steps are passed in-
    # order as they appear in the Track. One or the other may be nil, but not
    # both. May return nil if the steps condense to nothing.
    def condense_steps(step1, step2)
      # The Oxi seems to discard anything that begins on the second slot when
      # condensing.
      return nil if step1.nil?

      if step2.nil?
        total_gate = step1.gate / 2.0
      else
        total_gate = (step1.gate + step2.gate) / 2.0
      end

      # The probability and velocity of the second step is discarded; the first
      # step wins. (Again, just Oxi behavior.)
      step1.with_gate(total_gate)
    end

    # Condense the Steps from one or two slots into one new slot. The second
    # slot will be nil for the last slot in a Track with an odd number of slots.
    def condense_slots(slot1, slot2 = nil)
      steps_by_note = Hash.new { |h, k| h[k] = [nil, nil] }
      slot1.each { |step| steps_by_note[step.note][0] = step }
      slot2&.each { |step| steps_by_note[step.note][1] = step }

      new_slot = []
      steps_by_note.each_value do |steps|
        condensed_step = condense_steps(*steps)
        new_slot << condensed_step unless condensed_step.nil?
      end

      new_slot
    end

    new_grid = []
    @grid.each_slice(2) do |slot_chunk|
      new_grid << condense_slots(*slot_chunk)
    end

    mutate(grid: new_grid, granularity: @granularity.double)
  end

  # Calls expand or condense the appropriate number of times to return a new
  # Track with the given granularity.
  def regranularize(new_granularity)
    new_granularity = NoteLength.new(new_granularity)

    return self if @granularity == new_granularity

    # NOTE: this is obviously very silly, but the alternative would be making
    # expand and condense way more complicated, which is not worth it.

    steps = @granularity.steps_to(new_granularity)
    new_track = self
    steps.times do
      new_track = new_granularity < @granularity ? new_track.expand : new_track.condense
    end

    new_track
  end

  alias regrain regranularize
  alias grain regranularize

  # Returns a new track with the given scale.
  def with_scale(scale)
    mutate(scale: scale)
  end


  ## Grid-level mutations

  # Returns two tracks by extracting Steps that match the given note. The first
  # track contains the non-matching Steps, and the second contains the matching
  # ones. See `MIDINote.match?` for matching rules.
  def extract_note(note)
    extract { |step| step.note.match?(note) }
  end

  alias extract_notes extract_note


  ## Step-level mutations

  # Return a new Track where each Step has the given gate.
  def with_gate(new_gate)
    mutate_each_step { |step| step.with_gate(new_gate) }
  end

  alias gate with_gate

  # Return a new Track where each step's gate is scaled by the given factor.
  def scale_gate(factor)
    mutate_each_step { |step| step.with_gate(step.gate * factor) }
  end

  # Returns a new Track where each Step's gate is replaced with the result of
  # `curve_func`. `curve_func` must take 1-2 arguments:
  # - the percentage through the track (0.0-1.0) where the slot falls in the
  #   Track
  # - the index of the slot in the Track
  #
  # `curve_func` should return a floating point value 0-1 that will be used for
  # all Steps in the slot at that percentage/index.
  #
  # If `min` or `max` is provided, the curve function will be scaled via
  # `Curves.scale` so that it falls in the given range. If only one of `min` or
  # `max` is provided, the other defaults to the respective endpoint of the
  # range 0-1.
  def with_gate_curve(curve_func, min: nil, max: nil)
    raise "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2

    if !min.nil? || !max.nil?
      min = 0 if min.nil?
      max = 1 if max.nil?
      curve_func = Curves.scale(curve_func, min, max)
    end

    mutate_each_step do |step, slot_idx, pct|
      args = [pct, slot_idx].take(curve_func.arity)
      gate = curve_func.call(*args)

      step.with_gate(gate)
    end
  end

  alias gate_curve with_gate_curve

  # Return a new Track where each Step has the given velocity, specified in the
  # MIDI range of 0 - 127.
  def with_vel(new_vel)
    mutate_each_step { |step| step.with_vel(new_vel) }
  end

  alias vel with_vel

  # Return a new Track where each Step has the given velocity, specified as a
  # value between 0 and 1, inclusive.
  def with_velf(new_velf)
    mutate_each_step { |step| step.with_velf(new_velf) }
  end

  alias velf with_velf

  # Return a new Track where each Step's velocity is scaled by the given factor.
  def scale_vel(factor)
    mutate_each_step { |step| step.with_vel(step.vel * factor) }
  end

  alias scale_velf scale_vel

  # Returns a new Track where each Step's velocity is replaced with the result
  # of `curve_func`. `curve_func` must take 1-2 arguments:
  # - the percentage through the track (0.0-1.0) where the slot falls in the
  #   Track
  # - the index of the slot in the Track
  #
  # `curve_func` should return a velocity to use for all Steps in the slot at
  # that percentage/index. The value returned by `curve_func` should be either:
  # - If `zero_to_one` is true, a floating point number 0 - 1 that will be
  #   scaled to a velocity value between 0 and 127, inclusive.
  # - If `zero_to_one` is false, an integer between 0 and 127, inclusive.
  #
  # `with_velf_curve` is an alias where `zero_to_one` is true.
  #
  # If `min` or `max` is provided, the curve function will be scaled via
  # `Curves.scale` so that it falls in the given range. If only one of `min` or
  # `max` is provided, the other defaults to the respective endpoint of the
  # range of the curve function (0 - 127 if `zero_to_one` is false, otherwise
  # 0 - 1).
  def with_vel_curve(curve_func, zero_to_one: false, min: nil, max: nil)
    raise "Curve function must be a callable that takes 1-2 arguments" if !curve_func.respond_to?(:call) || curve_func.arity == 0 || curve_func.arity > 2

    if !min.nil? || !max.nil?
      min = 0 if min.nil?
      max = zero_to_one ? 1 : 127 if max.nil?

      curve_func = Curves.scale(curve_func, min, max, orig_min: 0, orig_max: zero_to_one ? 1 : 127)
    end

    mutate_each_step do |step, slot_idx, pct|
      args = [pct, slot_idx].take(curve_func.arity)
      vel = curve_func.call(*args)

      vel *= 127 if zero_to_one  # with_vel will round & clamp this
      step.with_vel(vel)
    end
  end

  alias vel_curve with_vel_curve

  # An alias for `with_vel_curve` with `zero_to_one` set to true.
  def with_velf_curve(curve_func, min: nil, max: nil)
    with_vel_curve(curve_func, zero_to_one: true, min: min, max: max)
  end

  alias velf_curve with_velf_curve

  # Returns a new Track that fades in linearly, via velocity. `min` is the
  # starting velocity and `max` is the final velocity. `start` specifies at what
  # percentage through the track to begin the fade; all steps before `start`
  # will have a velocity of min, and ones thereafter will linearly increase to
  # `max`.
  def fade_in_linear(min = 0.0, max = 1.0, start: 0.0)
    with_velf_curve(Curves.fade_in_linear(min, max, start))
  end

  alias fade_in_lin fade_in_linear
  alias fade_in fade_in_linear
  alias in_lin fade_in_linear

  # Same as `fade_in_linear`, but quadratically increases velocity.
  def fade_in_quad(min = 0.0, max = 1.0, start: 0.0)
    with_velf_curve(Curves.fade_in_quad(min, max, start))
  end

  alias in_quad fade_in_quad

  # Returns a new Track that fades out linearly, via velocity. `max` is the
  # starting velocity and `min` is the final velocity. `start` specifies at what
  # percentage through the track to begin the fade; all steps before `start`
  # will have a velocity of `max`, and ones thereafter will linearly decrease to
  # `min`.
  def fade_out_linear(max = 1.0, min = 0.0, start: 0.0)
    with_velf_curve(Curves.fade_out_linear(max, min, start))
  end

  alias fade_out_lin fade_out_linear
  alias fade_out fade_out_linear
  alias out_lin fade_out_linear

  # Same as `fade_in_quad`, but quadratically decreases velocity.
  def fade_out_quad(max = 1.0, min = 0.0, start: 0.0)
    with_velf_curve(Curves.fade_out_quad(max, min, start))
  end

  alias out_quad fade_out_quad

  # Finds runs of tied Steps with the same notes and yields to its block two
  # arguments for each: the index of the slot that begins the run, and the array
  # of Steps that belong to the run. A run is ended by the end of the track, or
  # a Step that is not tied. The final Step in a run is included in the array
  # yielded to the block. Runs that consist of a single Step (i.e. non-tied
  # Steps that are not continuing a note from the previous Step, or Steps at the
  # end of the Track that are not continuing a note) are also yielded to the
  # block.
  private def each_run
    ended_runs = []
    active_runs_by_note = {}  # notes -> { starting_slot_idx:, steps: }

    @grid.each_with_index do |slot, slot_idx|
      # Find what's new and what continues in this slot.
      slot.each do |step|
        run_info = active_runs_by_note[step.note]
        if run_info.nil?
          # A new run.
          run_info = { starting_slot_idx: slot_idx, steps: [step] }

          # If it's not tied it ends immediately.
          if step.tied?
            active_runs_by_note[step.note] = run_info
          else
            ended_runs << run_info
          end
        else
          # If the step is tied, the run continues. Otherwise it ends here.
          run_info[:steps] << step
          unless step.tied?
            ended_runs << run_info
            active_runs_by_note.delete(step.note)
          end
        end
      end

      # Now look for ended runs, which are missing in this slot.
      ended_notes = []
      active_runs_by_note.each do |note, run_info|
        next if slot.any? { |step| step.note == note }

        # This is an ended run.
        ended_runs << run_info
        ended_notes << note
      end

      ended_notes.each { |note| active_runs_by_note.delete(note) }
    end

    # Collect runs that lasted the whole track, and sort.
    ended_runs += active_runs_by_note.values
    ended_runs.sort_by! { |run_info| run_info[:starting_slot_idx] }

    ended_runs.each do |run_info|
      yield run_info[:starting_slot_idx], run_info[:steps]
    end
  end

  # Returns a new Track with the Steps in a run of tied Steps with the same note
  # is replaced with another set of Steps.
  #
  # `starting_slot_idx` is the index of the slot where replacement should begin.
  # `orig_steps` is an array of the original steps that are being replaced. ]
  # `new_steps` is an array of steps which should replace those from
  # `orig_steps`.
  #
  # `orig_steps` must be the actual Step instances that are currently in this
  # Track, not copies of them with the same properties. This method is meant to
  # be used in tandem with `each_run`, which returns such an array of steps.
  #
  # This method works by first removing all the steps from `orig_steps` from
  # their corresponding slots, and then adding all the steps from `new_steps`.
  # So, it is valid for new_steps to be a different length than `orig_steps`, as
  # long as `starting_slot_idx + new_steps.length` is not greater than the
  # length of the track.
  protected def set_run(starting_slot_idx, orig_steps, new_steps)
    raise "replacement steps are past the end of the track" if starting_slot_idx + new_steps.length > @grid.length

    new_grid = mutable_grid_dup

    orig_steps.each_with_index do |orig_step, i|
      new_grid[starting_slot_idx + i].delete orig_step
    end

    # TODO: gridify new_steps?
    new_steps.each_with_index do |new_step, i|
      new_grid[starting_slot_idx + i] << new_step
    end

    mutate(grid: new_grid)
  end

  # Returns a new Track with each run of tied Steps replaced with those returned
  # from the block. The block will be given two arguments: the index of the slot
  # where the run begins, and an array of the Steps that constitute the run. The
  # block should return an array of Steps, which will take the place of the
  # run's Steps in the returned track. The array returned from the block may
  # have a different length than the original run, but, when the new Steps are
  # added beginning at the run's starting slot, they must not exceed the length
  # of the Track.
  private def mutate_runs
    new_track = self
    each_run do |starting_slot_idx, orig_steps|
      new_steps = yield starting_slot_idx, orig_steps.dup  # TODO: why did I dup that?
      new_track = new_track.set_run(starting_slot_idx, orig_steps, new_steps)
    end
    new_track
  end

  # Returns a new track where the final Steps in runs of tied Steps with the
  # same note are replaced with the result of the block. Helper for `taper_vel`
  # and `taper_gate`.
  private def taper_steps(taper_final_tie: false, taper_single: false)
    mutate_runs do |starting_slot_idx, steps|
      run_loops = false

      if (starting_slot_idx + steps.length) == @grid.length && steps[-1].tied?
        run_loops = @grid[0].any? { |slot_0_step| slot_0_step.note == steps[-1].note }
        next steps if run_loops && !taper_final_tie
      end

      next steps if steps.length == 1 && !run_loops && !taper_single

      steps[-1] = yield steps[-1]
      steps
    end
  end

  # Returns a new Track by setting the gate on the final Step of runs of tied
  # Steps with the same note.
  #
  # The final Step does not have to be tied for this method to adjust its gate;
  # such a step's gate will be set to `trailing_gate`.
  #
  # If `taper_final_tie` is false (the default), Steps in the final slot of the
  # track will not have their gate adjusted if they are tied and are continued
  # with a Step with the same note in the first slot of the track.
  #
  # If `taper_single` is true, standalone Steps that are not continuations of a
  # tie also have their gate adjusted. Note that Steps in the final slot of the
  # Track that are tied and continue in the first slot of the track are not
  # effected by `taper_single`.
  def taper_gate(trailing_gate = 0.75, taper_final_tie: false, taper_single: false)
    taper_steps(taper_final_tie: taper_final_tie, taper_single: taper_single) { |s| s.with_gate(trailing_gate) }
  end

  # Returns a new Track by setting the velocity on the final Step of runs of
  # tied steps, in the same manner as `taper_gate`. If `zero_to_one` is true,
  # the velocity is a percentage between 0 and 1, rather than a MIDI value from
  # 0 - 127. `taper_velf` is an alias with zero_to_one set to true.
  def taper_vel(trailing_vel = 64, taper_final_tie: false, taper_single: false, zero_to_one: false)
    trailing_vel *= 127 if zero_to_one
    taper_steps(taper_final_tie: taper_final_tie, taper_single: taper_single) { |s| s.with_vel(trailing_vel) }
  end

  # An alias for `taper_vel` with `zero_to_one` set to true.
  def taper_velf(trailing_vel = 0.5, taper_final_tie: false, taper_single: false)
    taper_vel(trailing_vel, taper_final_tie: taper_final_tie, taper_single: taper_single, zero_to_one: true)
  end

  # Returns a new Track where the octave of each Step's note is set to the given
  # value.
  def with_octave(new_octave)
    mutate_each_step { |step| step.with_octave(new_octave) }
  end

  alias octave with_octave
  alias oct octave

  # Returns a new Track by shifting the octave of each Step's note by the given
  # amount.
  def shift_octave(shift)
    mutate_each_step { |step| step.shift_octave(shift) }
  end

  # Returns a new Track by increasing the octave of each Step's note by the
  # given amount.
  def up(octave_shift = 1)
    shift_octave(octave_shift)
  end

  # Returns a new Track by decreasing the octave of each Step's note by the
  # given amount.
  def down(octave_shift = 1)
    shift_octave(-octave_shift)
  end

  # Return a new Track that, with probability p, shifts the octave of each Step
  # by a random value in the given range. If range is an integer,
  # [-range, range] is used.
  def rand_octave(range = 1, p: 0.5)
    mutate_each_step do |step|
      next step unless ExtApi.rand < p

      # We've already decided to shift, so ignore random 0 values. Not using
      # rand_i here since it's exclusive. rand is too, but we're rounding.
      shift = 0
      while shift == 0
        if range.is_a?(Range)
          shift = ExtApi.rand(range).round
        else
          shift = ExtApi.rand(-range..range).round
        end
      end

      step.shift_octave(shift)
    end
  end

  alias roct rand_octave

  # Returns a new Track where each Step's note is shifted by the given number of
  # semitones.
  def shift_tone(shift)
    mutate_each_step { |step| step.shift_tone(shift) }
  end

  alias tone shift_tone
  alias transpose shift_tone

  # Returns a new Track where each Step's note is increased by the given number
  # of semitones.
  def semi_up(tone_shift = 1)
    shift_tone(tone_shift)
  end

  alias sup semi_up

  # Returns a new Track where each Step's note is decreased by the given number
  # of semitones.
  def semi_down(tone_shift = 1)
    shift_tone(-tone_shift)
  end

  alias sdown semi_down

  # For each slot, yields to its block a two-element array of:
  # - the Step in the slot being harmonized, or nil if the slot is empty
  # - an array of notes that harmonize with the note in the step, as given by
  #   `MIDINote.harmonize`. The note from the Step itself is not included.
  #   If the note is not in the given scale, or if the slot is empty, this array
  #   is empty.
  private def iter_harmonized_slots(tonic, scale_name, position:, voices: nil)
    # This is an artificial but pretty sensible limitation.
    raise 'Only a mono track can be harmonized' unless mono?

    raise "position must be 0, 1, 2, or :rand" unless position == :rand || (position >= 0 && position < 3)
    if voices.is_a?(Numeric)
      raise "If voices is an integer, it must be 1, 2, or 3" unless [1, 2, 3].contain?(voices)
    elsif voices.is_a?(Array)
      raise "If voices is an array, all of its elements must be 1, 2, or 3" unless voices.all? { |v| [1, 2, 3].contain?(v) }
    elsif !voices.nil?
      raise "voices must be an integer or an array"
    end

    random_pos = position == :rand
    position = ExtApi.rand_i(3) if random_pos

    # Massage the voice argument indices if needed
    if voices.is_a?(Array)
      voices = voices.map { |i| 3 - i }
    end

    @grid.each do |slot|
      if slot.empty?
        # Note that this early exit means position does not get incremented/
        # randomized for rests.
        yield [nil, []]
        next
      end

      s = slot[0]

      notes = s.note.harmonize(tonic, scale_name, position: position)
      notes.pop  # Remove the step note itself (which may leave the array empty)

      if voices.is_a?(Numeric)
        # Take the final voices-many notes (they're lowest->highest)
        notes = notes.pop(voices)
      elsif voices.is_a?(Array)
        notes = notes.values_at(*voices)
      end

      yield [s, notes]

      if random_pos
        position = case position
        when 0
          ExtApi.choose([1, 2])
        when 1
          ExtApi.choose([0, 2])
        when 2
          ExtApi.choose([0, 1])
        end
      else
        position = (position + 1) % 3
      end
    end
  end

  # Return a new Track where each slot has new Steps added to it for notes that
  # harmonize with the existing Step in that slot. Can only be called on mono
  # tracks. Arguments are as described in `MIDINote.harmonize`.
  #
  # `position` is the starting position to use when harmonizing. It may be 0, 1,
  # 2, or :rand. If it is an integer, the position will increment for each step.
  # If it is :rand, random, non-repeating positions will be used.
  #
  # `voices` represents which voices of the harmony to include in the results.
  # If it is an integer, it represents the number of voices to include (from
  # high to low). If it is an array, it represents individual voices to include
  # (from high to low; bass is 3 and soprano is 1).
  #
  # If a note in the Track is not in the given scale, no additional notes will
  # be added in that slot.
  def harmonize(tonic, scale_name, position: 0, voices: nil)
    new_grid = []
    iter_harmonized_slots(tonic, scale_name, position: position, voices: voices) do |step, notes|
      if step.nil?
        new_grid << []
      else
        new_slot = notes.map { |n| Step.new(n) }
        new_slot.unshift(step)
        new_grid << new_slot
      end
    end

    mutate(grid: new_grid)
  end

  # Returns an array of three new Tracks, each representing a voice harmonized
  # with the note in the corresponding slot in this track. Can only be called
  # on mono tracks. The tracks are returned from lowest (bass) to highest
  # (soprano). Arguments are as described in `harmonize`.
  #
  # If a note in the track is not in the given scale, there will be a rest in
  # the corresponding slots in the returned tracks.
  def split_harmonize(tonic, scale_name, position: 0)
    new_grids = [[], [], []]
    iter_harmonized_slots(tonic, scale_name, position: position) do |step, notes|
      if step.nil? || notes.empty?
        new_grids.each { |g| g << [] }
      else
        notes.each_with_index do |n, i|
          new_grids[i] << [Step.new(n)]
        end
      end
    end

    new_grids.map { |g| mutate(grid: g) }
  end

  # Return a new Track in which each Step has its note snapped to the nearest
  # note among the given array, which should consist of MIDI note numbers or
  # symbols.
  def snap_to_notes(notes)
    mutate_each_step { |step| step.with_note(step.note.snap(notes)) }
  end

  # Return a new Track in which each Step has its note snapped to the nearest
  # note in the given scale starting at the given tonic. `tonic` should be a
  # symbol or string for a pitch class (e.g. :c), and `scale_name` should be one
  # of the scale names known to the Scale class.
  #
  # Unlike providing a global Track scale for quantization in the initializer,
  # this action is destructive and will return a new track with modified notes.
  def snap_to_scale(tonic, scale_name)
    scale = Scale.full_scale(tonic, scale_name)
    mutate_each_step { |step| step.with_note(scale.snap(step.note)) }
  end

  # Returns a new Track where each Step with note `orig` is replaced with a Step
  # that has note `repl` but is otherwise identical. If `orig` has an explicit
  # octave (or is a MIDI note number), only Steps with that exact note are
  # effected. If `orig` does not have an explicit octave, all Steps with the
  # same pitch class as `orig` have their notes changed to `repl`. If `repl`
  # also does not have an octave, the replacements are in the same octave as the
  # original Step. For instance, consider a Track with Steps
  #     :c4, [:d1, :d2], :c3
  # `sub_note(:c, :e)` on that track would result in a Track with the Steps
  #     :e4, [:d1, :d2], :e3
  # And `sub_note(:c, :f9)` would result in
  #     :f9, [:d1, :d2], :f9
  # But `sub_note(:d2, :f9)` would only match the D2:
  #     :c4, [:d1, :f9], :c3
  # `repl` may be nil, :r, or :rest to remove Steps that match `orig`.
  def sub_note(orig, repl)
    orig_has_octave = MIDINote.has_octave?(orig)
    repl_is_rest = MIDINote.rest?(repl)
    repl_has_octave = repl_is_rest ? false : MIDINote.has_octave?(repl)

    orig = MIDINote.new(orig)

    mutate_each_step do |step|
      if (orig_has_octave && step.note == orig) || (!orig_has_octave && step.note.pitch_class == orig.pitch_class)
        if repl_is_rest
          nil
        elsif repl_has_octave
          step.with_note(repl)
        else
          step.with_note(step.note.with_pitch_class(repl))
        end
      else
        step
      end
    end
  end

  alias sub sub_note
  alias replace_note sub_note
  alias replace sub_note

  # Returns a new Track, applying controlled random mutations to each Step. The
  # probability that any given mutation will apply to a Step is given by the `p`
  # parameter. Any given Step may have 0 or more independent mutations applied
  # to it.
  #
  # Possible changes:
  # - A transposition. The `tone_shifts` array (which may be nil) provides the
  #   possible semitone offsets that may be applied to a Step; a random value
  #   from it will be chosen if a transposition is to be applied. The
  #   `octave_limit` range describes the valid octaves in which a transposition
  #   can result. If the transposition moves a note outside of `octave_limit`,
  #   the note's octave is clamped to the closest extreme of `octave_limit`.
  # - A gate shift. The `gate_delta` float provides the maximum shift to apply
  #   to a Step; a random value between 0 and `gate_delta` will be chosen if a
  #   gate shift is to be applied. The `gate_limit` range restricts the
  #   resulting gate value in the same way `octave_limit` restricts
  #   transpositions.
  # - A velocity shift, controlled by `velf_delta` and `velf_limit` in the same
  #   way as a gate shift.
  def evolve(tone_shifts: [-12, 12], octave_limit: 1..6, gate_delta: 0.5, gate_limit: 0.1..1, velf_delta: 0, velf_limit: 0.1..1, p: 0.25)
    gate_delta = -gate_delta..gate_delta unless gate_delta.is_a?(Range)
    velf_delta = -velf_delta..velf_delta unless velf_delta.is_a?(Range)
    tone_shifts = [0] if tone_shifts == 0 || tone_shifts.nil?

    mutate_each_step do |step|
      tone_shift = (ExtApi.rand < p) ? ExtApi.choose(tone_shifts) : 0
      gate_shift = (ExtApi.rand < p) ? ExtApi.rand(gate_delta) : 0
      velf_shift = (ExtApi.rand < p) ? ExtApi.rand(velf_delta) : 0

      if tone_shift != 0
        step = step.shift_tone(tone_shift)

        new_octave = step.note.octave
        new_octave = octave_limit.min if new_octave < octave_limit.min
        new_octave = octave_limit.max if new_octave > octave_limit.max

        step = step.with_octave(new_octave)
      end

      if gate_shift != 0
        new_gate = step.gate + gate_shift
        new_gate = gate_limit.min if new_gate < gate_limit.min
        new_gate = gate_limit.max if new_gate > gate_limit.max

        step = step.with_gate(new_gate)
      end

      if velf_shift != 0
        new_velf = step.velf + velf_shift
        new_velf = velf_limit.min if new_velf < velf_limit.min
        new_velf = velf_limit.max if new_velf > velf_limit.max

        step = step.with_velf(new_velf)
      end

      step
    end
  end


  ### CCTrack mappers

  # Return a new CCTrack generated by the result of a block which is called for
  # each slot in this track. The block must take 1-3 arguments:
  # - The slot
  # - The index of the slot in the Track
  # - The percent through the Track that the slot represents. For instance, the
  #   first slot of the track will have percent 0, the middle slot (in a Track
  #   with an odd number of slots) will have percent 0.5, and the final slot
  #   will have percent 1.0.
  #
  # The block may return:
  # - A single CCStep which will be converted to a single-step slot in the
  #   result.
  # - A slot (an array of CCSteps).
  # - nil, :r, or :rest, which will result in an empty slot (i.e. a rest) in the
  #   result. Note that this is the same as returning an empty array.
  # - An array of slots, which will all be added to the result in order.
  def to_cc(&block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    new_grid = []
    @grid.each_with_index do |slot, i|
      if i == 0
        pct = 0.0
      elsif i == @grid.length - 1
        pct = 1.0
      else
        pct = i.to_f / (num_slots - 1)
      end

      args = [slot, i, pct].take(block.arity)
      replacement = block.call(*args)

      # The block may return something convertible to a slot (a CCStep), or a
      # 1d array (which we will take as a slot), or an array that contains some
      # number of other arrays (which we will take as a set of slots). This
      # behavior is in keeping with mutate_slots.
      replacement = [replacement] unless ExtApi.enumerable?(replacement)
      is_gridish = replacement.any? { |e| ExtApi.enumerable?(e) }

      if is_gridish
        new_grid += CCTrack.gridify(replacement)
      else
        new_grid << replacement  # This will get slotified by the initializer.
      end
    end

    CCTrack.new(new_grid, granularity: @granularity, timescale: @timescale)
  end

  alias cc to_cc

  # Return a new CCTrack generated by the result of a block which is called for
  # each slot in this track. Unlike `to_cc`, this method assumes that all
  # CCSteps in the resulting track will effect the same CC number, which is
  # given as the `cc_number` argument.
  #
  # The block must take 1-3 arguments:
  # - The slot
  # - The index of the slot in the Track
  # - The percent through the Track that the slot represents. For instance, the
  #   first slot of the track will have percent 0, the middle slot (in a Track
  #   with an odd number of slots) will have percent 0.5, and the final slot
  #   will have percent 1.0.
  #
  # The block may return:
  # - A single number which will be used together with `cc_number` to make a
  #   one-step slot with a corresponding CCStep in the result.
  # - nil, :r, or :rest, which will result in an empty slot (i.e. a rest) in the
  #   result.
  # - An array of numbers, each of which will be converted as above and added
  #   to individual slots in the result.
  def to_simple_cc(cc_number, &block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    slots = []
    @grid.each_with_index do |slot, i|
      if i == 0
        pct = 0.0
      elsif i == @grid.length - 1
        pct = 1.0
      else
        pct = i.to_f / (num_slots - 1)
      end

      args = [slot, i, pct].take(block.arity)
      replacement = block.call(*args)

      # The block may return a scalar (which we take as a CC value), or an array
      # (which we will take as a definition for a set of slots).
      if ExtApi.enumerable?(replacement)
        if replacement.empty?
          slots << :r
        else
          slots += replacement
        end
      else
        slots << replacement
      end
    end

    CCTrack.simple(cc_number, slots, granularity: @granularity, timescale: @timescale)
  end

  alias simple_cc to_simple_cc


  ### Track construction helpers

  # Attempts to convert its argument to a Step. Conversion rules are:
  # - Steps are passed through verbatim.
  # - Notes (symbols, strings, numbers and MIDINote instances) are converted to
  #   Steps using that note and the default values for the other arguments of
  #   Step's initializer.
  # - It is an error to pass a rest (as defined by `MIDINote.rest?`) to this
  #   function.
  #
  # `def_gate` and `def_vel` will be used for any Steps that need to be
  # constructed.
  def self.stepify(x, def_gate: 1.0, def_vel: 127)
    raise "A rest cannot be converted to a Step" if MIDINote.rest?(x)

    case x
    when Step
      x
    when Symbol, String, Numeric, MIDINote
      Step.new(x, gate: def_gate, vel: def_vel)
    else
      raise "Not a valid value for a Step: #{x.inspect}"
    end
  end

  # Given a slot (an array of Steps), returns a new slot with at most one Step
  # with each note. If multiple Steps in the input have the same note, one with
  # the longest gate is chosen.
  def self.dedupe_slot(slot)
    steps_by_note = {}
    yelled = false
    slot.each do |step|
      old_step_with_same_note = steps_by_note[step.note]
      if old_step_with_same_note.nil?
        steps_by_note[step.note] = step
      else
        unless yelled
          ExtApi.puts("warning: more than one Step with note #{step.note} in the same slot! Picking one with the longest gate!")
          yelled = true
        end
        steps_by_note[step.note] = step if old_step_with_same_note.gate < step.gate
      end
    end

    steps_by_note.values
  end

  private_class_method :dedupe_slot

  # Attempts to convert its argument to a grid slot (i.e. an array of Steps).
  # The returned array will be frozen. Conversion rules:
  # - Rests (see `MIDINote.rest?`) become an empty slot ([]).
  # - Single notes (symbols, strings, numbers, or MIDINote instances) become a
  #   slot with a single Step that is the result of calling `stepify` on the
  #   argument.
  # - Single Steps become a slot containing just that Step.
  # - Array-like arguments are converted as follows:
  #   1. All rests are removed.
  #   2. All remaining elements are passed through `stepify`.
  #   3. If more than one of the resulting Steps has the same note, a warning is
  #      printed, and only the Step with the longest gate is chosen.
  #
  # `def_gate` and `def_vel` will be used for any Steps that need to be
  # constructed.
  def self.slotify(x, def_gate: 1.0, def_vel: 127)
    return [].freeze if MIDINote.rest?(x)

    case x
    when Step
      [x].freeze
    when Symbol, String, Numeric, MIDINote
      [stepify(x, def_gate: def_gate, def_vel: def_vel)].freeze
    else
      if ExtApi.enumerable?(x)
        # See the note in ExtApi about why we need to explicitly call to_a here.
        raw_slot = x.to_a.reject { |s| MIDINote.rest?(s) }.map { |s| stepify(s, def_gate: def_gate, def_vel: def_vel) }
        dedupe_slot(raw_slot).freeze
      else
        raise "Not a valid value for a slot: #{x.inspect}"
      end
    end
  end

  # Attempts to convert its argument to a grid (a 2d array of Steps). The
  # returned array and all of its elements will be frozen. Conversion rules:
  # - A single rest (see `MIDINote.rest?`) becomes a grid with one rest ([[]]).
  # - A single note (symbol, string, number or MIDINote instance) becomes a grid
  #   with one slot that is the result of calling `slotify` on the argument.
  # - A single Step becomes a grid with one slot containing that Step.
  # - Array-like arguments are converted by passing each element through
  #   `slotify`.
  #
  # `def_gate` and `def_vel` will be used for any Steps that need to be
  # constructed.
  def self.gridify(x, def_gate: 1.0, def_vel: 127)
    return [[].freeze].freeze if MIDINote.rest?(x)

    case x
    when Step
      [[x].freeze].freeze
    when Symbol, String, Numeric, MIDINote
      [slotify(x, def_gate: def_gate, def_vel: def_vel)].freeze
    else
      if ExtApi.enumerable?(x)
        # NOTE: this will convert non-array child elements into individual slots.
        # E.g. gridify([:a1, :b1]) will turn into [[:a1], [:b1]]. I think that's
        # desirable - it's a sort of 'smart' conversion, preferring mono-like
        # behavior unless notes are explicitly grouped into their own array.
        # See the note in ExtApi about why we need to explicitly call to_a here.
        x.to_a.map { |s| slotify(s, def_gate: def_gate, def_vel: def_vel) }.freeze
      else
        raise "Not a valid value for a grid: #{x.inspect}"
      end
    end
  end


  protected

  def ctor_kwargs
    kwargs = super
    kwargs[:scale] = nil
    kwargs
  end
end
