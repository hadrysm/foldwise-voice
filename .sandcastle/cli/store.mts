// The store that remembers the last run: which Work scope it was pointed at,
// which workflow ran, what model and effort each of its agents used, and where
// its two numbers were set.
//
// **Answers only, never outcomes.** The snapshot, its id, any wave plan, the
// run report and what each item did are all deliberately absent, because GitHub
// is the single source of truth about what is done and a second copy of it here
// would be a stale one.
//
// The store lives in the git *common* directory rather than the worktree. This
// repo is driven from Conductor, where every workspace is a separate worktree
// of one clone, and all of them resolve to the same common dir:
//
//   perth/.git   → .../foldwise-voice/.git/worktrees/perth
//   git rev-parse --git-common-dir → .../foldwise-voice/.git
//
// So a pick made in one workspace is the default in every other, including
// worktrees created later. Keeping it inside `.git` also means it is never
// committed and never shows up in a diff — which matters here beyond tidiness:
// the runner decides the backlog is empty from `implement.commits.length` and
// hands the reviewer a REVIEW_BASE SHA, so a tracked file rewritten on every
// run could be swept into an agent's commit or muddy the review diff.
//
// That sharing is also why a write is a key-level upsert and why parsing keeps
// keys it cannot interpret: those worktrees are on *different branches*, so one
// may know a workflow or an agent that another does not. Under a wholesale
// replace, whichever ran last would erase the other's memory.
//
// `knobs` is the first key to have gone through that retirement, and it needed
// no special case: SPEC #418 deleted `Knob`, so this version simply stops
// naming `knobs` and it becomes one more unrecognised top-level key, carried
// verbatim for whichever branch still writes one.
//
// The module is a leaf on purpose. It imports `node:*` and the model catalog and
// nothing else — no workflow registry, no agent catalog — which is what makes
// "keep the keys you do not recognise" enforceable rather than aspirational:
// there is nothing here to check an id against.

import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { findModel, type ModelID, type RunEffort } from "../agents/models.mts";

const STORE_FILENAME = "sandcastle-run.json";
const STORE_VERSION = 2;

/**
 * One agent's remembered pick. `effort` is optional because a stale effort is
 * dropped on its own: the model is the expensive, opinionated choice and effort
 * has a sound default, so losing the model to punish the effort would send the
 * picker back to index 0 as if the repo had never been run.
 */
export interface StoredPick {
  model: ModelID;
  effort?: RunEffort;
}

/**
 * The Work scope the last run was pointed at.
 *
 * `kind` is a bare string, never checked against a list: this module is a leaf
 * and has nothing to check one against, exactly as it has nothing to check an
 * agent id against. The picker looks up the kinds it declares and a kind it
 * does not know is inert.
 *
 * `origin` is the git dir of the worktree that wrote it, and it gates `target`
 * alone. The store lives in the git *common* dir, so every Conductor workspace
 * shares it — and every Conductor workspace is a different piece of work, so a
 * target pre-filled from a sibling would start an unattended run against a SPEC
 * this worktree has nothing to do with. `kind` is a habit and pre-fills
 * everywhere; a wrong one costs one arrow key.
 */
export interface StoredScope {
  kind: string;
  target?: string;
  origin?: string;
}

/**
 * The last run, as far as it can still be trusted. Agent picks key globally —
 * `IMPLEMENTER` and `REVIEWER` are single shared objects.
 */
export interface StoredRun {
  lastWorkflowId?: string;
  lastScope?: StoredScope;
  /** The run guard: how many work items an unattended run may drain. */
  maxWorkItems?: number;
  /** How many work items a concurrent driver runs at once. */
  maxParallel?: number;
  agents: Record<string, StoredPick>;
  /**
   * Every *top-level* key this version does not interpret, carried through a
   * read-modify-write untouched — `knobs` among them, now that `Knob` is gone.
   *
   * The same argument that makes an agent id survive, one level up. Worktrees
   * of one clone sit on different branches, so a branch that predates a field
   * would otherwise erase it on its next write, and a branch that has dropped
   * one would erase the branch that still uses it.
   */
  passthrough: Record<string, unknown>;
}

