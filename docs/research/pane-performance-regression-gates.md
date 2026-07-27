# Apple tooling for a non-flaky pane-performance regression gate

Research answer for
[Design a non-flaky pane-performance regression gate](https://github.com/hadrysm/foldwise-voice/issues/291),
researched on 2026-07-25 against current Apple documentation and videos, plus
two clearly linked archived Apple sources for the still-relevant
same-configuration baseline rule. The recommendations below distinguish
Apple's documented behavior from conclusions specific to FoldWise's
measurement contract.

## Executive answer

No single test should carry all three jobs of protecting the 100 ms outcome,
finding its cause, and proving smooth animation.

Use a layered gate:

1. **Every PR, on existing CI:** deterministic tests protect the amount of work
   on the navigation critical path and the empty/10,000-session fixture
   semantics. A Release timing run may report trends, but timing from
   `macos-latest` must not be the authority for the exact 100 ms threshold.
2. **Automated reference-Mac gate:** a separate Release UI-performance harness
   drives the real app and measures a custom pane-navigation signpost from the
   navigation action to the destination's agreed **first meaningful frame**.
   After one discarded harness warm-up, it records 20 comparable samples for
   each route/profile/visit class. The worst sample must be at most 100 ms, and
   a separate XCTest regression baseline permits no more than 20% degradation
   without ever waiving that absolute cap. On the pinned Xcode 26 reference
   lane, `XCTHitchMetric(application:)` must also report zero hitches.
3. **Manual release trace:** record the same journeys with the Xcode 26 SwiftUI
   Instruments template, Time Profiler, Hitches, and the app's signposts. This
   is the causal and animation-quality gate: no material main-thread stall,
   unexpected SwiftUI update fan-out, or navigation hitch may hide behind a
   passing duration.

This shape follows Apple's own separation of performance tests from ordinary
tests. Apple says accurate performance measurement needs a Release
configuration with the debugger, code coverage, and runtime sanitization
disabled. XCTest can compare metrics with baselines, while Instruments is the
tool for tracing the work behind those measurements
([Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests),
[Customizing build schemes](https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project)).

The reference machine is not merely a convenience. Apple recommends recording
the hardware and software configuration and measuring against the same
configuration, and XCTest historically stores baselines per device
configuration because processor, memory, and other hardware differences affect
results
([Establish Your Baseline Metrics](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/PerformanceOverview/DevelopingForPerf/DevelopingForPerf.html),
[Writing Test Classes and Methods](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/04-writing_tests.html)).
Therefore, a floating GitHub-hosted Mac can find catastrophic regressions or
provide trend data, but an exact 100 ms failure there would be a flaky claim
about FoldWise's documented maintainer-Mac target.

## What XCTest can and cannot establish

Apple's current performance-test API supplies clock, CPU, memory, storage,
signpost, launch, and hitch metrics. `XCTClockMetric` records monotonic elapsed
time, including time when the CPU is idle or another process runs, while
`XCTOSSignpostMetric` records only the elapsed time between the matching begin
and end of a named signposted interval
([Performance Tests](https://developer.apple.com/documentation/xctest/performance-tests),
[`XCTClockMetric`](https://developer.apple.com/documentation/xctest/xctclockmetric),
[`XCTOSSignpostMetric`](https://developer.apple.com/documentation/xctest/xctossignpostmetric)).

That distinction makes the named signpost the better primary metric for pane
navigation: the UI test's tap and polling overhead stays outside the product
interval. A clock metric remains useful around the entire journey as a
secondary sanity check.

XCTest performance baselines are regression baselines, not product
requirements. Xcode compares the recorded mean with a baseline and maximum
standard deviation, failing when the result is worse than the permitted
tolerance
([Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)).
A baseline of 62 ms plus a tolerance does not, by itself, express “every
required pane change is within 100 ms.” The reference-Mac harness therefore
uses two independent pass/fail checks:

- an **absolute acceptance check**: every one of the 20 recorded comparable
  samples must be at most 100 ms; and
- an **XCTest regression check**: the accepted hardware-specific baseline may
  allow no more than 20% degradation, while remaining subordinate to the
  absolute cap.

Record the samples as an attached machine-readable artifact and report at least
median, p95, and worst. The worst is the absolute pass/fail statistic because
the destination says every pane change must meet the target; median and p95
remain essential diagnostics. XCTest's mean and baseline catch trend movement
but cannot silently substitute for or waive the 100 ms worst-sample promise.

The 20% regression allowance is a ceiling, not a default amount of slack. Set a
tighter tolerance after the fixed lane establishes stable variance. For
example, a 70 ms accepted baseline with 20% tolerance fails above 84 ms even
though the product cap is 100 ms; a 90 ms baseline can never use 20% to permit
108 ms because the absolute gate fails first.

### Warm-up and iteration isolation

`XCTMeasureOptions.iterationCount` runs the block one extra time and discards
that first result specifically to reduce cache and other first-run variance
([`iterationCount`](https://developer.apple.com/documentation/xctest/xctmeasureoptions/iterationcount)).
Apple also demonstrates resetting application state outside the measured
portion between UI-performance iterations
([Eliminate animation hitches with XCTest](https://developer.apple.com/videos/play/wwdc2020/10077/)).

For FoldWise:

- Use one discarded harness warm-up plus **20 recorded iterations** for each
  required route/profile/visit class. Twenty makes p95 an observed sample
  rather than an interpolation between a very small number of runs.
- A **cold first visit** still needs a fresh destination lifetime for every
  measured iteration. Discarding the harness's first attempt must not turn the
  remaining “cold” attempts into warm revisits.
- A **warm revisit** needs the same destination priming sequence before each
  measurement, outside the measured interval.
- Restore the same source pane, window size, focus, and fixture before each
  iteration. Never swipe or navigate repeatedly into progressively different
  content.
- Generate and load the empty or 10,000-session fixture before measurement.
  Fixture construction is setup cost, not pane latency.

## The signpost contract

Use the current `OSSignposter` API rather than adding new calls to the legacy
`os_signpost` symbols. Apple documents:

- signposted intervals for duration;
- events for single points of interest;
- unique IDs to distinguish overlapping invocations with the same name; and
- Instruments' `os_signposts` instrument for a timeline grouped by subsystem
  and category
  ([Recording Performance Data](https://developer.apple.com/documentation/os/recording-performance-data),
  [`OSSignposter`](https://developer.apple.com/documentation/os/ossignposter)).

Adopt one stable subsystem/category and one stable top-level interval name, for
example `PaneNavigation`. Use the interval ID to associate metadata and
intermediate events:

1. begin at the accepted navigation action;
2. emit destination construction/invalidation and projection-ready events as
   applicable;
3. end at the destination's agreed first meaningful rendered frame.

The interval name, subsystem, and category must be static and shared with the
test's `XCTOSSignpostMetric(subsystem:category:name:)`. Apple notes that the
metric records no result when there is no matching begin/end pair, so a missing
frame marker must fail the harness rather than becoming a suspiciously fast
sample
([`XCTOSSignpostMetric.init(subsystem:category:name:)`](https://developer.apple.com/documentation/xctest/xctossignpostmetric/init%28subsystem%3Acategory%3Aname%3A%29)).

“First meaningful frame” is a FoldWise product boundary, not something
`onAppear`, an accessibility element lookup, or XCTest can infer. The
implementation ticket must define it pane by pane and end the interval only
from the rendering seam that proves that frame is committed. Ending in
`View.body` or `onAppear` would measure construction/appearance notification,
not the stated visible outcome.

For the navigation animation, use
`OSSignposter.beginAnimationInterval` around the animation interval if the
chosen seam can represent it. Apple documents animation intervals on the
current signposter API, and its XCTest guidance shows that an animation
signpost metric yields duration, frame count/rate, hitch count, total hitch
time, and hitch ratio
([`beginAnimationInterval`](https://developer.apple.com/documentation/os/ossignposter/beginanimationinterval%28_%3Aid%3A%29),
[Eliminate animation hitches with XCTest](https://developer.apple.com/videos/play/wwdc2020/10077/)).

Do not use `XCTOSSignpostMetric.navigationTransitionMetric` for this macOS
sidebar. In the Apple Xcode 26.2 macOS SDK, that predefined metric is explicitly
unavailable on macOS; a named custom interval is also a better match for
FoldWise's product-defined frame boundary. The current public API remains
documented at
[`navigationTransitionMetric`](https://developer.apple.com/documentation/xctest/xctossignpostmetric/navigationtransitionmetric).

## Exact gate matrix

| Gate | Fixture and journey | Metrics | Failure authority | Where it runs |
| --- | --- | --- | --- | --- |
| Deterministic critical-path tests | Empty and deterministic 10,000-session data; pure projection/query owners and view policies used by navigation | Result equality plus work/collection bounds that express the intended complexity | Blocks every PR | Existing SwiftPM XCTest/coverage job |
| Hosted integration smoke | Exact supported window size; pane built with the same model and fixture; cold construction and warm invalidation paths kept separate | Correct meaningful content, bounded realized rows/work, and broad catastrophic-time guard only if needed | Blocks every PR; no claim that hosted layout proves the user's 100 ms frame | Existing XCTest target |
| Release trend run | Same deterministic projection/hosted cases, compiled optimized, coverage and diagnostics off | `XCTClockMetric` or named signpost duration; attach raw samples | Report-only on floating runner, or blocks only against a deliberately broad catastrophe ceiling | Separate `macos-latest` job |
| Real navigation performance | Isolated release app; empty and 10,000-session profiles; required cold and warm routes after the window is visible; one discarded warm-up plus 20 recorded comparable samples per class | `XCTOSSignpostMetric` duration; worst ≤100 ms; median/p95/worst artifact; separate XCTest baseline with ≤20% tolerance | Blocks merge/release on the documented reference Mac; baseline tolerance never waives the absolute cap | Separate UI-performance scheme/test plan on a fixed self-hosted or maintainer Mac |
| Automated hitch check | Same real navigation journeys with ordinary motion enabled | `XCTHitchMetric(application:)` and/or custom animation-signpost hitch count, total time, and ratio | Zero hitches required on the fixed lane; any nonzero result fails and is confirmed in the saved trace, not retried away | Xcode 26 UI-performance target on a supported OS |
| Causal release trace | Representative violating/high-risk routes in both fixtures, including first-window work as a separate interval | SwiftUI Update Groups and causes, Long View/Platform/Other Updates, Hitches, Time Profiler, and app signposts | Human pass required: no unexplained fan-out, main-thread stall, or navigation hitch | Instruments 26 on the reference Mac |

The deterministic tests are deliberately not “microbenchmark coverage” of
every helper. They should pin only work proven to be on the pane path: for
example, how much History data a projection scans, how many row presentations a
lazy path realizes, and whether an unrelated publication rebuilds the active
pane. These tests remain useful across hardware because they protect the cause,
while the real navigation harness protects the visible outcome.

### UI-harness requirement

The repository currently has a SwiftPM unit-test target, not a macOS UI-testing
bundle. Apple's `XCUIApplication` performance flow and
`XCTHitchMetric(application:)` operate from a UI test targeting an application
([What’s new in Xcode 26](https://developer.apple.com/videos/play/wwdc2025/247/),
[`XCTHitchMetric`](https://developer.apple.com/documentation/xctest/xcthitchmetric)).
If automated real-app timing is selected, add a minimal dedicated macOS
UI-performance harness rather than pretending an `NSHostingView` unit test is
the shipped app.

Xcode 26 introduced `XCTHitchMetric`. The Apple headers installed with this
audit's Xcode 26.2 make the constraint concrete:
`XCTMetric.h` marks it `API_AVAILABLE(macos(16.0), ...)`, while
`XCTMetric+UIAutomation.h` supplies
`initWithApplication:(XCUIApplication *)`. In other words, it is both newer
than FoldWise's macOS 14 deployment target and UI-automation-only. The hitch
test must run only on a reference lane whose OS supports the API, or be
availability-guarded rather than becoming a new app deployment requirement.
Older supported systems remain covered by the manual Instruments trace and
ordinary behavior tests.

## Current repository constraints

FoldWise is a pure SwiftPM package. It has no checked-in `.xcodeproj`,
`.xctestplan`, or XCUITest target, so the existing test target can host AppKit
and SwiftUI in-process but cannot drive the built app through
`XCUIApplication`. The current GitHub Actions test job runs `macos-latest` and
`./scripts/coverage.sh`; that script invokes the default Debug
`swift test --enable-code-coverage`
([CI workflow](../../.github/workflows/ci.yml),
[`coverage.sh`](../../scripts/coverage.sh)).

There is already a useful catastrophic-regression precedent:
`HistoryPanePerfTests` hosts the History pane, measures with
`ContinuousClock`, and allows 750 ms for initial layout and 250 ms for a
republish layout
([`HistoryPanePerfTests.swift`](../../Tests/FoldWiseVoiceKitTests/Features/History/HistoryPanePerfTests.swift)).
During this ticket's audit, repeated warm invocations varied by roughly 2×
without a code change. That does not invalidate the test's broad protection
against restoring a five-second eager layout, but it is direct evidence that
the same host/process arrangement should not be tightened into a 100 ms product
gate.

## Release configuration and CI separation

Apple explicitly recommends all of the following for performance tests:

- a separate performance-test scheme;
- Release build configuration;
- debugger disabled;
- automatic screenshots and code coverage disabled; and
- runtime sanitization, runtime API checks, and memory diagnostics disabled
  ([Eliminate animation hitches with XCTest](https://developer.apple.com/videos/play/wwdc2020/10077/),
  [Writing and running performance tests](https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests)).

That directly conflicts with using FoldWise's current
`./scripts/coverage.sh` invocation as the timing authority: the script runs
Debug `swift test --enable-code-coverage`, and CI uses GitHub's moving
`macos-latest` image. Keep functional/complexity coverage there, but run
performance tests in a separate optimized invocation with no coverage.
Production signpost branches still need ordinary deterministic tests to satisfy
the repository's changed-line coverage policy; the timed execution itself does
not.

The reference run should record, alongside its samples:

- commit and app version;
- Mac model/chip/memory;
- macOS and Xcode build;
- power source and thermal state;
- display and refresh-rate configuration;
- window size and Appearance/Reduce Motion settings; and
- fixture identity and the exact cold/warm route list.

If an exact 100 ms result is required as a GitHub status check, use a fixed
self-hosted Mac with that recorded configuration. Do not tighten thresholds on
`macos-latest` until the provider happens to resemble the maintainer's Mac.

## Manual Instruments release gate

Apple's current SwiftUI template combines a SwiftUI track with Time Profiler
and Hitches. The SwiftUI track shows Update Groups, long view-body updates,
long platform-view updates, other long framework work such as geometry/text
layout, and a cause-and-effect graph for frequent updates. Apple recommends
using Time Profiler on the same selected range to identify the executing code
([Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance),
[Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)).

For each release candidate:

1. Profile the optimized candidate, not an attached Debug build.
2. Add the app's signposts to the SwiftUI template.
3. Record the high-risk cold and warm routes for empty and 10,000-session
   profiles; record first-window opening separately.
4. Select each `PaneNavigation` interval and inspect SwiftUI update groups,
   their cause graph, main-thread samples, and overlapping hitches.
5. Save the trace plus the environment and summary table as release evidence.

Apple defines a hitch as a frame that appears later than expected and explains
why a few milliseconds can matter during continuous motion even when a discrete
interaction remains below 100 ms
([Understanding hitches in your app](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app),
[Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/)).
Consequently, passing the pane-duration gate does not waive a hitch found in
the selection spring. The fixed-lane criterion is zero measured navigation
hitches. A nonzero result fails the run and requires review of the saved trace.
Do not automatically retry or average it away. If the trace proves the whole
run was invalid because the documented environment was not met, invalidate and
repeat the complete run with that reason recorded rather than selectively
rerunning the failed sample.

## Attractive options to reject

| Option | Why reject it |
| --- | --- |
| Fail PRs at 100 ms using `ContinuousClock` on `macos-latest` | Clock time includes scheduling by other processes, and the runner's hardware/image is not the documented target. Apple calls for stable recorded hardware/software and device-specific baselines. |
| Reuse the coverage job for timing | Apple says performance tests should use Release with code coverage, debugger, sanitizers, and diagnostics disabled. |
| Keep only projection microbenchmarks | They can pass while destination construction, SwiftUI invalidation, layout, commit, or animation still misses the visible outcome. |
| Keep only one end-to-end UI timer | It can identify a regression but cannot explain whether projection, observation, layout, AppKit/SwiftUI bridging, or rendering caused it. |
| End the interval in `body` or `onAppear` | Neither proves the meaningful pixels reached a rendered frame. This silently changes the product metric. |
| Mix cold and warm visits in one `measure` block | XCTest aggregates iterations; mixed lifecycle classes make the mean and baseline uninterpretable. |
| Let each iteration continue from the previous UI state | Apple specifically recommends resetting application state outside measurement so iterations exercise comparable content. |
| Treat FPS as the navigation-animation gate | Apple explains that FPS is skewed by resting time and intentionally lower frame rates; hitch time/ratio directly describes late frames. |
| Require zero automated hitches on a floating CI host | A compositor/scheduling outlier becomes a flaky failure. Zero remains the product goal; enforce the stable baseline on the fixed Mac and confirm any event in Instruments. |
| Use screenshots or UI-test video timestamps as the 100 ms clock | They are useful failure evidence, not the app-owned semantic interval or frame-deadline metric. |

## Decision carried forward

The 100 ms outcome should remain visible in every layer:

- deterministic tests protect the amount of work required to make it possible;
- the fixed-Mac UI harness enforces the actual action-to-meaningful-frame
  interval;
- hitch metrics protect the navigation animation; and
- Instruments proves why the candidate passes and catches main-thread or
  invalidation regressions that a duration alone can conceal.

The key implementation prerequisite is a pane-by-pane definition of **first
meaningful frame**. Once that boundary exists, Apple's current signpost, XCTest,
and SwiftUI Instruments tools fit the regression strategy without pretending
that variable CI hardware is the maintainer's Mac.
