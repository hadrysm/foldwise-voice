// What a draining run decides when something goes wrong, and how it says so.
//
// Pure over the snapshot and over what the driver observed — no git, no `gh`, no
// clock. That split is the point: every rule below is a rule about *judgment*,
// and the three `gh` calls that act on these decisions live in
// `drivers/tracker.mts` where they can be counted rather than reasoned about.
//
// Three rules run through the whole module:
//
//   1. **Every stop condition turns on one question: does the foundation
//      exist?** An item that produced no commits, crashed, timed out or was
//      rewound at fan-in leaves nothing to build on, so everything `blocked_by`
//      it goes with it. A bounce leaves working code that was judged incomplete,
//      so its dependents proceed. That asymmetry is deliberate.
//   2. **The driver observes; the body testifies to nothing.** Every value here
//      is derived from git, the process or GitHub. A workflow that could report
//      its own outcome would hold the transitive skip set.
//   3. **No skip is ever silent.** Every drop carries the reason it was dropped,
//      and every reason reaches the report — a run that quietly shrinks its own
//      list is a run that lies about what it did.

import type { Revalidation } from "../scope/github.mts";
import {
  blockersWithin,
  issueByNodeId,
  READY_FOR_AGENT,
  RUN_REPORT_MARKER,
  SPEC,
  type HandoffState,
  type WorkItem,
  type WorkScopeSnapshot,
} from "../scope/snapshot.mts";

// ---------------------------------------------------------------------------
// Two-phase outcomes
// ---------------------------------------------------------------------------

/**
 * What became of one item's implement→review loop, known the moment it settles.
 */
export type LoopOutcome = "committed" | "no-commits" | "crashed" | "timed-out";

/**
 * What became of a committed item's branch at fan-in. Exists only for a
 * `committed` item and only under a driver that has a fan-in phase at all.
 *
 * Two phases rather than one flat enum, because one flat enum makes
 * `{ outcome: "merged" }` representable for an item that timed out.
 */
export type MergeOutcome = "merged" | "conflict-rewound" | "skipped-upstream";

/**
 * One item's settled state.
 *
 * `bounced` is an annotation, never an outcome: it merges like a success and its
 * dependents proceed, and it changes only the report. Listing it beside
 * `crashed` would imply a structural consequence it explicitly does not have.
 */
export interface Settlement {
  readonly loop: LoopOutcome;
  /**
   * `null` on a driver with no fan-in — the sequential driver commits straight
   * onto the workspace branch — and on any item that never committed.
   */
  readonly merge: MergeOutcome | null;
  /** From `git rev-list --count`, never from the workflow. */
  readonly commits: number;
  /** The item's issue was open when it settled, re-read from live GitHub. */
  readonly bounced: boolean;
}

/**
 * Did this item leave its dependents something to build on?
 *
 * The one question every stop condition turns on. A merge phase that did not
 * merge is as empty as a loop that did not commit — slice 4 is never implemented
 * on slice 3's rewound foundation.
 */
export function foundationExists(settlement: Settlement): boolean {
  if (settlement.loop !== "committed") return false;
  return settlement.merge !== "conflict-rewound" && settlement.merge !== "skipped-upstream";
}

/** How the report and the tracker comment both name one settled item. */
export function outcomeLabel(settlement: Settlement): string {
  switch (settlement.loop) {
    case "no-commits":
      return "no commits";
    case "crashed":
      return "crashed";
    case "timed-out":
      return "timed out";
    case "committed":
      break;
  }
  switch (settlement.merge) {
    case "conflict-rewound":
      return "conflict rewound";
    case "skipped-upstream":
      return "not merged, upstream missing";
    default:
      return settlement.bounced ? "bounced" : "completed";
  }
}

// ---------------------------------------------------------------------------
// The branch one item's commits land on
// ---------------------------------------------------------------------------

/**
 * The namespace every branch a run cuts lives in, and the one the workspace
 * preflight refuses to start a run over a leftover of.
 *
 * One definition rather than two matching literals: the branch a driver cuts
 * and the branch the next run's `prepare()` refuses are the same fact, and a
 * rename that reached only one of them would leave a run unable to see its own
 * leftovers.
 */
export const SANDCASTLE_BRANCH_PREFIX = "sandcastle/";

/** How much of the title a branch name carries. */
const SLUG_LIMIT = 48;

