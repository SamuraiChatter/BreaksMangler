###########BREAK MANGLER############
## !!!! Click Send All on MidixMix after starting to have CC values from midi controller align to state in program !!! ##

# TODO: Explore Send All button and if I can update state that way!!!!!!!!!!!!!!!!
# TODO: create an amen sample named amen tight that I extract audio/add audio to make everything tight to the grid and see the difference.
# TODO: Flash Led off and on as part of sequence clock going through sequencer
# TODO: If I had an arduino midi controller I could limit how many events send, not full 127 for a sweep probably

################SETUP##############

######### Settings (read from breaksmangler.yml beside this file on every run) #########
# Every setting and its default is listed in README.md.
require "yaml"

define :load_settings do |path|
  defaults = {
    "samples_folder" => File.join(Dir.home, "Applications", "SonicPi", "Samples"),
    "midi_mix_input_port" => "midi_mix",
    "midi_mix_output_port" => "midi_mix",
    "clock_mode" => "internal",
    "tempo" => 160,
    "clock_trim_ms" => 0,
  }
  text =->(value) { value.is_a?(String) && !value.strip.empty? }
  valid = {
    "samples_folder" => text,
    "midi_mix_input_port" => text,
    "midi_mix_output_port" => text,
    "clock_mode" => ->(value) { ["internal", "external"].include?(value) },
    "tempo" => ->(value) { value.is_a?(Numeric) && value > 0 },
    "clock_trim_ms" => ->(value) { value.is_a?(Integer) },
  }

  if path.nil?
    puts "BreaksMangler: not started with run_file, so the settings file cannot be found - using every default"
    return defaults
  end

  loaded = begin
    File.write(path, defaults.to_yaml) unless File.exist?(path)
    YAML.safe_load(File.read(path))
  rescue SystemCallError, Psych::Exception => error
    puts "BreaksMangler: #{path} could not be read (#{error.message}) - using every default"
    nil
  end
  loaded = {} unless loaded.is_a?(Hash)

  (loaded.keys - defaults.keys).each do |name|
    puts "BreaksMangler: #{name} in #{path} is not a setting - ignoring it"
  end

  settings = defaults.to_h do |name, default|
    if !loaded.key?(name)
      puts "BreaksMangler: #{name} is missing from #{path} - using the default, #{default}"
      [name, default]
    elsif valid[name].call(loaded[name])
      [name, loaded[name]]
    else
      puts "BreaksMangler: #{name} in #{path} has an unrecognised value, #{loaded[name].inspect} - using the default, #{default}"
      [name, default]
    end
  end

  # Playing earlier than this would need more than Sonic Pi's 0.2 s schedule-ahead.
  # Not Integer#clamp: Sonic Pi replaces it with a one-argument version.
  trim = settings["clock_trim_ms"]
  settings["clock_trim_ms"] = [[trim, -150].max, 150].min
  if settings["clock_trim_ms"] != trim
    puts "BreaksMangler: clock_trim_ms in #{path} is #{trim}, outside -150 to 150 - using #{settings["clock_trim_ms"]}"
  end
  settings
end

# run_file gives the script its own path, which is how the settings file
# beside it is found. Code pasted into a buffer has no path.
settings_path = File.file?(__FILE__) ? File.join(File.dirname(File.expand_path(__FILE__)), "breaksmangler.yml") : nil
settings = load_settings(settings_path)

# In external mode the MPC sets the tempo and starts and stops the pattern (see "Follow the MPC" below)
external_clock = settings["clock_mode"] == "external"
use_bpm settings["tempo"]
use_sched_ahead_time 0.2

# External mode only: false lets a sounding slice ring out when the MPC stops, true cuts it off
cut_samples_on_stop = false
recent_slices = [] # the last few slices started, for cutting them off

########## Akai Midimix Details ##########
pattern_length = 8.0 # 8 Steps on Akai Midimix Contoller

midi_sample_notes = [16,20,24,28,46,50,54,58]
midi_sequence_slice_notes = [17,21,25,29,47,51,55,59]
midi_fx_notes = [18,22,26,30,48,52,56,60]
midi_fx_level_notes = [19,23,27,31,49,53,57,61]
midi_note_lookup = {}
midi_sample_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_samples, index: idx}}
midi_sequence_slice_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_sequence_slices, index: idx}}
midi_fx_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_fx, index: idx}}
midi_fx_level_notes.each_with_index {|note, idx| midi_note_lookup[note] = {midi_store: :midi_fx_level, index: idx}}

######### Sample Library (dynamic folder scan) #########
# Folder/filename conventions are documented in README.md. Full rationale
# in DEVELOPER_README.md.

