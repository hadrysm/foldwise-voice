// The one thing the canary's test and its refresher must agree on: which scope
// was recorded. Kept out of both so neither can drift from the other.

import type { WorkScope } from "../../../scope/snapshot.mts";

/** This repository's own SPEC — a real tree, with real dependency edges. */
export const CANARY_SCOPE: WorkScope = { kind: "specific-spec", target: "418" };
