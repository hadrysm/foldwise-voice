# Worktree contention for concurrent builds

Measurement summary for [#406](https://github.com/hadrysm/foldwise-voice/issues/406),
charted under the [Work scope map](https://github.com/hadrysm/foldwise-voice/issues/389).

The question: is wave parallelism worth having, and what should `MAX_PARALLEL`
default to? Everything below was measured on the maintainer's machine against
this repo. **The numbers are repo-specific and toolchain-specific by
construction** — Sandcastle is meant to drive web and mobile repos too, so the
portable output of this exercise is the *shape* of the answer, not the constants.
See [What generalises](#what-generalises).

## Machine and method

- Apple M1 Pro, 10 cores (8P + 2E), 16 GB, macOS 26.0, APFS.
- Swift 6.2.3 (Xcode toolchain), `swift-tools-version: 5.10`, macOS 14 platform.
- Package deps: FluidAudio, Sparkle (binary artifact), argmax-oss-swift/WhisperKit.
- Suite: 1520 XCTest cases, 8 skipped, including hosted AppKit/SwiftUI tests that
  drive `NSApp`, real windows and pixel/geometry assertions.
- N detached git worktrees of the same commit under one scratch root; each wave
  deletes `.build`, then runs `swift build --build-tests` followed by
  `swift test --skip-build`, all N concurrently. Wall clock measured per item
  and per wave. Throwaway bash scripts; nothing under `.sandcastle/` was changed.

Baselines, measured solo: full cold build **42s**, full test run **41s**, no-op
rebuild **1.0s**, one-file incremental rebuild **3.0s**. A cold `.build` is 1.3 GB.

## Does concurrency go faster?

Cold build + full test, per item and per wave, healthy runs only:

| N | build/item | test/item | wave wall | vs. sequential | amortized/item |
|---|-----------|-----------|-----------|----------------|----------------|
| 1 | 41.9s | 41.3s | 83.3s | 1.00× | 83.3s |
| 2 | 56.7s | 40.7s | 98.5s | 1.69× | 49.2s |
| 3 | 75.3s | 43.0s | 123.1s | 2.03× | 41.0s |
| 4 | 104.6s | 45.5s | 152.3s | 2.19× | 38.1s |

Yes — but it flattens fast, and the two phases behave completely differently.

**The build phase inverts at N=4.** Normalising to build work completed per unit
time (`N × 41.9 / build-time`): 1.00, 1.48, **1.67**, 1.60. `swift build` already
saturates all 10 cores on its own, so concurrent builds are pure contention past
the point where one build can't quite fill the machine. Peak is N=3; N=4 is
measurably *worse* at building than N=3.

**The test phase parallelises almost for free.** 41.3 → 45.5s from N=1 to N=4.
XCTest runs cases serially within a process, so each suite occupies roughly one
core; four of them fit comfortably.

Marginal wall-clock saved per added lane: N=2 saves 34.1s/item over N=1, N=3
saves 8.2s more, N=4 saves 2.9s more. The curve is flat by N=3.

**Caveat that dwarfs all of the above:** in a real wave, build+test is ~85s of an
implement→review iteration that is otherwise minutes of agent latency. Two lanes
rarely reach `swift build` at the same instant. The harness forces the collision
on every wave; real runs will not. Throughput is therefore *not* the binding
constraint on `MAX_PARALLEL` — reliability is.

## Does the suite tolerate concurrency? No.

Test-phase outcomes, counting individual items, freshly-linked test bundle:

| N | items | hangs | failures | clean |
|---|-------|-------|----------|-------|
| 1 | 7 | 0 | 0 | 7 |
| 2 | 8 | 1 | 0 | 7 |
| 3 | 6 | 2 | 0 | 4 |
| 4 | 16 | 4 | 2 | 10 |

N=1 is 7/7 clean and stable at 38–41s across five consecutive fresh-relink runs,
so this is caused by concurrency, not a pre-existing flake.

### The hang

Two or more concurrent suites intermittently **deadlock indefinitely** — not
slow down. Observed: zero log growth and 0% CPU for over nine minutes before
being killed. `sample` shows the main thread parked in
`XCTWaiter waitForExpectations:` → `_synchronouslyWaitForTimeInterval:` →
`CFRunLoopRun` → `mach_msg2_trap`: an expectation that never fulfils on a run
loop that never gets what it is waiting for.

It clusters tightly. Every observed hang was inside `SettingsWorkflowTests`
(around the `testDeleting…` group) or `PaneProjectionStoreTests`; two concurrent
processes in one run stalled at *exactly* the same case count (1236). The precise
case is masked by XCTest's block-buffered stdout, so the last flushed line is not
the last executed one.

This is a defect in the suite, not in the parallel design. Filed as
[#408](https://github.com/hadrysm/foldwise-voice/issues/408), outside this map —
but it is decisive for `MAX_PARALLEL` while it stands.

### The load-sensitive failures

Distinct from the hang, and still present after the hang is mitigated:

- `ContinuousFrameHostedTests.testHostedDisablingHistoryShowsACompactBottomRightToast`
  (`:132`) — a hosted window geometry assertion, `XCTAssertEqualWithAccuracy`
  against `1101.0 ± 1.0`. Observed at 1102.2, 1103.7 and 1120.8 under load. The
  toast's animated frame has not settled when the assertion runs.
- `ASRModelLifecycleTests.testDeletingSelectedModelCommitsDefaultAndWaitsForCapturedSession`
  (`:2003`) — asserts an exact async event order and got
  `delete-…, release-…` where it expected `release-…, delete-…`.

Both are latent races in the tests that only surface when the machine is loaded.
Filed together as [#409](https://github.com/hadrysm/foldwise-voice/issues/409).

### What actually triggers the hang

The hang needs **both** concurrency and a *freshly linked* test bundle:

| condition | items | hangs |
|-----------|-------|-------|
| N=3/N=4, bundle unchanged since a prior successful run | 15 | 0 |
| N=4, bundle relinked by a 6s incremental build | 4 | 2 |
| N=4, bundle relinked, each bundle run solo once first | 12 | 0 |

A 6-second incremental relink is enough to re-arm it, which rules out I/O
pressure from the full build as the cause and points at first-execution of a
newly-linked, ad-hoc-signed binary — plausibly `syspolicyd`/Gatekeeper
validation serialising across processes while a run loop waits on it.

That yields a mitigation: **run each worktree's test bundle once, alone, before
the wave starts.** Pre-warming with a single trivial `--filter` run removed every
hang (0 in 12 items at N=4, against 4 in 16 without). It does not fix the
load-sensitive failures (2 in 12 remained). Twelve items is suggestive, not
proof, and the mitigation is entirely macOS-specific — it belongs in this repo's
`host.onWorktreeReady` hook, never in the runner.

## What makes a fresh worktree cheap: neither `.build` nor `node_modules`

`copyToWorktree` on macOS runs `cp -cR` — an APFS clone, so it is fast (2.25s for
1.3 GB) and costs no extra disk. It is still the wrong tool here.

**`.build` must not be copied — it breaks the build outright:**

```
error: PCH was compiled with module cache path '…/w1/.build/…/ModuleCache/NOJTH7MAIRGC',
but the path is currently '…/w2/.build/…/ModuleCache/NOJTH7MAIRGC'
```

Clang PCHs record their absolute module-cache path, and a cloned `.build` carries
the donor's. Deleting `.build/<triple>/debug/ModuleCache` after the clone makes it
build again — in **41.0s**, recompiling all 219 FluidAudio, 101 kit, 122 test and
24 WhisperKit files, an identical compile count to the 42.7s cold build. SwiftPM's
build database keys on absolute paths, so a relocated `.build` is wholly
invalidated. Seeding it buys nothing and risks a confusing hard failure.

**`node_modules` does not need copying either.** `pnpm install --frozen-lockfile`
in a cold worktree takes **0.6s** against the warm content-addressed store, and
the `.sandcastle` suite then runs in 1.5s.

A cold worktree costs ~43s of build it would have to pay anyway. **The seed set
for this repo is empty.**

## The shared SwiftPM cache is safe

`~/Library/Caches/org.swift.swiftpm` is shared across all worktrees. Every wave
resolved and fetched all four dependencies concurrently from it, at N=2, 3 and 4,
with no corruption and no observable serialisation — the fetch is ~1s of a 42s
build. SwiftPM keeps no shared derived-data directory; the clang module cache
lives inside each `.build`, which is why the clone above fails and why nothing is
shared at build time. Disk cost is 1.3 GB per concurrent worktree.

## What upstream does, and why it does not transfer

[`mattpocock/sandcastle/.sandcastle/run.ts`](https://github.com/mattpocock/sandcastle/blob/main/.sandcastle/run.ts)
is the reference implementation. Three things in it bear on this measurement.

**It has no per-item timeout.** `Promise.allSettled` collects rejections, but a
*hung* item hangs the whole batch; the only backstop is Sandcastle's
`idleTimeoutSeconds` (default 600). Upstream can afford that because every item
runs in `docker()` — its own Linux container, with no shared WindowServer,
`syspolicyd` or GUI session for two suites to deadlock on. **Container isolation
is the mechanism that makes upstream's concurrency safe, and ADR-0001 rules it
out here on a hard constraint.** We therefore need an explicit substitute for
isolation, which upstream never had to build.

Checking the API: `Timeouts` covers lifecycle steps only (copy, git setup, commit
collection, merge-to-host), not the agent run. `run()` accepts
`signal?: AbortSignal`, so a per-item wall-clock timeout is the runner's to build
from a timer and an abort.

**`MAX_PARALLEL` is a module constant.** `const MAX_PARALLEL = 4` sits at the top
of `run.ts`, with a hand-rolled semaphore (`acquire`/`release` over a queue) so
lanes refill as items finish rather than chunking. Not a picker question, not
persisted — which confirms the mechanism recommended below. The value 4 is for a
Node/npm repo in containers and is no evidence about this machine.

**The setup hook is the framework-agnostic seam.** Upstream pairs
`copyToWorktree: ["node_modules"]` with
`hooks.sandbox.onSandboxReady: [{ command: "npm install && npm run build" }]`.
`host.onWorktreeReady` takes the same `{ command, timeoutMs }` shape and works
with `createWorktree`. That hook — not the prompt, and certainly not the runner —
is where a repo declares how to make a fresh worktree ready: `npm install && npm
run build` upstream, `swift build --build-tests` plus the solo pre-warm run here,
something else again for a mobile repo.

One thing upstream does that this repo deliberately will not: it re-plans on every
iteration and runs a flat refilling pool, with no waves at all.
[#403](https://github.com/hadrysm/foldwise-voice/issues/403) rejected the
semaphore — a wave starts all its items together and ends on the slowest. That
barrier is what this harness measured.

## Recommendation

**`MAX_PARALLEL = 3` for this repo.**

The evidence that sets it, in order of weight:

1. **Build throughput peaks at N=3 and inverts at N=4** (1.67 → 1.60). This is the
   only hard ceiling in the data and it is the one the ticket asked for.
2. **Every added lane adds a chance of a false failure.** Flake risk grows with N
   while wall-clock gain collapses: N=4 buys 2.9s/item over N=3 and costs a fourth
   lane's worth of exposure. That trade is not worth taking.
3. **N=2 is not clean either** (1 hang in 8 items), so a lower cap does not buy
   safety — it only buys less speed. There is no N > 1 that is safe today, which
   means the reliability work has to happen regardless of the cap, and the cap
   should therefore be set on throughput.

The *shape* is not this measurement's to choose:
[#403](https://github.com/hadrysm/foldwise-voice/issues/403) settled that
`MAX_PARALLEL` is a **picker question with one global store key**, taking its
value from here. Three is therefore the picker question's default.

That decision also fits the data better than upstream's pool would.
"Wave size is concurrency and there is no semaphore" means all N items start
together and the wave ends on the slowest — the barrier shape this harness ran.
Upstream's refilling pool staggers starts and would collide less, so the table
above is the right table for #403's design rather than an approximation of it.

Three things must land with it. The first two are framework-neutral and belong to
the runner; the third is this repo's and belongs to its setup hook.

- **A per-item wall-clock timeout, built from `run()`'s `AbortSignal`.** An
  indefinite hang is measured, not hypothetical, and upstream has nothing to
  borrow here. Without one a wave stalls until `idleTimeoutSeconds` (default 600)
  kills the silent agent, and orphaned test processes may outlive it.
- **"Timed out" must be a distinguishable outcome from "tests failed."** A hang is
  not evidence about the work item, and the stop conditions settled in
  [#394](https://github.com/hadrysm/foldwise-voice/issues/394) should not read one
  as the other.
- **The pre-warm goes in `host.onWorktreeReady`**, as this repo's substitute for
  the container isolation ADR-0001 denies us — `swift build --build-tests`
  followed by one solo `swift test --skip-build --filter …`. It is a shell command
  in repo config, so the runner never learns that this repo is a Swift repo.

## What generalises

Sandcastle is meant to drive web and mobile repos as well as this one, where the
verify loop is a different command in a different prompt. Nothing above may be
baked into the runner:

- **`MAX_PARALLEL` is per-repo.** 3 is this repo's answer because `swift build`
  saturates 10 cores on its own. A repo whose verify loop is single-threaded, or
  I/O-bound, or a headless browser suite, will sit somewhere else entirely.
- **The `copyToWorktree` seed set is per-repo, and its default is empty.**
  `.build` is Swift-shaped and `node_modules` is JS-shaped; both turned out
  unnecessary *here*, but the reasoning was empirical, not architectural.
- **"Is my suite concurrency-safe?" is not a question the runner can answer.** It
  can only bound the damage: a timeout, and an outcome that says *timed out*.
- **Framework-specific mitigations belong in the prompt.** Pre-warming a
  freshly-linked test bundle is a macOS code-signing workaround; it has no
  business in the runner or the contract.