define :build_loops do |samples_root, demo_loops|
  folder_pattern = /\A(\d+)_(beat|bar)\z/
  prefix_pattern = /\A(\d+)_/
  accepted_extensions = ["wav", "wave", "aiff", "aif", "flac"]

  entries = []
  # base: keeps glob characters in the samples path from being read as a pattern
  Dir.glob("*", base: samples_root).each do |folder_name|
    folder_path = File.join(samples_root, folder_name)
    next unless File.directory?(folder_path)
    match = folder_pattern.match(folder_name)
    next unless match
    beats = match[2] == "bar" ? match[1].to_i * 4 : match[1].to_i
    next if beats < 1 # a zero-beat loop cannot be sliced

    Dir.glob("*", base: folder_path).each do |file_name|
      file_path = File.join(folder_path, file_name)
      next unless File.file?(file_path)
      next unless accepted_extensions.include?(File.extname(file_path).delete(".").downcase)

      prefix_match = prefix_pattern.match(File.basename(file_path))
      if prefix_match
        entries << { sample: file_path, beats: beats, prefix: prefix_match[1].to_i, path: file_path }
      else
        puts "BreaksMangler: #{File.basename(file_path)} has no numeric prefix (e.g. 01_) - sorting it last"
        entries << { sample: file_path, beats: beats, prefix: nil, path: file_path }
      end
    end
  end

  prefixed, unprefixed = entries.partition { |entry| entry[:prefix] }
  ordered = prefixed.sort_by { |entry| [entry[:prefix], entry[:beats], entry[:path]] } +
            unprefixed.sort_by { |entry| [entry[:beats], entry[:path]] }

  if ordered.empty?
    puts "BreaksMangler: No custom samples found at #{samples_root} - playing Sonic Pi's built-in demo loops instead. Add your own there (see README.md) to replace them."
    demo_loops
  else
    ordered.map { |entry| { sample: entry[:sample], beats: entry[:beats] } }
  end
end

demo_loops = [
  { sample: :loop_amen, beats: 4 },
  { sample: :loop_amen_full, beats: 16 },
  { sample: :loop_breakbeat, beats: 4 },
  { sample: :loop_industrial, beats: 2 },
  { sample: :loop_garzul, beats: 16 },
]

loops = build_loops(settings["samples_folder"], demo_loops)

######### Loop and Effect Details #########
effects = [
  { effect: :reverb, level_control: :mix, opts: [[:room, 0.8]] },
  { effect: :gverb, level_control: :mix, opts: [[:room, 1.2]] },
  { effect: :pitch_shift, level_control: :pitch, opts: [[pitch_dis: 0.0001], [time_dis: 0.0001]]},
  { effect: :rate }, #Customized Behavior, does not support same format as preceeding effects
]

# Defined on every run, so a change here takes effect without restarting Sonic Pi
define :send_led_status do |note, status|
  velocity = status == 'off' ? 0 : 127
  midi_note_on note, velocity: velocity, port: settings["midi_mix_output_port"], channel: 1
end

######### Set Variables and reset LEDs on Initial Run ########
if get(:initial_run) == nil
  puts "Inital Run: #{get(:initial_run)}"
  set :initial_run, true
  
  set :sequence_trigger_leds, [0,0,0,0,0,0,0,0]
  set :note_off_leds, [0,0,0,0,0,0,0,0]
  set :midi_sequence_trigger_notes, [1,4,7,10,13,16,19,22,27]
  set :midi_note_off_notes, [3,6,9,12,15,18,21,24]
  
  
  set :midi_triggers, ring(0,0,0,0,0,0,0,0)
  set :midi_note_offs, ring(0,0,0,0,0,0,0,0)
  set :midi_samples, ring(0,0,0,0,0,0,0,0)
  set :midi_sequence_slices, ring(0,0,0,0,0,0,0,0)
  set :midi_fx, ring(0,0,0,0,0,0,0,0)
  set :midi_fx_level, ring(0,0,0,0,0,0,0,0)
  
  (get(:midi_sequence_trigger_notes) + get(:midi_note_off_notes)).each do |note|
    send_led_status(note, 'off')
  end
end

######### Follow the MPC (external mode) #########
# Start, Continue and Stop arrive as cues from whichever port the MPC is on. The clock itself
# is not a cue: Sonic Pi follows it, and midi_clock_sources reports its tempo.
define :mpc_bpm do
  source = midi_clock_sources.find { |s| s[:primary] }
  source ? source[:bpm] : settings["tempo"]
end

define :mpc_stop do |reason|
  if get(:mpc_playing)
    set :mpc_playing, false
    puts "BreaksMangler: #{reason} - stopping"
    recent_slices.each { |node| kill node } if cut_samples_on_stop
    # Step LEDs go out 0.2 s ahead plus the trim, so wait for any still on their way,
    # then hand the bottom row back to the note-off buttons
    sleep rt(0.4)
    get(:midi_note_off_notes).each_with_index do |note, index|
      send_led_status(note, get(:midi_note_offs)[index] == 1 ? 'on' : 'off')
    end
  end
end

