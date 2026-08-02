// Implement & Review (parallel) — the same pair, several items at a time.
//
// A driver declaration and a body, like every other workflow. Everything that
// makes this run differ from `sequential-reviewer` — the worktrees, the wave,
// the Planner, the fan-in, the Merger, the cleanup — belongs to the
// `wave-parallel` driver, and none of it is expressible from here.
//
// **The body is byte-for-byte the sequential one.** That is the strongest
// statement this slice can make about the seam: the shape a workflow describes
// is entirely a property of its `driver`, so the same six lines run one item at
// a time on the host checkout under one declaration and three items in three
// worktrees under another. If the two bodies ever diverge, something crossed the
// seam that should not have.
//
// **The two extra agents are declared but never dispatched from here.** `PLANNER`
// and `MERGER` are the driver's, made through `core.consult`; they are listed
// because `agents` is what the picker asks models for and what the preflight
// checks CLIs for, so a run must never reach wave one and discover the Planner's
// provider is logged out.
//
// **The sequential workflow stays.** It is the right choice when contention or a
// one-item scope makes concurrency pointless, and keeping it means nothing
// already shipped has to change to gain this.

import { IMPLEMENTER, MERGER, PLANNER, REVIEWER } from "../../agents/catalog.mts";
import type { Workflow } from "../../contract.mts";

export const waveParallelReviewer: Workflow = {
  // The folder's own name, like every other workflow: the run store keys on the
  // id, and a reader who has the id has the folder.
  id: "wave-parallel",
  label: "Implement & Review (parallel)",
  description: "Work through open issues in waves, each item alone in its own worktree",
  dir: import.meta.dirname,
  agents: [IMPLEMENTER, REVIEWER, PLANNER, MERGER],
  driver: "wave-parallel",

  // One number, and it is the work-item count rather than the wave width:
  // `MAX_PARALLEL` is a question the picker asks about the *driver*, and a
  // workflow that could name it here could contradict the answer. What is left
  // is the sequence and the ceiling, which is what this line is for.
  runShape: (workItems) =>
    `plan → implement → review in waves, up to ${workItems} issue${workItems === 1 ? "" : "s"}`,

  run: async ({ dispatch }) => {
    const implement = await dispatch(IMPLEMENTER, { promptFile: "implement-prompt.md" });
    // Nothing landed, so there is nothing to review. What that costs the rest of
    // the run — the item and everything blocked by it — is the driver's to work
    // out from git, never this body's to report.
    if (!implement.commits.length) return;

    // Both agents work on the current branch, so Sandcastle's TARGET_BRANCH
    // equals HEAD and cannot delimit this item. The implement dispatch's own
    // `baseSha` is the SHA that preceded it, so handing it over as REVIEW_BASE
    // diffs exactly this item's commits.
    await dispatch(REVIEWER, {
      promptFile: "review-prompt.md",
      promptArgs: { REVIEW_BASE: implement.baseSha },
    });
  },
};
