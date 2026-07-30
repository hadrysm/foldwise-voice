// The store that remembers the last run's picks, and the picked-plan types the
// serializer consumes. `RunConfiguration` and `RunPlan` sit here beside that
// serializer only until `ResolvedPlan` replaces them — this is a way station,
// not their home.
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

import { execSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { findModel, type ModelID, type RunEffort, type RunModel } from "../agents/models.mts";

const STORE_FILENAME = "sandcastle-run.json";
const STORE_VERSION = 1;

/** One phase's picks. */
export interface RunConfiguration {
  model: RunModel;
  effort: RunEffort;
}

/** Both phases' picks, plus how they were chosen. */
export interface RunPlan {
  implementer: RunConfiguration;
  reviewer: RunConfiguration;
  sameForBoth: boolean;
}

/** A remembered pick, already checked against the catalog. */
export interface StoredSelection {
  model: ModelID;
  effort: RunEffort;
}

/**
 * A remembered plan. Either role may be absent — a pick that no longer matches
 * the catalog is dropped on its own rather than discarding the whole file.
 */
export interface StoredRunPlan {
  sameForBoth: boolean;
  implementer?: StoredSelection;
  reviewer?: StoredSelection;
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

function parseSelection(value: unknown): StoredSelection | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  const { model, effort } = value as { model?: unknown; effort?: unknown };
  if (typeof model !== "string" || typeof effort !== "string") return undefined;

  // A model dropped from the catalog, or an effort that model never supported
  // (a stale "max" against a model that lost it), must not resurface.
  const known = findModel(model);
  if (!known) return undefined;
  if (!known.efforts.includes(effort as RunEffort)) return undefined;

  return { model: known.id, effort: effort as RunEffort };
}

/**
 * Read a stored plan out of raw file contents. Tolerant by design: anything
 * unrecognisable yields `undefined` so the picker falls back to its defaults. A
 * stale preference must never be able to break startup.
 */
export function parseStoredRunPlan(raw: string): StoredRunPlan | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return undefined;
  }

  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return undefined;
  }

  const candidate = parsed as {
    version?: unknown;
    sameForBoth?: unknown;
    implementer?: unknown;
    reviewer?: unknown;
  };
  if (candidate.version !== STORE_VERSION) return undefined;

  const plan: StoredRunPlan = {
    sameForBoth: typeof candidate.sameForBoth === "boolean" ? candidate.sameForBoth : true,
  };
  const implementer = parseSelection(candidate.implementer);
  const reviewer = parseSelection(candidate.reviewer);
  if (implementer) plan.implementer = implementer;
  if (reviewer) plan.reviewer = reviewer;
  return plan;
}

/** Last run's picks, or `undefined` if there are none to trust. Never throws. */
export function readStoredRunPlan(): StoredRunPlan | undefined {
  try {
    return parseStoredRunPlan(readFileSync(runStorePath(), "utf8"));
  } catch {
    return undefined;
  }
}

export function serializeRunPlan(plan: RunPlan): string {
  return `${JSON.stringify(
    {
      version: STORE_VERSION,
      sameForBoth: plan.sameForBoth,
      implementer: { model: plan.implementer.model.id, effort: plan.implementer.effort },
      reviewer: { model: plan.reviewer.model.id, effort: plan.reviewer.effort },
    },
    null,
    2,
  )}\n`;
}

/** Remember this run's picks. Returns false if the write failed; never throws. */
export function writeStoredRunPlan(plan: RunPlan): boolean {
  try {
    writeFileSync(runStorePath(), serializeRunPlan(plan), "utf8");
    return true;
  } catch {
    return false;
  }
}