/**
 * What the store needs from a run it is asked to remember. Declared here rather
 * than imported so the store stays a leaf and the picker keeps depending on the
 * store, not the reverse.
 *
 * `scope` is the maintainer's *answer* — the kind they chose and the target
 * that resolved — not the snapshot it produced. The snapshot is an outcome.
 *
 * Both numbers are optional for the same reason: a run that was never asked for
 * one carries a number derived from what it resolved, and the caller leaves it
 * out rather than passing a fact off as a choice.
 */
interface RunToRemember {
  workflow: { id: string };
  scope: { kind: string; target?: string };
  maxWorkItems?: number;
  maxParallel?: number;
  agents: readonly { agentId: string; model: { id: ModelID }; effort: RunEffort }[];
}

function gitDir(flag: "--git-common-dir" | "--git-dir", cwd: string): string {
  // Relative in a primary worktree (".git"), absolute in a linked one — resolve
  // covers both.
  const path = execSync(`git rev-parse ${flag}`, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
  return resolve(cwd, path);
}

export function runStorePath(cwd: string = process.cwd()): string {
  return resolve(gitDir("--git-common-dir", cwd), STORE_FILENAME);
}

/**
 * Which worktree is asking. A free sibling of the `--git-common-dir` call
 * `runStorePath` already makes, and unique where a branch name is not: the
 * common dir is shared by every workspace of the clone, the per-worktree git
 * dir is not.
 */
export function worktreeOrigin(cwd: string = process.cwd()): string {
  return gitDir("--git-dir", cwd);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * One agent entry. An unknown model id is the one thing that must not survive:
 * the runner resolves it into a provider, and the picker hands it to clack as an
 * `initialValue` that has to name a real catalog row.
 */
function parsePick(value: unknown): StoredPick | undefined {
  if (!isRecord(value)) return undefined;
  if (typeof value.model !== "string") return undefined;
  const model = findModel(value.model);
  if (!model) return undefined;

  const effort = value.effort;
  if (typeof effort !== "string" || !model.efforts.includes(effort as RunEffort)) {
    return { model: model.id };
  }
  return { model: model.id, effort: effort as RunEffort };
}

function parseAgents(value: unknown): Record<string, StoredPick> {
  const agents: Record<string, StoredPick> = {};
  if (!isRecord(value)) return agents;
  for (const [agentId, entry] of Object.entries(value)) {
    // The agent id itself is never checked: the flow only looks up the ids its
    // selected workflow declares, so one it does not know is inert.
    const pick = parsePick(entry);
    if (pick) agents[agentId] = pick;
  }
  return agents;
}

/**
 * One remembered Work scope. Only the shape is checked — a `kind` no picker
 * declares is kept for the same reason an unknown agent id is, and it is inert
 * because nothing looks it up.
 */
function parseScope(value: unknown): StoredScope | undefined {
  if (!isRecord(value)) return undefined;
  if (typeof value.kind !== "string") return undefined;
  const scope: StoredScope = { kind: value.kind };
  if (typeof value.target === "string") scope.target = value.target;
  if (typeof value.origin === "string") scope.origin = value.origin;
  return scope;
}

/**
 * One remembered number. Integers only, and no bounds check: the bounds belong
 * to the question that asks, which this module cannot see, so an out-of-range
 * value is dropped at the point of use.
 */
function parseCount(value: unknown): number | undefined {
  return typeof value === "number" && Number.isInteger(value) ? value : undefined;
}

/** Every top-level key this version writes for itself, and so never carries. */
const KNOWN_KEYS: ReadonlySet<string> = new Set([
  "version",
  "lastWorkflowId",
  "lastScope",
  "maxWorkItems",
  "maxParallel",
  "agents",
]);

function parsePassthrough(candidate: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(candidate).filter(([key]) => !KNOWN_KEYS.has(key)),
  );
}

/**
 * v1 read as v2, which is nearly free because v1's keys already are the v2
 * agent ids. `sameForBoth` is dropped rather than migrated: "one model for
 * every agent?" is a question the picker derives, not a fact worth storing.
 * An absent `lastWorkflowId` lands on exactly v1's behaviour — registry index 0.
 */
function parseV1(candidate: Record<string, unknown>): StoredRun {
  const agents: Record<string, StoredPick> = {};
  for (const agentId of ["implementer", "reviewer"]) {
    const pick = parsePick(candidate[agentId]);
    if (pick) agents[agentId] = pick;
  }
  return { agents, passthrough: {} };
}

/**
 * Read a stored run out of raw file contents. Tolerant by design: only what
 * would otherwise be unusable is rejected, and anything unrecognisable at the
 * top level yields `undefined` so the picker falls back to its defaults. A
 * stale preference must never be able to break startup.
 */
export function parseStoredRun(raw: string): StoredRun | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (!isRecord(parsed)) return undefined;

  if (parsed.version === 1) return parseV1(parsed);
  if (parsed.version !== STORE_VERSION) return undefined;

  const run: StoredRun = {
    agents: parseAgents(parsed.agents),
    passthrough: parsePassthrough(parsed),
  };
  // Kept even when no registry knows it — the flow falls back to index 0, and
  // pruning it would mean this branch garbage-collecting another's memory.
  if (typeof parsed.lastWorkflowId === "string") run.lastWorkflowId = parsed.lastWorkflowId;

  const scope = parseScope(parsed.lastScope);
  if (scope) run.lastScope = scope;

  const maxWorkItems = parseCount(parsed.maxWorkItems);
  if (maxWorkItems !== undefined) run.maxWorkItems = maxWorkItems;

  const maxParallel = parseCount(parsed.maxParallel);
  if (maxParallel !== undefined) run.maxParallel = maxParallel;

  return run;
}

