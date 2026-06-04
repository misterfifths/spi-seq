# spi-seq: A sequencer library for Sonic Pi

This is a library for creating, manipulating, and playing back sequenced tracks in [Sonic Pi](https://sonic-pi.net/). It is heavily inspired by the capabilities of the [Oxi One sequencer](https://oxiinstruments.com/oxi-one/).

Read on for an introduction, or see the [documentation](https://misterfifths.github.io/spi-seq).

## What can it do?

spi-seq allows you to quickly construct and manipulate tracks, starting with simple chords or arpeggios, then play them back over MIDI. You can mute and unmute (or even add) tracks on the fly; the library plays nice with all of Sonic Pi's live coding tools.

Under the name [Full Empty](https://soundcloud.com/full-empty-214000746), with the aid of a few hardware synthesizers, I've made quite a few tracks with spi-seq. Some personal favorites are ["2-18-26"](https://soundcloud.com/full-empty-214000746/2-8-26) and ["F00F Redux"](https://soundcloud.com/full-empty-214000746/f00f-redux). The source for the melody of the latter is in [the examples](examples/f00f.rb).

## Installation

You will of course need to install [Sonic Pi](https://sonic-pi.net/).

Clone or download this repository somewhere on your computer. Then, in a Sonic Pi workspace, `require` the `core.rb` file, which loads all the components of spi-seq. For example, if you downloaded the code to your home directory:

```ruby
require "~/spi-seq/core"
```

Read on for an introduction to using the library, or see the [examples](examples) or [documentation](https://misterfifths.github.io/spi-seq).

## Whirlwind tour

### Meant for MIDI

I should mention this up front: spi-seq is very much intended to control synths over MIDI. It *can* use Sonic Pi's built-in synthesis, but that is a subpar experience compared to MIDI. This is largely because there is no way to indefinitely hold a Sonic Pi note and later gracefully release it, which means that tied notes from spi-seq will end abruptly, and probably click. If that's not a dealbreaker, please continue!

### The basics

The core object in spi-seq is a `Track`. A `Track` consists of slots, and each slot contains zero or more `Step`s. An empty slot represents a rest. A `Step` is a note plus some metadata (its gate, velocity, the probability it will trigger, etc.). For example:

```
Track ➘
  +-------------------------------------------------------------------------------------------------+
  | Granularity (the duration of a slot): 8th note                                                  |
  |                                                                                                 |
  | Slots (played sequentially) ➘                                                                   |
  |   +----------------------------+ +----------------------------+ +----------------------------+  |
  |   | Steps ➘                    | | Steps ➘                    | | Empty slot (a rest)        |  |
  |   | (played simultaneously)    | | (played simultaneously)    | +----------------------------+  |
  |   |   +--------------------+   | |   +--------------------+   |                                 |
  |   |   | C2, gate 0.5,      |   | |   | E1, gate 0.25,     |   |                                 |
  |   |   | velocity 127       |   | |   | velocity 127       |   |                                 |
  |   |   +--------------------+   | |   +--------------------+   |                                 |
  |   |   +--------------------+   | |   +--------------------+   |                                 |
  |   |   | E2, gate 1 (tied), |   | |   | B3, gate 0.25,     |   |                                 |
  |   |   | velocity 127       |   | |   | velocity 64,       |   |                                 |
  |   |   +--------------------+   | |   | probability of     |   |                                 |
  |   |   +--------------------+   | |   | triggering: 50%    |   |                                 |
  |   |   | G2, gate 0.5,      |   | |   +--------------------+   |                                 |
  |   |   | velocity 64        |   | +----------------------------+                                 |
  |   |   +--------------------+   |                                                                |
  |   +----------------------------+                                                                |
  +-------------------------------------------------------------------------------------------------+
```

The power of spi-seq lies in its many tools to create, mutate, combine, and otherwise manipulate `Track`s and their `Step`s.

A track is played back using a `Player`, which walks through the slots in a `Track`, one after another, and plays their `Step`s simultaneously for the correct duration. You will not usually create a `Player` manually, instead relying on `track_live_loop` to do it for you.

The `Track` class is aliased to `T`, and its `new` method is aliased to `[]`, so the easiest way to make a track is to write `T[...]`. You can express the notes to play in a variety of ways, but the simplest is an number of symbols, strings, or MIDI note numbers. Here's a snippet that creates a simple progression of notes and loops it indefinitely:

```ruby
t = T[:c4, :e4, :f4, :c5]
track_live_loop :my_first_track, t
```

*Note:* Unlike the normal `live_loop`, `track_live_loop` does not require a block. Instead, it automatically makes a block that controls an internal `Player` instance to play the track you provide. You *can* pass it a block, but it has special powers and slightly different rules; we'll get to that [later](#track_live_loop-blocks).

As mentioned earlier, spi-seq is really much better when used to control MIDI devices, so let's play back over a specific MIDI channel instead of using Sonic Pi's built-in synthesis. We'll probably also want a MIDI clock pulse, which playback should sync to. And maybe we want to adjust the BPM as well (spi-seq respects the Sonic Pi BPM). All together:

```ruby
use_bpm 140

# This is a built-in Sonic Pi function, which spi-seq respects.
use_midi_defaults(port: "my_midi_device", channel: 1)

# Set default options for Players and track_live_loop. The
# :midi_clock live loop is defined by the midi_clock_live_loop call
# below.
use_player_defaults(midi: true, sync: :midi_clock)

# Start a new live loop (named :midi_clock by default) that sends
# MIDI clock messages in time with the global BPM. Note that we
# used that name as the default sync source in user_player_defaults
# above.
midi_clock_live_loop

t = T[:c4, :e4, :f4, :c5]
track_live_loop :my_first_track, t
```

You can set the `midi`, `sync`, `port`, and `channel` values on an individual `track_live_loop` call as well, so you can easily target different devices. It's often handy to set the defaults with the above functions though.

Also, since you'll be using `track_live_loop` a lot, there is an alias for it: `tll`.

See the [Everyday Use](#everyday-use) section for an example of a template you might start using for spi-seq sketches.

### More on `Track`s

The duration of each slot in a track is specified by the track's `granularity`, which is expressed in traditional note length terms. For instance, quarter-note granularity means that each slot will last for one beat (where the BPM is defined by Sonic Pi). The default granularity for a track is an eighth note, so each slot lasts for half a beat. You can specify the granularity at track construction time, using symbols for the names:

```ruby
T[:d4, :e5, granularity: :whole]
```

If you would like to rest for a particular slot, you can use `:r` instead of a note. For instance, this track is the same as the above, except there is a rest (lasting a whole note) between the other two notes:

```ruby
T[:d4, :r, :e5, granularity: :whole]
```

Aside from the standard initializer, there are many other ways to create new tracks. For instance, you can arpeggiate notes in a variety of patterns with `Track.arp` (here, using Sonic Pi's built-in `chord` method):

```ruby
Track.arp(chord(:fs4, :major9), :thumb)
```

That will create a track that arpeggiates the notes in an F#4 major 9th chord, playing the lowest note in the chord between each other note (a so-called "thumb" pattern).

Another interesting initializer is `Track.euclid`, which spreads notes out using [Euclidean rhythms](https://en.wikipedia.org/wiki/Euclidean_rhythm) (see also Sonic Pi's `spread` function). This call generates a 16-slot track where 11 of the slots are filled in a Euclidean rhythm, cycling through the given notes:

```ruby
Track.euclid([:a3, :b3, :c3], 11, 16)
```

### More on `Step`s

If you want to play more than one note simultaneously (e.g., to play a chord), group those notes together in an array when passing them to the initializer:

```ruby
T[
  [:c4, :c3],
  :e4,
  [:f4, :f3],
  :c5
]
```

In that track, the C4 and C3 will be played together (they share a slot), then the E4, then the F4 and F3 together, then the C5.

You'll notice that we haven't manually created any `Step` objects yet; we've just been providing raw notes inside of slots. That's because the `Track` initializer will make `Step`s out of notes for us, using some defaults for attributes like the velocity and gate. However, if you want to specify those parameters, you can pass a `Step` to the `Track` initializer instead of a note. `Step.new` is aliased to just `S` for convenience. Here's a track where the notes have increasingly shorter gates, and the second note has a low velocity:

```ruby
T[
  :a2,
  S(:c4, vel: 20, gate: 0.75)
  S(:d4, gate: 0.5),
  S(:e4, gate: 0.25)
]
```

The default velocity for a step is 127, and the default gate is the maximum, 1.0, which is a tie. Tied notes are continued without release if they would also play in the next slot. For instance, in this track, the :c4 is held for the first three slots, terminating 25% of the way through the third:

```ruby
T[
  S(:c4, gate: 1),
  [S(:c4, gate: 1), S(:c2, gate: 0.5)],
  S(:c4, gate: 0.25),
  S(:c2, gate: 0.75)
]

# or, equivalently, since a gate of 1 is the default:
T[
  :c4,
  [:c4, S(:c2, gate: 0.5)],
  S(:c4, gate: 0.25),
  S(:c2, gate: 0.75)
]
```

### Step probabilities

By giving a `Step` a *probability*, you can control the conditions under which that step will trigger during playback. There are a variety of built-in probability functions, and you can also write your own with a lambda.

The simplest way to express a probability is to pass a floating point number as the `prob` parameter to `Step.new` (aliased to `S`). That specifies the chance that the note will play, with 1.0 meaning a 100% chance. For instance, the C4 in this track only has a 25% chance of playing on any given loop; there is a 75% chance that slot will be just a rest instead:

```ruby
t = T[
  :e4,
  S(:c4, prob: 0.25),
  :g3
]
```

More elaborate probabilities are part of the `Prob` class. For instance, the `every` probability will trigger the given note every nth cycle. Here, the C4 will only play every 3rd loop; on other loops that slot will just be a rest:

```ruby
t = T[
  :e4,
  S(:c4, prob: Prob.every(3)),
  :g3
]
```

Check out the `Prob` documentation for more elaborate options. You can specify that a step should only trigger on the first loop of a track, or only if the previous slot was a rest, and so on. There is also a special probability called `fill` which we'll discuss [later](#fill-mode).

### Step Accumulation

While probabilities control whether a `Step` triggers at all, *accumulation* can change the note a step plays each time it is triggered. For instance, using accumulation, you can make a step that automatically plays a note several semitones higher each time. Accumulation is controlled by a number of parameters:

- *delta* is the number of semitones to adjust the step's note each time it is triggered.
- *min* and *max* define the acceptable range of semitone adjustment from accumulation.
- *mode* specifies the behavior when the overall accumulation reaches the min or max values. It can be one of `:freeze` (which holds at the extreme that was reached), `:wrap` (which wraps around to the opposite extreme), or `:reverse` (which bounces between the extremes).

You can most easily apply accumulation to a `Step` with the `accum` method, which takes the delta and keyword arguments for each of the other parameters described above. For example, consider this track:

```ruby
t = T[
  S(:c4).accum(1, max: 12, mode: :freeze)
]
```

When that track is played, the first loop will play a C4. In the next loop, the accumulation will take effect and it will play a C#4 - a note one semitone higher (the `delta` being 1). The next loop will play a D4, and so on for 12 cycles until it plays a C5 (12 semitones of accumulation). At that point, since the maximum accumulation has been reached and the mode is `:freeze`, all further cycles of the track will also play a C5.

The accumulation delta can be negative. Consider this track:

```ruby
t = T[
  S(:c4).accum(-12, min: -24, max: 24, mode: :reverse)
]
```

That will play a C4, then a C3 and a C2, then, since that's the minimum accumulation of -24 and the mode is `:reverse`, the delta is effectively negated and the following cycle will play a C3. Then a C4 again, a C5, and a C6. The C6 is the max accumulation, so the delta is negated again and the following cycle will play a C5, and so on.

Note that accumulation can have its own probability, independent of the step to which it belongs. For instance, take this track:

```ruby
t = T[
  S(:c4).accum(7, max: 21, prob: Prob.every_other)
]
```

The accumulation of 7 semitones will only trigger on every other playback of the track, so the first two cycles will play a C4, the next two will play a G4, and so on.

Accumulation can actually effect more than notes! You can apply accumulation to the gate or velocity of a step using the `target` argument, like this:

```ruby
t = T[
  S(:c4, gate: 0.5).accum(0.1, max: 0.5, mode: freeze)
]
```

That C4 will start with a gate of 0.5, increasing by 0.1 each time it plays, until it finally becomes a tie (and stays there because of the `freeze` mode).

### Manipulating `Track`s

Much of the power of spi-seq lies in its track mutation methods. Let's take a look at some of them. In these examples, I'm omitting most boilerplate and the `track_live_loop` calls for playback.

One thing that greatly effects how you'll interact with them: **`Track` objects are immutable**. All the methods that manipulate them return new `Track` instances, rather than changing the one on which they are called.

You can transpose all notes in a track some number of semitones with `transpose`. You can merge the slots in two tracks with the `|` operator. So here's how you might construct a track that plays the notes in a C3 major 9th chord, together with those same notes down a fifth:

```ruby
# Each note in the chord winds up in its own slot; this track has 5 slots.
t = T[*chord(:c3, :major9)]

# Remember, Tracks are immutable, so this transpose call returns a new
# track and won't change t!
t_transpose = t.transpose(-7)

# Merge the slots of t and t_transpose together, so that we hear,
# sequentially, each note together with itself down a fifth.
together = t | t_transpose

# The final track is equivalent to this:
# T[[:f2, :c3], [:a2, :e3], [:c3, :g3], [:e3, :b3], [:g3, :d4]]
```

Or, more concisely:

```ruby
t = T[*chord(:c3, :major9)]
t |= t.transpose(-7)
```

Let's play those notes forward and then backward, without repeating the notes in the middle or at the end. `reverse` reverses a track, and `drop(n)` removes the first `n` slots from a track (defaulting to 1). `drop_last` is like `drop`, but removes slots from the end of a track. The `+` operator concatenates two tracks. So:

```ruby
t = T[*chord(:c3, :major9)]
t |= t.transpose(-7)
t = t + t.reverse.drop.drop_last
```

The `reflect` method is actually shorthand for the `t + t.reverse.drop` pattern.

Now let's alternate between those notes and the same ones shifted up an octave, so that we hear e.g. C3+F3 then C4+F4, and so on. The `up(n)` method transposes a track up `n` octaves (defaulting to 1). The `zip` function takes another track and interleaves the two tracks' steps. And for kicks, let's give the higher notes a shorter gate, using the `gate` method, which sets the gate on all steps in a track. We can do something like this:

```ruby
t = T[*chord(:c3, :major9)]
t |= t.transpose(-7)
t = t.reflect.drop_last
t = t.zip(t.up.gate(0.5))
```

If we had constructed that track manually with `Track.new`, it would look like this:

```ruby
T[
  [:f2, :c3], [S(:f3, gate: 0.5), S(:c4, gate: 0.5)],
  [:a2, :e3], [S(:a3, gate: 0.5), S(:e4, gate: 0.5)],
  [:c3, :g3], [S(:c4, gate: 0.5), S(:g4, gate: 0.5)],
  ...,
  [:c3, :g3], [S(:c4, gate: 0.5), S(:g4, gate: 0.5)],
  [:a2, :e3], [S(:a3, gate: 0.5), S(:e4, gate: 0.5)]
]
```

Note the alternating pairs generated by `zip`: each slot is followed by a slot with same notes up an octave with a shorter gate. Note also how the track is mirrored due to the concatenation with its reverse (via `reflect`) - the early A+E, C+G progression appears backwards at the end of the track. But the leading F+C pair is missing at the very end so that the track loops cleanly (that was the `drop_last`).

We've barely scratched the surface, but already it's easy to assemble complicated tracks. Here's a nice melody using things you've seen so far and a few new tricks: the `*` operator concatenates a track with itself some number of times, and the `shl` method shifts a track's slots to the left, wrapping the first slots back around to the end. This is an intricate 64-step sequence, all constructed from simple manipulations of a minor 7th chord!

```ruby
t = T[*chord(:d4, :minor7)].gate(0.5)
t = t.zip(t.reverse.gate(0.25).shl)
t = t * 2 + t.transpose(7) * 2
t = t.zip(t.transpose(-7))
```

Just like normal `live_loop`s, you can have multiple `track_live_loops` running at the same time. So let's add a bass accompaniment to the above. We'll construct that from the melody track by shifting it down two octaves with `down` and, to add some rhythm, we'll turn every 3rd slot into a rest with `dropout`. Let's also make the bass notes have a longer gate than those in the melody.

```ruby
t = T[*chord(:d4, :minor7)].gate(0.5)
t = t.zip(t.rev.gate(0.25).shl)
t = t * 2 + t.transpose(7) * 2
t = t.zip(t.transpose(-7))

track_live_loop :melody, t
track_live_loop :bass, t.down(2).dropout(3).gate(0.9)
```

With the `midi`, `port` and `channel` arguments, the `:bass` track could easily be sent to another MIDI target and play on a separate synth than the melody.

There are many more ways to manipulate tracks. You can replace notes in a track based on some pattern (`sub_note`), adjust gate or velocity based on a curve (`gate_curve` and `vel_curve`), split a track into multiple tracks (`partition`, e.g.), do targeted manipulation of each step (`mutate_steps`), and more.

### `track_live_loop` blocks

You have probably noticed that, unlike normal Sonic Pi `live_loop`s, `track_live_loop`s do not require a block. By default, they will construct their own that manages a `Player` instance to handle the track you provide.

However, you can pass your own block to `track_live_loop`, which has some special rules and powers. Most importantly:

- Blocks should not `sleep` or `sync`, unlike `live_loop` blocks. The internal block will do that for you to ensure proper timing when playing back the track you provide. If you do `sleep` or `sync`, it will result in gaps between cycles of your track.
- If your block returns a `Track` instance, that track will be played instead of the track you provided as an argument to `track_live_loop`. In fact, if you provide a block that returns a `Track`, there may not be a reason to pass a track to `track_live_loop` at all. This is valid.
- The block can receive a number of arguments. See the documentation for all of them. For now we'll just look at `cycle`, which is the number of times the track has looped. It is 0 when the track starts and increments each time the track plays.

Returning a `Track` from your block is very powerful. It allows you to mutate the track you're playing each cycle. For example, let's say we wanted to transpose a track 1 semitone every loop (up to 7 semitones), and perhaps have the gate of its steps slowly increase each cycle. Using the `cycle` parameter, we can adjust our track accordingly in the block:

```ruby
t = Track.arp(chord(:c3, :major9), :thumb)

track_live_loop :t do |cycle:|
  t.transpose(cycle % 8).gate(0.1 * (cycle + 1))
end
```

Note that we did not need to pass `track_live_loop` a track up-front, since the block returns one. And since we mutate the track based on the `cycle`, it's different each loop.

For another example, we could randomly rearrange the notes in our track each cycle, using the `shuffle` method:

```ruby
t = T[*chord(:c3, :major13)].gate(0.5)

track_live_loop :t do
  t.shuffle
end
```

Here we did not need the `cycle` parameter, so we just omitted it from the block.

### Muting tracks

Just as you might use live-coding to add or stop `live_loops`, you can do the same with `track_live_loop`s. However, `track_live_loop`s can also be muted or unmuted after a cycle by other means. In these examples, we'll look at MIDI CC control, but you can also manually handle muting with the `mute_live_loop` function.

You can add the `cc` keyword parameter to a `track_live_loop` to specify that a CC should control whether it is muted. Sending a value of 0 for that CC will mute the track, and any other value will unmute it. Note that muting only takes effect *after a cycle of the track*; it will not abruptly make the track inaudible. Unmuting is the same; it will only happen in intervals of the track's duration, even though the track is not audible.

By default, a `track_live_loop` with a `cc` parameter will listen for the CC you specify from any MIDI port and any MIDI channel. To specify a specific device, use the `cc_port` and `cc_channel` arguments or set a default with the `use_cc_control_defaults` method.

Tracks start unmuted by default. You can use the `start_muted` parameter to change that (or `use_player_defaults` to set a global default).

Here's an example with two tracks. The melody starts unmuted (and is not controllable by CCs). The bassline starts muted, and may be unmuted by sending any nonzero value for CC 110 from `my_midi_device` channel 1.

```ruby
use_cc_control_defaults(port: "my_midi_device", channel: 1)

t = T[*chord(:c3, :major13)].gate(0.5)

track_live_loop :melody, t

bassline = t.down.transpose(-7).dropout(4)
track_live_loop :bassline, bassline, cc: 110, start_muted: true
```

### Fading tracks in and out

When a track is muted or unmuted, you may want it to gradually fade in or out via velocity. You might imagine how you could use a `track_live_loop` block to accomplish that: in the block you could adjust each step's velocity appropriately, and return the mutated track when needed. (In fact, there is a `vel_curve` method that will apply a curve to all steps' velocities.)

However, fading a track in or out is common enough that there are parameters to `track_live_loop` that will do it automatically for you.

To fade in a track when it is unmuted, pass the `fade_in` keyword parameter. Its value can either be `true`, which will fade the track in linearly, or `:quad`, which will fade it in quadratically. Fading out is likewise controlled with the `fade_out` parameter.

From the above example, here's how we could specify that the bassline should fade in linearly and out quadratically:

```ruby
track_live_loop :bassline, bassline, fade_in: true, fade_out: :quad, cc: 110, start_muted: true
```

Necessarily, fadeouts happen on the cycle *after* the track is muted. That is, when a track is set to fade out, it will play for one extra cycle after it's muted, during which it will fade out.

Note that fades take effect by setting the velocity of steps in each slot to particular values along a curve. That means that if your track has a long granularity (e.g. whole notes) and relatively few slots, the fade will not be gradual at all. In that case you may want to look into the `expand` method to attempt to change the granularity of your track while keeping it sounding the same.

### Fill mode

At any point during playback, a `Player` may be put in *fill mode*. In that state (and only in that state) steps with the special `fill` probability will trigger.

The true power of fill is that it can be controlled by a MIDI CC, just like muting. Pass the `fill_cc` parameter to `track_live_loop` to specify the CC value that should toggle fill mode. Like the muting `cc` parameter, the MIDI device that will be monitored for `fill_cc` is specified with `cc_port` and `cc_channel`. And like muting, a CC value of 0 turns fill off and any other value turns it on. Fill is always off by default.

Unlike muting, *fill mode takes effect immediately*. That is, steps with the fill probability will immediately start triggering after fill is set; you do not need to wait for another cycle of playback.

Here's an example where an E2 is only triggered in fill mode. The `track_live_loop` is configured to watch CC 111 for fill.

```ruby
t = T[
  :c4,
  [:e4, S(:e2, prob: Prob.fill)],
  :g4
]

track_live_loop :t, t, fill_cc: 111
```

There is also a `not_fill` probability, which specifies that a step should only trigger when fill is off. And, there is a `fill` method on `Track` that gives all steps the `fill` probability, which may be useful when assembling tracks by merging them.

In addition to `fill_cc`, you can manually enable or disable fill with `fill_live_loop` and `unfill_live_loop`, which take the name of the target loop.

### Sequencing CCs

So far we've only seen `Track`s and `Step`s, which both deal with sequencing notes. spi-seq can also sequence MIDI CCs using the `CCTrack` class. `CCTrack` shares the same structure and many methods with `Track`, but instead of note-based `Step`s, it contains `CCStep`s, which consist of a CC number and a value. `CCTrack` is aliased to `CCT`, and you can call its initializer with brackets, just like `T`. `CCStep.new` is aliased to `CC`. Constructing and using a `CCTrack` should look rather familiar:

```ruby
t = CCT[
  CC(10, 1),
  CC(10, 25),
  :r,
  CC(15, 3),
  granularity: :half
]

track_live_loop :my_cc_track, t
```

That builds a track with four slots that sends CC 10 with a value of 1, then 25, then rests, and then sends CC 15 with a value of 3. You play back `CCTrack`s with `track_live_loop`, just like normal `Tracks`.

Many of the means for manipulating `Track`s are also available for `CCTrack`s; if the method doesn't deal directly with note properties (like `transpose` or `gate`), it's probably available on `CCTrack`. To name just a few, `zip`, `dropout`, and the `|` operator are all at your disposal. `CCStep`s can have probabilities and even accumulation - `CCStep` accumulation works just like that on `Step`, but applies deltas to the value of the CC message instead of semitone offsets of the note.

The `CCTrack.simple` class method provides a concise way to construct a track that consists entirely of values for the same CC number. The `add_curve` method lets you add steps for a CC number with values along a curve. And if you want to generate a `CCTrack` with steps that correspond to notes in a `Track`, the `to_cc` and `to_simple_cc` methods on `Track` provide ways to map between the two.


## Recording tracks

As you've hopefully seen, spi-seq has rich tools for constructing `Track`s programmatically. However, it can still be tedious to create tracks for more organic melodies. To help with that, the `Track.record` method records and quantizes incoming MIDI note events and creates a `Track` object for you.

To use it, first set a BPM that is the same you intend to use when playing back the resulting track. The BPM determines how to map between real-world seconds and slots in a track, so it's important that it is the same between recording and playback.

Then, call `Track.record`. That method takes many arguments, the most important of which are:

- `cc`: Recording is started and stopped via this MIDI CC. The value sent for the CC is ignored; any message with this number will do. By default the CC is listened for on the device specified with `use_cc_control_defaults`, or all devices if none was set.
- `port` and `channel`: The MIDI device to listen to for note events. Defaults to the device specified by `use_midi_defaults`, or all devices if none was set.
- `granularity`: The granularity of the resulting `Track` (e.g. `:sixteenth`, `:eighth`, etc.). A shorter granularity means that the timing of incoming MIDI notes can be represented more precisely, which may or may not be desirable.
- `trim_start` and `trim_end`: If these are true, rests from the respective end of the track will be removed.
- `ignore_vel`: By default, the velocity of incoming events is recorded in the `Step`s in the track. If this is true, all steps will have the default velocity of 127.

`Track.record` returns a `Track`, but how do you save that track for future use or editing? The easiest way is to call `copy_repr` on the it, which will put a Ruby representation of the track on your clipboard. You can also print the track's Ruby representation in Sonic Pi with `puts track.repr`.

Here's an example use of `Track.record`:

```ruby
use_bpm 95

require "~/spi-seq/core"

t = Track.record(cc: 119,
                 granularity: :sixteenth,
                 trim_start: true, trim_end: false,
                 ignore_vel: true)
t.copy_repr
```


## Everyday use

### A template

I recommend writing a small template for a new sketch and keeping it handy. Here is roughly the template I use:

```ruby
use_bpm 120
use_midi_logging false
use_debug false

require "~/spi-seq/core"

uf = {port: "arturia_microfreak", channel: 7}
mf = {port: "minifreak_midi", channel: 8}

use_midi_defaults(**mf)
use_cc_control_defaults(port: "iphone")
use_player_defaults(midi: true, sync: :midi_clock)

on_cold_run do
  midi_panic(port: "*", channel: "*")
  midi_panic_on_stop(port: "*", channel: "*")
  midi_clock_live_loop(port: "*")
end
```

Some of that should be familiar, but let me explain:

- The MIDI device hashes (here `uf` for Microfreak and `mf` for Minifreak) are handy because you can use them to target playback by passing them directly to `track_live_loop` like this: `track_live_loop :some_track, some_track, **uf`. You can also pass them to `use_midi_defaults`, as seen here, which is a built-in Sonic Pi method that spi-seq also honors for playback with `track_live_loop`.
- We've seen `use_cc_control_defaults` and `use_player_defaults` before; they control default options for `Player`s and `track_live_loop`. I use the TouchOSC app on my phone as a MIDI controller, so I've set that as the default CC control device.
- `on_cold_run` is a helper provided by spi-seq that will execute its block only when a Sonic Pi sketch is started after having been stopped; it will not run if you restart a sketch. It's a handy place to do things like start the MIDI clock loop, and in this case send a MIDI stop and all notes off message to all devices (`midi_panic`). `midi_panic_on_stop` sets up a hook that will also do a `midi_panic` when playback is stopped in Sonic Pi, or when the app quits, to avoid stuck notes.

### Live coding

Of course, spi-seq plays well with Sonic Pi's live coding features. You can safely re-run a sketch using spi-seq; your existing `track_live_loops` will finish and changes will take effect on the next loop. There are a few things you should be aware of though.

If you add a new `track_live_loop` and re-run your sketch, that loop will start the next time its `sync` source fires. If you're using MIDI output, that is likely the MIDI clock, which means the loop will start almost immediately. That is probably not what you want! You probably intended for the track to start playback when some other track finishes a loop. Luckily, since `track_live_loops` are just `live_loops` under the hood, all you need to do is provide an explicit `sync` parameter for your loop, with the name of the loop you'd like it to start with.

Stopping existing live loops is always a little tricky in Sonic Pi. It's probably easiest to use the loop [muting functionality](#muting-tracks), which will silence playback of a track. The `cc` parameter to `track_live_loop` will watch for a MIDI CC to control muting. Or, you can add a call to `mute_live_loop(:loop_name)` (or `unmute_live_loop`) in your sketch and re-run it. Once muted, the track will stop playing once its current cycle completes.

Otherwise, if you don't think you'll be starting the loop again, you can just change (or add) a `track_live_loop`'s block to call Sonic Pi's `stop` function.
