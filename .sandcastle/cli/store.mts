// The store that remembers the last run: which workflow ran, what model and
// effort each of its agents used, and where its knobs were set.
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
// may know a workflow, an agent or a knob that another does not. Under a
// wholesale replace, whichever ran last would erase the other's memory.
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
 * The last run, as far as it can still be trusted. Agent picks key globally —
 * `IMPLEMENTER` and `REVIEWER` are single shared objects — while knobs key per
 * workflow, because two workflows declaring `maxIterations` declare two
 * different parameters that happen to share a spelling.
 */
export interface StoredRun {
  lastWorkflowId?: string;
  agents: Record<string, StoredPick>;
  knobs: Record<string, Record<string, number>>;
}

/**
 * What the store needs from a run it is asked to remember: a `ResolvedPlan`
 * satisfies it structurally. Declared here rather than imported so the store
 * stays a leaf and the picker keeps depending on the store, not the reverse.
 */
interface RunToRemember {
  workflow: { id: string };
  agents: readonly { agentId: string; model: { id: ModelID }; effort: RunEffort }[];
  knobs: Readonly<Record<string, number>>;
}

export function runStorePath(cwd: string = process.cwd()): string {
  // Relative in a primary worktree (".git"), absolute in a linked one — resolve
  // covers both.
  const commonDir = execSync("git rev-parse --git-common-dir", {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
  return resolve(cwd, commonDir, STORE_FILENAME);
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
 * One workflow's knob bucket. Integers only, and no bounds check — `min` and
 * `max` live on the `Knob` the workflow declares, which this module cannot see,
 * so an out-of-range value is rejected at the point of use instead.
 */
function parseKnobs(value: unknown): Record<string, Record<string, number>> {
  const knobs: Record<string, Record<string, number>> = {};
  if (!isRecord(value)) return knobs;
  for (const [workflowId, bucket] of Object.entries(value)) {
    if (!isRecord(bucket)) continue;
    const parsed: Record<string, number> = {};
    for (const [knobId, knobValue] of Object.entries(bucket)) {
      if (typeof knobValue === "number" && Number.isInteger(knobValue)) parsed[knobId] = knobValue;
    }
    knobs[workflowId] = parsed;
  }
  return knobs;
}

/**
 * v1 read as v2, which is nearly free because v1's keys already are the v2
 * agent ids. `sameForBoth` is dropped rather than migrated: "one model for
 * every agent?" is a question the picker derives, not a fact worth storing.
 * Both absent v2 fields land on exactly v1's behaviour — no `lastWorkflowId`
 * means registry index 0, and no knob bucket means each knob's declared
 * default, which is the constant v1 hardcoded.
 */
function parseV1(candidate: Record<string, unknown>): StoredRun {
  const agents: Record<string, StoredPick> = {};
  for (const agentId of ["implementer", "reviewer"]) {
    const pick = parsePick(candidate[agentId]);
    if (pick) agents[agentId] = pick;
  }
  return { agents, knobs: {} };
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
    knobs: parseKnobs(parsed.knobs),
  };
  // Kept even when no registry knows it — the flow falls back to index 0, and
  // pruning it would mean this branch garbage-collecting another's memory.
  if (typeof parsed.lastWorkflowId === "string") run.lastWorkflowId = parsed.lastWorkflowId;
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
 * run did not touch — another agent's model, another workflow's knobs, a knob
 * this workflow no longer declares — are carried across untouched, because a
 * one-agent, zero-knob run replacing the file wholesale would erase them.
 */
export function mergeStoredRun(existing: StoredRun | undefined, run: RunToRemember): StoredRun {
  const agents: Record<string, StoredPick> = { ...existing?.agents };
  for (const agent of run.agents) {
    agents[agent.agentId] = { model: agent.model.id, effort: agent.effort };
  }

  const knobs = { ...existing?.knobs };
  const bucket = { ...existing?.knobs[run.workflow.id], ...run.knobs };
  if (Object.keys(bucket).length) knobs[run.workflow.id] = bucket;

  return { lastWorkflowId: run.workflow.id, agents, knobs };
}

export function serializeStoredRun(run: StoredRun): string {
  return `${JSON.stringify(
    {
      version: STORE_VERSION,
      lastWorkflowId: run.lastWorkflowId,
      agents: run.agents,
      knobs: run.knobs,
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
export function writeStoredRun(run: RunToRemember, storePath: string = runStorePath()): boolean {
  const merged = mergeStoredRun(readStoredRun(storePath), run);
  try {
    writeFileSync(storePath, serializeStoredRun(merged), "utf8");
    return true;
  } catch {
    return false;
  }
}
