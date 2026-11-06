---
name: test-on-pi
description: Run a BreaksMangler script on the Raspberry Pi over SSH, with no GUI, and report what happened. Use when asked to test, run, or check something on the Pi, or to find out whether audio or the Midi Mix LEDs work there.
---

# Test on the Pi

`ssh pi` must work (key login, `Host pi` in `~/.ssh/config`) and Sonic Pi v5 must be unpacked on the Pi at `~/Applications/sonic-pi`. If either is missing, the steps are in `docs/sonic-pi-v5-midi.md` under "Raspberry Pi 4". Stop and say so rather than improvising.

## Run a script

From the worktree being tested:

```
bash tools/pi/pi-run.sh <script.rb> [seconds] [--record]
```

- It copies the script to `~/SonicPi/Scripts` on the Pi, so a `breaksmangler.yml` beside it is found. Running `BreaksMangler.rb` this way replaces the Pi's copy with the one in the worktree.
- It stops any Sonic Pi already running on the Pi, GUI included. Say so first if the user may be using the GUI.
- `--record` measures the level reaching the headphone sink. A `[sink] peak` under about 100 of 32767 is silence; around 5800 is default-amp `loop_amen` at 70% sink volume.
- `PI_RUN_VERBOSE=1` keeps the per-note MIDI lines. The tail of the output lists the audio device and `[midi] ports` lines from the engine log.

## Telling a silent run from a dead one

Run `tools/pi/pi_check.rb 12 --record`. It plays a loop and sweeps the LEDs together.

| LEDs | Sound | Likely cause |
|---|---|---|
| light | heard | working |
| light | silent | audio output (`[sink]` peak, `sound_card_name` in `~/.sonic-pi/config/v5-audio-settings.toml`, sink volume) |
| dark | heard | Midi Mix port name: compare `MIDI_PORT` with the `[midi] ports` line |
| dark | silent | engine did not start: read `~/.sonic-pi/log/spider.log` and `supersonic.log` |

Ask the user what they saw and heard. Never assume the LEDs lit: `[sink]` proves sound only, and the MIDI log proves only that notes were sent.

## Traps

- Never `pkill -f` or `pgrep -f` from an `ssh pi '...'` one-liner with a pattern that also appears in that command: it kills its own shell and the call exits 255 with no output. Use a script file, or `[x]` bracket patterns.
- Run paths with a leading `/` or `~/`. `run_file "home/..."` resolves against the home folder and doubles it.
- Two engines at once fight over the audio device and MIDI ports.
- The Midi Mix port name includes ALSA's client number (`..._28_0`) and may change.
