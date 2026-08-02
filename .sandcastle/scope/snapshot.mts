// The pure half of Work scope: what a run is allowed to touch, in what order,
// and what one failure takes down with it.
//
// No I/O of any kind — this module imports `node:crypto` and nothing else. That
// is the same split `resolveAgents`/`validateModels` already draws: fetching is
// side-effecting and lives in `scope/github.mts`; everything downstream is pure
// over a snapshot value. It is also what makes the map's biggest untested
// surface testable, because a tree of dependency edges can be written down as a
// literal while a GitHub response can only be recorded.
//
// Three rules run through the whole module and are worth stating once:
//
//   1. **Membership is frozen; eligibility only narrows the allow-list.** An
//      excluded node stays visible with its reason so the picker can say what it
//      is not running. Nothing is ever dropped from the tree.
//   2. **An in-scope open blocker is a precedence edge, not an exclusion.** Only
//      a blocker this run will never reach still excludes. Without that rule a
//      `blocked_by`-chained SPEC resolves to exactly one eligible descendant per
//      run, and waves cannot exist (#394).
//   3. **The runner owns the edges.** `WorkItem` here is identity only, so
//      nothing downstream of the runner can compute a skip, a level or an order
//      for itself — it has to ask this module, holding the snapshot.

import { createHash } from "node:crypto";

/** Releases an issue for unattended work. */
export const READY_FOR_AGENT = "ready-for-agent";
/** Always wins over `ready-for-agent`: this one is a human's. */
export const READY_FOR_HUMAN = "ready-for-human";
/** Marks a SPEC. Only a Specific SPEC target requires it. */
export const SPEC = "spec";
/**
 * The first line of every comment a run writes about itself. Normalization drops
 * any comment carrying it, so the fifth run of one SPEC does not read four
 * previous run reports as evidence about the work (#394).
 */
export const RUN_REPORT_MARKER = "<!-- sandcastle-run-report -->";

// ---------------------------------------------------------------------------
// Work scope
// ---------------------------------------------------------------------------

/**
 * What the maintainer chose, before GitHub has seen it. `target` is the raw
 * string they typed — a bare number or a URL — because parsing it is the
 * resolver's job and a scope that pre-parses would have two ways to be wrong.
 *
 * Kind literals are kebab-case throughout. Nothing external consumes them, and
 * two spellings for one concept is a defect waiting for a mismatched `switch`.
 */
export type WorkScope =
  | { readonly kind: "specific-spec"; readonly target: string }
  | { readonly kind: "specific-issue"; readonly target: string }
  | { readonly kind: "all-ready-for-agent" };

export type ScopeKind = WorkScope["kind"];

// ---------------------------------------------------------------------------
// The normalized issue
// ---------------------------------------------------------------------------

/**
 * Why an issue is in the tree but not in the allow-list. Retained in this fixed
 * precedence order when more than one applies, so a handoff report reads the
 * same way twice.
 */
export type ExclusionReason = "closed" | "ready-for-human" | "unreleased" | "blocked";

const REASON_PRECEDENCE: readonly ExclusionReason[] = [
  "closed",
  "ready-for-human",
  "unreleased",
  "blocked",
];

