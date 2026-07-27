# Pane navigation performance harness

The pane harness drives the real packaged FoldWise application in Release
configuration. It is the fixed-Mac source of truth for action-to-first-meaningful-
frame navigation measurements; ordinary hosted XCTest timing remains a broad
regression signal only.

The supported release lane runs on the repository's dedicated
`foldwise-pane-reference` Apple-silicon runner. Do not substitute a hosted runner
or another Mac when accepting a baseline.

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
The packaged process holds a latency-critical activity to prevent App Nap and
keeps its foreground window ordered before each independent sample. The
performance-only window never activates FoldWise or requests key-window status,
so the harness can render while keyboard focus remains in another application.

Use a non-authoritative smoke run while changing the harness:

```sh
python3 scripts/run_pane_performance.py \
  --samples 1 \
  --skip-trace \
  --output-directory .context/pane-performance-smoke
```

`--no-build` reuses the existing packaged app. It is safe only when that bundle
was built from the source revision being measured.

An authoritative run exits unsuccessfully unless all of the following hold:

- the complete 2-profile × 6-destination × cold/warm matrix is present;
- every class has exactly 20 raw samples after its discarded warm-up;
- every raw sample is at most 100 ms;
- every route median is at most 20% slower than
  [`pane-performance-baselines.json`](pane-performance-baselines.json);
- all required trace components and application signposts were recorded; and
- the representative navigation intervals contain no Hitches, SwiftUI update
  groups, or potential hangs.

The absolute cap always wins: a slower accepted baseline never permits a sample
above 100 ms. A smoke run is deliberately non-authoritative and cannot update
the baseline.

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
After every first-meaningful-frame marker, the driver waits 350 ms outside the
measured interval. This returns control to the run loop, drains transient view
work, and lets the sidebar-selection spring settle before the next independent
journey. After each cold or warm journey, it also detaches the hosting
controller, releases the model, and waits another unmeasured interval so view
tasks from one sample cannot contaminate the next.

`FirstWindowOpening` is a separate signposted interval from loading the
profile's production JSONL History through settings-window construction to
Home's first meaningful frame. It is reported but is never judged against the
pane-navigation 100 ms target.

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

- `pane-performance-report.json`: the combined report, with an explicit
  `authoritative` flag;
- `raw/<profile>/result.json`: every raw duration plus median, observed p95,
  and worst for each route and visit class;
- each validated plan and its isolated profile data; and
- one SwiftUI trace for each fixture under `traces/`. Each trace retains SwiftUI
  update groups, Time Profiler samples, Hitches, potential hangs, and the
  `PaneNavigation` and `FirstWindowOpening` signposts from that same execution.

The combined report records the commit and app version, Mac model/chip/memory,
macOS and Xcode versions, power and thermal state, display configuration,
window size, Appearance, Reduce Motion, Increase Contrast, fixture identities,
route matrix, and calculated pre-/post-Sparkle medians, deltas, and ratios.

Run the authoritative 20-sample journey on the documented reference Mac with
its normal display configuration and stable power/thermal conditions. A trace
capture failure is evidence failure even if the duration matrix completed.
Passing `--skip-trace` always produces a non-authoritative report; without that
explicit smoke-run option, a trace failure fails the harness instead of
publishing a combined report.

## Fixed-Mac release lane

The `pane-performance` job in `release-validation.yml` runs for release-please
pull requests and manual release validation. It uses the fixed reference Mac,
does not retry a failure, runs the Python gate, then independently checks the
retained report against the same absolute and relative limits through XCTest.
Its artifact retains the report, raw samples, environment, plans, isolated
fixtures, trace exports, and trace bundles for 90 days.

Before accepting a new baseline:

1. Run the lane from a clean source commit under stable AC power and thermal
   conditions.
2. Confirm the report is `authoritative: true` and the artifact belongs to that
   exact commit.
3. Compare every route with `postSparkleComparison`; investigate rather than
   retry any duration, hitch, update-group, or hang violation.
4. Update `pane-performance-baselines.json` only from the accepted run, preserving
   the 20% maximum and the 100 ms absolute cap.

Ordinary PR CI continues to run projection/cancellation/bounded-work tests,
hosted catastrophic-regression checks, the Python policy tests, and coverage.
Those checks are deterministic safety nets; they do not claim hosted Debug
timing enforces the 100 ms Release budget.

## Causal trace review

The automated causal gate correlates trace timestamps with the app-reported
navigation intervals. Any overlapping Hitches row, SwiftUI update group, or
potential hang in a recorded sample fails the lane. Continuous main-thread
bursts over one 60 Hz frame are retained too. A burst is classified as explained
frame rendering only when at least 80% of its sampled weight is in SwiftUI
graph/layout/display-list, RenderBox, or Core Animation frames; every other burst
fails as an unexplained stall. Open the retained trace at the failed
app-reported epoch interval and explain the responsible invalidation or
main-thread work in the fix. A rerun is evidence for a changed implementation,
not a way to discard a bad sample.

`FirstWindowOpening` remains visible in the Logging trace and in each raw run,
but it is never evaluated against the pane-navigation duration baseline.
