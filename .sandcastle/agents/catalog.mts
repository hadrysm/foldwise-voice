// The agents a workflow can drive. Identity only — a model, an effort and a
// prompt all arrive from somewhere else (the picker, the store, the workflow).
//
// The ids are load-bearing beyond this file: they are the run store's keys and
// Sandcastle's log prefixes, so renaming one silently orphans a remembered pick.

import type { Agent } from "../contract.mts";

export const IMPLEMENTER: Agent = { id: "implementer", label: "Implementer" };
export const REVIEWER: Agent = { id: "reviewer", label: "Reviewer" };
