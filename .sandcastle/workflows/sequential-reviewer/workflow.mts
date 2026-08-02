// Sequential Reviewer — the in-place implement-then-review loop.
//
// One issue per iteration: the implementer picks the next open issue and
// commits, then a second agent reviews exactly that iteration's commits and
// either approves them or corrects them in place. The loop stops early once an
// implement dispatch produces no commits, which means the backlog is empty or
// everything left is blocked.
//
// This module imports no Sandcastle, no provider and no git. `dispatch` is the
// whole of its access to the outside world, which is what lets the loop above
// be tested without a CLI.

import { IMPLEMENTER, REVIEWER } from "../../agents/catalog.mts";
import type { Workflow } from "../../contract.mts";

export const sequentialReviewer: Workflow = {
  // Pinned: the id is this workflow's lineage to the upstream template
  // ADR-0001 cites, and it is what the run store remembers.
  id: "sequential-reviewer",
  label: "Implement & Review",
  description: "Work through open issues one at a time, reviewing each before the next",
  dir: import.meta.dirname,
  agents: [IMPLEMENTER, REVIEWER],
  // The `maxIterations` knob is gone: the universal run guard is the same
  // parameter asked once, for every scope and every workflow that drains. Two
  // number questions for one number must never both be on screen.
  knobs: [],
  drains: true,
  concurrent: false,

  runShape: (workItems) =>
    `implement → review, up to ${workItems} issue${workItems === 1 ? "" : "s"}`,

  run: async ({ dispatch, maxWorkItems }) => {
    for (let iteration = 1; iteration <= maxWorkItems; iteration++) {
      console.log(`\n=== Iteration ${iteration}/${maxWorkItems} ===\n`);

      const implement = await dispatch(IMPLEMENTER, { promptFile: "implement-prompt.md" });

      if (!implement.commits.length) {
        console.log("Implementation agent made no commits. Stopping.");
        break;
      }

      console.log(`\nImplementation complete. Commits: ${implement.commits.length}`);

      // Both agents work on the current branch, so Sandcastle's TARGET_BRANCH
      // equals HEAD and cannot delimit this iteration. The implement
      // dispatch's own `baseSha` is the SHA that preceded it, so handing it
      // over as REVIEW_BASE diffs exactly this iteration's commits.
      await dispatch(REVIEWER, {
        promptFile: "review-prompt.md",
        promptArgs: { REVIEW_BASE: implement.baseSha },
      });

      console.log("\nReview complete.");
    }
  },
};
