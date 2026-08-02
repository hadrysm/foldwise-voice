// The only per-repo module. Everything else under `.sandcastle/` is portable,
// so dropping Sandcastle into a web or mobile repo is this one file to edit
// plus whatever prompts differ. The line the seam draws is not *runner vs
// workflow* but **portable vs per-repo** — see ADR-0010, "Repo-shaped
// configuration lives in `.sandcastle/repo.mts`".
//
// A typed module rather than JSON or TOML: the defaults stay typed and no
// parser is added. Per-repo rather than per-workflow, because
// `swift package resolve` is a fact about this repository, not about Implement
// & Review.
//
// The boundary this module sits on, stated as a rule:
//
//   The runner may run a command whose output it discards. It may never run a
//   command whose exit code it branches on — except git's, which is
//   framework-neutral.
//
// A pre-warm is fire-and-forget: idempotent, result ignored, opaque to the
// runner. A verify's exit code has to be interpreted and *repaired*, which is
// judgment — so the fan-in verify loop lives in `merge-prompt.md` and belongs
// to the Merger, never to a driver.

export interface RepoConfig {
  /**
   * `owner/name`, and the only place it is written down. `scope/github.mts`
   * builds every API path from this plus a locally parsed issue number, and
   * accepts a pasted URL only when it names this repository — so a target can
   * never redirect a read somewhere else.
   */
  readonly repository: string;
  /** Run on the host checkout before each dispatch that works in place. */
  readonly onHostReady: readonly { readonly command: string }[];
  /** Run inside a freshly cut worktree, before that item's agent starts. */
  readonly onWorktreeReady: readonly { readonly command: string }[];
  /** Paths copied from the host checkout into a new worktree. */
  readonly copyToWorktree: readonly string[];
  /** The `MAX_PARALLEL` the picker offers when the driver runs items concurrently. */
  readonly maxParallelDefault: number;
  /** The wall-clock bound on one work item, after which it is `timed out`. */
  readonly itemTimeout: { readonly minutes: number };
}

export const repo: RepoConfig = {
  repository: "hadrysm/foldwise-voice",

  // Idempotent, and its output is discarded: pre-resolving dependencies keeps
  // the agent's first build fast and tells the runner nothing.
  onHostReady: [{ command: "swift package resolve" }],

  // The pre-warm is this repo's substitute for the isolation ADR-0001 denies.
  // N verify loops on one macOS host share WindowServer, `syspolicyd`, the GUI
  // session and the SwiftPM cache, and this suite deadlocks from N=2 upward
  // (#408) — which needs *both* concurrency and a freshly-linked test bundle,
  // so linking it here, before the item's agent starts, disarms the trigger.
  onWorktreeReady: [{ command: "swift package resolve" }, { command: "swift build --build-tests" }],

  // A finding, not a default. Cloning `.build` *breaks* the build on an
  // absolute PCH module-cache path, and removing that cache still recompiles
  // all 446 files — so the copy buys nothing it does not also cost. There is
  // nothing else worth carrying: `pnpm install` cold is 0.6s (#406).
  copyToWorktree: [],

  // Measured, not guessed: build throughput is 1.00, 1.48, 1.67, 1.60 at
  // N=1..4, so it peaks at three and *inverts* at four — `swift build` already
  // saturates ten cores on its own (#406).
  maxParallelDefault: 3,

  // Provisional. Forty-five minutes is invented and nothing has yet measured
  // it; the maintainer's acceptance run calibrates it from real per-item
  // wall-clock durations.
  itemTimeout: { minutes: 45 },
};
