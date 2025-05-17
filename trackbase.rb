# frozen_string_literal: true

require_relative "extapi"
require_relative "theory/notelength"
require_relative "step"
require_relative "prob"


# Set global Track behaviors.
# strict_track_merging: If true, Tracks with mismatched granularities or
# timescales cannot interact with one another. That is, they cannot be merged,
# joined, zipped, or otherwise commingle. If false, generally speaking, the
# track on which a method is being called is the one that will determine the
# granularity and timescale of the result. E.g., in t1.zip(t2), the result will
# have the properties of t1. Default: false.
def use_track_defaults(strict_track_merging:)
  ExtApi.set(:__track_defaults, { strict_track_merging: strict_track_merging })
end


# A Track is mostly a "grid" of Steps together with a granularity. The grid is a
# 2d array, each element of which is a "slot". A slot contains some number
# (possibly 0) of Steps. Those are the Steps that should trigger (subject to
# their probabilities) when that slot is played. The order of Steps within a
# slot is not significant. There should not be more than one Step with the same
# note in a given slot; if there is, one with the longest gate will be used.
# Each slot represents the Steps for a timespan equal to the Track's
# granularity, which is some fraction of a beat (e.g. 1/4 for sixteenth note
# granularity). An empty slot represents a rest for the same duration. Thus the
# length of a Track in beats is the granularity multiplied by the number of
# slots in the grid.
# Tracks also have a timescale, which is the speed at which this track will play
# relative to the global bpm. A timescale of 2 means that this track will play
# at twice the global bpm, e.g., and 0.5 means half-speed.
# A Track may have a global scale assigned, which should be an instance of Scale
# (you probably want one from the `full_scale` method). If such a scale is
# provided, all the notes in the track are quantized to that scale before being
# played. Note that that operation is non-destructive; a Track with a scale can
# contain Steps with notes that are not on the scale, and they will be snapped
# to the scale just in time for playback. Also note that the snapping operation
# may result in duplicate notes within one slot (e.g. a C# and a D on a C major
# scale will both result in a D). In that case, the Step with the longest gate
# is played.
# TODO: does timescale belong here? really only effects the Player, so it could
# live there, but this feels like a convenient place for it (& to mutate it)
class TrackBase
  attr_reader :granularity, :grid, :timescale


  ### Basic constructors

  # Constructs a track with the given "gridish" definition. gridish will be
  # converted into a proper grid, an array of "slots". A slot is itself an
  # array of Steps, which all play simultaneously for a duration of the
  # granularity. A slot may be empty to represent a rest.
  # gridish is converted to a grid in the following way:
  # - A single MIDI note (symbol, string, or number) becomes grid with one slot
  #   containing a single Step created with that note and the default arguments
  #   to Step.new.
  # - A single Step becomes a grid with one slot containing just that Step.
  # - A single rest (see MIDINote.rest?) becomes a grid with one empty slot.
  # - Each element of an array-like value is converted to a slot. Conversion
  #   rules for each child element:
  #   1. Rests become empty slots.
  #   2. Single steps become slots containing just that step.
  #   3. Single MIDI notes become slots containing a single step created with
  #      that note and the default arguments to Step.new.
  #   4. Each element of an array-like child is converted into an array of
  #      Steps using rules analogous to the above, except that rests are
  #      ignored.
  # If, after all the above conversions, there is more than one Step with the
  # same note in the same slot, a warning is printed, and only the Step with the
  # longest gate is chosen.
  # The resulting grid must have at least one slot.
  # In the end, gridish should do what you expect. For example:
  # - Pass a single note to get a one-slot track with just that note.
  # - Pass a 1-d array of notes or Steps to get a mono track where each element
  #   becomes its own slot.
  # - Pass a 2-d array of notes or Steps to get a poly track where each subarray
  #   represents the contents of a slot.
  # - Pass an array with some mixure of solitary notes and arrays to easily
  #   express a track with some slots that contain multiple Steps and some that
  #   only contain one. E.g. if gridish is [:a1, [:b2, :c3], :d4], the result
  #   will be a Track with three slots, :a1 in the first, :b2 + :c3 in the
  #   second, and :d4 in the third.
  def initialize(gridish, granularity: NoteLength::Eighth, timescale: 1)
    @grid = self.class.gridify(gridish)
    raise "A Track's grid must have at least one slot" if @grid.empty?
    @granularity = NoteLength.new(granularity)

    raise "Timescale must be a number greater than 0" unless timescale.is_a?(Numeric) && timescale > 0
    @timescale = timescale
  end

  # Constructs an empty track that rests for the given number of slots.
  def self.rest(num_slots = 1, granularity: NoteLength::Eighth, timescale: 1)
    grid = [[]] * num_slots
    new(grid, granularity: granularity, timescale: timescale)
  end


  ### More interesting constructors

  # Constructs a track that plays the slots of gridish in a Euclidean rhythm.
  # The length of the rhythm is length, and the number of hits to play over
  # that length is pulses. gridish should be an array of notes or Steps or
  # arrays thereof, or a single note/Step. The elements (or the single element)
  # will be passed through gridify; see it for conversion rules. Any elements
  # of gridish that need to be converted to Steps will use the given gate and
  # vel. They are ignored for elements that are already Steps.
  # Unless full_cycle is true (see below), the returned track will the given
  # length. The cycle parameter controls how gridish is used when placing slots
  # in the track. If it is true, each time there is a hit in the rhythm, the
  # next slot from gridish is used (wrapping around if needed). For example,
  # when spreading [:c3, :d3] over 3 pulses and length 4, the result will be a
  # track with the following slots:
  #   :c3, rest, :d3, :c3
  # If cycle is false, when there is a hit in the rhythm, the note at the
  # corresponding index of that hit in gridish is used (wrapping around as
  # needed). Using the same spread as above with cycle false would result in:
  #   :c3, rest, :c3, :d3
  # The third note is :c3 because the hit index, 2, corresponds :c3 in gridish
  # (modulo its length).
  # If full_cycle is true, the returned track will repeat the Euclidean pattern
  # (while cycling through gridish) however many times is needed to ensure
  # that all the slots are played and that the track loops cleanly. full_cycle
  # implies cycle. For instance, spreading [:a1, :b1, :c1, :d1] over 3 pulses
  # and 4 length with full_cycle true will result in a track with the following
  # slots (the pipes are only to visually discriminate between groups of the
  # the Euclidean pattern):
  #   :a1 rest :b1 :c1 | :d1 rest :a1 :b1 | :c1 rest :d1 :a1 | :b1 rest :c1 :d1
  # Note that each group repeats the same pattern of hits (hit rest hit hit),
  # but the slots cycle across repetitions, so that every given slot is played
  # and the overall track is a perfect loop.
  def self.euclid(gridish, pulses, length, invert: false, rotate: 0, cycle: true, full_cycle: false, granularity: NoteLength::Eighth, timescale: 1)
    hits = ExtApi.spread(pulses, length).to_a
    hits.rotate!(rotate) if rotate != 0
    hits.map! { |hit| !hit } if invert

    gridish = self.class.gridify(gridish)

    # If we're doing a full cycle, we may need multiple copies of the Euclidean
    # pattern to complete a perfect loop. If we're spreading n slots over p
    # hits, we need exactly lcm(p, n) hits. And since the pattern contains
    # exactly p hits itself, we need lcm(p, n) / p copies of it.
    if full_cycle
      cycle = true
      needed_groups = pulses.lcm(gridish.length) / pulses
    else
      needed_groups = 1
    end

    slot_idx = 0
    grid = hits.cycle(needed_groups).map.with_index do |hit, i|
      if hit
        if cycle
          slot = gridish[slot_idx % gridish.length]
          slot_idx += 1
        else
          slot = gridish[i % gridish.length]
        end

        slot
      else
        []
      end
    end

    new(grid, granularity: granularity, timescale: timescale)
  end


  ### Properties

  def num_slots
    @grid.length
  end

  alias length num_slots

  def beat_length
    num_slots * @granularity.to_f
  end

  # Returns whether the track consists entirely of rests (i.e., empty slots).
  def empty?
    @grid.all? { |slot| slot.empty? }
  end

  alias all_rests? empty?
  alias rest? empty?

  # Returns whether the track is monophonic (i.e., all slots have <=1 Step).
  def mono?
    @grid.all? { |slot| slot.length <= 1 }
  end

  # Returns whether the track is polyphonic (i.e., any slot has >1 Step).
  def poly?
    @grid.any? { |slot| slot.length > 1 }
  end


  ### Etc.

  def repr
    raise "subclasses must implement repr"
  end

  def inspect
    res = "Track slots=#{num_slots} granularity=#{granularity} timescale=#{timescale} grid:\n"
    @grid.each_with_index do |slot, i|
      res += "slot #{i} @ t=#{i * granularity.to_f}\n"
      slot.each { |step| res += "  #{step.inspect}\n" }
    end
    res
  end


  ### Mutators

  ## Granularity manipulations

  # Returns a new track with the given granularity. Does not effect the timing
  # of any Steps; to change granularity while attempting to keep the track
  # sounding roughly the same, use condense, expand, or regranularize.
  def with_granularity(granularity)
    mutate(granularity: granularity)
  end


  ## Grid-level mutations

  # Return a new Track, replacing each slot in this track with the result of the
  # given block. The block must take 1-3 arguments:
  # - The slot
  # - The index of the slot in the Track
  # - The percent through the Track that the slot represents. For instance, the
  #   first slot of the track will have percent 0, the middle slot (in a Track
  #   with an odd number of slots) will have percent 0.5, and the final slot
  #   will have percent 1.0.
  # The block may return:
  # - A slot (an array of Steps), which will replace the slot yielded to the
  #   block
  # - nil, :r, or :rest, which will replace the slot yielded to the block with
  #   an empty slot (i.e. a rest). Note that this is the same as returning an
  #   empty array.
  # - An array of slots, which will all be added in place of the yielded slot
  def mutate_each_slot(&block)
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

      # The block may return something convertible to a slot (step/note/etc.),
      # or a 1d array (which we will take as a slot), or an array that contains
      # some number of other arrays (which we will take as a set of slots). This
      # behavior is pretty odd. But, it's somewhat in keeping with set_slot, and
      # having the ability to expand one slot into multiple here is nice...
      replacement = [replacement] unless replacement.is_a?(::Enumerable) || replacement.is_a?(SonicPi::Core::SPVector)
      is_gridish = replacement.any? { |e| e.is_a?(::Enumerable) || e.is_a?(SonicPi::Core::SPVector) }

      if is_gridish
        new_grid += self.class.gridify(replacement)
      else
        new_grid << replacement  # This will get slotified by the initializer.
      end
    end
    mutate(grid: new_grid)
  end

  alias mutate_slots mutate_each_slot

  def with_rate(rate)
    mutate(timescale: rate)
  end

  alias rate with_rate

  # Returns a new track with other_track appended to this one. If other_track
  # is not a Track, it is converted to a compatible one using the initializer.
  def append(other_track)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)
    mutate(grid: @grid + other_track.grid)
  end

  alias concat append
  alias add append
  alias + append

  # Create a new Track that merges the Steps in corresponding slots of from this
  # track and other_track. The length of the resulting track is the maximum
  # length of the two tracks. If other_track is not a Track, it is converted to
  # a compatible one using the initializer.
  def merge(other_track)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    if num_slots > other_track.num_slots
      longer_track = self
      shorter_track = other_track
    else
      longer_track = other_track
      shorter_track = self
    end

    new_grid = longer_track.mutable_grid_dup
    shorter_track.grid.each_with_index { |slot, i| new_grid[i].concat(slot) }

    mutate(grid: new_grid)
  end

  alias | merge

  # Creates a new Track by merging each group of n consecutive slots into one
  # slot each. If n does not evenly divide the number of slots in the original
  # track, the final slot will merge the remaining slots. For example, consider
  # a track with slots [:c3, :d3, :e3, :f3, :g3]. Calling grouped_merge(2) on
  # that track would result in a new track with three slots:
  # [[:c3, :d3], [:e3, :f3], [:g3]].
  def grouped_merge(n)
    new_grid = @grid.each_slice(n).map { |slots| slots.flatten }
    mutate(grid: new_grid)
  end

  alias gmerge grouped_merge
  alias group grouped_merge

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. If other_track is not a Track, it is converted to a compatible
  # one using the initializer.
  # cycle and pad_with_rests control the behavior if other_track is shorter than
  # this track. If cycle is true (the default), the slots of other_track will be
  # looped as needed.
  # If cycle is false, the behavior depends on pad_with_rests. If it is true
  # (the default), when other_track's slots are exhausted, empty slots (rests)
  # are inserted in place of the missing slots. If it is false, the remaining
  # slots of this track appear consecutively once other_track is exhausted.
  # pad_with_rests is only relevant when cycle is false.
  # For example, consider zipping together two sequences with Steps
  # [:a1, :b1, :c1, :d1] and [:e5, :f5].
  # When cycle is true (the default), the resulting Track will contain slots
  # with the following steps:
  #    :a1 :e5 :b1 :f5 :c1 :e5 :d1 :f5
  # When cycle is false and pad_with_rests is true (the default), the resulting
  # Track will contain slots with the following steps:
  #    :a1 :e5 :b1 :f5 :c1 rest :d1 rest
  # If cycle is false and pad_with_rests is also false, the result is
  #    :a1 :e5 :b1 :f5 :c1 :d1
  def zip(other_track, cycle: true, pad_with_rests: true)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    new_grid = []
    b_idx = 0
    @grid.each do |slot|
      new_grid << slot
      b_idx %= other_track.length if cycle
      if b_idx < other_track.length
        new_grid << other_track.grid[b_idx]
      elsif pad_with_rests
        new_grid << []
      end

      b_idx += 1
    end

    mutate(grid: new_grid)
  end

  # Creates a new Track that interleaves the slots of other_track with those of
  # this track. If other_track is not a Track, it is converted to a compatible
  # one using the initializer.
  # Unlike zip, this function does not alternate between 1 slot of each track.
  # Instead, group_size many slots of this track appear consecutively, followed
  # by other_group_size slots of other_track, then group_size many slots of this
  # track, and so on.
  # `cycle` controls the behavior when either track does not have enough
  # remaining  slots to fill a group. If it is true, the group is filled by
  # returning to the beginning of the short track and using slots from there.
  # If it is true, when one track is exhausted, no more groups from it are
  # added to the resulting track.
  # `pad_with_rests` only takes effect when `cycle` is false. If it is true,
  # when either track is exhausted, empty slots (rests) are added to the
  # resulting track in place of the missing slots.
  # For instance, consider gzipping together a track with slots with the steps
  #     :a1 :b1 :c1 :d1
  # and one with slots with steps
  #     :e2 :f2
  # If group_size is 3, other_group_size is 1, and cycle is true, you'll get
  #     :a1 :b1 :c1 :e2 :d1 :a1 :b1 :f2
  # Note that when the tracks in the first slot were exhausted (after the :d1),
  # the remaining slots in that group came from wrapping around to the beginning
  # of the track - hence the :a1 and :b1.
  # If cycle were false in that example, the result would be
  #     :a1 :b1 :c1 :e2 :d1 :f2
  # No wrap-around occurred here, and the group beginning with :d1 is just cut
  # short. If cycle were false and pad_with_rests were true, the result would be
  #     :a1 :b1 :c1 :e2 :d1 rest rest :f2
  # In this case, the shortfall from the first track was replace with rests, so
  # that the group beginning with :d1 was ensured to have group_size many slots.
  def grouped_zip(other_track, group_size, other_group_size, cycle: true, pad_with_rests: true)
    other_track = compatibly_trackify(other_track)
    assert_compatible_track(other_track)

    new_grid = []

    # Append n elements to new_grid from grid, starting at idx, wrapping around
    # if we're cycling or adding empty slots if we're padding. Returns the index
    # from which we should begin adding on the next iteration.
    add_group = lambda do |n, grid, idx|
      n.times do
        idx %= grid.length if cycle
        if idx < grid.length
          new_grid << grid[idx]
        elsif pad_with_rests
          new_grid << []
        end

        idx += 1
      end

      idx
    end

    a_idx = 0
    b_idx = 0
    num_groups = (@grid.length / group_size.to_f).ceil
    num_groups.times do
      a_idx = add_group.call(group_size, @grid, a_idx)
      b_idx = add_group.call(other_group_size, other_track.grid, b_idx)
    end

    mutate(grid: new_grid)
  end

  alias gzip grouped_zip

  # Returns a new track that plays each successive overlapped set of n slots.
  # E.g. when called with n=3 on a track with slots :a :b :c :d :e, the
  # resulting track will have slots :a :b :c :b :c :d :c :d :e. If flatten is
  # false, each overlapped set of slots will be grouped into a slot. For
  # example, with n=2 and flatten=false, a track with slots :a :b :c :d will
  # result in a track with three slots: [[:a, :b], [:b, :c], [:c, :d]].
  # Raises an error if n is greater than the length of the track.
  def each_cons(n, flatten: true)
    raise "n=#{n} is greater than the length of the track (#{@grid.length})" if n > @grid.length

    new_grid = @grid.each_cons(n).to_a
    if flatten
      new_grid = new_grid.flatten(1)
    else
      new_grid.map!(&:flatten)
    end
    mutate(grid: new_grid)
  end

  # Returns a new track that plays every permutation of n slots. The order of
  # the permutations is indeterminate. If n is nil, permutes all slots.
  def permutation(n = nil)
    mutate(grid: @grid.permutation(n).to_a.flatten(1))
  end

  alias permutations permutation

  # Returns a new track that plays every combination of n slots. The order of
  # the combinations is indeterminate.
  def combination(n)
    mutate(grid: @grid.combination(n).to_a.flatten(1))
  end

  alias combinations combination

  def repeat(n)
    mutate(grid: @grid * n)
  end

  alias * repeat

  # Returns a new track that repeats the slots of this track for n slots. Note
  # that if n does not evenly divide the length of this track, the final
  # repetition in the result will be truncated so that the overall track has n
  # slots.
  def cycle_to_length(n)
    mutate(grid: @grid.cycle.take(n))
  end

  # Returns a new track with all empty slots (rests) removed.
  def compact
    mutate(grid: @grid.reject { |slot| slot.empty? })
  end

  def reverse
    mutate(grid: @grid.reverse)
  end

  alias rev reverse
  alias bw reverse

  # Returns a new Track that will play the grid forwards and then backwards,
  # repeating the slot in the middle.
  def mirror
    mutate(grid: @grid + @grid.reverse)
  end

  # Returns a new Track that will play the grid forwards and then backwards,
  # without repeating the slot in the middle.
  def reflect
    mutate(grid: @grid + @grid.reverse.drop(1))
  end

  alias bnf reflect

  # Returns a new Track with the slots in the grid shuffled.
  def shuffle
    mutate(grid: @grid.shuffle)
  end

  # Returns a new Track by shuffling the filled slots in the grid. Any slots
  # that were rests remain so; only the contents of filled slots is effected.
  def shuffle_filled_slots
    shuffled_idxs = indexes_of_filled_slots.shuffle

    shuffled_idxs_cursor = 0
    mutate_each_slot do |slot|
      next [] if slot.empty?
      ret = @grid[shuffled_idxs[shuffled_idxs_cursor]]
      shuffled_idxs_cursor += 1
      ret
    end
  end

  alias shuffle_filled shuffle_filled_slots

  # Returns a new Track with the slots in the grid rotated to the right by the
  # given amount. The track duration is maintained; slots will be wrapped around
  # to the beginning of the grid as needed.
  def rotate(rightward_shift = 1)
    mutate(grid: @grid.rotate(-rightward_shift))
  end

  alias right rotate
  alias rshift rotate
  alias shr rotate

  def left(leftward_shift = 1)
    rotate(-leftward_shift)
  end

  alias lshift left
  alias shl left

  # Returns a new Track by adding num_rests many empty slots (rests) to the
  # beginning of the track.
  def left_pad(num_rests = 1)
    mutate(grid: [[]] * num_rests + @grid)
  end

  alias lpad left_pad

  # Returns a new Track by adding num_rests many empty slots (rests) to the end
  # of the track.
  def right_pad(num_rests = 1)
    mutate(grid: @grid + [[]] * num_rests)
  end

  alias rpad right_pad

  # Returns a new Track by adding num_rests many empty slots (rests) after each
  # existing slot.
  def space(num_rests = 1)
    new_grid = []
    @grid.each do |slot|
      new_grid << slot
      new_grid.concat([[]] * num_rests)
    end

    mutate(grid: new_grid)
  end

  # Adds num_rests many empty slots (rests) between each group of group_size
  # slots.
  def space_every(group_size, num_rests = 1)
    new_grid = []
    @grid.each_slice(group_size) do |chunk|
      new_grid += chunk
      new_grid += [[]] * num_rests
    end

    mutate(grid: new_grid)
  end

  # Returns a new Track with the first n slots removed.
  def drop(n = 1)
    mutate(grid: @grid.drop(n))
  end

  # Returns a new Track with the final n slots removed.
  def drop_last(n = 1)
    new_grid = @grid.dup
    new_grid.pop(n)
    mutate(grid: new_grid)
  end

  # Returns a new Track consisting of only the first n slots of this track.
  def take(n)
    mutate(grid: @grid.take(n))
  end

  # Returns a new Track consisting of only the selected slots of this track.
  # Takes the same arguments as Array#slice (aka []): a single integer index, an
  # index and a length, or a range.
  def slice(*args)
    s = @grid.slice(*args)
    s = [s] if s.empty? || !s[0].is_a?(Array)
    mutate(grid: s)
  end

  alias [] slice

  # Returns a new Track consisting of n random slots from this track's grid. The
  # relative order of the slots is maintained.
  def sample(n)
    # TODO: does this use spi's rng?
    idxs = (0...@grid.length).to_a.sample(n).sort
    mutate(grid: @grid.values_at(*idxs))
  end

  # Returns a new Track consisting of n random slots from this track's grid.
  # Only picks from filled slots; rests are not considered. The relative order
  # of the slots is maintained.
  def sample_filled_slots(n)
    idxs = indexes_of_filled_slots.sample(n).sort
    mutate(grid: @grid.values_at(*idxs))
  end

  alias sample_filled sample_filled_slots

  # Returns a new Track with all Steps in every nth slot removed. The duration
  # of the Track does not change; the emptied slots simply become rests. Does
  # nothing if n is zero.
  def drop_every(n, skip_empty: false)
    return self if n == 0

    # e.g., drop every 3:
    # keep  | 0 1 - 3 4 - 6 7 - 9
    # drop  |     2     5     8
    # i % 3 | 0 1 2 0 1 2 0 1 2 0
    i = 0
    new_grid = @grid.map do |slot|
      if skip_empty && slot.empty?
        []
      else
        i += 1
        (i - 1) % n == n - 1 ? [] : slot
      end
    end

    mutate(grid: new_grid)
  end

  alias dropout drop_every

  # Return a new Track by, with probability p, removing all Steps in any given
  # slot.
  def rand_dropout(p = 0.5)
    new_grid = @grid.map { |slot| ExtApi.rand < p ? [] : slot }
    mutate(grid: new_grid)
  end

  alias rdropout rand_dropout

  # Returns a new Track with the steps in slot idx replaced with the given
  # steps.
  def replace_slot(idx, new_steps)
    raise "Index #{idx} is beyond the length of the track (#{@grid.length})" if idx >= @grid.length
    new_grid = @grid.dup
    new_grid[idx] = new_steps  # This will get slotified by the initializer.
    mutate(grid: new_grid)
  end

  alias set_slot replace_slot

  def append_slot(idx, new_steps)
    new_slot = @grid[idx] + self.class.slotify(new_steps)
    new_grid = @grid.dup
    new_grid[idx] = new_slot
    mutate(grid: new_grid)
  end

  # Returns two tracks by extracting Steps for which the block returns true.
  # The block must take 1 to 3 arguments:
  # 1. the Step
  # 2. the slot to which the Step belongs
  # 3. the index of the slot to which the Step belongs.
  # If the block returns true, the step will be placed in the second of the two
  # returned tracks. If it returns false, the step will be placed in the first.
  # The returned tracks will have the same length; if the process results in all
  # steps in a slot winding up in only one of the tracks, the slot in the other
  # track will be empty (i.e., a rest).
  # As an example, consider a Track with slots [:c2, :d2, :e2, :f2]. If the
  # block returns true for odd indices, the returned tracks will have slots
  # [:c2, rest, :e2, rest] and [rest, :d2, rest, :f2].
  def extract(&block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    grid1 = []
    grid2 = []

    @grid.each_with_index do |slot, i|
      slot1 = []
      slot2 = []

      slot.each do |step|
        args = [step, slot, i].take(block.arity)
        should_extract = block.call(*args)

        if should_extract
          slot2 << step
        else
          slot1 << step
        end
      end

      grid1 << slot1
      grid2 << slot2
    end

    [mutate(grid: grid1), mutate(grid: grid2)]
  end

  # Returns two tracks by extracting the steps in every nth slot. The first
  # returned track will have steps in all the slots that are not every nth, and
  # the second will have steps in every nth slot.
  def extract_every(n)
    extract { |_, _, i| i % n == n - 1 }
  end


  ## Step-level mutations

  # Return a new Track, replacing each Step in this track with the result of the
  # given block. The block must take 1-3 arguments:
  # - the Step
  # - the index of the slot to which the Step belongs
  # - the percentage through the Track that the slot the Step belongs to
  #   represents. For instance, Steps in the first slot of the track will have
  #   percent 0, steps in the middle slot (in a Track with an odd number of
  #   slots) will have percent 0.5, and steps in the final slot will have
  #   percent 1.0.
  # The block may return:
  # - A Step, which will replace the step yielded to the block
  # - nil, :r, or :rest, which will remove the step yielded to the block
  # - An array of Steps, which will all be added in place of the yielded step to
  #   the corresponding slot of the yielded step.
  def mutate_each_step(&block)
    raise "Block must take 1-3 arguments" if block.arity == 0 || block.arity > 3

    new_grid = @grid.map.with_index do |slot, i|
      if i == 0
        pct = 0.0
      elsif i == @grid.length - 1
        pct = 1.0
      else
        pct = i.to_f / (num_slots - 1)
      end

      new_slot = []
      slot.each do |step|
        args = [step, i, pct].take(block.arity)
        new_step = block.call(*args)

        new_slot += self.class.slotify(new_step)
      end

      new_slot
    end

    mutate(grid: new_grid)
  end

  alias mutate_steps mutate_each_step

  # Return a new track, replacing the Steps in the given slot with the result of
  # the given block. The block must take 1 argument, and will be called for each
  # Step in the slot. The result of the block will replace the Step it is called
  # with. The block should return:
  # - A single Step, which will replace the given Step in the slot.
  # - An array of Steps, which will all be added to the slot in place of the
  #   given Step.
  # - An empty array or a rest, which will remove the given Step from the slot.
  # - Equivalents of any of the above (see slotify).
  # Note that if the slot at the given index is empty, the block will not be
  # called and no changes will be made.
  def mutate_steps_in_slot(idx, &block)
    raise "Block must take 1 argument" if block.arity != 1

    new_slot = @grid[idx].map { |step| block.call(step) }.flatten
    set_slot(idx, new_slot)
  end

  alias mutate_slot_steps mutate_steps_in_slot
  alias mutate_slot mutate_steps_in_slot

  # Return a new track, replacing the Steps in the nth non-empty slot with the
  # result of the given block. This is equivalent to a call to
  # mutate_steps_in_slot with the index of the nth non-empty slot; see that
  # method for details.
  def mutate_filled_slot(n, &block)
    idx = indexes_of_filled_slots[n]
    mutate_steps_in_slot(idx, &block)
  end

  # Return a new track, replacing the Steps in the nth non-empty slot with the
  # given steps.
  def replace_filled_slot(n, new_steps)
    idx = indexes_of_filled_slots[n]
    set_slot(idx, new_steps)
  end

  alias set_filled_slot replace_filled_slot

  # Returns a new track where every step has the 'fill' probability. Or, if the
  # argument is false, a new track where all steps with the 'fill' probability
  # have their probability cleared (steps with other probabilities are
  # unchanged).
  def fill(fill = true)
    mutate_each_step do |step|
      if fill
        step.with_prob(Prob.fill)
      elsif step.prob.equal?(Prob.fill)
        step.with_prob(nil)
      else
        step
      end
    end
  end


  ### Getters

  # Returns the indexes of all non-empty slots in the grid.
  def indexes_of_filled_slots
    idxs = []
    @grid.each_with_index { |slot, i| idxs << i unless slot.empty? }
    idxs
  end

  # Returns the nth non-empty slot in the grid.
  def nth_filled_slot(n)
    @grid[indexes_of_filled_slots[n]]
  end

  alias filled_slot nth_filled_slot


  ### Track construction helpers
  # TODO: philosophically I want these to be private class methods, but you
  # can't call private class methods from instance methods :(. Figure out a way
  # to deal with that, or maybe just give up and make them instance methods.

  # Attempts to convert its argument to a Step. Conversion rules are:
  # - Steps are passed through verbatim.
  # - Notes (symbols, strings and numbers) are converted to Steps using that
  #   note and the default values for the other arguments of Step's initializer.
  # - It is an error to pass a rest (as defined by MIDINote.rest?) to this
  #   function.
  # def_gate and def_vel will be used for any Steps that need to be constructed.
  def self.stepify(_)
    raise "subclasses must implement stepify"
  end

  # Attempts to convert its argument to a grid slot (i.e. an array of Steps).
  # The returned array will be frozen. Conversion rules:
  # - Rests (see MIDINote.rest?) become an empty slot ([]).
  # - Single notes (symbols, strings, or numbers) become a slot with a single
  #   Step that is the result of calling `stepify` on the argument.
  # - Single Steps become a slot containing just that step.
  # - Array-like arguments are converted as follows:
  #   1. All rests are removed.
  #   2. All remaining elements are passed through `stepify`.
  #   3. If more than one of the resulting Steps has the same note, a warning is
  #      printed, and only the Step with the longest gate is chosen.
  # def_gate and def_vel will be used for any Steps that need to be constructed.
  def self.slotify(_)
    raise "subclasses must implement slotify"
  end

  # Attempts to convert its argument to a grid (a 2d array of Steps). The
  # returned array and all of its elements will be frozen. Conversion rules:
  # - A single rest (see MIDINote.rest?) becomes a grid with one rest ([[]]).
  # - A single note (symbol, string, or number) becomes a grid with one slot
  #   that is the result of calling `slotify` on the argument.
  # - A single Step becomes a grid with one slot containing that step.
  # - Array-like arguments are converted by passing each element through
  #   `slotify`.
  # def_gate and def_vel will be used for any Steps that need to be constructed.
  def self.gridify(_)
    raise "subclasses must implement gridify"
  end


  protected

  # Does a deep dup of the grid, returning a version where the grid itself and
  # each slot is mutable.
  def mutable_grid_dup
    @grid.map { |slot| slot.dup }
  end

  def ctor_kwargs
    [:granularity, :scale, :timescale]
  end

  def mutate(**mutations)
    grid = mutations.delete(:grid) || @grid
    ctor_kwargs.each do |ivar|
      mutations[ivar] = send(ivar) unless mutations.has_key?(ivar)
    end

    self.class.new(grid, **mutations)
  end

  def strict_track_merging?
    defaults = ExtApi.get(:__track_defaults) || {}
    defaults[:strict_track_merging] || false
  end

  def assert_compatible_track(other_track)
    return unless strict_track_merging?

    if @granularity != other_track.granularity
      raise "Granularity mismatch: #{@granularity} != #{other_track.granularity}"
    end

    if @timescale != other_track.timescale
      raise "Timescale mismatch: #{@timescale} != #{other_track.timescale}"
    end
  end

  # Attempts to convert its argument into a Track. If it is already a Track,
  # it is returned as-is. Otherwise, constructs a new Track which will inherit
  # the granularity and timescale from self.
  def compatibly_trackify(x)
    return x if x.is_a?(self.class)

    # We can just pass this off to the initializer and let it call gridify.
    mutate(grid: x)
  end
end
