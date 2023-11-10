############BREAK MANGLER############
use_bpm 120

# TODO: Is there a way to get initial knob midi values from midi controller on start? # SOUNDS LIKE NOT POSSIBLE UNLESS SOMETHING HAPPEND SINCE 2021
# TODO: Midi Knob events seem like they are sometimes not getting processed. Go real quick across a line and they don't end up recording all of them. # Maybe they need to be separate threads.
# TODO: create an amen sample named amen tight that I extract audio/add audio to make everything tight to the grid and see the difference.
# TODO: More efficient to access variable then get lookup, so I should refactor to make that better. especially around midi events if possible.
# TODO: Flash Led off and on as part of sequence clock going through sequencer
################SETUP##############

# Define what samples to utilize, input beats and it creates sensible slices
# TODO: May be able to extract start_points away since I have moved to slices and just have number of slices rather than array of start points
# TODO: this structure leaves something lacking, maybe use string for key, or try and abstract that away entirely
# TODO: Add loop amen but with 8 beats, make sure it works and more interesting chop points

# TODO: May need to get last midi values and input so when I click run again state is correct.
# TODO: Figure out why it takes so long to update midi values, maybe a way to see if still turning knob


# TODO: !!!!!!!!!!!!!!!!!!!!!!! CONVERT TO ARRAY, integrate sample select, Rename Loops NOT samples
loops = [
  {
    sample: :loop_amen, # sample that is called
    beats: 4 #Used for time synce
    # slices: 4 maybe abstract away start points, but maybe allow me to declare number of slices for specific sample
  },
  {
    sample: :loop_amen_full,
    beats: 16
  },
  {
    sample: :loop_breakbeat,
    beats: 4
  }
]

effects = [
  {
    effect: :reverb,
    level_control: :mix,
    opts: {
      room: 0.8,
    }
  },
  {
    effect: :distortion,
    level_control: :distort,
    opts: {}
  }
]

# 8 Part Sequence on Midimix
set :pattern_length, 8.0

# Initial state of leds
# TODO: Send signal at beginning of script to turn everything off since they don't turn off at end of run
set :sequence_trigger_leds, [0,0,0,0,0,0,0,0]
set :note_off_leds, [0,0,0,0,0,0,0,0]


# PROBABLY NEED TO COMPLILE THESE INTO A DICTIONARY TO REMOVE IF ELSE STATEMENTS AND VARIOUS LOOKUPS
# SINCE THEESE HAPPEN SO FREQUENTLY. AND UPDATE.
# ONE IDEA IS TO ALSO STORE CREATE DICTIONARY IN STEP OF A LOT OF THINGS GOING ON TO REDUCE NUMBER OF LOOKUPS

# Notes Values we receive from Midimix


# TODO: Convert these to variables since they don't change? I think that will be more performant.
set :midi_sequence_trigger_notes, [1,4,7,10,13,16,19,22,27]
set :midi_note_off_notes, [3,6,9,12,15,18,21,24]
set :midi_sample_notes, [16,20,24,28,46,50,54,58]
set :midi_sequence_slice_notes, [17,21,25,29,47,51,55,59]
set :midi_fx_notes, [18,22,26,30,48,52,56,22]
set :midi_fx_level_notes, [19,23,27,31,49,53,57,61]

# Initial values for midi
set :midi_triggers, ring(0,0,0,0,0,0,0,0)
set :midi_note_offs, ring(0,0,0,0,0,0,0,0)
set :midi_samples, ring(0,0,0,0,0,0,0,0)
set :midi_sequence_slices, ring(0,0,0,0,0,0,0,0)
set :midi_fx, ring(0,0,0,0,0,0,0,0)
set :midi_fx_level, ring(0,0,0,0,0,0,0,0)


# Need to define this here apparently since called in next method
define :send_led_status do |note, status|
  velocity = status == 'off' ? 0 : 127
  midi_note_on note, velocity: velocity, port: 'midi_mix_1', channel: 1
