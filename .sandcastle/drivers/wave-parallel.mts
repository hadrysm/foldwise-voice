// A wave at a time, each item alone in a worktree cut from the workspace
// branch's current tip.
//
// The shape, and why each piece is where it is:
//
//   **A wave is a level, narrowed.** `levels()` says what *could* run together;
//   a wave is what actually does. Levels are never frozen — they are recomputed
//   from `(pending, accumulated skip set)` at every wave boundary, because a
//   transitive skip shrinks what is ready, and a frozen level would dispatch a
//   dependent onto a foundation that was never laid. Slice 9 puts a Planner in
//   front of the narrowing; until then the wave is the first `MAX_PARALLEL` of
//   the ready level, which is also the fallback a bad plan lands on.
//
//   **Wave size *is* concurrency.** No semaphore drains a wider plan through a
//   narrower gate: that would let two items the Planner deliberately separated
//   overlap anyway, which is the one power it has.
//
//   **The driver observes; the body testifies to nothing.** Committed or not is
//   `git rev-list`, crashed is a rejected promise `allSettled` caught, timed out
//   is this driver's own `AbortSignal`, merged or rewound is `git merge`'s exit
//   code, and bounced is the issue re-read from live GitHub. The body returns
//   `void` and is believed about nothing.
//
//   **Fan-in is the runner's; verification is the prompt's.** This module keeps
//   only what git gives it free — merging, conflict detection from an exit code,
//   the rewind, cleanup and the timeout. Whether the merged tree *builds* is a
//   question whose answer has to be interpreted and repaired, which is judgment,
//   and it belongs to the Merger in slice 9. No toolchain command reaches here.
//
//   **A conflict rewinds one item; a broken tree aborts the run.** The asymmetry
//   is attribution: a conflict belongs to exactly one branch, and a tree that
//   merges cleanly and then fails to build is a semantic conflict this driver
//   cannot attribute to anybody.
//
// Cleanup is merge-gated and self-enforcing. **No `--force`, `-D` or `-f`
// appears in this file or in `drivers/git.mts`** — git itself refuses to remove
// a dirty worktree or delete an unmerged branch, so a refusal becomes a line in
// the report rather than destroyed work. Nothing is ever auto-cleaned on abort,
// and there is no resume.

import type { Workflow } from "../contract.mts";
import { levels, type WorkItem } from "../scope/snapshot.mts";
import type { ItemWorktree, RunCore } from "./core.mts";
import { waveGit } from "./git.mts";
import {
  cascade,
  driftAction,
  foundationExists,
  itemBranch,
  outcomeLabel,
  type ItemOutcome,
  type ItemRecord,
  type LoopOutcome,
  type MergeOutcome,
  type Settlement,
} from "./outcomes.mts";
import { correctItem, ghTracker, handOff, type Tracker } from "./tracker.mts";

/** What the driver needs that is neither the run's core nor its workflow. */
export interface WaveDeps {
  /**
   * The workspace repo this run merges into.
   *
   * Explicit rather than `process.cwd()` and honest rather than test-only: this
   * driver operates on *the workspace repo*, and saying so is what lets its
   * suite point real git at a disposable one — which is the only way the three
   * claims #404 rests on get asserted against git rather than against a fake
   * written by whoever wrote the assumption.
   */
  readonly repoRoot: string;
  readonly tracker: Tracker;
}

export function driveWaveParallel(core: RunCore, workflow: Workflow): Promise<void> {
  return driveWaveParallelWith(core, workflow, {
    repoRoot: process.cwd(),
    tracker: ghTracker(),
  });
}

/** One item's attempt, from the branch it was given to what git said about it. */
interface Attempt {
  readonly item: WorkItem;
  readonly branch: string;
  /** Fires at `repo.itemTimeout`, and is how `timed out` is told from `crashed`. */
  readonly signal: AbortSignal;
  worktree: ItemWorktree | null;
}

