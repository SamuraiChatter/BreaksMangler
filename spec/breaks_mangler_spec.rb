#!/usr/bin/env ruby
# Loads the real BreaksMangler.rb with the handful of Sonic Pi-only calls it
# needs stubbed out, then exercises the functions that don't depend on
# actual audio/MIDI I/O directly against the production source (no
# copy-pasted logic to drift out of sync).
#
# Sonic Pi's `live_loop`/`in_thread` blocks are stubbed to accept and
# discard their block entirely, so nothing inside them ever runs here -
# that's what keeps this a fast, side-effect-free process instead of an
# actual live-coding session. `Dir.home` is redirected to a throwaway temp
# directory before loading, since BreaksMangler.rb calls
# `resolve_samples_root`/`build_loops` eagerly at the top level and would
# otherwise touch the real developer machine's home directory.
#
# Run with: ruby spec/breaks_mangler_spec.rb

require "tmpdir"
require "fileutils"

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

load File.expand_path("../BreaksMangler.rb", __dir__)

##### build_loops / resolve_samples_root #####

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
end

Dir.mktmpdir("breaksmangler_spec_config") do |config_home|
  Dir.define_singleton_method(:home) { config_home }
  config_path = File.join(config_home, ".breaksmangler_samples_root")

  root = resolve_samples_root
  assert_equal(
    File.join(config_home, "Applications", "SonicPi", "Samples"),
    root,
    "resolve_samples_root seeds the config file with the default path on first run",
    failures
  )
  assert_equal(true, File.exist?(config_path), "resolve_samples_root creates the config file if missing", failures)

  File.write(config_path, "  /somewhere/else  \n")
  assert_equal(
    "/somewhere/else",
    resolve_samples_root,
    "resolve_samples_root reads and trims an existing config file instead of overwriting it",
    failures
  )
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
