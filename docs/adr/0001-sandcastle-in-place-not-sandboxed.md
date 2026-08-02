# ADR-0001: Sandcastle runs in place on the host, not in a sandbox

## Status

Accepted (2026-07-03). Amended (2026-07-03): the runner moved from custom
orchestration with the `head` branch strategy to the stock upstream
sequential-reviewer template, which works in host git worktrees on named
`sandcastle/sequential-reviewer/*` branches. Amended (2026-07-04): reverted
branch handling to the `head` strategy — the runner now works in place on the
current Conductor workspace branch, creating no per-cycle
`sandcastle/sequential-reviewer/*` branch and no host worktree. Amended
(2026-08-01): the wave-parallel driver reinstates a host worktree **per work
item**, so the 2026-07-04 removal now holds for the sequential drivers only;
the price of running those loops without container isolation is recorded as a
new consequence. The no-sandbox (host execution) decision, the rejection of
container mode, and the rule that the run never pushes and never opens a PR are
unchanged throughout — see "Parallelism does not reopen containers" below.

## Context

The Sandcastle batch runner under `.sandcastle/` drives autonomous
implement→review agents against this repo's GitHub issues. Sandcastle's
default posture is to isolate each agent in a Linux Docker container built
from a repo-provided Dockerfile, working on a throwaway `sandcastle/*`
branch that the human later merges.

Two facts about this repo make that default unworkable or redundant:

- **The app cannot build in a Linux container.** FoldWiseVoice is a macOS
  AppKit Swift package (`platforms: [.macOS(.v14)]`) depending on AppKit,
  Carbon hotkey APIs, and other Apple-only frameworks. `swift build` and
  `swift test` — the verification the agents must run before every commit —
  only succeed on a macOS host with Xcode toolchains. There is no Linux
  image that can compile this code, so a container sandbox could never
  verify its own work.
- **The workspace is already the isolation boundary.** The maintainer works
  in Conductor, where each workspace is its own git worktree on its own
  branch. An agent scribbling on "the current checkout" is scribbling on an
  isolated, disposable workspace — not on the maintainer's main checkout.
  This isolates the *run* from the maintainer, which is all a sequential run
  needs. It does not isolate concurrent loops from each other, which is why
  the 2026-08-01 amendment exists.

## Decision

Run Sandcastle **on the macOS host**, under the no-sandbox provider on every
path. **No Dockerfile is included in this repo**, deliberately — its absence
signals that container mode is not a supported configuration, not an omission.
The maintainer reviews the resulting branch in Conductor and opens any PR by
hand.

### Sequential runs work in place

The sequential drivers use the `head` branch strategy. Both the implement and
review phases execute directly on the current Conductor workspace checkout and
commit straight to its branch — no per-cycle worktree and no
`sandcastle/sequential-reviewer/*` branch.

Because the `head` strategy leaves the implementer and reviewer on the same
branch, Sandcastle's built-in `TARGET_BRANCH` prompt argument equals `HEAD` and
can no longer delimit a cycle's work. The runner therefore captures HEAD before
each implement phase and passes it to the review prompt as `REVIEW_BASE`, which
the reviewer diffs against (`git diff {{REVIEW_BASE}}...HEAD`).

### Concurrent runs get one host worktree per work item

*Amendment, 2026-08-01.* The wave-parallel driver runs several implement→review
loops at once, and two agents cannot share one checkout. Each work item
therefore gets its own **host** worktree, cut from the workspace branch's
current tip onto a named `sandcastle/<number>-<slug>` branch — `noSandbox()`
passed explicitly to `Worktree.run()` (where `sandbox` is required and does not
default), plus `createWorktree({ branchStrategy })`, whose type excludes `head`
by construction.

This **reverses the 2026-07-04 amendment for that driver only**, and the
distinction is worth stating precisely, because the two worktrees are not the
same thing wearing different names:

- What 2026-07-04 removed was a per-**cycle** worktree in a **sequential** run.
  One agent ran at a time on one branch, so the worktree bought nothing the
  Conductor workspace was not already providing. That reasoning still holds and
  the sequential drivers still work in place.
- What 2026-08-01 adds is a per-**item** worktree in a **concurrent** run,
  where the checkout is not spare capacity but the resource being contended
  for. Two loops in one checkout would interleave each other's edits, builds
  and commits.

Nothing else about the host posture moves: same provider, same host, same
`REVIEW_BASE` hand-off inside each loop.

### The run still never publishes

Concurrency changes where the work is written, not who publishes it. When a
wave settles, the runner merges each settled item's branch back into the
workspace branch with `git merge --no-ff` in run order, and cuts the next wave
from the new tip. The `--no-ff` is load-bearing: the merge commits are the only
per-item boundary in an otherwise flat diff.

