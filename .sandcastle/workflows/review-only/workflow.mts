// Review Only — one pass over the whole branch, by a model that did not write it.
//
// The workflow the folder seam exists for. A same-session skill cannot do this:
// it runs in the session that wrote the code, on the provider that wrote it, and
// the per-iteration reviewer only ever sees one iteration's diff against one
// issue's criteria. Point a different provider's model at `origin/main...HEAD`
// and the two questions that need the whole branch — does it add up, and does it
// contain anything nothing claims — become askable.
//
// No knobs, so `origin/main` is written into the prompt rather than passed in,
// and this `run` sends no `promptArgs` at all. A knob for the branch's issue or
// PRD number was considered and rejected: that is work selection wearing a
// different hat.

import { REVIEWER } from "../../agents/catalog.mts";
import type { Workflow } from "../../contract.mts";

export const reviewOnly: Workflow = {
  id: "review-only",
  label: "Review Only",
  description: "Review this whole branch in one pass, diffed against origin/main",
  dir: import.meta.dirname,
  agents: [REVIEWER],
  knobs: [],

  runShape: () => "review once, origin/main...HEAD",

  run: async ({ dispatch }) => {
    // The result is deliberately dropped. `commits.length` delimits nothing
    // here — there is no next iteration to stop — and `baseSha` is not the base:
    // the review is against the remote's main, not against HEAD before the run.
    await dispatch(REVIEWER, { promptFile: "review-prompt.md" });
  },
};
