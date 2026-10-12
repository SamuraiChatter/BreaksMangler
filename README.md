# BreaksMangler
Sonic Pi Drum Break Mangler (Drum Machine)

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
