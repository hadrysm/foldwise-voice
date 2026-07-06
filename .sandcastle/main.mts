// Sequential Reviewer — in-place implement-then-review loop
//
// This template drives a two-phase workflow per issue:
//   Phase 1 (Implement): An agent picks the next open issue, commits the
//                        changes, and signals completion.
//   Phase 2 (Review):    A second agent reviews that iteration's commits and
//                        either approves them or corrects them in place.
//
// Both phases run directly on the CURRENT branch via the `head` branch
// strategy — no per-cycle branch, no host worktree. This runner is launched
// inside Conductor, where the workspace is already an isolated git worktree on
// its own branch, so Sandcastle adds no isolation of its own: the agents'
// commits land straight on the workspace branch for review
// (see docs/adr/0001-sandcastle-in-place-not-sandboxed.md).
//
// The outer loop repeats up to MAX_ITERATIONS times, processing one issue per
// iteration and stopping early once the backlog is exhausted (an implement
// phase that produces no commits).
//
// Agents run directly on the macOS host via noSandbox() because the app cannot
// build in a Linux container (see the same ADR).
//
// Usage (from the repo root — Sandcastle resolves prompt files and git
// against process.cwd()):
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts

import { execSync } from "node:child_process";
import * as sandcastle from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Maximum number of implement→review cycles to run before stopping.
// Each cycle works on one issue. Raise this to process more issues per run.
const MAX_ITERATIONS = 10;

// Separate agents per phase, so the reviewer works from a fresh, independent
// context rather than sharing the implementer's. Tune either one's model or
// effort on its own line.
const implementerAgent = sandcastle.claudeCode("claude-opus-4-8", { effort: "xhigh" });
const reviewerAgent = sandcastle.claudeCode("claude-opus-4-8", { effort: "xhigh" });

// Hooks run on the host checkout before the agent starts each phase.
// Pre-resolving Swift dependencies keeps the agent's first build fast; the
// command is idempotent, so running it once per phase is harmless.
const hooks = {
  sandbox: { onSandboxReady: [{ command: "swift package resolve" }] },
};

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

for (let iteration = 1; iteration <= MAX_ITERATIONS; iteration++) {
  console.log(`\n=== Iteration ${iteration}/${MAX_ITERATIONS} ===\n`);

  // Capture HEAD before the implementer runs. In `head` mode the implementer
  // and reviewer both work on the current branch, so Sandcastle's built-in
  // TARGET_BRANCH equals HEAD and can't delimit this iteration's work. We hand
  // the reviewer this SHA as REVIEW_BASE so it diffs exactly the commits this
  // iteration produced.
  const reviewBase = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();

  // -------------------------------------------------------------------------
  // Phase 1: Implement
  //
  // The agent picks the next open issue, writes the implementation (using
  // RGR: Red → Green → Refactor), and commits the result. maxIterations: 1
  // keeps it to a single issue so the reviewer sees one issue's diff; a higher
  // value would let one pass drain the whole backlog and defeat per-issue
  // review. The agent signals completion via <promise>COMPLETE</promise>.
  // -------------------------------------------------------------------------
  const implement = await sandcastle.run({
    name: "implementer",
    sandbox: noSandbox(),
    branchStrategy: { type: "head" },
    agent: implementerAgent,
    maxIterations: 1,
    hooks,
    promptFile: "./.sandcastle/implement-prompt.md",
  });

  if (!implement.commits.length) {
    // No commits means the backlog is empty or every remaining issue is
    // blocked — there is nothing left to implement or review, so stop.
    console.log("Implementation agent made no commits. Stopping.");
    break;
  }

  console.log(`\nImplementation complete. Commits: ${implement.commits.length}`);

  // -------------------------------------------------------------------------
  // Phase 2: Review
  //
  // A second agent reviews this iteration's commits (everything since
  // REVIEW_BASE on the current branch) and either approves or corrects them in
  // place.
  // -------------------------------------------------------------------------
  await sandcastle.run({
    name: "reviewer",
    sandbox: noSandbox(),
    branchStrategy: { type: "head" },
    agent: reviewerAgent,
    maxIterations: 1,
    hooks,
    promptFile: "./.sandcastle/review-prompt.md",
    promptArgs: {
      REVIEW_BASE: reviewBase,
    },
  });

  console.log("\nReview complete.");
}

console.log("\nAll done.");
