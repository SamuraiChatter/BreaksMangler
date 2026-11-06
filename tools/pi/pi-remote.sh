#!/usr/bin/env bash
# Runs on the Pi, started by pi-run.sh. Not meant to be run by hand.
# Usage: pi-remote.sh <script.rb> <seconds> <record: 0|1>
set -u
script=$1; secs=${2:-20}; record=${3:-0}
here=$(cd "$(dirname "$0")" && pwd)
ruby_bin=$HOME/Applications/sonic-pi/usr/ruby/bin/ruby
export XDG_RUNTIME_DIR=/run/user/$(id -u)

if [ ! -x "$ruby_bin" ]; then
  echo "Sonic Pi is not unpacked at ~/Applications/sonic-pi - see docs/sonic-pi-v5-midi.md (Installing Sonic Pi v5)" >&2
  exit 2
fi

# Two engines fight over the audio device and the MIDI ports, so stop any first.
# This file's own command line contains none of these patterns, so pkill -f is safe here.
# The GUI's engine outlives the GUI, so it is stopped by name as well.
pkill -f 'Sonic-Pi-for-Linux' 2>/dev/null
pkill -f 'ruby.*sp-run.rb' 2>/dev/null
pkill -f 'sonic-pi-supersonic' 2>/dev/null
sleep 2

# Measure what reaches the headphone sink, halfway through the run.
if [ "$record" = 1 ]; then
  (
    sleep $((secs / 2))
    timeout 4 pw-record -P stream.capture.sink=true --rate 48000 --channels 2 --format s16 /tmp/pi-run-sink.wav >/dev/null 2>&1
    python3 - <<'PY'
import wave, struct
w = wave.open("/tmp/pi-run-sink.wav")
d = w.readframes(w.getnframes())
s = struct.unpack("<%dh" % (len(d) // 2), d)
peak = max((abs(x) for x in s), default=0)
print("[sink] peak %d of 32767 (%d%%) %s" % (peak, peak * 100 // 32767, "- SILENT" if peak < 50 else ""))
PY
  ) &
fi

log=$HOME/.sonic-pi/log/supersonic.log
lines_before=$(wc -l < "$log" 2>/dev/null || echo 0)
timeout $((secs + 60)) "$ruby_bin" "$here/sp-run.rb" "$script" "$secs" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | { if [ -n "${PI_RUN_VERBOSE:-}" ]; then cat; else grep --line-buffered -vE 'midi_note_on|midi_cc|Defining fn|^\s*$'; fi; }
wait

echo "--- engine log lines from this run (audio device, drift, errors)"
tail -n +$((lines_before + 1)) "$log" \
  | grep -E 'attaching audio|aboutToStart|audioDeviceStopped|DRIFT|\[midi\] ports|rror' | cut -c1-200
