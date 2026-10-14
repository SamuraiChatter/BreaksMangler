# BreaksMangler
Sonic Pi Drum Break Mangler (Drum Machine)

## Running it

Needs Sonic Pi v5 and an Akai Midi Mix, which v5 lists as `midi_mix` under Prefs → IO.

### Audio driver on Windows

In Prefs → Audio, set the driver to **Windows Audio (Exclusive Mode)** and pick your speakers or headphones as the output. While Sonic Pi is open it has that output to itself: other programs play no sound through it.

Sonic Pi v5 times outgoing MIDI from the audio clock, so the Midi Mix LEDs are only as steady as the audio output, and a script cannot run at all without one. v4 sent MIDI on its own clock, so it did not have this problem. The other drivers did not hold up here:

- **DirectSound** (`Primary Sound Driver`, which v5 chooses by default) ran slow and stalled for over a second at a time, freezing the LEDs. When the engine gave up on the clock it re-opened the audio device, which wiped the running script.
- **Windows Audio** lost its output about 20 seconds after every launch and never got it back. Scripts then fail with `Promise timed out after 3 seconds`, and Prefs → Audio shows no drivers to choose from.

If Prefs → Audio is empty, quit Sonic Pi and set the driver by hand in `~/.sonic-pi/config/v5-gui-settings.ini`:

```ini
audio-driver=Windows Audio (Exclusive Mode)
```

The details are in [docs/sonic-pi-v5-midi.md](docs/sonic-pi-v5-midi.md).

### Starting the script

Run the file from the repo rather than pasting it into a buffer. In an empty Sonic Pi buffer, run this one line, with the path changed to your checkout (use forward slashes):

```ruby
run_file "C:/programming/BreaksMangler/BreaksMangler.rb"
```

This always runs the file as it is on disk, so what you test is what gets committed. A pasted copy goes stale as soon as the file changes.

That path is the main checkout, which only has what is merged. To test a ticket that is still in progress, point at its worktree instead, with the branch name filled in:

```ruby
run_file "C:/programming/BreaksMangler/.claude/worktrees/<branch>/BreaksMangler.rb"
```

Once it is running:

- A lit LED walks along the bottom row of buttons, one column per beat.
- Press Send All on the Midi Mix so the knob and slider positions are picked up.
- Press a top-row button to set a trigger; its LED lights and the break starts playing.

To check that Sonic Pi can reach the Midi Mix at all, run `midi_probe.rb` the same way. It lights each LED in turn, then records the MIDI it hears in `~/.sonic-pi/log/midi_probe.log` until stopped. What Sonic Pi v5 does with MIDI on each machine is written up in [docs/sonic-pi-v5-midi.md](docs/sonic-pi-v5-midi.md).

If the Midi Mix is unplugged while Sonic Pi is open, restart Sonic Pi after plugging it back in. The LEDs carry on working but the buttons and knobs are ignored until then.

Time State is shared by every buffer and survives Stop. If the script behaves oddly after other code has been run, restart Sonic Pi and run it again.

## Adding your own samples

You don't need to edit any code to add sounds — just drop audio files (`.wav`,
`.aiff`, or `.flac`) into a `Samples` folder, following two simple rules:

1. Put each file in a folder named after its length, like `1_bar` (a 1-bar
   loop) or `4_bar` (a 4-bar loop). It's fine for some of these folders to
   be empty — only add the ones you're using.
2. Start each filename with a two-digit number, like `01_`, so BreaksMangler
   knows what order to play them in.

For example:

```
Samples/
  1_bar/
    01_amen.wav
    02_breakbeat.wav
  4_bar/
    01_garzul.wav
```

Turn the knob on your MIDI controller and it cycles through whatever
samples you've added.

By default, BreaksMangler looks for this folder at
`Applications/SonicPi/Samples` inside your home folder. If it can't find any
samples there, it plays a small set of built-in demo loops instead so you
can try it out right away — you'll see a message telling you it's doing
this. If you'd rather keep your samples somewhere else, edit the file
`.breaksmangler_samples_root` in your home folder (BreaksMangler creates
this automatically the first time it runs) and put the full path to your
samples folder in it.
