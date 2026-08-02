// Implement & Review — one work item's implement-then-review pair.
//
// A driver declaration and a body, and nothing else. The loop that used to live
// here belongs to the `sequential` driver now, along with the run guard that
// bounded it and the stop condition that ended it — this module cannot see how
// many items there are, which one it has, or that there is a next one.
//
// What is left is the sequence that was always the interesting part: implement,
// and if that produced commits, review exactly those commits. `dispatch` is the
// whole of its access to the outside world, which is what lets the pair be
// tested without a CLI.

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
  driver: "sequential",

  runShape: (workItems) =>
    `implement → review, up to ${workItems} issue${workItems === 1 ? "" : "s"}`,

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
