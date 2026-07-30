// Run configuration — the model catalog Sandcastle offers, and the store that
// remembers the last run's picks.
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

export type RunEffort = "low" | "medium" | "high" | "xhigh" | "max";
export type Provider = "claude-code" | "codex";
export type VersionComponents = readonly [number, number, number];
export type ModelID =
  | "claude-opus-5"
  | "claude-fable-5"
  | "claude-opus-4-8"
  | "claude-sonnet-4-6"
  | "gpt-5.6-sol"
  | "gpt-5.5";

export interface MinimumVersion {
  components: VersionComponents;
  label: string;
}

export interface RunModel {
  id: ModelID;
  label: string;
  provider: Provider;
  providerLabel: string;
  description: string;
  efforts: readonly RunEffort[];
  minimumCliVersion?: MinimumVersion;
}

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

const COMMON_EFFORTS = ["low", "medium", "high", "xhigh"] as const;

export const RUN_MODELS: readonly RunModel[] = [
  {
    id: "claude-opus-5",
    label: "Claude Opus 5",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Current default · deepest reasoning available",
    efforts: [...COMMON_EFFORTS, "max"],
  },
  {
    id: "claude-fable-5",
    label: "Claude Fable 5",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Strong general-purpose coding",
    efforts: COMMON_EFFORTS,
  },
  {
    id: "claude-opus-4-8",
    label: "Claude Opus 4.8",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Deep reasoning for demanding changes",
    efforts: [...COMMON_EFFORTS, "max"],
  },
  {
    id: "claude-sonnet-4-6",
    label: "Claude Sonnet 4.6",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Fast, capable everyday engineering",
    efforts: COMMON_EFFORTS,
  },
  {
    id: "gpt-5.6-sol",
    label: "GPT-5.6 Sol",
    provider: "codex",
    providerLabel: "OpenAI · Codex",
    description: "OpenAI flagship · preview access may be required",
    efforts: COMMON_EFFORTS,
    minimumCliVersion: { components: [0, 144, 0], label: "0.144.0" },
  },
  {
    id: "gpt-5.5",
    label: "GPT-5.5",
    provider: "codex",
    providerLabel: "OpenAI · Codex",
    description: "Frontier coding with broad availability",
    efforts: COMMON_EFFORTS,
  },
];

/** Preferred effort when nothing is remembered. */
export const DEFAULT_EFFORT: RunEffort = "high";

/** Width that keeps the picker's echoed "<phase> model/effort" values aligned. */
export const PHASE_LABEL_WIDTH = "Implementer effort".length;

export function findModel(id: string): RunModel | undefined {
  return RUN_MODELS.find((model) => model.id === id);
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

const STORE_FILENAME = "sandcastle-run.json";
const STORE_VERSION = 1;

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