/**
 * `sandcastle/<issue-number>-<slug>`, composed by the runner from the frozen
 * snapshot's title.
 *
 * Deterministic and never negotiated: the Planner carries numbers only, so
 * nothing a model returns can name, widen or redirect a branch. The number
 * leads because it is the part that has to survive truncation — the slug is
 * there for the human reading `git log --merges`, and a merge commit that named
 * only a slug would be a merge commit nobody could trace back to an issue.
 */
export function itemBranch(item: { readonly number: number; readonly title: string }): string {
  const words = item.title
    .toLowerCase()
    // Apostrophes close rather than separate, so `driver's` is one word.
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  // Cut on a word boundary when there is one, so a truncated branch reads as
  // words rather than ending mid-syllable.
  const cut = words.length > SLUG_LIMIT ? words.slice(0, SLUG_LIMIT) : words;
  const boundary = words.length > SLUG_LIMIT ? cut.lastIndexOf("-") : -1;
  const slug = (boundary > 0 ? cut.slice(0, boundary) : cut).replace(/-+$/, "");
  return `${SANDCASTLE_BRANCH_PREFIX}${item.number}${slug ? `-${slug}` : ""}`;
}

// ---------------------------------------------------------------------------
// What the run records about one item
// ---------------------------------------------------------------------------

export type ItemOutcome =
  | ({ readonly kind: "settled" } & Settlement)
  /** Never dispatched, because a foundation it is `blocked_by` went missing. */
  | { readonly kind: "skipped"; readonly reason: string }
  /** Never dispatched, because the tracker moved under the run. */
  | { readonly kind: "drift"; readonly detail: string };

export interface ItemRecord {
  readonly item: WorkItem;
  readonly outcome: ItemOutcome;
  /** The branch this item's work lives on, or `null` when it worked in place. */
  readonly branch: string | null;
}

// ---------------------------------------------------------------------------
// The transitive skip
// ---------------------------------------------------------------------------

/** One item this run will not reach, and the foundation it lost. */
export interface Cascaded {
  readonly nodeId: string;
  /** Report-ready, e.g. `depends on #420`. */
  readonly reason: string;
}

/**
 * Everything `failed` takes down with it, in the order the run would have
 * reached it, and never anything already skipped.
 *
 * The provenance is the whole reason this is not `transitiveSkip`'s set: a
 * report that says *#422 skipped* teaches nothing, and a report that says
 * *#422 depends on #421* is the difference between a record and a shrug.
 *
 * `failed` itself is not returned — the caller already knows what it observed,
 * and recording it twice would double-count it in the report.
 */
