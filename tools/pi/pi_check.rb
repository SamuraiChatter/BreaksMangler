############ PI CHECK ############
# Plays a drum loop and sweeps the Midi Mix LEDs at the same time, so a silent run can be
# told apart from a dead one: if the LEDs light but nothing is heard, it is the audio
# output; if the sound plays but the LEDs stay dark, it is the MIDI port name.
#
#   tools/pi/pi-run.sh tools/pi/pi_check.rb 12 --record
#
# Change MIDI_PORT if the engine log at the end of the run lists a different Midi Mix name.
MIDI_PORT = "midi_mix_midi_mix_midi_1_28_0"

sequence_trigger_notes = [1,4,7,10,13,16,19,22]
note_off_notes = [3,6,9,12,15,18,21,24]
notes = sequence_trigger_notes + note_off_notes

puts "pi_check: sweeping LEDs on #{MIDI_PORT.inspect}"

in_thread do
  4.times { sample :loop_amen; sleep sample_duration(:loop_amen) }
end

notes.each { |n| midi_note_on n, 127, channel: 1, port: MIDI_PORT; sleep 0.2 }
sleep 0.5
notes.each { |n| midi_note_on n, 0, channel: 1, port: MIDI_PORT }
puts "pi_check: done"
