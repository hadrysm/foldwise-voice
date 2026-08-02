// The agents a workflow can drive. Identity only — a model, an effort and a
// prompt all arrive from somewhere else (the picker, the store, the workflow).
//
// The ids are load-bearing beyond this file: they are the run store's keys and
// Sandcastle's log prefixes, so renaming one silently orphans a remembered pick.

import type { Agent } from "../contract.mts";

export const IMPLEMENTER: Agent = { id: "implementer", label: "Implementer" };
export const REVIEWER: Agent = { id: "reviewer", label: "Reviewer" };

/**
 * The two a concurrent driver adds. Listed here for the same reason as the other
 * two and with no special case: a workflow that declares them gets their models
 * asked for by the picker and their CLIs checked by the preflight, so a run
 * never reaches wave one and discovers the Planner's provider is logged out.
 *
 * What is different about them is *who* dispatches them — the driver, on the
 * host, through `core.consult` rather than through a workflow's `Dispatch`. That
 * is what lets these two alone use structured output, and it is invisible from
 * here: identity is identity.
 */
export const PLANNER: Agent = { id: "planner", label: "Planner" };
export const MERGER: Agent = { id: "merger", label: "Merger" };
