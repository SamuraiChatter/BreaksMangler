# BreaksMangler
Sonic Pi Drum Break Mangler (Drum Machine)

## Running it

Needs Sonic Pi v5 and an Akai Midi Mix, which v5 lists as `midi_mix` under Prefs → IO.

Run the file from the repo rather than pasting it into a buffer. In an empty Sonic Pi buffer, run this one line, with the path changed to your checkout (use forward slashes):

```ruby
run_file "C:/programming/BreaksMangler/BreaksMangler.rb"
```

This always runs the file as it is on disk, so what you test is what gets committed. A pasted copy goes stale as soon as the file changes.

Once it is running:

- A lit LED walks along the bottom row of buttons, one column per beat.
- Press Send All on the Midi Mix so the knob and slider positions are picked up.
- Press a top-row button to set a trigger; its LED lights and the break starts playing.

Time State is shared by every buffer and survives Stop. If the script behaves oddly after other code has been run, restart Sonic Pi and run it again.
