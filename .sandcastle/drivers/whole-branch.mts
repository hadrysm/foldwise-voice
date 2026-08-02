// No work items at all: one pass over the branch, in the host checkout.
//
// A Work scope still resolves before this runs — the run guard and `MAX_PARALLEL`
// are simply not decisions here, and what the scope produces is an *anchor*
// rather than a queue. That is why `{{ANCHOR}}` is this driver's arg and
// `{{WORK}}` is not: a whole-branch prompt asks what the branch was selected to
// deliver, not which issue this iteration was handed.
//
// This module imports no Sandcastle, no provider and no git, and spawns nothing.

import type { Workflow } from "../contract.mts";
import type { RunCore } from "./core.mts";

export async function driveWholeBranch(core: RunCore, workflow: Workflow): Promise<void> {
  await workflow.run({ item: null, dispatch: core.forBranch() });
}