export interface IssueComment {
  readonly databaseId: number;
  readonly nodeId: string;
  /** Null rather than absent: a deleted account stays representable. */
  readonly authorLogin: string | null;
  readonly body: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

/**
 * A blocker's identity. Only *open* blockers are ever carried:
 * `/dependencies/blocked_by` returns closed relationships too, so relationship
 * presence is not the gate — the fetch layer filters on state before this
 * module sees anything.
 *
 * A blocker may live outside the repository. That is valid as a gate even
 * though it can never be work, which is exactly the "outside the set" case.
 */
export interface BlockerRef {
  readonly nodeId: string;
  readonly repository: string;
  readonly number: number;
  readonly url: string;
  readonly title: string;
}

/**
 * One issue as the fetch layer hands it over: identity, content and native
 * edges, with no judgment applied yet.
 */
export interface IssueRecord {
  readonly databaseId: number;
  readonly nodeId: string;
  readonly number: number;
  readonly repository: string;
  readonly url: string;
  readonly title: string;
  readonly body: string;
  readonly state: "open" | "closed";
  readonly stateReason: string | null;
  /** Lexically sorted by `normalizeIssue`. */
  readonly labels: readonly string[];
  readonly updatedAt: string;
  /** Marker-filtered and sorted by ascending id by `normalizeIssue`. */
  readonly comments: readonly IssueComment[];
  readonly parentNodeId: string | null;
  /**
   * Authored sub-issue order, never sorted. GitHub's reprioritise endpoint
   * edits this list, which is what makes it the one signal carrying maintainer
   * intent — an issue number is only creation time.
   */
  readonly childNodeIds: readonly string[];
  readonly openBlockers: readonly BlockerRef[];
}

export type Eligibility =
  | { readonly status: "eligible" }
  | { readonly status: "excluded"; readonly reasons: readonly ExclusionReason[] };

/** A normalized issue, plus what this scope makes of it. */
export interface IssueSnapshot extends IssueRecord {
  /** The target itself, or something the walk found below it. */
  readonly role: "anchor" | "work-item";
  readonly eligibility: Eligibility;
}

/**
 * The frozen result of resolving one Work scope. `memberNodeIds` is the complete
 * visible tree; `executableNodeIds` is the only allow-list an agent may ever be
 * dispatched against, and nothing widens it for the life of the run.
 */
export interface WorkScopeSnapshot {
  readonly schemaVersion: 1;
  readonly repository: string;
  readonly scopeKind: ScopeKind;
  readonly anchorNodeId: string | null;
  readonly memberNodeIds: readonly string[];
  readonly executableNodeIds: readonly string[];
  readonly issues: readonly IssueSnapshot[];
  readonly snapshotId: `sha256:${string}`;
}

/** What the fetch layer assembled, before any of it was judged. */
export interface SnapshotInput {
  readonly scopeKind: ScopeKind;
  readonly repository: string;
  readonly anchorNodeId: string | null;
  readonly issues: readonly IssueRecord[];
}

/**
 * One item in run order. Identity only, deliberately: a driver holding this
 * cannot see a dependency edge, so it cannot compute its own skip set, its own
 * levels or its own order — the fourth instance of ADR-0010's rule that a
 * component able to read something will eventually branch on it.
 *
 * Not the `WorkItem` ADR-0010 once put on `DispatchOptions`; that type is gone.
 * A driver hands this to the body it invokes, to *read* — but never to
 * `dispatch`, which takes no work item at all.
 */
export interface WorkItem {
  readonly nodeId: string;
  readonly number: number;
  readonly title: string;
  readonly url: string;
}

/** An order, or the cycle that made one impossible. */
export type RunOrder =
  | { readonly ok: true; readonly items: readonly WorkItem[] }
  /** The issue numbers on the cycle, in the order the walk found them. */
  | { readonly ok: false; readonly cycle: readonly number[] };

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

function carriesRunReportMarker(comment: IssueComment): boolean {
  return comment.body.split("\n", 1)[0]?.trim() === RUN_REPORT_MARKER;
}

/**
 * One issue in its canonical form. Two orderings are imposed and one is
 * deliberately left alone: labels sort lexically and comments sort by ascending
 * id so the digest is a function of the state rather than of the fetch, while
 * `childNodeIds` keeps GitHub's authored order because that order *is* the
 * maintainer's priority.
 *
 * The marker filter is a content filter over pages that were fetched
 * successfully. It is never a tolerance for a page that failed — an API failure
 * is not an empty comment list.
 */
export function normalizeIssue(record: IssueRecord): IssueRecord {
  return {
    ...record,
    labels: [...record.labels].sort(),
    comments: record.comments
      .filter((comment) => !carriesRunReportMarker(comment))
      .sort((left, right) => left.databaseId - right.databaseId),
  };
}

// ---------------------------------------------------------------------------
// Membership order
// ---------------------------------------------------------------------------

/**
 * The order membership is recorded in, which every derived list inherits.
 *
 * For a tree it is a depth-first pre-order over each parent's `childNodeIds`,
 * so a slice's own children precede the next sibling. The repository-wide queue
 * has no parent and therefore no authored order, so ascending issue number is
 * the only stable signal left.
 *
 * Members the walk never reaches are appended by number rather than dropped:
 * this function stays total, and a tree that failed to hold together is the
 * fetch layer's problem to refuse, not this one's to hide.
 */
function memberOrder(input: SnapshotInput, issues: readonly IssueRecord[]): readonly IssueRecord[] {
  const byNumber = [...issues].sort((left, right) => left.number - right.number);
  if (input.scopeKind === "all-ready-for-agent" || input.anchorNodeId === null) return byNumber;

  const byNodeId = new Map(issues.map((issue) => [issue.nodeId, issue]));
  const visited = new Set<string>();
  const walked: IssueRecord[] = [];

  const visit = (nodeId: string): void => {
    if (visited.has(nodeId)) return;
    const issue = byNodeId.get(nodeId);
    if (!issue) return;
    visited.add(nodeId);
    walked.push(issue);
    for (const child of issue.childNodeIds) visit(child);
  };

  visit(input.anchorNodeId);
  return [...walked, ...byNumber.filter((issue) => !visited.has(issue.nodeId))];
}

// ---------------------------------------------------------------------------
// Eligibility
// ---------------------------------------------------------------------------

/**
 * Whether this scope would ever dispatch this node, ignoring its state. A SPEC
 * anchor is controlling context and never work — an agent handed the SPEC
 * itself would try to implement every slice in one dispatch — while a Specific
 * issue's anchor is the single work item the scope exists to name.
 */
function isCandidateRole(input: SnapshotInput, nodeId: string): boolean {
  switch (input.scopeKind) {
    case "specific-spec":
      return nodeId !== input.anchorNodeId;
    case "specific-issue":
      return nodeId === input.anchorNodeId;
    case "all-ready-for-agent":
      return true;
  }
}

/** Everything wrong with an issue that does not depend on any other issue. */
function ownExclusions(issue: IssueRecord): ExclusionReason[] {
  const reasons: ExclusionReason[] = [];
  if (issue.state === "closed") reasons.push("closed");
  // `ready-for-human` always wins, and reports alone. Both labels present is a
  // maintainer contradiction, and resolving it towards unattended execution is
  // the one reading that cannot be undone; and an issue released to a human is
  // released, so adding `unreleased` beside it would describe it wrongly.
  if (issue.labels.includes(READY_FOR_HUMAN)) reasons.push("ready-for-human");
  else if (!issue.labels.includes(READY_FOR_AGENT)) reasons.push("unreleased");
  return reasons;
}

/**
 * The eligible set, as a fixed point.
 *
 * A candidate is excluded when one of its open blockers is not itself a
 * candidate — and excluding it can take its own dependents with it, so one pass
 * is not enough. #421 is unreleased, so #420 will never run, so #419 has no
 * foundation either. Iterating to a fixed point is what makes that chain fall
 * out of the rule instead of needing a rule of its own.
 */
function eligibleSet(input: SnapshotInput, issues: readonly IssueRecord[]): ReadonlySet<string> {
  const candidates = new Set(
    issues
      .filter((issue) => isCandidateRole(input, issue.nodeId) && ownExclusions(issue).length === 0)
      .map((issue) => issue.nodeId),
  );

  for (let settled = false; !settled; ) {
    settled = true;
    for (const issue of issues) {
      if (!candidates.has(issue.nodeId)) continue;
      if (issue.openBlockers.every((blocker) => candidates.has(blocker.nodeId))) continue;
      candidates.delete(issue.nodeId);
      settled = false;
    }
  }

  return candidates;
}

// ---------------------------------------------------------------------------
// The canonical digest
// ---------------------------------------------------------------------------

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value === null || typeof value !== "object") return value;
  const record = value as Record<string, unknown>;
  return Object.fromEntries(
    Object.keys(record)
      .sort()
      .map((key) => [key, canonicalize(record[key])]),
  );
}

