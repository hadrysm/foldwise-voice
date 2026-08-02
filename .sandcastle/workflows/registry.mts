// Every workflow the picker offers, in the order it offers them. Position 0 is
// the default when nothing is remembered.
//
// A static list rather than a glob over `workflows/*/workflow.mts`: a glob
// costs the `tsc --noEmit` gate (a dynamic import cannot be checked against
// `Workflow`), makes the catalog async, and hands the default option to
// `readdir`'s alphabet.

import type { Workflow } from "../contract.mts";
import { reviewOnly } from "./review-only/workflow.mts";
import { sequentialReviewer } from "./sequential-reviewer/workflow.mts";
import { waveParallelReviewer } from "./wave-parallel/workflow.mts";

export const WORKFLOWS: readonly Workflow[] = [
  sequentialReviewer,
  waveParallelReviewer,
  reviewOnly,
];
