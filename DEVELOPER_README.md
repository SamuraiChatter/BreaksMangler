# Developer Notes

Concise rationale behind the sample-loading design (spec in Jira ticket
BREAK-2, user-facing version in `README.md`).

## Decisions

- **Dynamic folder scan, not a hardcoded array.** Lets anyone drop files in
  without touching code. Trade-off: a bit more startup logic than a plain
  array literal.
- **Folder names carry beat length** (`N_beat/`, `N_bar/`, 4 beats/bar).
  Matches physical hardware/Eurorack sample-slot conventions users may
  already know.
- **Zero-padded numeric filename prefixes** (`01_`, `02_`...) for ordering.
  Avoids lexicographic-sort bugs (`1, 10, 2...`) and matches common
  hardware-sampler naming norms.
- **Global sort (prefix number, then folder beat count, then path) — not
  grouped by folder.** Independently-numbered folders interleave short and
  long loops by default, which suits a "mangler" more than strict
  short-then-long grouping. Users who want strict grouping just use
  non-overlapping number ranges per folder.
- **Samples root, port names and tempo via one self-creating settings
  file, `breaksmangler.yml`, beside the script** (BREAK-6), not
  `RUBY_PLATFORM` branching. Sonic Pi v5's `run_file` evaluates the file
  under its own path, so `__FILE__` finds the folder; a pasted buffer has no
  path and plays with every default. The file is ignored by git rather than
  tracked: a tracked file would show as modified once edited, could carry a
  personal path or port name into a commit, and would conflict on pull when
  a setting is added. Default samples folder (used to seed the file, and
  used directly if the setting is missing):
  `~/Applications/SonicPi/Samples` — matches the Pi's existing layout,
  mirrored under `$HOME` on any OS. The file replaced
  `~/.breaksmangler_samples_root`, which is no longer read or created.
- **YAML, read with `YAML.safe_load`.** Sonic Pi v5's bundled Ruby (4.0)
  loads `yaml` on Windows. A setting that is missing, misspelt or holds a
  value of the wrong kind falls back to its default with a message, one
  setting at a time; a file that will not parse falls back to every default.
- **Note and CC numbers stay in the script.** The settings file covers the
  same controller under a different port name, not a different controller.
- **Falls back to Sonic Pi's built-in demo loops (the old hardcoded
  `loops` array) when the scan is totally empty**, all-or-nothing — never
  partially blended with real user samples, so a partial-load mistake is
  never masked as "it's working." Empty individual folders are normal and
  don't trigger this.
- **Accepted formats: `.wav`, `.aiff`, `.flac`** — whatever Sonic Pi's
  `sample` natively supports (SuperCollider/libsndfile), nothing narrower.
- **No sample audio committed to git** — folder structure only, via
  `.gitkeep`. Actual `.wav`/`.aiff`/`.flac` files are gitignored.
- **One spec file (`spec/breaks_mangler_spec.rb`), not several.** It's a
  single script, so a single file that `load`s the real `BreaksMangler.rb`
  (with a handful of Sonic Pi-only calls stubbed out — see below) beats
  scattering copy-pasted logic across multiple throwaway test files that
  can silently drift from what's actually shipped.

## Running the tests

```
ruby spec/breaks_mangler_spec.rb
```

No gems, no Sonic Pi install required. It works by defining minimal stand-ins
for the small set of Sonic Pi-only calls that execute *eagerly* at the top
level of `BreaksMangler.rb` (`use_bpm`, `use_sched_ahead_time`, `define`, `get`/`set`, `ring`,
`midi_note_on`), then `load`s the real file — `live_loop`/`in_thread` blocks
are stubbed to discard their block entirely, so nothing inside them ever
runs. `Dir.home` is redirected to a throwaway temp directory first, and the
script is loaded from a copy in another, since
`load_settings`/`build_loops` run for real during that eager load.
Once loaded, the spec calls the pure-logic functions (`build_loops`,
`load_settings`, `midi_value_to_range`, `determine_behavior`,
`sample_slice`) directly with controlled inputs — this is the actual
production code, not a copy, so there's nothing to keep in sync by hand.

Functions that call `sample`/`with_fx`/MIDI I/O directly (`play_sample`,
`play_slice`) aren't covered this way — they need ears or Sonic Pi's own log
pane, not an assertion.

## PC test directory structure

Create this next to `BreaksMangler.rb` for local testing (mirrors the Pi's
`Applications/SonicPi/Samples` tree one level down):

```
BreaksMangler/
  BreaksMangler.rb
  Samples/
    1_beat/
    2_beat/
    3_beat/
    4_beat/
    1_bar/
    2_bar/
    3_bar/
    4_bar/
    8_bar/
```

Drop a couple of test `.wav` files into 2-3 of these folders (leaving the
rest empty is fine and expected — see decisions above). Point your local
settings at this tree by setting `samples_folder` in `breaksmangler.yml`
to the full path of this `Samples` folder, since it won't match the
`~/Applications/SonicPi/Samples` default unless you happen to be testing
from that exact location.

To exercise the empty-scan fallback path, temporarily point `samples_folder`
at a folder with no matching subfolders (or an empty `Samples/`) and confirm
the built-in demo loops play with the expected warning message.

## Not yet verified

`spec/breaks_mangler_spec.rb` runs the scan/sort/fallback logic
(`build_loops`) against a real temp directory tree —
numeric vs. lexicographic sort, cross-folder interleaving, extension
filtering, unmatched-folder skipping, no-prefix warning, and the empty-scan
demo-bank fallback all pass there, against the actual production code. What
that testing **cannot** confirm is behavior inside the actual Sonic Pi
runtime, specifically:

- Whether `File.write`, `File.read`, `Dir.home`, and `Dir.glob` run
  unrestricted inside a Sonic Pi buffer on the target Sonic Pi
  version/platform (expected to work, since Sonic Pi doesn't sandbox
  standard Ruby file I/O, but this hasn't been run inside Sonic Pi itself).
- Whether `breaksmangler.yml` actually gets created on first run, in the
  expected location, on the Pi (BREAK-11).
- Whether `sample` correctly loads a full filesystem path string for each
  of the accepted formats (`.wav`, `.wave`, `.aiff`, `.aif`, `.flac`) the
  same way it loads built-in sample symbols today.
- End-to-end knob behavior with a populated `Samples/` tree — i.e. that the
  computed `loops` array actually drives `play_slice` the way it did with
  the old static array.

Load `BreaksMangler.rb` in Sonic Pi and run through the PC test tree above
before considering this done.
