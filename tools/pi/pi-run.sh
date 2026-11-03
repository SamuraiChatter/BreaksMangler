#!/usr/bin/env bash
# Run a Sonic Pi script on the Raspberry Pi from this PC, with no GUI, and print the result.
#
#   tools/pi/pi-run.sh <script.rb> [seconds] [--record]
#
# Copies the script to ~/SonicPi/Scripts on the Pi (so a breaksmangler.yml beside it is
# found by run_file), runs it for <seconds> (default 20), and prints the run log plus the
# audio-device lines from the engine log. --record also measures the level reaching the
# headphone sink, so a silent run is told apart from a quiet one without anyone listening.
#
# Needs an ssh host called "pi" (or set PI_HOST), and Sonic Pi unpacked on the Pi as in
# docs/sonic-pi-v5-midi.md. Set PI_RUN_VERBOSE=1 to keep the per-note MIDI lines.
set -euo pipefail

script=${1:?usage: pi-run.sh <script.rb> [seconds] [--record]}
secs=${2:-20}
record=0; [ "${3:-}" = "--record" ] && record=1
host=${PI_HOST:-pi}
here=$(cd "$(dirname "$0")" && pwd)

ssh "$host" 'mkdir -p ~/pi-run ~/SonicPi/Scripts'
scp -q "$here/sp-run.rb" "$here/pi-remote.sh" "$host:pi-run/"
scp -q "$script" "$host:SonicPi/Scripts/"
ssh "$host" "PI_RUN_VERBOSE=${PI_RUN_VERBOSE:-} bash ~/pi-run/pi-remote.sh ~/SonicPi/Scripts/$(basename "$script") $secs $record"
