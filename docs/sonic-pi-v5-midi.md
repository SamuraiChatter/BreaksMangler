# How Sonic Pi v5 handles MIDI

What was found by running BreaksMangler and `midi_probe.rb` against Sonic Pi v5, on each machine.

## Windows

Sonic Pi v5.0 (Ruby 4.0.5, SuperSonic v0.71.0) on Windows 11, 12 October 2026.

### Port names

| Device | Input | Output |
|---|---|---|
| Akai Midi Mix | `midi_mix` | `midi_mix` |

v4 added a number to each name, taken from the device's position in Windows' list: the Midi Mix was `midi_mix_0` for input and `midi_mix_1` for output. v5 uses the bare name for both.

Windows' built-in synth also appears as an output, `microsoft_gs_wavetable_synth`.

### Cue paths

| Event | Cue path | Values |
|---|---|---|
| Midi Mix button press | `/midi:midi_mix:1/note_on` | note, 127 |
| Midi Mix button release | `/midi:midi_mix:1/note_off` | note, 127 |
| Midi Mix knob turn | `/midi:midi_mix:1/control_change` | controller, value |

Captured by the probe. The Midi Mix sends on channel 1.

### Replugging the Midi Mix

A Midi Mix unplugged and plugged back in while Sonic Pi is open comes back half working:

- **Output: on.** The engine logs the port leaving and returning under the same name, and the probe's LED sweep works straight away.
- **Input: off.** No cue arrives from its buttons or knobs, in the probe or in BreaksMangler, although the engine lists `midi_mix` as an input again. Restarting Sonic Pi brings the input back. Whether switching it off and on in Prefs → IO does too has not been tried.

### Probe script

`midi_probe.rb` lights each sequence-trigger LED in turn, then each note-off LED, then turns them all off. Seen on the Midi Mix and logged four times with no errors.

### Audio driver

Sonic Pi v5 times outgoing MIDI from the audio clock and will not run a script without an audio output, so the driver decides whether BreaksMangler works at all. Only **Windows Audio (Exclusive Mode)** held its output here.

About five seconds after start-up the GUI asks the engine for its list of audio devices. The engine takes 15 to 20 seconds to answer, and under most drivers the scan stops the device it is playing through: `supersonic.log` shows `audioDeviceStopped` within about 30 ms of the first `[device-list]` line. What happens next depends on the driver. Each was tried by starting the engine on its own and sending it the same request (`/supersonic/devices/report`), as well as in Sonic Pi itself.

| Driver | Device after the scan | Device list reaches the GUI |
|---|---|---|
| Windows Audio (Exclusive Mode) | keeps running | yes |
| Windows Audio | stops and is not re-opened | no |
| Windows Audio (Low Latency Mode) | stops; clock reported at 1509x real-time | yes |
| DirectSound | stops; re-opened within a second in Sonic Pi, in five sessions of six | yes, in Sonic Pi |

