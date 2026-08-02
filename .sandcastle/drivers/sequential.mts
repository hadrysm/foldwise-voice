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
// ordered and already truncated, and a failure now costs exactly what it should
// — the item, and everything that was going to be built on top of it.
//
// Two properties this loop has and the old one did not:
//
//   1. **It observes rather than asks.** Committed or not comes from
//      `git rev-list`, crashed from a rejected promise, bounced from re-reading
//      the issue. The body returns `void` and is believed about nothing, which
//      is what keeps the transitive skip set out of a workflow's hands.
//   2. **It says what it did.** Every skip carries the foundation it lost, and
//      every reason reaches the report — a run that quietly drops items is a run
//      that lies about what it did.
//
// The judgment is `drivers/outcomes.mts`'s and the writes are
// `drivers/tracker.mts`'s, so what is left here is the shape of the walk. This
// module still imports no Sandcastle and no provider, and spawns nothing itself:
// git, `gh` and the agents all arrive as values.

import type { Workflow } from "../contract.mts";
import type { WorkItem } from "../scope/snapshot.mts";
import type { RunCore } from "./core.mts";
import {
  cascade,
  driftAction,
  foundationExists,
  outcomeLabel,
  type ItemOutcome,
  type ItemRecord,
  type LoopOutcome,
  type Settlement,
} from "./outcomes.mts";
import { correctItem, ghTracker, handOff, type Tracker } from "./tracker.mts";

export function driveSequential(core: RunCore, workflow: Workflow): Promise<void> {
  return driveSequentialWith(core, workflow, ghTracker());
}

/**
 * The loop, with the tracker injected.
 *
 * Exported so the whole of it — the cascade, the drift table, the corrections
 * and the handoff — is assertable against a fake core and a counting tracker,
 * without a network, a login or a git repository. You only fake what is
 * expensive: agents cost money, minutes and a provider login, and the decisions
 * themselves are pure.
 */
export async function driveSequentialWith(
  core: RunCore,
  workflow: Workflow,
  tracker: Tracker,
): Promise<void> {
  const records = new Map<string, ItemRecord>();
  const skipped = new Set<string>();
  const total = core.work.length;
  let aborted: string | null = null;

  const record = (item: WorkItem, outcome: ItemOutcome): void => {
    // This driver commits straight onto the workspace branch, so an item has no
    // branch of its own to name. `wave-parallel` fills this in.
    records.set(item.nodeId, { item, outcome, branch: null });
  };

  /**
   * Drop everything this failure takes down with it. Independent items are
   * untouched, and **a skip never backfills** — item eleven is not promoted when
   * item three is skipped, because the list was cut before the run began.
   */
  const dropDependents = (failed: WorkItem): void => {
    for (const drop of cascade(core.scope, failed.nodeId, skipped)) {
      skipped.add(drop.nodeId);
      const item = core.work.find((candidate) => candidate.nodeId === drop.nodeId);
      // A dependent the run guard already cut is skipped without being reported:
      // it was never part of this run to begin with.
      if (!item) continue;
      record(item, { kind: "skipped", reason: drop.reason });
      console.log(`  ↷ #${item.number} skipped — ${drop.reason}`);
    }
    skipped.add(failed.nodeId);
  };

  for (const [index, item] of core.work.entries()) {
    if (skipped.has(item.nodeId)) continue;

    const check = await core.issues.revalidate(item);
    if (check.status !== "ok") {
      const action = driftAction(check.status);
      if (action === "abort-run") {
        // The controlling contract is gone, so there is no per-item answer to
        // give. The report still goes out; nothing is labelled.
        aborted = check.detail;
        console.log(`\n✖ Aborting the run — ${check.detail}`);
        break;
      }
      console.log(`\n=== ${index + 1}/${total} · #${item.number} — drift: ${check.detail} ===`);
      record(item, { kind: "drift", detail: check.detail });
      if (action === "skip-transitively") dropDependents(item);
      continue;
    }

    console.log(`\n=== ${index + 1}/${total} · #${item.number} ${item.title} ===\n`);

    // Captured before the body, so what it produced is measured rather than
    // reported. The item is handed over to read, never to dispatch against: the
    // dispatch this body receives already *is* that item.
    const baseSha = core.git.headSha();
    let loop: LoopOutcome = "committed";
    try {
      await workflow.run({ item, dispatch: core.forItem(item) });
    } catch (error) {
      // A failure interrupts no sibling: the run records it, drops what was
      // going to be built on it, and moves to the next independent item.
      loop = "crashed";
      const detail = error instanceof Error ? error.message : String(error);
      console.log(`  ✖ #${item.number} crashed: ${detail}`);
    }

    const commits = core.git.commitsSince(baseSha);
    if (loop === "committed" && commits === 0) loop = "no-commits";
    const live = await core.issues.liveState(item);
    const settlement: Settlement = {
      loop,
      // Working in place means there is no fan-in phase at all, which is not the
      // same as a merge that did not happen.
      merge: null,
      commits,
      // The reviewer reopens what it judges incomplete, so an item whose issue
      // is open once its loop has finished was bounced.
      bounced: loop === "committed" && live.state === "open",
    };
    record(item, { kind: "settled", ...settlement });
    console.log(`  · #${item.number} ${outcomeLabel(settlement)}`);

    correctItem(tracker, {
      item,
      settlement,
      closed: live.state === "closed",
      // This driver's reading of *unmerged* is *zero commits*, which catches an
      // implementer that closed its issue without committing anything —
      // something neither driver could previously detect.
      merged: commits > 0,
      workspaceBranch: core.git.branch,
      branch: null,
      logPath: null,
    });

    // A reopened item is never eligible again in the run that reopened it, and
    // needs no rule of its own to say so: everything that reopens is something
    // that left no foundation, which is exactly what this drops.
    if (!foundationExists(settlement)) dropDependents(item);
  }

  await handOff(tracker, core, {
    records: core.work.flatMap((item) => records.get(item.nodeId) ?? []),
    aborted,
  });
}