So the unit of review is unchanged — the maintainer still reviews **one
Conductor branch**, and the run still never pushes and never opens a pull
request. That holds for all three workflows, and it is why this amendment
touches the worktree consequence below and leaves the human-gate consequence
standing.

### Consequences that follow from this decision

- **The Node runtime is quarantined in `.sandcastle/`.** With no container
  image to hold the runner's toolchain, it lives on the host instead — as a
  self-contained pnpm project inside `.sandcastle/`, so the Swift repo root
  stays free of `package.json`/`node_modules` noise.
- **Agents inherit the host environment.** Their `claude` and `gh` calls use
  the maintainer's existing logins; no token juggling in a `.env` file.
- **The human gate is the Conductor review.** The run never pushes and never
  opens a PR — commits land on the current workspace branch, directly under a
  sequential driver and via `--no-ff` fan-in under the parallel one, and the
  maintainer reviews that branch and opens any PR by hand. A parallel run's
  `sandcastle/*` branches are merged by the runner and deleted with plain
  `git branch -d`; nothing is left for the maintainer to merge.
- **Host runs are trust-scoped.** Agents run with the maintainer's user
  privileges, so the runner is a local, human-launched tool only — never
  wired into CI or run on untrusted input. Everything the runner does to
  narrow what an agent may touch — the frozen work-scope allow-list, the
  prompts that never mention other work — is therefore **structural and
  auditable scope control, not a security boundary**. An agent that ignored
  it would be caught by review, not by a sandbox.
- **Concurrency has no isolation, and that is the price of no-sandbox.**
  *Amendment, 2026-08-01.* Container mode's real second benefit was never
  named here: a Linux userspace per item is also what keeps concurrent verify
  loops from interfering. Upstream Sandcastle needs no per-item timeout
  precisely because `docker()` gives every item its own. N verify loops on one
  macOS host share WindowServer, `syspolicyd`, the GUI session and the SwiftPM
  cache, and this suite deadlocks indefinitely from N=2 upward
  ([#408](https://github.com/hadrysm/foldwise-voice/issues/408)), with two more
  tests failing under load
  ([#409](https://github.com/hadrysm/foldwise-voice/issues/409)). Measurements
  and method are recorded in
  [`docs/worktree-parallelism-measurements.md`](../worktree-parallelism-measurements.md)
  — the N=1..4 throughput series, the deadlock trigger table and the
  `copyToWorktree` finding, summarised for
  [#406](https://github.com/hadrysm/foldwise-voice/issues/406). *(Amendment,
  2026-08-01: this cited the issue alone until the measurements landed at a path
  that resolves.)*

  Three things substitute for the isolation, and they are framework-neutral by
  intent — Sandcastle is meant to drive web and mobile repos too, so these are
  the price of `noSandbox()` in general, not Swift workarounds:

  - a **per-item wall-clock timeout**, built from `run()`'s `AbortSignal`
    (Sandcastle's own `Timeouts` covers lifecycle steps, not the agent run);
  - **"timed out" as an outcome distinct from "tests failed"**, because a hang
    is not evidence either way about the work item;
  - a **per-repo warm-up** in `host.onWorktreeReady`, declared in
    `.sandcastle/repo.mts` — here, `swift build --build-tests` plus one solo
    test run, which removed every observed hang.

## Rejected alternative: Docker container sandbox

Sandcastle's containerized mode (agent in a Linux Docker sandbox, commits on
a throwaway `sandcastle/*` branch) was rejected because:

- The macOS-only Swift package cannot compile in a Linux container, so the
  agents' mandatory verify loop (`swift build --build-tests`, then
  `swift test --skip-build`) would fail on every iteration. This is a hard constraint, not a
  preference.
- The isolation it buys is already provided by the Conductor workspace
  worktree the runner executes in — the container adds nothing but the build
  breakage above.

Should the package ever gain a Linux-buildable core (e.g. a platform-free
library target), this decision is worth revisiting for that subset.

### Parallelism does not reopen containers

*Amendment, 2026-08-01.* Because the natural reading of "concurrent agents"
is "one container each," state the negative explicitly: **the 2026-08-01
amendment does not amend this rejection.** Its hard constraint is unchanged —
the macOS-only Swift package still cannot compile on Linux, so a containerised
agent still could not run the verify loop it is required to run.

Nor is a container the mechanism concurrency needs. Verified against the
installed `@ai-hero/sandcastle@0.12.0`: `noSandbox()` supports all three branch
strategies, and `createWorktree({ branchStrategy })` plus
`Worktree.run({ sandbox: noSandbox() })` gives per-item worktrees on the host.
Upstream's use of `docker()` is upstream's choice, not the mechanism's
requirement. What the rejection *does* still cost us is isolation between
concurrent loops, and that cost is now written down as a consequence above
rather than left implied.
