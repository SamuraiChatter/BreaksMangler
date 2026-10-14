#!/usr/bin/env ruby
# Loads the real BreaksMangler.rb with the handful of Sonic Pi-only calls it
# needs stubbed out, then exercises the functions that don't depend on
# actual audio/MIDI I/O directly against the production source (no
# copy-pasted logic to drift out of sync).
#
# Sonic Pi's `live_loop`/`in_thread` blocks are stubbed to accept and
# discard their block entirely, so nothing inside them ever runs here -
# that's what keeps this a fast, side-effect-free process instead of an
# actual live-coding session. BreaksMangler.rb calls
# `load_settings`/`build_loops` eagerly at the top level, so before loading,
# `Dir.home` is redirected to a throwaway temp directory and the script is
# copied to another: its settings file is created beside it, and the scan
# would otherwise read the real developer machine's settings and samples.
#
# Run with: ruby spec/breaks_mangler_spec.rb

require "tmpdir"
require "fileutils"
require "stringio"

failures = []

def assert_equal(expected, actual, message, failures)
  if expected == actual
    puts "PASS: #{message}"
  else
    failures << message
    puts "FAIL: #{message}"
    puts "  expected: #{expected.inspect}"
    puts "  actual:   #{actual.inspect}"
  end
end

##### Sonic Pi DSL shims #####

def use_bpm(*); end
def use_sched_ahead_time(*); end
def midi_note_on(*); end
def live_loop(*); end
def in_thread(*); end

def define(name, &block)
  define_method(name, &block)
end

$test_state = {}

def get(key = nil)
  key.nil? ? $test_state : $test_state[key]
end

def set(key, value)
  $test_state[key] = value
end

def ring(*args)
  args
end

##### Isolate Dir.home before loading the real script #####

fake_home = Dir.mktmpdir("breaksmangler_spec_home")
Dir.define_singleton_method(:home) { fake_home }

script_dir = Dir.mktmpdir("breaksmangler_spec_script")
FileUtils.cp(File.expand_path("../BreaksMangler.rb", __dir__), script_dir)
load File.join(script_dir, "BreaksMangler.rb")

assert_equal(
  true,
  File.exist?(File.join(script_dir, "breaksmangler.yml")),
  "running the script creates its settings file beside it",
  failures
)
assert_equal([], Dir.children(fake_home), "running the script creates nothing in the home folder", failures)

##### build_loops #####

Dir.mktmpdir("breaksmangler_spec_samples") do |root|
  demo_loops = [{ sample: :loop_amen, beats: 4 }, { sample: :loop_amen_full, beats: 16 }]

  result = build_loops(root, demo_loops)
  assert_equal(demo_loops, result, "build_loops falls back to the demo bank when the root has no matching folders", failures)

  FileUtils.mkdir_p(File.join(root, "1_beat"))
  FileUtils.mkdir_p(File.join(root, "4_bar"))
  FileUtils.mkdir_p(File.join(root, "not_a_match"))
  FileUtils.mkdir_p(File.join(root, "1_bar")) # left empty on purpose

  File.write(File.join(root, "1_beat", "01_short.wav"), "")
  File.write(File.join(root, "1_beat", "09_short.wav"), "")
  File.write(File.join(root, "1_beat", "10_short.wav"), "") # numeric, not lexicographic, sort
  File.write(File.join(root, "1_beat", "ignored.mp3"), "")  # unaccepted extension
  File.write(File.join(root, "1_beat", "no_prefix.wav"), "") # sorts after all valid-prefix files
  File.write(File.join(root, "4_bar", "01_long.flac"), "")
  File.write(File.join(root, "not_a_match", "01_nope.wav"), "") # folder doesn't match N_beat/N_bar
  FileUtils.mkdir_p(File.join(root, "0_beat"))
  File.write(File.join(root, "0_beat", "01_zero.wav"), "") # zero beats can't be sliced, so it's skipped

  result = build_loops(root, demo_loops)
  names = result.map { |entry| File.basename(entry[:sample]) }
  beats = result.map { |entry| entry[:beats] }

  assert_equal(
    ["01_short.wav", "01_long.flac", "09_short.wav", "10_short.wav", "no_prefix.wav"],
    names,
    "build_loops orders by numeric prefix across folders, interleaving by design",
    failures
  )
  assert_equal([1, 16, 1, 1, 1], beats, "build_loops tags each entry with its folder's beat count", failures)

  bracket_root = File.join(root, "my [new] samples")
  FileUtils.mkdir_p(File.join(bracket_root, "1_beat"))
  File.write(File.join(bracket_root, "1_beat", "01_found.wav"), "")
  names = build_loops(bracket_root, demo_loops).map { |entry| File.basename(entry[:sample]) }
  assert_equal(["01_found.wav"], names, "build_loops finds samples under a path holding glob characters", failures)
end

##### load_settings #####

def capture_output
  original = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = original
end