/**
 * Deterministic bytes for a value. Keys are sorted recursively rather than
 * written in a hand-maintained schema order, which reaches the same
 * determinism without a list that silently stops covering a field somebody
 * adds later.
 */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

// ---------------------------------------------------------------------------
// Building the snapshot
// ---------------------------------------------------------------------------

/**
 * Freeze one resolved Work scope.
 *
 * Total by construction: it classifies, it never refuses. A cycle is found by
 * `runOrder`, because a cycle is a property of the *order* and the caller has to
 * be able to show the picker what the tree looks like while it explains why the
 * run cannot start.
 */
export function buildSnapshot(input: SnapshotInput): WorkScopeSnapshot {
  const normalized = memberOrder(input, input.issues.map(normalizeIssue));
  const eligible = eligibleSet(input, normalized);

  const issues = normalized.map((issue): IssueSnapshot => {
    const reasons = ownExclusions(issue);
    // Computed for every member, not only candidates: a blocked SPEC anchor
    // that read "eligible" because nobody asked would be a confusing lie on the
    // confirmation screen.
    if (!eligible.has(issue.nodeId) && issue.openBlockers.some((b) => !eligible.has(b.nodeId))) {
      reasons.push("blocked");
    }
    return {
      ...issue,
      role: issue.nodeId === input.anchorNodeId ? "anchor" : "work-item",
      eligibility: reasons.length
        ? {
            status: "excluded",
            reasons: REASON_PRECEDENCE.filter((reason) => reasons.includes(reason)),
          }
        : { status: "eligible" },
    };
  });

  const payload = {
    schemaVersion: 1 as const,
    repository: input.repository,
    scopeKind: input.scopeKind,
    anchorNodeId: input.anchorNodeId,
    memberNodeIds: issues.map((issue) => issue.nodeId),
    executableNodeIds: issues
      .filter((issue) => eligible.has(issue.nodeId))
      .map((issue) => issue.nodeId),
    issues,
  };

  return {
    ...payload,
    snapshotId: `sha256:${createHash("sha256").update(canonicalJson(payload)).digest("hex")}`,
  };
}

