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
// Three properties this loop has and the old one did not:
//
//   1. **It observes rather than asks.** Committed or not comes from
//      `git rev-list`, crashed from a rejected promise, bounced from re-reading
//      the issue. The body returns `void` and is believed about nothing.
//   2. **It corrects the tracker per item, at settle.** Not in an end-of-run
//      sweep: nothing is auto-cleaned on abort and there is no resume, so a
//      sweep never executes in precisely the run that went worst.
//   3. **It says what it did.** Every skip carries its reason into the report,
//      and the report goes to stdout and onto the anchor.
//
// This module still imports no Sandcastle and no provider, and spawns nothing
// itself: git, `gh` and the agents all arrive as values on `RunCore` and the
// injected `Tracker`.

import type { Workflow } from "../contract.mts";
import {
  CODE_REVIEW,
  issueByNodeId,
  SPEC,
  type WorkItem,
  type WorkScopeSnapshot,
} from "../scope/snapshot.mts";
import type { RunCore } from "./core.mts";
import {
  cascade,
  correctionComment,
  deservesCodeReview,
  driftAction,
  foundationExists,
  outcomeLabel,
  runReport,
  trackerActs,
  type ItemOutcome,
  type ItemRecord,
  type LoopOutcome,
  type Settlement,
} from "./outcomes.mts";
import { ghTracker, type Tracker } from "./tracker.mts";

export function driveSequential(core: RunCore, workflow: Workflow): Promise<void> {
  return driveSequentialWith(core, workflow, ghTracker());
}

/**
 * The loop, with the tracker injected.
 *
 * Exported so the whole of it — the cascade, the drift table, the corrections
 * and the handoff — is assertable against a fake core and a counting tracker,
 * without a network, a login or a git repository. What is faked is what is
 * expensive; the decisions themselves are pure and live in `outcomes.mts`.
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
    // The sequential driver commits straight onto the workspace branch, so an
    // item has no branch of its own to name. `wave-parallel` fills this in.
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

    correct(tracker, core, item, settlement, live.state === "closed");

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

/**
 * The two tracker acts for one settled item, on their different keys.
 *
 * `merged` for this driver is *commits exist*: an item that works in place and
 * commits has reached the workspace branch by definition. That reading is what
 * catches an `implement-prompt.md` violation neither driver could previously
 * detect — an issue closed by an implementer that committed nothing.
 */
function correct(
  tracker: Tracker,
  core: RunCore,
  item: WorkItem,
  settlement: Settlement,
  closed: boolean,
): void {
  const acts = trackerActs({ closed, commits: settlement.commits, merged: settlement.commits > 0 });
  if (!acts.reopen && !acts.comment) return;

  const body = correctionComment({
    reopened: acts.reopen,
    workspaceBranch: core.git.branch,
    outcome: outcomeLabel(settlement),
    branch: null,
    commits: settlement.commits,
    logPath: null,
  });

  // One act, not two: a reopen carries its comment, so an issue never gets the
  // same paragraph twice.
  if (acts.reopen) {
    tracker.reopen(item.number, body);
    console.log(`  ↻ #${item.number} reopened — its work never reached ${core.git.branch}`);
  } else {
    tracker.comment(item.number, body);
    console.log(`  ✎ #${item.number} commented — its work never reached ${core.git.branch}`);
  }
}

function anchorOf(scope: WorkScopeSnapshot): { number: number; isSpec: boolean } | null {
  const anchor = scope.anchorNodeId === null ? undefined : issueByNodeId(scope, scope.anchorNodeId);
  return anchor ? { number: anchor.number, isSpec: anchor.labels.includes(SPEC) } : null;
}

/**
 * What the run leaves behind: the report, and the one label it is allowed to
 * write.
 *
 * The order matters and is the whole payoff. Every per-item reopen has already
 * landed by the time the anchor's condition is evaluated against **live** state,
 * so a drained SPEC with a rewound slice correctly goes unlabelled — and neither
 * rule had to know about the other.
 *
 * An aborted run reports and labels nothing.
 */
async function handOff(
  tracker: Tracker,
  core: RunCore,
  run: { records: readonly ItemRecord[]; aborted: string | null },
): Promise<void> {
  const anchor = anchorOf(core.scope);
  const report = runReport({
    anchor,
    records: run.records,
    selected: core.work.length,
    eligible: core.scope.executableNodeIds.length,
    aborted: run.aborted,
  });

  console.log(`\n${report}`);
  // The repository-wide scope gets no durable report: there is no anchor to
  // comment on, and an invented home would be worse than none.
  if (anchor) tracker.comment(anchor.number, report);

  if (run.aborted !== null) {
    // An unattended run that stopped on a changed contract did not do what it
    // was asked, and whatever launched it has to be able to tell.
    process.exitCode = 1;
    return;
  }

  const handoff = await core.issues.handoff();
  if (handoff === null || !deservesCodeReview(handoff)) return;
  tracker.addLabel(handoff.anchor.number, CODE_REVIEW);
  console.log(
    `\n  ✓ #${handoff.anchor.number} labelled \`${CODE_REVIEW}\` — every released slice is closed.`,
  );
}
