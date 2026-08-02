// Review Only — one pass over the whole branch, by a model that did not write it.
//
// The workflow the folder seam exists for. A same-session skill cannot do this:
// it runs in the session that wrote the code, on the provider that wrote it, and
// the per-item reviewer only ever sees one item's diff against one issue's
// criteria. Point a different provider's model at `origin/main...HEAD` and the
// two questions that need the whole branch — does it add up, and does it contain
// anything nothing claims — become askable.
//
// A driver declaration and a body. `whole-branch` walks no work items, so the
// run guard and `MAX_PARALLEL` are not decisions here; what the resolved Work
// scope gives this run is an anchor, which the runner writes into `{{ANCHOR}}`
// without this module naming it.

import { REVIEWER } from "../../agents/catalog.mts";
import type { Workflow } from "../../contract.mts";

export const reviewOnly: Workflow = {
  id: "review-only",
  label: "Review Only",
  description: "Review this whole branch in one pass, diffed against origin/main",
  dir: import.meta.dirname,
  agents: [REVIEWER],
  driver: "whole-branch",

  runShape: () => "review once, origin/main...HEAD",

  run: async ({ dispatch }) => {
    // The result is deliberately dropped. `commits.length` delimits nothing
    // here — there is no next item to stop — and `baseSha` is not the base:
    // the review is against the remote's main, not against HEAD before the run.
    await dispatch(REVIEWER, { promptFile: "review-prompt.md" });
  },
};
