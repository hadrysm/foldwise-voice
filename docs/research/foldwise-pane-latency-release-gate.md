# FoldWise pane latency release-gate comparison

Issue: [Enforce pane performance as a release gate](https://github.com/hadrysm/foldwise-voice/issues/325)
Measured: 2026-07-27
Baseline: [`foldwise-pane-latency-post-sparkle-baseline.md`](foldwise-pane-latency-post-sparkle-baseline.md)
Harness: [`pane-performance-harness.md`](../pane-performance-harness.md)

The final local duration investigation used the packaged SwiftPM Release
application on the reference Mac, the versioned `pane-empty-v1` and
`pane-10000-v1` fixtures, and the documented 980×720 nonactivating window. Every
class discarded one warm-up and retained 20 raw samples. Combining the clean
per-profile diagnostic results passes the matrix and duration policies: all 24
routes are present, no raw sample exceeds 100 ms, no route median regresses by
more than 20% from its accepted baseline, and first-window opening remains
outside the pane threshold. This composite is not an authoritative release-gate
report.

Times below are milliseconds. Current values are shown as
`median / observed p95 / worst`.

## Empty profile

| Destination | Visit | Post-Sparkle median | Current | Median change |
| --- | --- | ---: | ---: | ---: |
| Home | cold | 34.794 | 32.985 / 38.369 / 40.127 | -1.809 (-5.2%) |
| Home | warm | 31.968 | 31.572 / 34.760 / 40.954 | -0.396 (-1.2%) |
| Modes | cold | 131.608 | 67.613 / 70.818 / 85.571 | -63.995 (-48.6%) |
| Modes | warm | 131.838 | 68.383 / 70.475 / 73.272 | -63.455 (-48.1%) |
| Models | cold | 42.331 | 39.626 / 50.806 / 53.601 | -2.705 (-6.4%) |
| Models | warm | 43.188 | 37.406 / 51.714 / 54.223 | -5.782 (-13.4%) |
| History | cold | 56.989 | 43.452 / 51.754 / 52.462 | -13.537 (-23.8%) |
| History | warm | 53.930 | 45.207 / 62.524 / 63.006 | -8.723 (-16.2%) |
| Stats | cold | 194.418 | 38.983 / 42.082 / 50.585 | -155.435 (-79.9%) |
| Stats | warm | 182.433 | 37.380 / 51.539 / 52.075 | -145.053 (-79.5%) |
| Settings | cold | 78.996 | 71.091 / 82.701 / 88.574 | -7.905 (-10.0%) |
| Settings | warm | 73.913 | 70.856 / 82.523 / 85.212 | -3.057 (-4.1%) |

## 10,000-session profile

| Destination | Visit | Post-Sparkle median | Current | Median change |
| --- | --- | ---: | ---: | ---: |
| Home | cold | 289.577 | 73.624 / 82.504 / 87.373 | -215.953 (-74.6%) |
| Home | warm | 288.551 | 79.277 / 84.715 / 86.209 | -209.274 (-72.5%) |
| Modes | cold | 140.686 | 77.878 / 86.023 / 87.532 | -62.808 (-44.6%) |
| Modes | warm | 143.169 | 78.813 / 82.599 / 85.760 | -64.356 (-45.0%) |
| Models | cold | 59.107 | 48.801 / 51.146 / 54.809 | -10.306 (-17.4%) |
| Models | warm | 51.874 | 47.821 / 52.472 / 52.622 | -4.053 (-7.8%) |
| History | cold | 386.664 | 71.430 / 77.809 / 82.451 | -315.234 (-81.5%) |
| History | warm | 376.112 | 66.676 / 77.453 / 98.887 | -309.436 (-82.3%) |
| Stats | cold | 453.896 | 47.928 / 50.590 / 52.091 | -405.968 (-89.4%) |
| Stats | warm | 411.628 | 43.866 / 51.023 / 52.742 | -367.762 (-89.3%) |
| Settings | cold | 95.897 | 83.521 / 89.170 / 93.171 | -12.376 (-12.9%) |
| Settings | warm | 83.766 | 84.591 / 90.417 / 93.685 | +0.825 (+1.0%) |

The former collection-size failures are now bounded: 10,000-session Home,
History, and Stats worst samples are 87.373, 98.887, and 52.742 ms respectively.
Empty-profile Stats improved from 194.418/182.433 ms cold/warm medians to
38.983/37.380 ms.

## Evidence disposition

An earlier complete matrix correctly failed on a 101.678 ms raw Home warm
sample. A subsequent isolated run exposed trace timestamp bookkeeping inside the
measured interval; moving completion to after the AppKit draw turn made the
instrumentation reflect the full first meaningful frame. The corrected full
large-fixture duration matrix passed both duration gates.

A later empty-profile trace isolated a one-time RenderBox initialization hitch
when the Modes Canvas first appeared. Prewarming that renderer during the
separately measured first-window interval removed all correlated cold and warm
Modes and Stats hitches in the repeated empty-profile trace. Its continuous
main-thread bursts were classified as explained frame rendering, with no
SwiftUI update groups, potential hangs, or unexplained stalls.

At the operator's request, all generated 10,000-session trace and raw output was
deleted after the investigation, so this document records the observed
comparison but does not claim retained or `authoritative: true` evidence. The
fixed-Mac release lane remains the source of truth: it must reproduce the full
matrix from a clean commit and retain SwiftUI, Time Profiler, Hitches, and
signpost evidence.
