# FoldWise pane latency baseline

Issue: [Measure cold and warm FoldWise pane latency](https://github.com/hadrysm/foldwise-voice/issues/292)  
Measured: 2026-07-25  
Source: `b1f8502db2a4691aeab361f4eceb64778829d116` plus temporary, uncommitted probes  
Build: SwiftPM release (`swift test -c release`)  
Reference Mac: MacBook Pro 16-inch 2021 (`MacBookPro18,1`), Apple M1 Pro,
16 GiB RAM, macOS 26.5 (25F71), Xcode 26.2 (17C52), Swift 6.2.3

## Result

The 100 ms pane-change target is violated by:

- Stats for both profiles, cold and warm.
- Home and History with 10,000 saved Dictation sessions, cold and warm.
- Settings with 10,000 saved Dictation sessions at p95, cold and warm.
- One empty-profile cold History outlier (211 ms), despite a 71 ms p95.

Modes and Models remain below 100 ms in every observed sample.

The demonstrated primary cause is synchronous main-thread work:

- Home scans all 10,000 entries for usage statistics before it draws.
- History filters, sorts, groups, and constructs presentation for all 10,000
  entries before its lazy visible-row tree can help.
- Stats scans all 10,000 entries and formats its monthly/lifetime projection,
  then pays a substantial fixed calendar/layout cost.
- Switching the `destination` branch recreates the pane-local projection caches,
  so a warm revisit is not materially cheaper than a cold visit.

The 0.28-second sidebar spring does not cause the latency. The focused
Animation Hitches recording classifies the stalls as expensive application
updates.

## Measurement contract and limitations

The deterministic benchmark hosts the real `SettingsView` in a 980×720
`NSWindow`. It measures a release build from direct `SettingsModel.pane`
mutation—the state change performed by the navigation action—to the
destination's `NSView.draw(_:)` callback. Home, History, and Stats do not
install the draw marker until their initial projection has completed. Each
cell below contains 20 independent samples.

“Cold” means a first visit in a fresh hosted `SettingsView`. “Warm” means a
revisit after returning to the source pane in the same host. Home is measured
from Settings; the other destinations are measured from Home.

`draw(_:)` is an app-side draw-completion proxy, not proof that the frame
reached the display. Apple separates SwiftUI updates, rendering, and
presentation. The focused Animation Hitches trace therefore supplies the
authoritative displayed-frame/hitch evidence. Apple also recommends release
profiling because Debug and Release optimization differ.

The 10,000-session fixture uses fixed timestamps, stable UUIDs, seeded text
lengths, and a mix of polished/flagged entries. It exists only in memory for
pane transitions and in a UUID-named temporary directory for first-window
JSONL loading. It never reads or overwrites the maintainer's live FoldWise
files.

Primary Apple references:

- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)
- [Analyzing CPU profiles with call tree views](https://developer.apple.com/documentation/xcode/analyzing-cpu-profiles-with-call-tree-views)
- [Recording performance data with Points of Interest](https://developer.apple.com/documentation/os/recording-performance-data)
- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)

## Pane baseline

Times are milliseconds, shown as `median / p95 / worst`. “Projection” is the
median synchronous projection time included in the action-to-draw interval.

### Empty profile

| Destination | Cold action→draw | Cold projection | Warm action→draw | Warm projection |
| --- | ---: | ---: | ---: | ---: |
| Home | 25.606 / 42.761 / 46.611 | 0.243 | 25.602 / 33.916 / 60.233 | 0.235 |
| Modes | 23.817 / 30.522 / 36.697 | — | 21.700 / 23.831 / 24.296 | — |
| Models | 34.950 / 40.558 / 59.469 | — | 33.933 / 36.660 / 38.897 | — |
| History | 45.113 / 71.385 / 211.171 | 0.049 | 44.714 / 63.645 / 69.904 | 0.045 |
| Stats | **149.477 / 167.333 / 232.875** | 6.347 | **149.484 / 152.360 / 162.158** | 6.325 |
| Settings | 56.639 / 64.414 / 73.593 | — | 55.005 / 61.592 / 63.758 | — |

Empty Stats demonstrates a fixed view-tree/calendar cost: roughly 143 ms of
its median occurs after its six-millisecond projection.

### 10,000-session profile

| Destination | Cold action→draw | Cold projection | Warm action→draw | Warm projection |
| --- | ---: | ---: | ---: | ---: |
| Home | **257.702 / 291.977 / 465.017** | 182.068 | **255.074 / 269.767 / 270.480** | 180.831 |
| Modes | 31.215 / 33.630 / 36.354 | — | 31.458 / 33.355 / 34.043 | — |
| Models | 42.553 / 53.650 / 75.859 | — | 41.742 / 44.798 / 46.060 | — |
| History | **343.608 / 359.798 / 362.653** | 222.957 | **339.932 / 350.072 / 363.991** | 221.824 |
| Stats | **357.928 / 416.465 / 421.731** | 190.026 | **355.071 / 372.908 / 377.018** | 190.196 |
| Settings | 74.305 / **190.634** / 309.106 | — | 68.810 / **108.970** / 247.814 | — |

The history-backed destinations scale while Modes and Models do not. Cold and
warm Home/History/Stats are effectively identical, demonstrating that current
pane lifetime does not preserve useful projection warmth.

## Instruments evidence

A focused release recording used Settings as the cheap source pane and
navigated to 10,000-session Stats three times cold and three times warm. The
draw proxy measured 374 ms cold and 420 ms warm at the median under recording
overhead.

Animation Hitches recorded six displayed-frame hitches—one for each measured
transition—with durations:

```text
700 ms, 58 ms, 342 ms, 75 ms, 400 ms, 408 ms
```

The matching application-update intervals were:

```text
708 ms, 547 ms, 351 ms, 86 ms, 447 ms, 423 ms
```

The instrument labeled the largest frames “Potentially expensive app
update(s).” It reported no separate potential-hang record and no evidence that
GPU work was the limiting stage.

The focused Time Profiler export contained 620 sampled backtraces. Counts below
are inclusive and overlap when one stack contains several frames:

| Stack category | Sampled backtraces |
| --- | ---: |
| SwiftUI / AttributeGraph / layout | 366 |
| `StatsPane` | 222 |
| `StatsProjection` | 213 |
| `UsageStatsAggregator` | 207 |
| `SettingsView` | 20 |

This establishes a mixed bottleneck: roughly two hundred samples occur in the
10,000-session Stats projection/aggregation path, while the larger SwiftUI and
layout count explains the fixed empty-profile Stats cost.

The Xcode 26 SwiftUI template did not emit SwiftUI-specific lanes for the
SwiftPM `xctest` host (“Trace file had no SwiftUI data”). That limitation is
recorded rather than treating an empty lane as proof of no SwiftUI work.
Animation Hitches and Time Profiler remained populated.

## First-window opening

The first-window budget is reported separately and is not judged against the
100 ms pane-change target. Each result contains 20 release samples. Times are
milliseconds; the first three values are `median / p95 / worst`, while the
stage values are medians.

| Profile | Action→draw | Window construction | Preferences | Accessibility check | History load + publish | Model refresh kickoff | Update check kickoff | Activate + order front |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Empty | 108.885 / 114.467 / 246.516 | 66.151 | 0.191 | 0.006 | 0.115 | 0.007 | 0.017 | 9.745 |
| 10,000 | 283.129 / 291.159 / 297.426 | 64.397 | 0.183 | 0.006 | **56.114** | 0.015 | 0.028 | 9.433 |

The synchronous JSONL load is a demonstrated 10,000-session opening cost, but
it is not the dominant pane-navigation cost. Model discovery and update
checking only schedule asynchronous work here; their synchronous kickoff is
negligible. Window construction is the largest fixed opening stage. Stage
medians are not additive because SwiftUI update and layout work can be
scheduled across the surrounding calls.

## Demonstrated bottlenecks vs remaining hypotheses

Demonstrated:

1. Home, History, and Stats synchronously perform collection-size-dependent
   work on the main thread before meaningful content draws.
2. Stats has a separate, large fixed SwiftUI/calendar construction and layout
   cost even with no History.
3. Destination-local state and caches do not make revisits warm; the switch
   branch recreates them.
4. The resulting visible failures are application-update hitches, not merely a
   slow observer that leaves animation frames smooth.
5. First-window JSONL decode/publish is material at 10,000 sessions; model and
   update-check kickoff are not.

Still hypotheses for fix design:

- Moving immutable projections off the main actor may reduce the O(n) portion,
  but it still needs a stale-result/invalidation contract.
- Owning projections above the destination switch may turn revisits warm, but
  the correct lifetime and invalidation seam is not yet decided.
- Retaining pane instances may preserve scroll/search/focus state, but that is
  a behavior decision rather than a measured performance conclusion.
- Lazy History rows already prevent eager row layout; lazy projection or
  indexed storage may be needed to avoid constructing every row presentation.
- The 56 ms first-window JSONL cost may justify separate opening work, but it
  does not by itself require a storage migration for the pane-change target.

## Reproduction

The temporary benchmark command was:

```sh
FOLDWISE_PANE_BENCHMARK=1 \
FOLDWISE_BENCHMARK_OUTPUT=.context/wayfinder-292-pane-samples.json \
swift test -c release \
  --filter PaneNavigationBenchmarkTests/testPaneNavigationFirstMeaningfulFrames
```

The first-window benchmark used the same release configuration and wrote raw
samples to `.context/wayfinder-292-first-window-samples.json`.

The focused displayed-frame recording was:

```sh
xcrun xctrace record \
  --template 'Animation Hitches' \
  --env FOLDWISE_PANE_BENCHMARK=1 \
  --env FOLDWISE_BENCHMARK_ITERATIONS=3 \
  --env FOLDWISE_BENCHMARK_PROFILE=10k \
  --env FOLDWISE_BENCHMARK_SOURCE=Settings \
  --env FOLDWISE_BENCHMARK_DESTINATION=Stats \
  --launch -- /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest FoldWiseVoiceKitTests.PaneNavigationBenchmarkTests/testPaneNavigationFirstMeaningfulFrames \
  .build/arm64-apple-macosx/release/FoldWiseVoicePackageTests.xctest
```

Raw JSON, logs, exported XML, and `.trace` bundles remain under `.context/` in
this workspace. Temporary product probes and benchmark tests are intentionally
not part of the proposed implementation.
