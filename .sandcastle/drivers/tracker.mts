// The side-effecting tracker edge: the three writes a run makes to GitHub, and
// the two moments a draining driver makes them.
//
// Every decision behind them is in `drivers/outcomes.mts`, which is pure — so
// this module has almost no branches of its own and one property worth
// asserting: **there are exactly three writes, and none of them closes an
// issue.** A runner that could close a SPEC would be making the judgment
// `docs/agents/triage-labels.md` reserves for a human, and a wrongly-closed SPEC
// is far harder to notice than a wrongly-labelled open one.
//
// It lives here rather than in `sequential.mts` because both draining drivers
// make the same two calls at the same two moments. What differs between them is
// only what they observed — a branch and a log path under `wave-parallel`, and
// neither under `sequential`, which works in place — so both arrive as values on
// one record instead of as a second copy of this file.
//
// `gh` subcommands, never REST paths: `scope/github.mts` is the module that owns
// the endpoint vocabulary, and a second module building a path of its own is
// exactly what the boundary sweep exists to catch.
//
// A failed write **warns and does not stop the run.** These are corrections to
// bookkeeping, and losing item seven's implement→review pair because a label
// write failed would trade the expensive thing for the cheap one. The warning
// lands in the run's own scrollback, so nothing here is silent.

import { execFileSync } from "node:child_process";
import {
  CODE_REVIEW,
  issueByNodeId,
  SPEC,
  type WorkItem,
  type WorkScopeSnapshot,
} from "../scope/snapshot.mts";
import type { RunCore } from "./core.mts";
import {
  correctionComment,
  deservesCodeReview,
  outcomeLabel,
  runReport,
  trackerActs,
  type ItemRecord,
  type Settlement,
  type TrackerActs,
} from "./outcomes.mts";

/**
 * What a run may do to an issue. Three methods, deliberately named for the acts
 * rather than for `gh` — a driver holding this cannot compose a fourth.
 */
export interface Tracker {
  /** `closed ∧ unmerged`: the work never reached the workspace branch. */
  reopen: (issueNumber: number, comment: string) => void;
  /** `commits ∧ unmerged`: name the branch the work actually lives on. */
  comment: (issueNumber: number, body: string) => void;
  /** The handoff, and the only label this runner ever writes. */
  addLabel: (issueNumber: number, label: string) => void;
}

function warn(act: string, issueNumber: number, error: unknown): void {
  const detail = error instanceof Error ? error.message.split("\n")[0] : String(error);
  console.log(`  ! could not ${act} #${issueNumber}: ${detail}`);
}

/** The real tracker: `gh`, with each write reported rather than thrown. */
export function ghTracker(): Tracker {
  const gh = (act: string, issueNumber: number, args: readonly string[]): void => {
    try {
      execFileSync("gh", [...args], { stdio: ["ignore", "ignore", "pipe"] });
    } catch (error) {
      warn(act, issueNumber, error);
    }
  };

  return {
    reopen: (issueNumber, comment) =>
      gh("reopen", issueNumber, ["issue", "reopen", String(issueNumber), "--comment", comment]),
    comment: (issueNumber, body) =>
      gh("comment on", issueNumber, ["issue", "comment", String(issueNumber), "--body", body]),
    addLabel: (issueNumber, label) =>
      gh("label", issueNumber, ["issue", "edit", String(issueNumber), "--add-label", label]),
  };
}

// ---------------------------------------------------------------------------
// Per item, at settle
// ---------------------------------------------------------------------------

/** One settled item, as the two acts read it. */
export interface Correction {
  readonly item: WorkItem;
  readonly settlement: Settlement;
  /** The issue's live state when the item settled. */
  readonly closed: boolean;
  /**
   * Did any of this item's work reach the workspace branch? A real `--no-ff`
   * merge under `wave-parallel`; simply *commits exist* under `sequential`,
   * which commits straight onto that branch.
   */
  readonly merged: boolean;
  readonly workspaceBranch: string;
  /** The item's own branch, or `null` when it worked in place. */
  readonly branch: string | null;
  readonly logPath: string | null;
}

/**
 * The two tracker acts for one settled item, on their different keys.
 *
 * **Per item at settle, not in an end-of-run sweep.** A broken merged tree
 * aborts the run, nothing is auto-cleaned on abort and there is no resume — so a
 * sweep would never execute in precisely the run that went worst. Per-item
 * correction is abort-safe by construction.
 *
 * Returns what it did rather than narrating it. The two drivers say it
 * differently — `sequential` writes a line of its own and `wave-parallel` folds
 * the reopen into its item line as a `↻ reopened` annotation — and a module that
 * printed for both would force one of them to print twice.
 */
export function correctItem(tracker: Tracker, correction: Correction): TrackerActs {
  const acts = trackerActs({
    closed: correction.closed,
    commits: correction.settlement.commits,
    merged: correction.merged,
  });
  if (!acts.reopen && !acts.comment) return acts;

  const body = correctionComment({
    reopened: acts.reopen,
    workspaceBranch: correction.workspaceBranch,
    outcome: outcomeLabel(correction.settlement),
    branch: correction.branch,
    commits: correction.settlement.commits,
    logPath: correction.logPath,
  });

  // One act, not two: a reopen carries its comment, so an issue never gets the
  // same paragraph twice.
  if (acts.reopen) tracker.reopen(correction.item.number, body);
  else tracker.comment(correction.item.number, body);
  return acts;
}

// ---------------------------------------------------------------------------
// Once, at end of run
// ---------------------------------------------------------------------------

/** What the run has to say for itself. */
export interface RunOutcome {
  /** One per item the run reached, in run order. */
  readonly records: readonly ItemRecord[];
  /** Why the run stopped before its list ran out, when it did. */
  readonly aborted: string | null;
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
export async function handOff(
  tracker: Tracker,
  core: RunCore,
  run: RunOutcome,
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

  // The one GitHub read whose failure must not throw. Everything this run was
  // launched to do has already happened and its report is already printed, so
  // surfacing a rate limit here as a run failure would misreport a completed
  // run — and the label is a handoff to a human who can add it themselves.
  let handoff;
  try {
    handoff = await core.issues.handoff();
  } catch (error) {
    warn("read the handoff state for", anchor?.number ?? 0, error);
    return;
  }

  if (handoff === null || !deservesCodeReview(handoff)) return;
  tracker.addLabel(handoff.anchor.number, CODE_REVIEW);
  console.log(
    `\n  ✓ #${handoff.anchor.number} labelled \`${CODE_REVIEW}\` — every released slice is closed.`,
  );
}
