# Pane navigation performance harness

The pane harness drives the real packaged FoldWise application in Release
configuration. It is the fixed-Mac source of truth for action-to-first-meaningful-
frame navigation measurements; ordinary hosted XCTest timing remains a broad
regression signal only.

## Run

From the repository root:

```sh
python3 scripts/run_pane_performance.py
```

The command builds `dist/bundle/FoldWise Voice.app` with SwiftPM's Release
configuration and launches its executable without a debugger, coverage,
screenshots, sanitizers, or runtime diagnostics. It measures both deterministic
profiles, all six destinations, and cold and warm visit classes. Every class
discards one harness warm-up and records 20 samples.

Use a non-authoritative smoke run while changing the harness:

```sh
python3 scripts/run_pane_performance.py \
  --samples 1 \
  --skip-trace \
  --output-directory .context/pane-performance-smoke
```

`--no-build` reuses the existing packaged app. It is safe only when that bundle
was built from the source revision being measured.

## Measurement contract

The production `PaneNavigation` signpost begins when `SettingsModel.selectPane`
accepts a different destination. It ends from a one-point AppKit draw marker
only after the destination has prepared its current semantic content:

- Home ends after usage statistics and recent Dictation-session presentation
  are current.
- History ends after the current search/filter/grouping projection is ready.
- Stats ends after its current monthly activity projection is ready.
- Modes, Models, and Settings end when their current value-fed destination
  draws.

Home uses Settings as its source route. Every other destination uses Home. A
cold sample installs a fresh `SettingsView` before navigating. A warm sample
primes the destination, returns to the source in the same host, and then
measures the revisit. This preserves disposable destination views and allows
later controller-retained projection work to become observably warm.

`FirstWindowOpening` is a separate signposted interval from settings-window
construction to Home's first meaningful frame. It is reported but is never
judged against the pane-navigation 100 ms target.

## Profile isolation

The harness activates only when an explicit, validated plan is supplied through
`FOLDWISE_PANE_PERFORMANCE_PLAN`. The launcher creates a dedicated directory for
each run and passes file URLs for its configuration, History, and output. The
performance application path does not construct the dictation Pipeline, request
permissions, install hotkeys, load ASR models, contact Ollama or Sparkle, or
resolve the normal Application Support History location.

The fixtures are versioned as `pane-empty-v1` and `pane-10000-v1`. The large
fixture has stable UUIDs, timestamps, text, Polish status, flags, source apps,
word/duration values, and Mode attribution. Its JSONL is read through the
production `JSONLHistoryStore`.

## Evidence

The output directory contains:

- `pane-performance-report.json`: the combined authoritative report;
- `raw/<profile>/result.json`: every raw duration plus median, observed p95,
  and worst for each route and visit class;
- each validated plan and its isolated profile data; and
- `hitches/stats-10000.trace`: an Animation Hitches recording of representative
  cold and warm 10,000-session Stats journeys, plus the trace command's output.

The combined report records the commit and app version, Mac model/chip/memory,
macOS and Xcode versions, power and thermal state, display configuration,
window size, Appearance, Reduce Motion, Increase Contrast, fixture identities,
route matrix, and the pre-Sparkle comparison values.

Run the authoritative 20-sample journey on the documented reference Mac with
its normal display configuration and stable power/thermal conditions. A trace
capture failure is evidence failure even if the duration matrix completed.
