// The Merger: the one thing in a run that sees a wave's items in one tree.
//
// Dispatched once per settled wave, on the host with no worktree, handed
// whatever happened — nothing, a conflicted branch, a broken tree, or both. Two
// jobs, in order: finish the merges git could not complete on its own, then
// prove the merged combination still builds and its tests still pass.
//
// **The runner still merges in code.** An agent never merges what git merges
// cleanly: paying one to run three clean `git merge --no-edit` calls is waste
// that also makes the merge non-deterministic. What reaches the Merger is only
// what git refused, already rewound.
//
// **Fan-in is the runner's; verification is the prompt's.** The runner may run a
// command whose output it discards and never one whose exit code it branches on,
// git excepted — so it *cannot* re-derive `verified` for itself. That is not a
// preference either: a dispatch is narrowed to its commits on the way out and a
// completion signal carries no payload even when one is set (#430), and the
// contract's two-key allow-list denies a workflow `output`. Structured output on
// a driver-internal consult is the only channel there is.
//
// **It never closes an issue.** Upstream's CLOSE ISSUES section dies entirely:
// the runner never closes a SPEC and the implementer already closes its own
// item.
//
// **Accepted cost:** a clean multi-item wave pays one dispatch that usually runs
// two commands and returns. That is the price of the runner not knowing what
// language this repository is written in.

import { MERGER } from "../agents/catalog.mts";
import type { RunCore } from "./core.mts";
import {
  fields,
  readArray,
  readBoolean,
  readIssueNumber,
  readString,
  validator,
  type Validator,
} from "./schema.mts";

/** Resolved against the workflow's own folder, like every other prompt. */
export const MERGE_PROMPT = "merge-prompt.md";
/** The XML tag `merge-prompt.md` emits its one block in. */
export const MERGE_TAG = "merge";

/**
 * What the Merger reports.
 *
 * `unresolved` is the Merger's **own account** of what it could not merge, and
 * the runner does not act on it: which branches reached the workspace branch is
 * a question git answers, and the driver observes rather than believes. It is
 * carried anyway because it is what the agent claims, and a claim printed beside
 * git's answer is how a maintainer notices the two disagreeing.
 */
export interface MergeVerdict {
  readonly verified: boolean;
  readonly unresolved: readonly number[];
  readonly notes: string;
}

export const MERGE_SCHEMA: Validator<MergeVerdict> = validator("sandcastle/merge", (value) => {
  const verdict = fields(value, "merge");
  return {
    verified: readBoolean(verdict["verified"], "verified"),
    unresolved: readArray(verdict["unresolved"], "unresolved", readIssueNumber),
    notes: readString(verdict["notes"], "notes"),
  };
});

// ---------------------------------------------------------------------------
// What the Merger is handed
// ---------------------------------------------------------------------------

/** One item git merged for itself. Finished, and not the Merger's to revisit. */
export interface MergedItem {
  readonly number: number;
  readonly branch: string;
  /** The `--no-ff` commit — the only per-item boundary in an otherwise flat diff. */
  readonly commit: string;
}

/** One item git refused, already rewound, and the paths it refused over. */
export interface UnmergedItem {
  readonly number: number;
  readonly branch: string;
  readonly paths: readonly string[];
}

/**
 * The `{{WAVE}}` payload: what the runner already did, stated precisely enough
 * that the Merger's precondition is checkable from the prompt alone — the
 * working tree is clean and holds exactly the merged items.
 */
export interface WavePayload {
  /** The workspace branch, which is also the branch the Merger is standing on. */
  readonly branch: string;
  /** The SHA that branch pointed at before this wave's merges. */
  readonly base: string;
  readonly merged: readonly MergedItem[];
  readonly unmerged: readonly UnmergedItem[];
}

// ---------------------------------------------------------------------------
// What the runner does with the verdict
// ---------------------------------------------------------------------------

export type MergerAction =
  | { readonly kind: "carry-on" }
  | { readonly kind: "abort"; readonly detail: string };

/**
 * The two readings of `verified: false`, which must never blur.
 *
 * - **A conflict belongs to exactly one branch.** It is already rewound, its
 *   dependents already skip, and nothing else in the wave is implicated — so the
 *   run carries on and that one item is the cost.
 * - **A broken tree belongs to no branch.** Every item merged, every item's
 *   tests passed in isolation, and the combination is still wrong; there is
 *   nobody to leave out and nothing to rewind. **The run aborts.**
 *
 * `stillUnmerged` is git's answer, never the Merger's: a verdict that claimed
 * nothing was unresolved while a branch sat unmerged would otherwise abort a run
 * that had one branch to blame all along.
 */
export function mergerAction(
  verdict: MergeVerdict,
  stillUnmerged: readonly number[],
): MergerAction {
  if (verdict.verified) return { kind: "carry-on" };
  if (stillUnmerged.length > 0) return { kind: "carry-on" };
  return {
    kind: "abort",
    detail: `the merged tree failed verification and no branch is left to attribute it to — ${verdict.notes}`,
  };
}

/** What the maintainer reads about one wave's fan-in, in one line. */
export function mergeLine(waveNumber: number, verdict: MergeVerdict): string {
  const unresolved =
    verdict.unresolved.length === 0
      ? ""
      : `, unresolved ${verdict.unresolved.map((number) => `#${number}`).join(", ")}`;
  const glyph = verdict.verified ? "⊕" : "⚠";
  const state = verdict.verified ? "verified" : "not verified";
  return `  ${glyph} wave ${waveNumber} ${state}${unresolved} — ${verdict.notes}`;
}

// ---------------------------------------------------------------------------
// The dispatch
// ---------------------------------------------------------------------------

/**
 * Ask the Merger what became of this wave's combination.
 *
 * Driver-internal, like the Planner: a `consult` rather than a `Dispatch`, which
 * is what lets it answer in a shape rather than in prose.
 */
export function askMerger(core: RunCore, wave: WavePayload): Promise<MergeVerdict> {
  return core.consult(MERGER, {
    promptFile: MERGE_PROMPT,
    promptArgs: { WAVE: JSON.stringify(wave) },
    tag: MERGE_TAG,
    schema: MERGE_SCHEMA,
  });
}