- **Windows Audio** is left with no output (`currentOut=''` on every later `[device-list]` line, one every 3.5 seconds). Scripts fail with `Promise timed out after 3 seconds`, no MIDI goes out, and Prefs → Audio shows no drivers, because the list never arrives. This happened in six sessions of six. Naming the output device, asking for two output channels, and a buffer of 480 made no difference. The one session that held was switched from DirectSound to Windows Audio in Prefs while running, after the scan had finished.
- **DirectSound**, on `Primary Sound Driver`, ran slow (the engine logged it "delivering 0.86x real-time") and stalled for over a second at a time. When the engine gave up on the clock it re-opened the device, which wiped the running script.
- Under Windows Audio the Realtek speakers are reported as having 64 output channels, and the engine's first attempt to open them fails (`init with 0 in / 64 out failed: Couldn't open the output device!`) before it falls back to two. Under Exclusive Mode they are reported as 8 and open first time.

Exclusive Mode gives Sonic Pi the output to itself; other programs are silent on it while Sonic Pi is open.

The driver is saved as `audio-driver` in `~/.sonic-pi/config/v5-gui-settings.ini`. Sonic Pi rewrites that file when it quits, so edit it only while Sonic Pi is closed.

### Other things v5 does differently from v4

- **A MIDI command needs `port:`.** `midi_note_on 4, 127` with no port did not light the Midi Mix. With `port: "midi_mix", channel: 1` it did.
- **Buffers are not saved to disk.** The files under `~/.sonic-pi/store` were last written in December 2024, and the log shows `Permission denied` on `store/system/cache.json` at every start. Whether the two are connected has not been checked.
- **Time State is shared across buffers.** Old code in another buffer that set `:midi_samples` broke BreaksMangler until Sonic Pi was restarted. This is not known to be new in v5.

## Raspberry Pi 4

Sonic Pi v5.0 (Ruby 3.4.4, SuperSonic v0.71.0) on a Raspberry Pi 4 running 64-bit Raspberry Pi OS (Debian 13 "trixie", `aarch64`, labwc on Wayland), 2 to 3 November 2026.

### Installing Sonic Pi v5

1. Download `Sonic-Pi-for-Linux-arm64-v5.0.0.AppImage` and put it in `~/Applications`.
2. `chmod +x ~/Applications/Sonic-Pi-for-Linux-arm64-v5.0.0.AppImage`, then run it from a terminal on the desktop or double-click it. Plug the Midi Mix in first.
3. To start it when the desktop starts, add `~/.config/autostart/sonic-pi.desktop` with `Type=Application`, `Name=Sonic Pi` and `Exec=` the full path of the AppImage. This was written but a reboot has not been tried; starting at boot is BREAK-8.
4. For running without the GUI (see below), unpack the AppImage once: `./Sonic-Pi-for-Linux-arm64-v5.0.0.AppImage --appimage-extract`, then move the `squashfs-root` folder to `~/Applications/sonic-pi`. It is about 765 MB.

### Port names

| Device | Input | Output |
|---|---|---|
| Akai Midi Mix | `midi_mix_midi_mix_midi_1_28_0` | `midi_mix_midi_mix_midi_1_28_0` |

The name is built from ALSA's device name, `midi_mix_midi_mix_midi_1`, plus ALSA's client number and port (`28_0`). Through-port: `midi_through_midi_through_port-0_14_0`. The client number comes from the order devices were plugged in, so it may change; whether it does across a replug or reboot has not been checked.

The Pi needs this name in `breaksmangler.yml` as both `midi_mix_input_port` and `midi_mix_output_port`. With the defaults the script listens on `/midi:midi_mix:1/note_on`, which never arrives.

### Cue paths

| Event | Cue path | Values |
|---|---|---|
| Midi Mix button press | `/midi:midi_mix_midi_mix_midi_1_28_0:1/note_on` | note, 127 |
| Midi Mix button release | `/midi:midi_mix_midi_mix_midi_1_28_0:1/note_off` | note, 127 |
| Midi Mix knob or slider | `/midi:midi_mix_midi_mix_midi_1_28_0:1/control_change` | controller, value |

Captured by the probe. Same shapes as Windows; only the port in the path differs. Controllers 18 and 19 were seen.

### Audio

Sonic Pi v5 on Linux uses PipeWire. The audio goes out of the Pi's 3.5 mm headphone jack (`bcm2835 Headphones`), through the PipeWire sink `Built-in Audio Stereo`.

- **GUI:** opens `System Default` (2 outputs) and `sample :loop_amen` is heard. No `audioDeviceStopped` after the start-up device scan, unlike Windows Audio.
- **No GUI:** started with no saved preferences, the engine opens `Patchbay (16 ch)`, a PipeWire patch point that goes nowhere, and nothing is heard. `sound_card_name = "System Default"` in `~/.sonic-pi/config/v5-audio-settings.toml` fixes it. The file is all comments until edited; the GUI reads it too.
- **Level:** quiet at the sink's default 40%. Measured by recording the sink: a peak of 5809 of 32767 for `sample :loop_amen` at default amp, and 11619 at `amp: 2`. The sink was raised to 70% with `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.7`.

### Running scripts over SSH, with no GUI

`repl.rb`, which comes with Sonic Pi, stalled at start-up with the engine already running, and printed nothing, so it was not used. `headless-run.rb` mutes the mixer. `tools/pi/sp-run.rb` is a short script built on the same `headless_boot.rb` that is audible and starts `run_file`, so the settings file is found.

From the PC, with `ssh pi` set up:

```
bash tools/pi/pi-run.sh <script.rb> [seconds] [--record]
```

It copies the script to `~/SonicPi/Scripts`, stops any Sonic Pi already running (both start an engine, and two fight over the audio device and MIDI ports), runs it, and prints the log and the engine's audio lines. `--record` also measures the level reaching the headphone sink. `tools/pi/pi_check.rb` plays a loop and sweeps the LEDs together, to tell a silent run from a dead one. The `test-on-pi` skill describes how to read the result.

### Checked so far

- `sample :loop_amen` is heard.
- `midi_probe.rb`: the LED sweep lights, then clears; the cue lines above were logged.
- BreaksMangler started with `run_file`: the first run created `breaksmangler.yml` beside the script. Played for 90 seconds with the Midi Mix, it sounded and responded as expected to buttons, knobs and sliders (judged by ear and by hand), and the log showed no errors and no audio stops. The LED walk and the top-row start have not yet been ticked off one by one.
- With no samples, the demo loops play and the log names the folder it searched.

### Not yet checked

- A full two minutes without the LEDs pausing, and the BREAK-1 button, knob and Send All checks one by one.
- The sample knob sweeping real length folders in filename-number order.
- Whether a replugged Midi Mix is switched on, and whether the port name changes after a replug or reboot.
- Whether `"midi_mix"` alone lights the LEDs on the output side (the short name is not a match for the input path).

### Differences from Windows

- The port name is long, and carries ALSA's client number.
- No audio driver choice and no Exclusive Mode: PipeWire, with the engine's own `System Default`.
- With no GUI, the engine picks a silent device unless `sound_card_name` is set.
- The default samples folder, `~/Applications/SonicPi/Samples`, does not exist on this Pi: the samples folders are at `~/SonicPi/Samples`, and are empty.

## Repeating the checks on another machine

Nothing has to be copied out of Sonic Pi's panes. The answers end up in two files under `~/.sonic-pi/log`:

- `midi_probe.log`, written by `midi_probe.rb`: every MIDI cue path it hears (at most one line a second per path) and each change in the ports sending clock.
- `supersonic.log`, written by Sonic Pi: a `[midi] ports: in=[...] out=[...]` line at start-up and whenever a device is plugged in or removed, and the audio device's opens and stops.

Sonic Pi moves both into `~/.sonic-pi/log/history/<date and time>/` the next time it starts, so read them before restarting it, or look there afterwards.

Steps:

1. Install Sonic Pi v5. Connect the Midi Mix by USB before starting it.
2. On Windows, set the audio driver to Windows Audio (Exclusive Mode) (see the README).
3. Start Sonic Pi and wait 30 seconds. Run `sample :loop_amen` in an empty buffer; if it fails or is silent, sort out the audio driver before going on.
4. Run `midi_probe.rb` with `run_file` and leave it running. Every top-row LED should light in turn, then every bottom-row LED, then all go out.
5. Without pressing Stop, press a Midi Mix button and turn a knob.
6. Unplug the Midi Mix, plug it back in, and press a button and turn a knob again without touching Prefs → IO.
7. Press Stop and run the probe once more. If the LEDs light, the replugged output is switched on.
8. Read the results:
   - The port names are in the last `[midi] ports` lines in `supersonic.log`.
   - The `cue` lines in `midi_probe.log` from step 5 give the cue paths for a button press and a knob turn.
   - A `cue` line from step 6, after the port's return in `supersonic.log`, means a replugged input is switched on. None means it is off.
   - An `audioDeviceStopped` line in `supersonic.log` with no re-open after it means the audio driver has lost its output.
