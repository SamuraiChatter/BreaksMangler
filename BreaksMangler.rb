############BREAK MANGLER############
use_bpm 120

# TODO: Explore Send All button and if I can update state that way!!!!!!!!!!!!!!!!

# TODO: create an amen sample named amen tight that I extract audio/add audio to make everything tight to the grid and see the difference.
# TODO: More efficient to access variable then get lookup, so I should refactor to make that better. especially around midi events if possible.
# TODO: Flash Led off and on as part of sequence clock going through sequencer
# TODO: If I had an arduino midi controller I could limit how many events send, not full 127 for a sweep probably
# TODO: May need to get last midi values and input so when I click run again state is correct.
# TODO: Clear lights at initial run, grab last state of things.
# Chat GPT suggested
##| if get(:initial_run) == nil
##|   set :initial_run, true

##|   # Code to be executed only on the initial run
##|   puts "This code runs only on the first run"
##| end

##| # Rest of your code which will run every time
##| puts "This code runs every time"

################SETUP##############

loops = [
  { sample: :loop_amen, beats: 4 },
  { sample: :loop_amen_full, beats: 16 },
  { sample: :loop_breakbeat, beats: 4 },
  { sample: :loop_industrial, beats: 2}
]

# TODO: Incorporate options
# Support two optons currently #TODO: Would like to change to hash if possible for readability, relying on dig for arrays though in play sample
effects = [
  { effect: :reverb, level_control: :mix, opts: [[:room, 0.8]] },
  { effect: :distortion, level_control: :distort, opts: [[:mix, 0.5],] },
  { effect: :bitcrusher, level_control: :mix, opts: []},
  { effect: :echo, level_control: :mix, opts: []},
  { effect: :panslicer, level_control: :mix, opts: []},
  { effect: :compressor, level_control: :mix, opts: []},
  { effect: :pitch_shift, level_control: :mix, opts: []},
  { effect: :flanger, level_control: :mix, opts: []}
]

# TODO no need to set this, can make variable like the above
# 8 Part Sequence on Midimix
set :pattern_length, 8.0

# Initial state of leds
set :sequence_trigger_leds, [0,0,0,0,0,0,0,0]
set :note_off_leds, [0,0,0,0,0,0,0,0]


# TODO: Note lookup for sequence trigger notes and note offs as well like the below
set :midi_sequence_trigger_notes, [1,4,7,10,13,16,19,22,27]
set :midi_note_off_notes, [3,6,9,12,15,18,21,24]
midi_sample_notes = [16,20,24,28,46,50,54,58]
midi_sequence_slice_notes = [17,21,25,29,47,51,55,59]
midi_fx_notes = [18,22,26,30,48,52,56,60]
midi_fx_level_notes = [19,23,27,31,49,53,57,61]

midi_note_lookup = {}

midi_sample_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_samples, index: idx}}
midi_sequence_slice_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_sequence_slices, index: idx}}
midi_fx_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_fx, index: idx}}
midi_fx_level_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_fx_level, index: idx}}


# Initial values for midi
# TODO: Can I have these remain in subsequent runs if I only set on initial run?
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

in_thread(name: :step_monitor) do
  set :step, 0
  loop do
    sync :pulse
    puts get[:step]
    set :step, (get[:step]+1) % get(:pattern_length)
  end
end

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
# Seperated these from note events because the sequencer relies on understanding history, where as, I want these to be more performative
live_loop :midi_mix_control_changes do
  use_real_time
  control_note, control_velocity = sync "/midi:midi_mix_0:1/control_change"
  lookup = midi_note_lookup[control_note]
  index = lookup[:index]
  midi_store = lookup[:midi_store]
  update_midi_store(midi_store, control_velocity, index)
  #sleep 0.01 # This may miss events, but also performs better under a full sweep. Chat GPT suggested sleeping 0.01
end

######## Loop Music #############
live_loop :f do
  sync :pulse
  sample :bd_tek
end

live_loop :e do
  sync :pulse
  step = get(:step)
  midi_triggers = get(:midi_triggers)
  trigger = midi_triggers[step]
  midi_note_offs = get(:midi_note_offs)
  note_off = midi_note_offs[step]
  
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
  
  # Changing to round.floor seems to fix things when I use effects, but I have a bug in loop amen 16 bit
  (midi_value.to_f / 127 * range_limit).round.floor
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
  opts = hash[:opts]
  puts #{opts}
  puts "loop #{loop}, sample #{loop[:sample]}, beats #{loop[:beats]}"
  with_fx fx, level_attribute, level, opts.dig(0,0), opts.dig(0,1), opts.dig(1,0), opts.dig(1,1) do
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

define :update_midi_store do |midi_store, value, index|
  specific_midi_store = get(midi_store)
  values = specific_midi_store.to_a
  values[index] = value
  set midi_store, values.ring
end

# THINGS TO TALK ABOUT FOR LUNCH AND LEARN
# MIDI EVENTS, circuit breaking with faraday, not sure if comparison there but feels like it, microservices, we need to think about it more, triage ticket I had for this that I messaged Chrispy about
# Refactoring
# When to abstract, determining when too much
# Change of concepts note_ons vs note_offs from user experience level, working with red, so it seemed like a bad user experience
# Sequence of events and utilizing start point on further steps. Hard to wrap head around but creates problems
# Concept of rings is really interesting
# model samples makes sense they used limitless encoders since I ran into issues with current state of knobs and you have to have sysex to rectify.