export function issueByNodeId(
  snapshot: WorkScopeSnapshot,
  nodeId: string,
): IssueSnapshot | undefined {
  return snapshot.issues.find((issue) => issue.nodeId === nodeId);
}

/**
 * The blockers of `nodeId` that lie inside `within`. Every caller asks the same
 * question — a blocker nobody is going to run is not an ordering constraint,
 * it is either an exclusion (at build time) or already satisfied (at a wave
 * boundary).
 */
function blockersWithin(
  snapshot: WorkScopeSnapshot,
  nodeId: string,
  within: ReadonlySet<string>,
): readonly string[] {
  const issue = issueByNodeId(snapshot, nodeId);
  if (!issue) return [];
  return issue.openBlockers
    .map((blocker) => blocker.nodeId)
    .filter((blocker) => within.has(blocker));
}

function toWorkItem(issue: IssueSnapshot): WorkItem {
  return { nodeId: issue.nodeId, number: issue.number, title: issue.title, url: issue.url };
}

// ---------------------------------------------------------------------------
// What a prompt is told
// ---------------------------------------------------------------------------

/**
 * One issue as an agent reads it. The four fields the eligibility decision was
 * made from, and nothing else: no node id, no `updatedAt`, and above all no
 * edges — an implementer told what depends on it has a motive to widen its own
 * work, and a reviewer told the same has a motive to judge work it was not shown.
 */
export interface IssueBrief {
  readonly number: number;
  readonly title: string;
  readonly body: string;
  readonly labels: readonly string[];
}

/**
 * One work item as its implementer and its reviewer both read it: the brief,
 * the comments that carry any earlier review bounce, and the ancestor SPEC the
 * item sits inside, or `null`.
 *
 * Comments are bodies alone, which is the shape the shipped prompts have always
 * been handed — the old `gh issue list` block projected `[.comments[].body]`.
 * Run reports are already gone by this point: `normalizeIssue` drops every
 * comment carrying `RUN_REPORT_MARKER`, so the fifth run of one SPEC does not
 * read four previous run reports as evidence about the work.
 */
export interface WorkRecord extends IssueBrief {
  readonly comments: readonly string[];
  readonly spec: IssueBrief | null;
}

function toBrief(issue: IssueRecord): IssueBrief {
  return { number: issue.number, title: issue.title, body: issue.body, labels: issue.labels };
}

/**
 * The nearest ancestor of `nodeId` inside this snapshot that carries `spec`.
 *
 * Bounded by the snapshot rather than by GitHub: the fetch layer refuses a tree
 * that reaches an issue twice, so the walk terminates — and an ancestor outside
 * the scope was never read, so there is nothing here to guess at. Under a
 * Specific SPEC run this is the anchor; under the other two scopes it is
 * normally `undefined`, which is exactly the honest answer.
 */
