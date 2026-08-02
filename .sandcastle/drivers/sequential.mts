// One work item at a time, in the host checkout.
//
// This is the loop ADR-0010 used to call "the workflow's `for`". It moved here,
// and the claim moved with it: **there is exactly one loop over work items per
// run, and it belongs to the driver. A workflow supplies that loop's body; it
// can neither create a loop nor bound one.**
//
// The old loop stopped on the first dispatch that produced no commits, under a
// comment reading *"the backlog is empty or everything left is blocked"* — one
// conflation of two facts, and the reason a `blocked_by`-chained SPEC took one
// launch per slice. There is nothing left to conflate: the list arrives frozen,
// ordered and already truncated, so the run works exactly the items it was
// given and stops because it ran out of them.
//
// This module imports no Sandcastle, no provider and no git, and spawns nothing.

import type { Workflow } from "../contract.mts";
import type { RunCore } from "./core.mts";

export async function driveSequential(core: RunCore, workflow: Workflow): Promise<void> {
  const total = core.work.length;
  for (const [index, item] of core.work.entries()) {
    console.log(`\n=== ${index + 1}/${total} · #${item.number} ${item.title} ===\n`);
    // The item is handed over to read, never to dispatch against: the dispatch
    // this body receives already *is* that item.
    await workflow.run({ item, dispatch: core.forItem(item) });
  }
}