if external_clock
  set :mpc_playing, false

  live_loop :mpc_transport do
    use_real_time
    event = sync_event "/midi:*/*"
    case event.path.split("/").last
    when "start", "continue"
      # Play Start joins at the next two-bar boundary, so step 1 falls on one of the MPC's odd bars;
      # Play (Continue) resumes mid-song, so it joins at the next bar
      set :mpc_join_beats, event.path.end_with?("/start") ? 8 : 4
      set :mpc_restart, true
      set :mpc_play_time, Time.now.to_f
      set :mpc_playing, true
      cue :mpc_play
    when "stop"
      mpc_stop "the MPC stopped"
    end
  end

  # A pulled cable sends no Stop; Sonic Pi marks the clock stale two to three seconds after it goes
  live_loop :mpc_clock_watch do
    use_real_time
    source = midi_clock_sources.find { |s| s[:primary] }
    recently_started = Time.now.to_f - get(:mpc_play_time).to_f < 1
    mpc_stop "the MPC's clock stopped" if source && source[:stale] && !recently_started
    sleep 0.5
  end
end

######### Establish Sync Pulse and Step Counter #########
live_loop :pulse do
  if external_clock
    sync :mpc_play unless get(:mpc_playing)
    if get(:mpc_restart)
      set :mpc_restart, false
      tick_reset
      midi_sync get(:mpc_join_beats) # also switches this loop's sleep to the MPC's tempo
    end
    next unless get(:mpc_playing) # stopped while waiting for the bar
  end
  # The step travels with the cue, so every loop that syncs on it gets the same step
  step = (tick % pattern_length).to_i
  puts "PULSE #{step}"
  if external_clock
    time_warp(rt(settings["clock_trim_ms"] / 1000.0)) { cue :step, step: step }
  else
    cue :step, step: step
  end
  sleep 1
end

######## MIDI monitoring #########
live_loop :sync_midi_controller_lights do
  step = sync(:step)[:step]
  current_midi_note = get(:midi_note_off_notes)[step]
  previous_midi_note = get(:midi_note_off_notes)[step - 1]
  send_led_status(previous_midi_note, 'off') if get(:midi_note_offs)[step -1] == 0
  send_led_status(current_midi_note, 'on')
end

live_loop :update_midi_button_events do
  use_real_time
  sequence_note, sequence_velocity = sync "/midi:#{settings["midi_mix_input_port"]}:1/note_on"
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

live_loop :update_midi_knob_slider_values do
  use_real_time
  control_note, control_velocity = sync "/midi:#{settings["midi_mix_input_port"]}:1/control_change"
  lookup = midi_note_lookup[control_note]
  if lookup # This may need to stay since I won't be using all the various banks on midi controller
    index = lookup[:index]
    midi_store = lookup[:midi_store]
    update_midi_store(midi_store, control_velocity, index)
  end
  
  #sleep 0.01 # This may miss events, but also performs better under a full sweep. Chat GPT suggested sleeping 0.01
end

######### Play Music #########
live_loop :e do
  step = sync(:step)[:step]
  use_bpm mpc_bpm if external_clock # so beat_stretch fits each slice to the MPC's current tempo
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

# Plays a slice and remembers it, so mpc_stop can cut it off
define :slice_sample do |name, opts|
  node = sample name, opts
  recent_slices << node
  recent_slices.shift while recent_slices.size > 4
  node
end

define :play_sample do |loop, slice, step|
  hash = effects[midi_value_to_range(get(:midi_fx)[step], effects.size - 1)]
  fx = hash[:effect]
  level = get(:midi_fx_level)[step] / 128.0 #128 instead of 127 beacause a lot of values need to be less than 1.0
  if fx == :rate
    if (0.0..0.1).include?(level)
      slice_sample loop[:sample], beat_stretch: loop[:beats], num_slices: loop[:beats], slice: slice
    elsif (0.1..0.3).include?(level)
      slice_sample loop[:sample], beat_stretch: loop[:beats], num_slices: loop[:beats], slice: slice, rate: -1
    elsif (0.3..0.5).include?(level)
      slice_sample loop[:sample], beat_stretch: loop[:beats], num_slices: loop[:beats] * 1.5, slice: slice, rate: 0.5
    elsif (0.5..0.7).include?(level)
      slice_sample loop[:sample], beat_stretch: loop[:beats], num_slices: loop[:beats] * 1.25, slice: slice, rate: 0.75
    elsif (0.7..0.9).include?(level)
      slice_sample loop[:sample], beat_stretch: loop[:beats], num_slices: loop[:beats] / 1.5, slice: slice, rate: 1.25
    else
      slice_sample loop[:sample], beat_stretch: loop[:beats], num_slices: loop[:beats] / 2, slice: slice, rate: 1.5
    end
  else
    level_attribute = hash[:level_control]
    opts = hash[:opts]
    with_fx fx, level_attribute, level, opts.dig(0,0), opts.dig(0,1), opts.dig(1,0), opts.dig(1,1) do
      slice_sample loop[:sample],
        beat_stretch: loop[:beats],
        num_slices: loop[:beats],
        slice: slice
    end
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
  return if specific_midi_store[index] == value
  values = specific_midi_store.to_a
  values[index] = value
  set midi_store, values.ring
end