export function ancestorSpec(
  snapshot: WorkScopeSnapshot,
  nodeId: string,
): IssueSnapshot | undefined {
  const seen = new Set<string>([nodeId]);
  let parentNodeId = issueByNodeId(snapshot, nodeId)?.parentNodeId ?? null;

  while (parentNodeId !== null && !seen.has(parentNodeId)) {
    seen.add(parentNodeId);
    const parent = issueByNodeId(snapshot, parentNodeId);
    if (!parent) return undefined;
    if (parent.labels.includes(SPEC)) return parent;
    parentNodeId = parent.parentNodeId;
  }
  return undefined;
}

/**
 * The record the runner substitutes into `{{WORK}}` — the exact issue its
 * eligibility decision was made from, so what the agent reads is provably what
 * the runner selected.
 *
 * Throws on a node the snapshot does not hold: a prompt arg built from an item
 * outside the frozen allow-list is the one failure that must never degrade into
 * an agent choosing its own work.
 */
export function workRecord(snapshot: WorkScopeSnapshot, nodeId: string): WorkRecord {
  const issue = issueByNodeId(snapshot, nodeId);
  if (!issue) throw new Error(`Built a work record for an item outside the snapshot: ${nodeId}`);
  const spec = ancestorSpec(snapshot, nodeId);
  return {
    ...toBrief(issue),
    comments: issue.comments.map((comment) => comment.body),
    spec: spec ? toBrief(spec) : null,
  };
}

/**
 * The record the runner substitutes into `{{ANCHOR}}`, or `null` when the scope
 * named no target. Always substituted, never an absent key — Sandcastle fails
 * loudly on a `{{KEY}}` it has no value for, and a literal `null` is what routes
 * a whole-branch prompt into its own no-anchor section.
 */
export function anchorRecord(snapshot: WorkScopeSnapshot): IssueBrief | null {
  if (snapshot.anchorNodeId === null) return null;
  const anchor = issueByNodeId(snapshot, snapshot.anchorNodeId);
  return anchor ? toBrief(anchor) : null;
}

// ---------------------------------------------------------------------------
// Run order
// ---------------------------------------------------------------------------

/**
 * Walk the remaining nodes until one repeats, and return that loop. Every
 * remaining node has at least one blocker that is also remaining — otherwise it
 * would have been emitted — so the walk cannot run out of edges.
 */
function findCycle(
  snapshot: WorkScopeSnapshot,
  remaining: readonly IssueSnapshot[],
): readonly number[] {
  const pending = new Set(remaining.map((issue) => issue.nodeId));
  const byNodeId = new Map<string, IssueSnapshot>(
    remaining.map((issue) => [issue.nodeId, issue]),
  );
  const path: IssueSnapshot[] = [];
  const seen = new Set<string>();
  let current: IssueSnapshot | undefined = remaining[0];

  while (current && !seen.has(current.nodeId)) {
    const node: IssueSnapshot = current;
    seen.add(node.nodeId);
    path.push(node);
    const blocker: string | undefined = blockersWithin(snapshot, node.nodeId, pending)[0];
    current = blocker === undefined ? undefined : byNodeId.get(blocker);
  }

  const entry = current;
  const start = entry ? path.findIndex((issue) => issue.nodeId === entry.nodeId) : -1;
  return path.slice(start === -1 ? 0 : start).map((issue) => issue.number);
}

/**
 * The allow-list as an ordered list of work: a topological sort of the
 * `blocked_by` edges, stable on membership order.
 *
 * Stable is the whole point. Repeatedly taking the *first still-unblocked item
 * in authored order* means the maintainer's ordering survives everywhere the
 * dependency edges do not have an opinion, which is most of a SPEC.
 */