end

# Turn Off all LEDs
(get(:midi_sequence_trigger_notes) + get(:midi_note_off_notes)).each do |note|
  send_led_status(note, 'off')
end

# Pulse for syncing
live_loop :pulse do
  puts "PULSE"
  sleep 1
end

# Allows other processes to understand what step we are on in sequence
in_thread(name: :step_monitor) do
  set :step, 0
  loop do
    sync :pulse
    puts get[:step]
    set :step, (get[:step]+1) % get(:pattern_length)
  end
end

# Shows what point you are at on the midi controller
live_loop :sequence_led_clock do
  sync :pulse
  step = get(:step)
  current_midi_note = get(:midi_note_off_notes)[step]
  previous_midi_note = get(:midi_note_off_notes)[step - 1]
  send_led_status(previous_midi_note, 'off') if get(:midi_note_offs)[step -1] == 0
  send_led_status(current_midi_note, 'on')
end


# MIDI Button Events
live_loop :midi_mix_note_events do
  use_real_time
  sequence_note, sequence_velocity = sync "/midi:midi_mix_0:1/note_on"
  if get(:midi_sequence_trigger_notes).index(sequence_note)
    update_sequence(sequence_note, :midi_sequence_trigger_notes, :midi_triggers)
    handle_led_status(sequence_note, :midi_sequence_trigger_notes, :sequence_trigger_leds)
  elsif get(:midi_note_off_notes).index(sequence_note)
    update_sequence(sequence_note, :midi_note_off_notes, :midi_note_offs)
    handle_led_status(sequence_note, :midi_note_off_notes, :note_off_leds)
  else
    puts "Unaccounted for Sequence Note for :midi_mix_note_events"
  end
end

# MIDI Knob Events
# Seperated these from note events because the sequencer relies on understanding history
# Where as I want these to be more performative
live_loop :midi_mix_control_changes do
  use_real_time
  control_note, control_velocity = sync "/midi:midi_mix_0:1/control_change"
  if get(:midi_sequence_slice_notes).index(control_note)
    update_midi(control_note, control_velocity, :midi_sequence_slice_notes, :midi_sequence_slices)
    puts "!!!!!!!!!!!!! Sequence_slices: #{get(:midi_sequence_slices)}"
  elsif get(:midi_sample_notes).index(control_note)
    update_midi(control_note, control_velocity, :midi_sample_notes, :midi_samples)
  elsif get(:midi_fx_notes).index(control_note)
    update_midi(control_note, control_velocity, :midi_fx_notes, :midi_fx)
  elsif get(:midi_fx_level_notes).index(control_note)
    update_midi(control_note, control_velocity, :midi_fx_level_notes, :midi_fx_level)
  else
    puts "Unaccounted for Control Note for :midi_mix_control_changes"
  end
end

# Move this down in script when finished
# Need to interpret these values in the playing of samples

#I think I am going to need a midi store that then updates values behind it in what the sequencer is refrencing,
#otherwise if value is updated no longer going to play the correct next step if a trigger
# Good test for this would be have only first triger and all note ons and start fucking with the sample start control on that first trigger
# Additional thinking not enough to work backwards in array, need to consider it with rings and last trigger event.
define :update_midi do |control_note, control_velocity, control_notes, control_type|
  index = get(control_notes).index(control_note)
  values = get(control_type).to_a
  values[index] = control_velocity
  set control_type, values.ring
end

######## Loop Music #############
live_loop :f do
  sync :pulse
  sample :bd_tek
end

live_loop :e do
  sync :pulse
  step = get(:step)
  puts "Live loop step #{step}"
  midi_triggers = get(:midi_triggers)
  trigger = midi_triggers[step]
  midi_note_offs = get(:midi_note_offs)
  note_off = midi_note_offs[step]
  start_points =
    puts "note_offs: #{midi_note_offs}"
    puts "Live loop trigger #{trigger}"
  puts "TRIGGERS: #{get(:midi_triggers)}"
  
  if note_off == 0 && midi_triggers.to_a.include?(1)
    play_slice(step, midi_triggers)
  end
