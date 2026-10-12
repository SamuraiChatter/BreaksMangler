# BreaksMangler
Sonic Pi Drum Break Mangler (Drum Machine)

## Running it

Needs Sonic Pi v5 and an Akai Midi Mix, which v5 lists as `midi_mix` under Prefs → IO.

### Audio driver on Windows

In Prefs → Audio, set the driver to **Windows Audio** and pick your speakers or headphones as the output. Do not leave it on DirectSound's `Primary Sound Driver`, which is what v5 chooses by default.

Sonic Pi v5 times outgoing MIDI from the audio clock, so the Midi Mix LEDs are only as steady as the audio output. On DirectSound the output ran slow (the engine logged it "delivering 0.86x real-time") and stalled for over a second at a time. Each stall froze the LEDs. When the engine gave up on the clock it re-opened the audio device, which wiped the running script and left its loops failing with `Promise timed out after 3 seconds`. v4 sent MIDI on its own clock, so it did not have this problem.

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

Time State is shared by every buffer and survives Stop. If the script behaves oddly after other code has been run, restart Sonic Pi and run it again.