Dir.mktmpdir("breaksmangler_spec_settings") do |settings_home|
  Dir.define_singleton_method(:home) { settings_home }
  settings_path = File.join(settings_home, "breaksmangler.yml")
  legacy_path = File.join(settings_home, ".breaksmangler_samples_root")
  defaults = {
    "samples_folder" => File.join(settings_home, "Applications", "SonicPi", "Samples"),
    "midi_mix_input_port" => "midi_mix",
    "midi_mix_output_port" => "midi_mix",
    "clock_mode" => "internal",
    "tempo" => 160,
  }

  File.write(legacy_path, "/old/path/file")
  settings = nil
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(defaults, settings, "load_settings returns every default when there is no settings file, ignoring the old path file", failures)
  assert_equal(defaults, YAML.safe_load(File.read(settings_path)), "load_settings creates the settings file holding every default", failures)
  assert_equal("", output, "load_settings says nothing when it creates the file", failures)

  File.delete(legacy_path)
  load_settings(settings_path)
  assert_equal(false, File.exist?(legacy_path), "load_settings never creates the old path file", failures)

  output = capture_output { settings = load_settings(nil) }
  assert_equal(defaults, settings, "load_settings returns every default when the script has no path", failures)
  assert_equal(true, output.include?("not started with run_file"), "load_settings says when the script has no path", failures)

  custom = {
    "samples_folder" => "/somewhere/else",
    "midi_mix_input_port" => "MIDI Mix:MIDI Mix MIDI 1 20:0",
    "midi_mix_output_port" => "midi_mix_out",
    "clock_mode" => "external",
    "tempo" => 87.5,
  }
  File.write(settings_path, custom.to_yaml)
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(custom, settings, "load_settings reads each setting from the file", failures)
  assert_equal("", output, "load_settings says nothing when every setting is good", failures)

  File.write(settings_path, "tempo: 120\n")
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(defaults.merge("tempo" => 120), settings, "load_settings uses the default for a missing setting", failures)
  assert_equal(true, output.include?("clock_mode is missing"), "load_settings names a missing setting", failures)

  File.write(settings_path, custom.merge("clock_mode" => "sideways", "tempo" => "fast", "midi_mix_input_port" => 5).to_yaml)
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(
    custom.merge("clock_mode" => "internal", "tempo" => 160, "midi_mix_input_port" => "midi_mix"),
    settings,
    "load_settings uses the default for a setting with an unrecognised value",
    failures
  )
  assert_equal(
    [true, true, true],
    ["clock_mode", "tempo", "midi_mix_input_port"].map { |name| output.include?("#{name} in #{settings_path} has an unrecognised value") },
    "load_settings names each setting with an unrecognised value",
    failures
  )

  File.write(settings_path, custom.merge("tempoo" => 90).reject { |name, _| name == "tempo" }.to_yaml)
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(160, settings["tempo"], "load_settings uses the default when a setting's name is misspelt", failures)
  assert_equal(true, output.include?("tempoo in #{settings_path} is not a setting"), "load_settings names a misspelt setting", failures)

  File.write(settings_path, "tempo: [1\n")
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(defaults, settings, "load_settings uses every default when the file is not valid YAML", failures)
  assert_equal(true, output.include?("could not be read"), "load_settings says when the file could not be read", failures)

  File.delete(settings_path)
  FileUtils.mkdir_p(settings_path) # a settings path that can't be read as a file
  output = capture_output { settings = load_settings(settings_path) }
  assert_equal(defaults, settings, "load_settings uses every default when the file can't be opened", failures)
  assert_equal(true, output.include?("could not be read"), "load_settings says when the file can't be opened", failures)
end

##### midi_value_to_range #####

assert_equal(0, midi_value_to_range(0, 7), "midi_value_to_range maps the lowest MIDI value to the first slot", failures)
assert_equal(7, midi_value_to_range(127, 7), "midi_value_to_range maps the highest MIDI value to the last slot", failures)

##### determine_behavior #####

# Rather than hardcoding expected indices, assert the invariant the function
# is documented to provide: it finds the step where the trigger fired, and
# reports how many steps have elapsed since then (wrapping through the ring).

# `step` can come back negative when the search wraps past index 0 - that's
# expected, not a bug: Ruby's negative array indexing already resolves it to
# the right slot (e.g. -2 on an 8-element array == index 6), and that's how
# play_slice actually uses it downstream. Normalize with % for comparison.
midi_triggers = [0, 1, 0, 0, 0, 0, 0, 0]
trigger_index, previous_steps = determine_behavior(3, midi_triggers)
assert_equal(1, trigger_index % midi_triggers.size, "determine_behavior finds the step where the trigger fired", failures)
assert_equal((3 - 1) % midi_triggers.size, previous_steps, "determine_behavior counts steps elapsed since the trigger", failures)

midi_triggers = [0, 0, 0, 0, 0, 0, 1, 0]
trigger_index, previous_steps = determine_behavior(1, midi_triggers)
assert_equal(6, trigger_index % midi_triggers.size, "determine_behavior finds the trigger step when the search wraps around the ring", failures)
assert_equal((1 - 6) % midi_triggers.size, previous_steps, "determine_behavior counts elapsed steps correctly across the wrap", failures)

##### sample_slice #####

set(:midi_sequence_slices, [0, 0, 127, 0, 0, 0, 0, 0])
loop_entry = { beats: 4 }
expected_trigger_slice = midi_value_to_range(127, loop_entry[:beats] - 1)
actual = sample_slice(loop_entry, 2, 1)
assert_equal((expected_trigger_slice + 1) % loop_entry[:beats], actual, "sample_slice advances from the triggered slice by the elapsed steps, wrapping at the loop length", failures)

##### Summary #####

puts ""
if failures.empty?
  puts "ALL TESTS PASSED"
  exit 0
else
  puts "#{failures.size} FAILURE(S):"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