end


###### SAMPLER METHODS #######################

define :play_slice do |step, midi_triggers|
  trigger_index, previous_steps = determine_behavior(step, midi_triggers)
  loop = loops[midi_value_to_range(get(:midi_samples)[trigger_index], loops.size - 1)]
  puts "loop: #{loop}"
  slice_index = sample_slice(loop, trigger_index, previous_steps)
  
  play_sample(loop, slice_index, step)
end

define :sample_slice do |loop, trigger_index, previous_steps|
  # Retrieve midi value for slice point on initial trigger and calculate what slice we should use
  # This keeps sample playing continuously through until note off or another trigger event
  
  sample_start_midi_value = get(:midi_sequence_slices)[trigger_index]
  num_beats = loop[:beats]
  trigger_slice = midi_value_to_range(sample_start_midi_value, num_beats - 1)
  (trigger_slice + previous_steps) % num_beats
end

def midi_value_to_range(midi_value, range_limit)
  # This method allows us to send a midi value 0-127 and break it into even parts based on the range limit
  puts "midi: #{midi_value.to_f}, #{range_limit}, @#{ (midi_value.to_f / 127 * range_limit).floor}"
  # TODO: There is a problem here. Not even distribution, rounding with floor maybe?
  (midi_value.to_f / 127 * range_limit).floor
end

define :determine_behavior do |step, midi_triggers|
  # Determine where last trigger was and how many steps have taken place in the interim.
  
  previous_steps = midi_triggers.size.times do |idx|
    break idx if midi_triggers[step] == 1
    step = step - 1
  end
  
  [step, previous_steps]
end

define :play_sample do |loop, slice, step|
  puts "RESULT!!!!!!!: #{midi_value_to_range(get(:midi_fx)[step], get(:midi_fx).size - 1)}"
  hash = effects[midi_value_to_range(get(:midi_fx)[step], effects.size - 1)]
  puts "hash: #{hash}"
  fx = hash[:effect]
  level_attribute = hash[:level_control]
  level = get(:midi_fx_level)[step] / 128.0 #128 instead of 127 beacause a lot of values need to be less than 1.0
  
  with_fx fx, level_attribute, level do
    sample loop[:sample],
      beat_stretch: loop[:beats],
      num_slices: loop[:beats],
      slice: slice
  end
end


############# MIDI METHODS ############

define :handle_led_status do |note, notes, leds|
  index = get(notes).index(note)
  led_statuses = get(leds).dup
  led_status = led_statuses[index]
  if led_status == 1
    send_led_status(note, 'off')
    led_statuses[index] = 0
    set leds, led_statuses
  else
    send_led_status(note, 'on')
    led_statuses[index] = 1
    set leds, led_statuses
  end
end




define :update_sequence do |note, notes, sequence_type|
  index = get(notes).index(note)
  sequence = get(sequence_type).to_a
  sequence_value = sequence[index]
  if sequence_value == 1
    sequence[index] = 0
    set sequence_type, sequence.ring
    puts "!!!!!!!!!!#{sequence_type}: #{get(sequence_type)}"
    
  else
    sequence[index] = 1
    set sequence_type, sequence.ring
    puts "!!!!!!!!!!#{sequence_type}: #{get(sequence_type)}"
  end
end



# THINGS TO TALK ABOUT FOR LUNCH AND LEARN
# MIDI EVENTS, circuit breaking with faraday, not sure if comparison there but feels like it, microservices, we need to think about it more, triage ticket I had for this that I messaged Chrispy about
# Refactoring
# When to abstract, determining when too much
# Change of concepts note_ons vs note_offs from user experience level, working with red, so it seemed like a bad user experience
# Sequence of events and utilizing start point on further steps. Hard to wrap head around but creates problems
# Concept of rings is really interesting