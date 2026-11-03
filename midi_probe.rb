############ MIDI PROBE ############
# Checks that Sonic Pi can reach the Midi Mix, then records what MIDI it hears until stopped.
# Run it with run_file (see README), with BreaksMangler stopped.
#
# Everything it finds is printed and appended to ~/.sonic-pi/log/midi_probe.log,
# so the results can be read from the file rather than from Sonic Pi's panes.
# Results from each machine are written up in docs/sonic-pi-v5-midi.md.

# The Midi Mix's LED port comes from breaksmangler.yml beside this file when there is one,
# since the Raspberry Pi names it differently from Windows; otherwise it is "midi_mix".
require "yaml"
midi_mix_port = "midi_mix"
settings_path = File.file?(__FILE__) ? File.join(File.dirname(File.expand_path(__FILE__)), "breaksmangler.yml") : nil
if settings_path && File.exist?(settings_path)
  begin
    configured = YAML.safe_load(File.read(settings_path))["midi_mix_output_port"]
    midi_mix_port = configured if configured.is_a?(String) && !configured.empty?
  rescue StandardError
    # an unreadable settings file leaves the default
  end
end
sequence_trigger_notes = [1,4,7,10,13,16,19,22]
note_off_notes = [3,6,9,12,15,18,21,24]
all_notes = sequence_trigger_notes + note_off_notes

log_path = File.join(Dir.home, ".sonic-pi", "log", "midi_probe.log")

define :probe_log do |line|
  File.open(log_path, "a") { |f| f.puts "#{Time.now.strftime('%H:%M:%S.%L')} #{line}" }
  puts line
end

probe_log "---- probe started #{Time.now.strftime('%Y-%m-%d')} ----"

######### Record incoming MIDI #########
# Every MIDI cue, whatever the port: /midi:<port>:<channel>/<event> and /midi:<port>/<event>
last_logged = {}
live_loop :probe_record_cues do
  use_real_time
  event = sync_event "/midi:*/*"
  path = event.path
  now = Time.now
  # A knob sweep or a running clock repeats the same path many times a second; one line a second is enough
  if last_logged[path].nil? || now - last_logged[path] > 1
    probe_log "cue #{path} #{event.val.inspect}"
    last_logged[path] = now
  end
end

######### Record which ports are sending clock #########
last_sources = nil
live_loop :probe_clock_sources do
  sources = midi_clock_sources.map do |s|
    "#{s[:port]} (#{s[:name]}) bpm=#{s[:bpm].to_f.round} clocking=#{s[:clocking]} stale=#{s[:stale]} primary=#{s[:primary]}"
  end
  if sources != last_sources
    probe_log "clock sources: #{sources.empty? ? 'none' : sources.join(' | ')}"
    last_sources = sources
  end
  sleep 1
end

######### Light each LED in turn: top row left to right, then bottom row #########
all_notes.each do |note|
  midi_note_on note, 127, port: midi_mix_port, channel: 1
  sleep 0.25
end

sleep 1

all_notes.each do |note|
  midi_note_on note, 0, port: midi_mix_port, channel: 1
end

probe_log "LED sweep sent to #{midi_mix_port}: notes #{all_notes.inspect} on, then off"