export function runOrder(snapshot: WorkScopeSnapshot): RunOrder {
  const within = new Set(snapshot.executableNodeIds);
  // `issues` and `executableNodeIds` are both written in membership order, so
  // filtering the issues keeps that order and spares every step below a lookup
  // that could miss.
  const executable = snapshot.issues.filter((issue) => within.has(issue.nodeId));
  const emitted = new Set<string>();
  const items: WorkItem[] = [];

  while (items.length < executable.length) {
    const next = executable.find(
      (issue) =>
        !emitted.has(issue.nodeId) &&
        blockersWithin(snapshot, issue.nodeId, within).every((blocker) => emitted.has(blocker)),
    );
    if (!next) {
      const remaining = executable.filter((issue) => !emitted.has(issue.nodeId));
      return { ok: false, cycle: findCycle(snapshot, remaining) };
    }
    emitted.add(next.nodeId);
    items.push(toWorkItem(next));
  }

  return { ok: true, items };
}

/**
 * The run guard, applied to the sorted order and never before it. A prefix of a
 * topological order always contains its own blockers, so the guard cannot hand
 * a driver an item whose foundation it cut — which any filter applied earlier
 * could.
 *
 * A skip never backfills either: item eleven is not promoted when item three is
 * skipped, because the list was already cut before the run began.
 */
export function truncate(items: readonly WorkItem[], max: number): readonly WorkItem[] {
  return items.slice(0, Math.max(0, max));
}

// ---------------------------------------------------------------------------
// Levels and skips
// ---------------------------------------------------------------------------

const NOTHING_SKIPPED: ReadonlySet<string> = new Set();

/**
 * The remaining topological levels of `pending`, in order. A level is what
 * *could* run together; a wave is what actually does, and is a subset the
 * Planner may narrow.
 *
 * Never frozen, and recomputed from `(list, accumulated skip set)` at every wave
 * boundary — a transitive skip shrinks what is ready, and a frozen level would
 * dispatch a dependent onto a foundation that was never laid.
 *
 * Blockers outside `pending` are treated as satisfied, which is what makes the
 * second wave work: wave one's items merged and left the pending list, and
 * their dependents are ready precisely because of that.
 */
export function levels(
  snapshot: WorkScopeSnapshot,
  pending: readonly WorkItem[],
  skipped: ReadonlySet<string> = NOTHING_SKIPPED,
): readonly (readonly WorkItem[])[] {
  let rest = pending.filter((item) => !skipped.has(item.nodeId));
  const within = new Set(rest.map((item) => item.nodeId));
  const settled = new Set<string>();
  const out: (readonly WorkItem[])[] = [];

  while (rest.length) {
    const ready = rest.filter((item) =>
      blockersWithin(snapshot, item.nodeId, within).every((blocker) => settled.has(blocker)),
    );
    // Unreachable once `runOrder` has gated the run, and loud rather than silent
    // if it ever is reached: dropping the stuck items would run a partial SPEC
    // and report a clean sweep.
    if (!ready.length) {
      throw new Error(
        `Work items are cyclically blocked: ${rest.map((item) => `#${item.number}`).join(", ")}`,
      );
    }
    for (const item of ready) settled.add(item.nodeId);
    out.push(ready);
    rest = rest.filter((item) => !settled.has(item.nodeId));
  }

  return out;
}

/**
 * Everything that is out of this run because a foundation is missing.
 *
 * The trigger is always the same question — *does the foundation exist?* — so an
 * item that produced no commits, crashed, timed out or was rewound at fan-in
 * drops every in-set item `blocked_by` it, directly or through a chain.
 * Independent items are untouched. A bounce is deliberately not a trigger: the
 * code landed and was judged incomplete, which is a report to read rather than a
 * missing foundation.
 */
export function transitiveSkip(
  snapshot: WorkScopeSnapshot,
  failed: Iterable<string>,
  skipped: ReadonlySet<string> = NOTHING_SKIPPED,
): ReadonlySet<string> {
  const within = new Set(snapshot.executableNodeIds);
  const dependents = new Map<string, string[]>();
  for (const nodeId of snapshot.executableNodeIds) {
    for (const blocker of blockersWithin(snapshot, nodeId, within)) {
      const existing = dependents.get(blocker);
      if (existing) existing.push(nodeId);
      else dependents.set(blocker, [nodeId]);
    }
  }

  const out = new Set(skipped);
  const queue = [...failed];
  while (queue.length) {
    const nodeId = queue.shift();
    if (nodeId === undefined || out.has(nodeId)) continue;
    out.add(nodeId);
    queue.push(...(dependents.get(nodeId) ?? []));
  }
  return out;
}