export async function driveWaveParallelWith(
  core: RunCore,
  workflow: Workflow,
  deps: WaveDeps,
): Promise<void> {
  const git = waveGit(deps.repoRoot);
  const records = new Map<string, ItemRecord>();
  const skipped = new Set<string>();
  // Everything the run has an answer about, settled or drifted. Membership is
  // frozen, so this only ever grows and the total never shrinks.
  const answered = new Set<string>();
  const total = core.work.length;
  const timeoutMs = Math.round(core.repo.itemTimeout.minutes * 60_000);
  let aborted: string | null = null;
  let waveNumber = 0;

  const record = (item: WorkItem, outcome: ItemOutcome, branch: string | null): void => {
    records.set(item.nodeId, { item, outcome, branch });
    answered.add(item.nodeId);
  };

  /**
   * Drop everything this failure takes down with it, transitively. Independent
   * items are untouched, and **a skip never backfills** — item eleven is not
   * promoted when item three is skipped, because the list was cut before the
   * run began.
   */
  const dropDependents = (failed: WorkItem): void => {
    for (const drop of cascade(core.scope, failed.nodeId, skipped)) {
      skipped.add(drop.nodeId);
      const item = core.work.find((candidate) => candidate.nodeId === drop.nodeId);
      // A dependent the run guard already cut is skipped without being reported:
      // it was never part of this run to begin with.
      if (!item) continue;
      record(item, { kind: "skipped", reason: drop.reason }, null);
      console.log(`  ↷ #${item.number} skipped — ${drop.reason}`);
    }
    skipped.add(failed.nodeId);
  };

  while (aborted === null) {
    const pending = core.work.filter(
      (item) => !answered.has(item.nodeId) && !skipped.has(item.nodeId),
    );
    if (pending.length === 0) break;

    // Recomputed here and nowhere else: wave one's items left `pending` when
    // they merged, which is precisely what makes their dependents ready.
    const [ready = []] = levels(core.scope, pending, skipped);
    const wave: Attempt[] = [];

    for (const item of ready.slice(0, core.maxParallel)) {
      const check = await core.issues.revalidate(item);
      if (check.status === "ok") {
        wave.push({
          item,
          branch: itemBranch(item),
          signal: AbortSignal.timeout(timeoutMs),
          worktree: null,
        });
        continue;
      }
      const action = driftAction(check.status);
      if (action === "abort-run") {
        // The controlling contract is gone, so there is no per-item answer to
        // give — and nothing is cleaned up, because nothing is ever cleaned up
        // on an abort.
        aborted = check.detail;
        console.log(`\n✖ Aborting the run — ${check.detail}`);
        break;
      }
      console.log(`\n· #${item.number} — drift: ${check.detail}`);
      record(item, { kind: "drift", detail: check.detail }, null);
      if (action === "skip-transitively") dropDependents(item);
    }

    if (aborted !== null) break;
    // Every candidate drifted away. The next pass recomputes the level against
    // the grown skip set rather than treating an empty wave as an empty run.
    if (wave.length === 0) continue;

    waveNumber += 1;
    // Read once, before anything is dispatched: every worktree in this wave is
    // cut from it, and every item's commits are counted against it.
    const waveBase = core.git.headSha();
    console.log(
      `\n=== wave ${waveNumber} · ${wave.map((attempt) => `#${attempt.item.number}`).join(", ")} ===\n`,
    );

    // A failure interrupts no sibling. `allSettled` is what makes a partial wave
    // ordinary rather than exceptional — the survivors merge and the run goes on.
    const outcomes = await Promise.allSettled(
      wave.map(async (attempt) => {
        const worktree = await core.openWorktree(attempt.item, attempt.branch, attempt.signal);
        attempt.worktree = worktree;
        // The dispatch already *is* this item; the body is handed the item to
        // read and can neither name another nor learn that a sibling exists.
        await workflow.run({ item: attempt.item, dispatch: worktree.dispatch });
      }),
    );

    // Fan-in, in **run order** rather than completion order. Without it the
    // merge commits are ordered by whichever agent happened to finish first, and
    // they are the only per-item boundary in an otherwise flat diff.
    for (const [index, attempt] of wave.entries()) {
      const { settlement, closed } = await settle(attempt, outcomes[index], waveBase);
      record(attempt.item, { kind: "settled", ...settlement }, attempt.branch);
      console.log(`  · #${attempt.item.number} ${outcomeLabel(settlement)}`);

      correctItem(deps.tracker, {
        item: attempt.item,
        settlement,
        closed,
        merged: settlement.merge === "merged",
        workspaceBranch: core.git.branch,
        branch: attempt.branch,
        logPath: attempt.worktree?.logPath ?? null,
      });

      cleanUp(attempt, settlement.merge === "merged");
      if (!foundationExists(settlement)) dropDependents(attempt.item);
      console.log(`  ${answered.size}/${total} settled`);
    }
  }

  await handOff(deps.tracker, core, {
    records: core.work.flatMap((item) => records.get(item.nodeId) ?? []),
    aborted,
  });

  /**
   * What became of one item, from git, the process and GitHub — never from the
   * body, which returned `void`.
   *
   * Two phases rather than one flat enum: a `LoopOutcome` the moment the item
   * settles, then a `MergeOutcome` for a committed item only, so
   * `{ merge: "merged" }` is not representable for an item that timed out.
   */
  async function settle(
    attempt: Attempt,
    outcome: PromiseSettledResult<void> | undefined,
    waveBase: string,
  ): Promise<{ readonly settlement: Settlement; readonly closed: boolean }> {
    let loop: LoopOutcome = "committed";
    if (outcome?.status === "rejected") {
      // The signal is the discriminator, and it has to be: a hang is not
      // evidence about the work item, and every stop condition turns on *does
      // the foundation exist* — which a timeout answers neither way.
      loop = attempt.signal.aborted ? "timed-out" : "crashed";
      const detail =
        outcome.reason instanceof Error ? outcome.reason.message : String(outcome.reason);
      const label = loop === "timed-out" ? "timed out" : "crashed";
      console.log(`  ✖ #${attempt.item.number} ${label}: ${detail}`);
    }

    const commits = git.commitsOn(attempt.branch, waveBase);
    if (loop === "committed" && commits === 0) loop = "no-commits";

    let merge: MergeOutcome | null = null;
    if (loop === "committed") {
      const attempted = git.merge(attempt.branch);
      merge = attempted.kind === "merged" ? "merged" : "conflict-rewound";
      if (attempted.kind === "conflict-rewound") {
        const where = attempted.paths.join(", ") || "the merge itself";
        console.log(`  ⤺ #${attempt.item.number} rewound — ${attempt.branch} conflicts on ${where}`);
      }
    }

    const live = await core.issues.liveState(attempt.item);
    return {
      settlement: {
        loop,
        merge,
        commits,
        // The reviewer reopens what it judges incomplete, so an item whose
        // issue is open once its loop has finished was bounced. A bounce is an
        // annotation, never an outcome: it merges and its dependents proceed.
        bounced: loop === "committed" && live.state === "open",
      },
      closed: live.state === "closed",
    };
  }

  /**
   * A merged item's worktree and branch go; everything else stays.
   *
   * `#407`'s *"no worktree is ever removed"* narrows to **"no unmerged worktree
   * is ever removed"** — the property it was actually protecting. A merged
   * item's commits are provably on the workspace branch, so its worktree is a
   * copy rather than work; ten items across three runs is otherwise thirty
   * worktrees carrying a build directory each.
   *
   * Both steps are attempted and neither is forced, so git is what decides. A
   * refusal is reported and never thrown: the run has already done the
   * expensive part, and a leftover is what `prepare()` refuses the *next* run
   * over.
   */
  function cleanUp(attempt: Attempt, merged: boolean): void {
    if (!merged || !attempt.worktree) return;

    const removed = git.removeWorktree(attempt.worktree.path);
    if (!removed.ok) console.log(`  ! kept ${attempt.worktree.path} — ${removed.detail}`);
    const deleted = git.deleteBranch(attempt.branch);
    if (!deleted.ok) console.log(`  ! kept ${attempt.branch} — ${deleted.detail}`);
  }
}