export function cascade(
  snapshot: WorkScopeSnapshot,
  failed: string,
  skipped: ReadonlySet<string>,
): readonly Cascaded[] {
  const within = new Set(snapshot.executableNodeIds);
  const dependents = new Map<string, string[]>();
  for (const nodeId of snapshot.executableNodeIds) {
    for (const blocker of blockersWithin(snapshot, nodeId, within)) {
      const existing = dependents.get(blocker);
      if (existing) existing.push(nodeId);
      else dependents.set(blocker, [nodeId]);
    }
  }

  // Breadth-first, so a dependent is reported against the nearest foundation it
  // lost rather than against whatever the walk reached last.
  const seen = new Set<string>([...skipped, failed]);
  const out: Cascaded[] = [];
  const queue = [failed];

  for (let head = 0; head < queue.length; head += 1) {
    const blocker = queue[head] as string;
    for (const dependent of dependents.get(blocker) ?? []) {
      if (seen.has(dependent)) continue;
      seen.add(dependent);
      out.push({
        nodeId: dependent,
        reason: `depends on #${issueByNodeId(snapshot, blocker)?.number ?? "?"}`,
      });
      queue.push(dependent);
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// Mid-run drift
// ---------------------------------------------------------------------------

/**
 * What a run does about a pre-dispatch mismatch. Three actions, because the
 * three mismatches mean different things about the foundation — and an abort
 * outranks a skip, so a run whose controlling contract is gone never reports a
 * per-item cause instead.
 */
export type DriftAction = "abort-run" | "skip-item" | "skip-transitively";

/**
 * #394's drift table, by cause:
 *
 * - **item closed** — someone did the work, so the foundation exists and only
 *   this item is dropped.
 * - **item deregulated** — the work will not happen, so nothing may be built on
 *   it either.
 * - **anchor changed** — the contract the whole run serves is gone, and there is
 *   no per-item answer to give.
 */
export function driftAction(status: Exclude<Revalidation["status"], "ok">): DriftAction {
  switch (status) {
    case "anchor-changed":
      return "abort-run";
    case "item-closed":
      return "skip-item";
    case "item-deregulated":
      return "skip-transitively";
  }
}

// ---------------------------------------------------------------------------
// The tracker corrections
// ---------------------------------------------------------------------------

/**
 * What the two acts are decided from. `merged` is the driver's reading of *did
 * any of this reach the workspace branch* — a real `--no-ff` merge under
 * wave-parallel, and simply *commits exist* under sequential, which works in
 * place.
 */
export interface SettledFacts {
  /** The issue's live state when the item settled. */
  readonly closed: boolean;
  readonly commits: number;
  readonly merged: boolean;
}

export interface TrackerActs {
  readonly reopen: boolean;
  readonly comment: boolean;
}

/**
 * The two acts, on **different keys**.
 *
 * The defect is a predicate, never an outcome: *closed, yet nothing of this item
 * reached the workspace branch.* The discriminator that would make it an outcome
 * — did the implementer reach its close step — is exactly what the driver cannot
 * observe, and the contract forbids asking the workflow.
 *
 * The split is forced by the **bounced-and-rewound** item: already open, so no
 * reopen fires, and its branch would otherwise be named in no durable place at
 * all. A **merged-but-bounced** item gets neither act — open claims *unfinished*,
 * which is exactly the reviewer's ruling, and it never claimed no code exists.
 */
export function trackerActs(facts: SettledFacts): TrackerActs {
  const unmerged = !facts.merged;
  return { reopen: facts.closed && unmerged, comment: facts.commits > 0 && unmerged };
}

export interface CorrectionComment {
  /** Whether this comment rides on a `gh issue reopen`. */
  readonly reopened: boolean;
  readonly workspaceBranch: string;
  /** From `outcomeLabel`, so the comment and the report cannot disagree. */
  readonly outcome: string;
  readonly branch: string | null;
  readonly commits: number;
  readonly logPath: string | null;
}

/**
 * The human-facing comment a correction leaves behind.
 *
 * Carries the run-report marker, so normalization drops it and no later agent
 * reads it: `prepare()` guarantees a human cleared that branch before any later
 * agent could act on the item, which makes the branch it names **stale by
 * construction** — handing a worktree-sealed implementer a dangling reference
 * and a reason to reach outside would be worse than saying nothing.
 */
export function correctionComment(input: CorrectionComment): string {
  const opening = input.reopened
    ? `Reopened by Sandcastle — this item's work never reached \`${input.workspaceBranch}\`.`
    : `Sandcastle left this item's work outside \`${input.workspaceBranch}\`.`;

  const lines = [`Outcome:  ${input.outcome}`];
  if (input.branch !== null) {
    const plural = input.commits === 1 ? "" : "s";
    lines.push(`Branch:   ${input.branch}  (${input.commits} commit${plural}, unmerged)`);
  }
  if (input.logPath !== null) lines.push(`Log:      ${input.logPath}`);

  const closing =
    input.branch === null
      ? `Nothing from this item reached \`${input.workspaceBranch}\`, so there is no branch to salvage — the work is still to do.`
      : [
          "The branch and its worktree are kept, and no force flag is used anywhere, so",
          "nothing here can be destroyed by the run. `prepare()` will refuse the next run",
          "until they are merged, salvaged or removed.",
        ].join("\n");

  return [RUN_REPORT_MARKER, opening, "", ...lines, "", closing].join("\n");
}

// ---------------------------------------------------------------------------
// The handoff
// ---------------------------------------------------------------------------

/**
 * Whether this run drained the anchor, evaluated against **live** state.
 *
 * Three conditions, and no special case for anything: a truncated list leaves
 * descendants open, and a bounce reopened its issue, so both simply fail the
 * last one. That is also what makes the payoff self-enforcing — every reopen
 * lands before this is asked, so a drained SPEC with a rewound slice correctly
 * goes unlabelled, and neither rule knows about the other.
 *
 * There is no fourth condition closing the SPEC. That judgment has twice been a
 * deliberate human call on this tracker, and a wrongly-closed SPEC is far harder
 * to notice than a wrongly-labelled open one.
 */
export function deservesCodeReview(state: HandoffState | null): boolean {
  if (state === null) return false;
  if (state.anchor.state !== "open") return false;
  if (!state.anchor.labels.includes(SPEC)) return false;
  return state.descendants
    .filter((descendant) => descendant.labels.includes(READY_FOR_AGENT))
    .every((descendant) => descendant.state === "closed");
}

// ---------------------------------------------------------------------------
// The report
// ---------------------------------------------------------------------------

export interface RunReportInput {
  /** The anchor this run served, or `null` under a repository-wide scope. */
  readonly anchor: { readonly number: number; readonly isSpec: boolean } | null;
  /** One per item the run reached, in run order. */
  readonly records: readonly ItemRecord[];
  /** How many items the run guard handed over. */
  readonly selected: number;
  /** How many the scope made eligible, before the guard cut the list. */
  readonly eligible: number;
  /** Why the run stopped before its list ran out, when it did. */
  readonly aborted: string | null;
}

/** Wide enough for `completed`, which is the longest label a row carries. */
const LABEL_WIDTH = 11;
/** Wide enough for the run guard's ceiling of 50. */
const COUNT_WIDTH = 2;

function row(label: string, count: number, detail: readonly string[]): string {
  const heading = `  ${label.padEnd(LABEL_WIDTH)}${String(count).padEnd(COUNT_WIDTH)}`;
  return (detail.length === 0 ? heading : `${heading} ${detail.join("; ")}`).trimEnd();
}

/**
 * What the run did, as one screen.
 *
 * Goes to stdout on every run and, when there is an anchor, as one comment on
 * it — marker-first, so the fifth run of one SPEC does not read four previous
 * run reports as evidence about the work. The repository-wide scope gets no
 * durable report, because there is no anchor to comment on.
 *
 * Zero rows are omitted rather than printed as `0`, with one exception:
 * `completed` always appears, because a run that completed nothing has to say so
 * in the same place a run that completed everything does.
 *
 * **The rows are not a partition and are not meant to sum.** A bounce is an
 * annotation rather than an outcome, so an item that bounced *and* was rewound
 * at fan-in is named on both lines — which is what it was. Making them sum would
 * mean choosing one of two true things to hide.
 */
export function runReport(input: RunReportInput): string {
  const settled = input.records.flatMap((record) =>
    record.outcome.kind === "settled" ? [{ record, settlement: record.outcome }] : [],
  );
  const completed = settled.filter(
    ({ settlement }) => foundationExists(settlement) && !settlement.bounced,
  );
  const bounced = settled.filter(({ settlement }) => settlement.bounced);
  // Everything that did not land, whether it ran and produced nothing or never
  // ran because something it depends on produced nothing.
  const lost = input.records.flatMap((record) => {
    if (record.outcome.kind === "skipped") {
      return [`#${record.item.number} ${record.outcome.reason}`];
    }
    if (record.outcome.kind === "settled" && !foundationExists(record.outcome)) {
      return [`#${record.item.number} ${outcomeLabel(record.outcome)}`];
    }
    return [];
  });
  const drift = input.records.flatMap((record) =>
    record.outcome.kind === "drift" ? [record.outcome.detail] : [],
  );

  const subject =
    input.anchor === null
      ? ""
      : `${input.anchor.isSpec ? "SPEC " : ""}#${input.anchor.number}, `;

  const lines = [
    RUN_REPORT_MARKER,
    `Run summary — ${subject}${input.selected} of ${input.eligible} eligible`,
  ];
  // The abort leads, and it counts what it cost: the items the run never
  // reached exist only because it stopped, so they are that line's number
  // rather than a row of their own.
  if (input.aborted !== null) {
    lines.push(row("aborted", input.selected - input.records.length, [input.aborted]));
  }
  lines.push(row("completed", completed.length, []));
  if (bounced.length) {
    lines.push(
      row(
        "bounced",
        bounced.length,
        bounced.map(({ record }) => `#${record.item.number}`),
      ),
    );
  }
  if (lost.length) lines.push(row("skipped", lost.length, lost));
  if (drift.length) lines.push(row("drift", drift.length, drift));

  const excluded = input.eligible - input.selected;
  if (excluded > 0) lines.push(row("excluded", excluded, ["truncated by the run guard"]));

  return lines.join("\n");
}
