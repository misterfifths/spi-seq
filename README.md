# spi-seq: A sequencer library for Sonic Pi

This is a library for creating, manipulating, and playing back sequenced tracks in [Sonic Pi](https://sonic-pi.net/). It is heavily inspired by the capabilities of the [Oxi One sequencer](https://oxiinstruments.com/oxi-one/).

## Installation

Clone or download this repository somewhere on your computer. Then, in a Sonic Pi workspace, `require` the `core.rb` file, which loads all the components of spi-seq, and call the `init_spi_seq` method. For example, if you downloaded the code to your home directory:

```ruby
require "~/spi-seq/core"
init_spi_seq
```

## Whirlwind tour

### Meant for MIDI

I should mention this up front: spi-seq is very much intended to control synths over MIDI. It *can* use Sonic Pi's built-in synthesis, but it is a subpar experience compared to MIDI. This is largely because there is no way to indefinitely hold a Sonic Pi note and later gracefully release it, which means that tied notes from spi-seq will end abruptly, and probably click. If that's not a dealbreaker, please continue!

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

The easiest way to create a `Track` is to use `Track.new`, which is also aliased to `T`. You can express the notes to play in a variety of ways, but the simplest is an array of symbols, strings, or MIDI note numbers. Here's a snippet that creates a simple progression of notes and loops it indefinitely:

```ruby
t = T([:c4, :e4, :f4, :c5])
track_live_loop :my_first_track, t
```

*Note:* Unlike the normal `live_loop`, `track_live_loop` does not require a block. Instead, it automatically makes a block that controls an internal `Player` instance to play the track you provide. You *can* pass it a block, but it has special powers and slightly different rules; we'll get to that later.

As mentioned earlier, spi-seq is really much better when used to control MIDI devices, so let's play back over a specific MIDI channel instead of using Sonic Pi's built-in synthesis. We'll probably also want a MIDI clock pulse, which playback should sync to. And maybe we want to adjust the BPM as well (spi-seq respects the Sonic Pi BPM). All together:

```ruby
use_bpm 140

# This is a built-in Sonic Pi function, which spi-seq respects.
use_midi_defaults(port: "my_midi_device", channel: 1)

# Set default options for Players and track_live_loop.
use_player_defaults(midi: true, sync: :midi_clock)

# Start a new live loop (named :midi_clock by default) that sends
# MIDI clock messages in time with the global BPM. Note that we
# used that name as the default sync source above.
midi_clock_live_loop

t = T([:c4, :e4, :f4, :c5])
track_live_loop :my_first_track, t
```

You can set the `midi`, `sync`, `port`, and `channel` values on an individual `track_live_loop` call as well, so you can easily target different devices. It's often handy to set the defaults with the above functions though.

### More on `Track`s

The duration of each slot in a track is specified by the track's `granularity`, which is expressed in traditional note length terms. That is, quarter note granularity means that each slot will last for one beat (where the BPM is defined by Sonic Pi). The default granularity for a track is an eighth note, so each slot lasts for half a beat. You can specify the granularity at track construction time, using symbols for the names:

```ruby
T([:d4, :e5], granularity: :whole)
```

Aside from the standard initializer, there are many other ways to create new tracks. For instance, you can arpeggiate notes in a variety of patterns with `Track.arp` (here, using Sonic Pi's built-in `chord` method):

```ruby
Track.arp(chord(:fs4, :major9), :thumb)
```

That will create a track that arpeggiates the notes in an F#4 major 9th chord, playing the lowest note in the chord between each other note (a so-called "thumb" pattern).

There is also `Track.euclid`, which spreads notes out using [Euclidean rhythms](https://en.wikipedia.org/wiki/Euclidean_rhythm) (see also Sonic Pi's `spread` function). This call generates a 16-slot track where 11 of the slots are filled in a Euclidean rhythm, cycling through the given notes:

```ruby
Track.euclid([:a3, :b3, :c3], 11, 16)
```

### More on `Step`s

If you want to play more than one note simultaneously, group those notes together when passing them to the initializer:

```ruby
T([ [:c4, :c3], :e4, [:f4, :f3], :c5 ])
```

In that track, the C4 and C3 will be played together (they share a slot), then the E4, then the F4 and F3 together, then the C5.

You'll notice that we haven't manually created any `Step` objects yet. The `Track` initializer makes them for us as needed. However, if you want more control over a step, such as its gate, you can pass a `Step` to the `Track` initializer instead of a note. `Step.new` is aliased to just `S` for convenience. Here's a track where the notes have increasingly shorter gates, and the second note has a low velocity:

```ruby
T([ :a2, S(:c4, vel: 20, gate: 0.75), S(:d4, gate: 0.5), S(:e4, gate: 0.25) ])
```

The default velocity for a step is 127, and the default gate is 1.0 (tied). Tied notes are continued without release if they also appear in the following step.

### Step probabilities

By giving a `Step` a *probability*, you can control the conditions under which that step will trigger during playback. There are a variety of built-in probability functions, and you can also write your own with a lambda.

The simplest way to express a probability is to pass a floating point number as the `prob` parameter to `Step.new`. That specifies the chance that the note will play, with 1.0 meaning a 100% chance. For instance, the C4 in this track only has a 25% chance of playing on any given loop:

```
t = T([:e4, S(:c4, prob: 0.25), :g3])
```

More elaborate probabilities are part of the `Prob` class. For instance, the `every` probability will trigger the given note every nth cycle. Here, the C4 will only play every 3rd loop:

```
t = T([:e4, S(:c4, prob: Prob.every(3)), :g3])
```

Check out the `Prob` documentation for more elaborate options. You can specify that a step should only trigger on the first loop of a track, or only if the previous slot was a rest, and so on. There is also a special probability called `fill` which we'll discuss later.

### Manipulating `Track`s

One thing that greatly effects how you'll interact with them: `Track` objects are immutable. All the methods that manipulate them return new `Track` instances, rather than changing the one on which they are called.

In these examples, I'm omitting most boilerplate and the `track_live_loop` calls for playback.

You can transpose all notes in a track some number of semitones with `transpose`. You can merge the slots in two tracks with the `|` operator. So here's how you might construct a track that plays the notes in a C3 major 9th chord, together with those same notes down a fifth:

```ruby
# Each note in the chord winds up in its own slot; this track has 5 slots.
t = T(chord(:c3, :major9))

# Remember, Tracks are immutable, so this transpose call returns a new
# track and won't change t!
t_transpose = t.transpose(-7)

# Merge the slots of t and t_transpose together, so that we hear,
# sequentially, each note together with itself down a fifth.
together = t | t_transpose

# The final track is equivalent to this:
# T([ [:f2, :c3], [:a2, :e3], [:c3, :g3], [:e3, :b3], [:g3, :d4] ])
```

Or, more concisely:

```ruby
t = T(chord(:c3, :major9))
t |= t.transpose(-7)
```

Let's play those notes forward and then backward, without repeating the notes in the middle or at the end. `reverse` reverses a track, and `drop(n)` removes the first `n` slots from a track (defaulting to 1). `drop_last` is like `drop`, but removes slots from the end of a track. The `+` operator concatenates two tracks. So:

```ruby
t = T(chord(:c3, :major9))
t |= t.transpose(-7)
t = t + t.reverse.drop.drop_last
```

Now let's alternate between those notes and the same ones shifted up an octave, so that we hear e.g. C3+F3 then C4+F4, and so on. The `up(n)` method transposes a track up `n` octaves (defaulting to 1). The `zip` function takes another track and interleaves the two tracks' steps. And for kicks, let's give the higher notes a shorter gate, using the `gate` method, which sets the gate on all steps in a track. We can do something like this:

```ruby
t = T(chord(:c3, :major9))
t |= t.transpose(-7)
t = t + t.reverse.drop.drop_last
t = t.zip(t.up.gate(0.5))
```

If we had constructed that track manually with `Track.new`, it would look like this:

```ruby
T([
   [:f2, :c3], [S(:f3, gate: 0.5), S(:c4, gate: 0.5)],
   [:a2, :e3], [S(:a3, gate: 0.5), S(:e4, gate: 0.5)],
   [:c3, :g3], [S(:c4, gate: 0.5), S(:g4, gate: 0.5)],
   ...,
   [:c3, :g3], [S(:c4, gate: 0.5), S(:g4, gate: 0.5)],
   [:a2, :e3], [S(:a3, gate: 0.5), S(:e4, gate: 0.5)]
])
```

Note the alternating pairs generated by `zip`: each slot is followed by a slot with same notes up an octave with a shorter gate. Note also how the track is mirrored due to the concatenation with its `reverse` - the early A+E, C+G progression appears backwards at the end of the track. But the leading F+C pair is missing at the very end so that the track loops cleanly (that was the `drop_last`).

We've barely scratched the surface, but already it's easy to assemble complicated tracks. Here's a nice melody using things you've seen so far and a few new tricks: the `*` operator concatenates a track with itself some number of times, and the `shl` method shifts a track's slots to the left, wrapping the first slots back around to the end. This is an intricate 64-step sequence, all constructed from simple manipulations of a minor 7th chord!

```ruby
t = T(chord(:d4, :minor7)).gate(0.5)
t = t.zip(t.reverse.gate(0.25).shl)
t = t * 2 + t.transpose(7) * 2
t = t.zip(t.transpose(-7))
```

Just like normal `live_loop`s, you can have multiple `track_live_loops` running at the same time. So let's add a bass accompaniment to the above. We'll construct that from the melody track by shifting it down two octaves with `down` and, to add some rhythm, we'll turn every 3rd slot into a rest with `dropout`. Let's also make the bass notes have a longer gate than those in the melody.

```ruby
t = T(chord(:d4, :minor7)).gate(0.5)
t = t.zip(t.rev.gate(0.25).shl)
t = t * 2 + t.transpose(7) * 2
t = t.zip(t.transpose(-7))

track_live_loop :melody, t
track_live_loop :bass, t.down(2).dropout(3).gate(0.9)
```

With the `midi`, `port` and `channel` arguments, the `:bass` track could easily be sent to another MIDI target and play on a separate synth than the melody.

There are many more ways to manipulate tracks. You can replace notes in a track based on some pattern (`sub_note`), adjust gate or velocity based on a curve (`gate_curve` and `vel_curve`), split a track into multiple tracks (`extract`, e.g.), do targeted manipulation of each step (`mutate_steps`), and more.

### `track_live_loop` blocks

You have probably noticed that, unlike normal Sonic Pi `live_loop`s, `track_live_loop`s do not require a block. By default, they will construct their own that manages a `Player` instance to handle the track you provide.

However, you can pass your own block to `track_live_loop`, which has some special rules and powers. Most importantly:

- Blocks should not `sleep` or `sync`, unlike `live_loop` blocks. The internal block will do that for you to ensure proper timing when playing back the track you provide. If you do `sleep` or `sync`, it will result in gaps between cycles of your track.
- If your block returns a `Track` instance, that track will be played instead of the track you provided as an argument to `track_live_loop`. In fact, if you provide a block that returns a `Track`, there may not be a reason to pass a track to `track_live_loop` at all. This is valid.
- The block can receive a number of arguments. See the documentation for all of them. For now we'll just look at `cycle`, which is the number of times the track has looped. It is 0 when the track starts and increments each time the block is executed.

Returning a `Track` from your block is very powerful. It allows you to mutate the track you're playing back each cycle. For example, let's say we wanted to transpose a track 1 semitone every loop (up to 7 semitones), and perhaps have the gate of its steps slowly increase each cycle. Using the `cycle` parameter, we can adjust our track accordingly in the block:

```ruby
t = Track.arp(chord(:c3, :major9), :thumb)

track_live_loop :t do |cycle:|
  t.transpose(cycle % 8).gate(0.1 * (cycle + 1))
end
```

Note that we did not need to pass `track_live_loop` a track up-front, since the block returns one. And since we mutate the track based on the `cycle`, it's different each loop.

For another example, we could randomly rearrange the notes in our track each cycle, using the `shuffle` method:

```ruby
t = T(chord(:c3, :major13)).gate(0.5)

track_live_loop :t do
    t.shuffle
end
```

Here we did not need the `cycle` parameter, so we just omitted it from the block.

### Muting tracks

Just as you might use live-coding to add or stop `live_loops`, you can do the same with `track_live_loop`s. However, `track_live_loop`s can also be muted or unmuted after a cycle by other means. In these examples, we'll look at MIDI CC control, but you can also manually handle muting with the `mute_live_loop` function.

You can add the `cc` keyword parameter to a `track_live_loop` to specify that a CC should control whether it is muted. Sending a value of 0 for that CC will mute the track, and any other value will unmute it. Note that muting only takes effect *after a cycle of the track*; it will not abruptly make the track inaudible. Unmuting is the same; it will only happen in intervals of the track's duration, even though the track is not audible.

By default, a `track_live_loop` will listen for the CC you specify from any MIDI port and any MIDI channel. To specify a specific device, use the `cc_port` and `cc_channel` arguments or set a default with the `use_cc_control_defaults` method.

Tracks start unmuted by default. You can use the `start_muted` parameter to change that (or `use_player_defaults` to set a global default).

Here's an example with two tracks. The melody starts unmuted (and is not controllable by CCs). The bassline starts muted, and may be unmuted by sending any nonzero value for CC 110 from `my_midi_device` channel 1.

```ruby
use_cc_control_defaults(port: "my_midi_device", channel: 1)

t = T(chord(:c3, :major13)).gate(0.5)

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

Unlike muting, *fill mode takes effect immediately*. That is, steps with the fill probability will immediately start being triggering after fill is set; you do not need to wait for another cycle of playback.

Here's an example where an E2 is only triggered in fill mode. The `track_live_loop` is configured to watch CC 111 for fill.

```ruby
t = T([:c4, [:e4, S(:e2, prob: Prob.fill)], :g4])

track_live_loop :t, t, fill_cc: 111
```

There is also a `not_fill` probability, which specifies that a step should only trigger when fill is off. And, there is a `fill` method on `Track` that gives all steps the `fill` probability, which may be useful when assembling tracks by merging them.