/** Last run's picks, or `undefined` if there are none to trust. Never throws. */
export function readStoredRun(storePath: string = runStorePath()): StoredRun | undefined {
  try {
    return parseStoredRun(readFileSync(storePath, "utf8"));
  } catch {
    return undefined;
  }
}

/**
 * Fold this run into what was already remembered, key by key. The entries this
 * run did not touch — another agent's model, a top-level field this branch has
 * never heard of — are carried across untouched, because a one-agent run
 * replacing the file wholesale would erase them.
 *
 * `origin` is the worktree doing the writing, and is the only part of the
 * remembered scope that does not come from the run itself.
 */
export function mergeStoredRun(
  existing: StoredRun | undefined,
  run: RunToRemember,
  origin?: string,
): StoredRun {
  const agents: Record<string, StoredPick> = { ...existing?.agents };
  for (const agent of run.agents) {
    agents[agent.agentId] = { model: agent.model.id, effort: agent.effort };
  }

  const lastScope: StoredScope = { kind: run.scope.kind };
  if (run.scope.target !== undefined) lastScope.target = run.scope.target;
  if (origin !== undefined) lastScope.origin = origin;

  return {
    lastWorkflowId: run.workflow.id,
    lastScope,
    // Upsert, like every other key: a run that was not asked for one of these
    // leaves the last answered value standing rather than erasing it.
    maxWorkItems: run.maxWorkItems ?? existing?.maxWorkItems,
    maxParallel: run.maxParallel ?? existing?.maxParallel,
    agents,
    passthrough: { ...existing?.passthrough },
  };
}

export function serializeStoredRun(run: StoredRun): string {
  return `${JSON.stringify(
    {
      version: STORE_VERSION,
      lastWorkflowId: run.lastWorkflowId,
      lastScope: run.lastScope,
      maxWorkItems: run.maxWorkItems,
      maxParallel: run.maxParallel,
      agents: run.agents,
      // Last, and by construction disjoint from every key above: whatever this
      // version does not interpret goes back out exactly as it came in.
      ...run.passthrough,
    },
    null,
    2,
  )}\n`;
}

/**
 * Remember this run. Read-modify-write, so a store that cannot be read is
 * treated as empty and overwritten rather than as a reason to skip the write —
 * otherwise one corrupt file would freeze the store forever. Returns false only
 * if the write itself failed; never throws.
 */
export function writeStoredRun(
  run: RunToRemember,
  storePath: string = runStorePath(),
  origin: string = worktreeOrigin(),
): boolean {
  const merged = mergeStoredRun(readStoredRun(storePath), run, origin);
  try {
    writeFileSync(storePath, serializeStoredRun(merged), "utf8");
    return true;
  } catch {
    return false;
  }
}
