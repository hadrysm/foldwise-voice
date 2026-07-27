# FoldWise pane latency after Sparkle

Issue: [Rebaseline FoldWise pane navigation after Sparkle](https://github.com/hadrysm/foldwise-voice/issues/319)  
Measured: 2026-07-26  
Source: `c939d8d2ff94732fa547fe68bff83b1d672dccda`  
Harness: [`docs/pane-performance-harness.md`](../pane-performance-harness.md)  
Result: authoritative

## Environment

- Packaged SwiftPM Release app, without debugger, coverage, screenshots,
  sanitizers, or runtime diagnostics.
- MacBook Pro 16-inch 2021 (`MacBookPro18,1`), Apple M1 Pro, 16 GiB RAM.
- macOS 26.5 (25F71), Xcode 26.2 (17C52).
- AC power, no recorded thermal or performance warning.
- Dark Appearance, Reduce Motion off, Increase Contrast off.
- 980×720 foreground key window with App Nap disabled for the measurement
  process.
- Deterministic `pane-empty-v1` and `pane-10000-v1` fixtures, isolated from
  live Application Support data.

Every class discarded one warm-up and retained 20 samples. Times below are
milliseconds, shown as `median / observed p95 / worst`.

## Empty profile

| Destination | Cold action→frame | Warm action→frame |
| --- | ---: | ---: |
| Home | 34.794 / 44.577 / 52.991 | 31.968 / 44.761 / 45.076 |
| Modes | **131.608 / 140.571 / 141.412** | **131.838 / 142.134 / 142.305** |
| Models | 42.331 / 51.679 / 52.925 | 43.188 / 49.261 / 51.593 |
| History | 56.989 / 66.101 / 70.481 | 53.930 / 62.347 / 63.590 |
| Stats | **194.418 / 202.609 / 204.083** | **182.433 / 192.811 / 210.003** |
| Settings | 78.996 / 86.060 / 88.163 | 73.913 / 83.178 / 85.496 |

## 10,000-session profile

| Destination | Cold action→frame | Warm action→frame |
| --- | ---: | ---: |
| Home | **289.577 / 310.858 / 316.445** | **288.551 / 298.307 / 303.679** |
| Modes | **140.686 / 149.314 / 150.263** | **143.169 / 147.907 / 148.013** |
| Models | 59.107 / 66.693 / 66.877 | 51.874 / 58.260 / 77.483 |
| History | **386.664 / 395.025 / 415.568** | **376.112 / 401.611 / 416.146** |
| Stats | **453.896 / 471.020 / 480.785** | **411.628 / 424.172 / 431.492** |
| Settings | 95.897 / **108.694** / 108.821 | 83.766 / 94.850 / 95.716 |

Bold values violate the 100 ms pane-navigation target. Models is the only
destination below 100 ms in every measured class. Home and History remain
collection-size dependent. Stats retains a fixed empty-profile cost and grows
further with 10,000 sessions.

## Pre-/post-Sparkle comparison

The combined machine-readable report calculates these cold-median comparisons
against [`foldwise-pane-latency-baseline.md`](foldwise-pane-latency-baseline.md):

| Profile | Destination | Before | After | Delta | Ratio |
| --- | --- | ---: | ---: | ---: | ---: |
| Empty | Stats | 149.477 | 194.418 | +44.941 | 1.301× |
| 10,000 | Home | 257.702 | 289.577 | +31.875 | 1.124× |
| 10,000 | History | 343.608 | 386.664 | +43.056 | 1.125× |
| 10,000 | Stats | 357.928 | 453.896 | +95.968 | 1.268× |

The earlier baseline used a temporary Release XCTest host, while this
post-Sparkle source of truth drives the packaged Release application. These
deltas describe the observed baselines; they do not by themselves attribute
the difference to Sparkle.

## First-window and hitch evidence

First-window opening is reported separately from the pane target:

| Profile | JSONL load→Home first meaningful frame |
| --- | ---: |
| Empty | 309.617 |
| 10,000 | 845.783 |

The authoritative run also completed an `Animation Hitches` recording of cold
and warm 10,000-session Stats journeys. `xctrace` exited successfully and wrote
the trace bundle alongside the raw report. The combined report, every raw
duration, validated plans, isolated profiles, and trace remain under
`.context/pane-performance-issue-319-authoritative/` in the measurement
workspace.
