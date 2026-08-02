// The Planner: a level splitter, and nothing else.
//
// The runner has already frozen membership, computed the order and computed the
// levels. Upstream's Planner exists to *infer* a dependency graph out of prose;
// ours is handed real `blocked_by` edges, so that job is the one job it
// definitively cannot have. What is left is the judgment the edges do not
// encode: **two ready items that rewrite the same module are unsafe to run
// together.**
//
// So it is handed the current ready level and may only **subset** it. It cannot
// discover work, add an item, widen a wave, cross a level, name a branch or
// reach past the resolved Work scope, and it sees no dependency edges. An
// omitted item is deferred to the next wave, never dropped.
//
// **Wave size *is* concurrency; there is no semaphore.** A semaphore would
// silently undo the Planner's only power — two items it deliberately separated
// could still overlap while a wide plan drains — so a too-wide plan is a
// validation failure rather than something quietly degraded.
//
// **Validation splits in two, and the split is load-bearing.** Shape is
// `schema.mts`'s, through `Output.object({ maxRetries: 1 })`, which resumes the
// agent's own session and asks for a corrected tag. Semantics are this module's,
// applied *after* the dispatch returns. The runner composes that schema per
// wave, so it *could* close over the ready set and get semantic retries free —
// which is exactly why it must not: keeping semantics out here is what makes
// *no semantic retry* true rather than aspirational.
//
// **An invalid plan falls back to the runner's computed wave**, with no retry
// and no abort. Valid by construction, because it is the same baseline the check
// is made against. The stakes are lower than they look: each item builds in its
// own worktree off a common base, so a bad co-schedule costs a rebase conflict
// at fan-in, not a corrupted run.
//
// **And the fallback renders a wave-level ledger line.** Not decoration. Three
// decisions compose badly — the silent fallback, a prompt that never mentions
// it, and seven outcomes that are all per-*item* — so the Planner's failure mode
// was designed to be invisible: every wave could silently become the computed
// wave, the run completes, every item merges, the ledger looks perfect, and the
// one genuinely new component has never once worked. **Telling the human after
// the run is not telling the agent during it**; `plan-prompt.md` stays silent,
// and the maintainer reads the ledger.

import { PLANNER } from "../agents/catalog.mts";
import { issueByNodeId, type WorkItem, type WorkScopeSnapshot } from "../scope/snapshot.mts";
import type { RunCore } from "./core.mts";
import {
  fields,
  readArray,
  readIssueNumber,
  readString,
  validator,
  type Validator,
} from "./schema.mts";

/** Resolved against the workflow's own folder, like every other prompt. */
export const PLAN_PROMPT = "plan-prompt.md";
/** The XML tag `plan-prompt.md` emits its one block in. */
export const PLAN_TAG = "plan";

/** One item the Planner left out, and the reason a maintainer reads. */
export interface Deferral {
  readonly number: number;
  readonly reason: string;
}

/**
 * **Identity is the number.** The runner supplies titles from the snapshot and
 * names branches deterministically, so everything it already knows is a forgery
 * surface if echoed back.
 *
 * `deferrals` are validated for shape and **never cross-checked against what was
 * actually left out**: a level splitter whose deferrals are unexplained is
 * unauditable, and policing them would add a second way for a plan to fail for a
 * reason nobody reads.
 */
export interface Plan {
  readonly wave: readonly number[];
  readonly deferrals: readonly Deferral[];
}

export const PLAN_SCHEMA: Validator<Plan> = validator("sandcastle/plan", (value) => {
  const plan = fields(value, "plan");
  return {
    wave: readArray(plan["wave"], "wave", readIssueNumber),
    deferrals: readArray(plan["deferrals"], "deferrals", (element, field) => {
      const deferral = fields(element, field);
      return {
        number: readIssueNumber(deferral["number"], `${field}.number`),
        reason: readString(deferral["reason"], `${field}.reason`),
      };
    }),
  };
});

// ---------------------------------------------------------------------------
// What the Planner is handed
// ---------------------------------------------------------------------------

/** One ready item, as the Planner reads it. Three fields, and no fourth. */
export interface ReadyRecord {
  readonly number: number;
  readonly title: string;
  readonly body: string;
}

/**
 * The `{{READY}}` payload.
 *
 * Number, title and body — no labels, because eligibility was decided before
 * this prompt was written; no comments, because a review bounce is the
 * implementer's business; and above all **no dependency edges**, because a level
 * splitter is handed a level with the edges already applied and a Planner that
 * could see them would start second-guessing the order.
 */
export function readyRecords(
  snapshot: WorkScopeSnapshot,
  ready: readonly WorkItem[],
): readonly ReadyRecord[] {
  return ready.map((item) => ({
    number: item.number,
    title: item.title,
    body: issueByNodeId(snapshot, item.nodeId)?.body ?? "",
  }));
}

// ---------------------------------------------------------------------------
// The two decisions the runner makes for itself
// ---------------------------------------------------------------------------

/**
 * Is there a plan to make?
 *
 * **One dispatch per wave, skipped at a one-item level** — a zero-item plan
 * being invalid means the only valid plan is that item, so the dispatch could
 * only agree with the runner or be overruled by it.
 *
 * **Not** skipped merely because the level fits `MAX_PARALLEL`: at three, a
 * two-item level can still hold two items that must not run together, which is
 * the only judgment the Planner exists to make.
 */
export function needsPlan(ready: readonly WorkItem[]): boolean {
  return ready.length > 1;
}

/** The first `MAX_PARALLEL` of the ready level, in settled order. */
export function computedWave(
  ready: readonly WorkItem[],
  maxParallel: number,
): readonly WorkItem[] {
  return ready.slice(0, maxParallel);
}

export type PlanCheck =
  | { readonly ok: true; readonly wave: readonly WorkItem[] }
  | { readonly ok: false; readonly reason: string };

/**
 * The semantic half, outside the schema validator on purpose.
 *
 * Four ways a shape-valid plan is still not a wave. **Omitting ready items is
 * legal — that is the power** — so there is deliberately no check that the plan
 * is the whole level.
 *
 * **A zero-item plan is invalid, not "done."** Forced rather than chosen:
 * upstream's `if (issues.length === 0) break` is its stop condition, but our
 * ready set is runner-computed and known non-empty, so an empty plan can only
 * mean *defer everything* — a livelock.
 */
export function checkPlan(
  plan: Plan,
  ready: readonly WorkItem[],
  maxParallel: number,
): PlanCheck {
  if (plan.wave.length === 0) {
    return {
      ok: false,
      reason: "the plan holds no items, and something ready has to start first",
    };
  }

  const duplicate = plan.wave.find(
    (number, index) => plan.wave.indexOf(number) !== index,
  );
  if (duplicate !== undefined) {
    return { ok: false, reason: `the plan holds #${duplicate} twice` };
  }

  const unknown = plan.wave.find(
    (number) => !ready.some((item) => item.number === number),
  );
  if (unknown !== undefined) {
    return { ok: false, reason: `#${unknown} is not ready in this wave` };
  }

  if (plan.wave.length > maxParallel) {
    return {
      ok: false,
      reason: `the plan holds ${plan.wave.length} items and at most ${maxParallel} may run at once`,
    };
  }

  // Read back in the order the level settled rather than the order the plan
  // listed: order inside `wave` carries no meaning, and the fan-in merges in run
  // order, so this is the one ordering the rest of the run agrees on.
  return { ok: true, wave: ready.filter((item) => plan.wave.includes(item.number)) };
}

// ---------------------------------------------------------------------------
// The wave-level ledger line
// ---------------------------------------------------------------------------

export type PlanOutcome =
  | { readonly kind: "accepted"; readonly deferrals: readonly Deferral[] }
  | { readonly kind: "fallback"; readonly reason: string };

function numbersOf(wave: readonly WorkItem[]): string {
  return wave.map((item) => `#${item.number}`).join(", ");
}

/**
 * What the maintainer reads about one wave's planning, in one line.
 *
 * Rendered on **both** paths, which is the whole point: a run in which every
 * wave silently fell back has proven nothing about the Planner, and only this
 * line can tell that run from one where the plan was taken.
 */
export function planLine(
  waveNumber: number,
  outcome: PlanOutcome,
  wave: readonly WorkItem[],
): string {
  if (outcome.kind === "fallback") {
    return `  ⚠ wave ${waveNumber} — the plan was rejected: ${outcome.reason}; ran the computed wave ${numbersOf(wave)}`;
  }
  const deferred = outcome.deferrals
    .map((deferral) => `#${deferral.number} — ${deferral.reason}`)
    .join("; ");
  const tail = deferred === "" ? "" : `, deferring ${deferred}`;
  return `  ⊂ wave ${waveNumber} — the Planner chose ${numbersOf(wave)}${tail}`;
}

// ---------------------------------------------------------------------------
// The dispatch
// ---------------------------------------------------------------------------

export interface WaveChoice {
  readonly wave: readonly WorkItem[];
  /** The wave-level line, or `null` when the Planner was never asked. */
  readonly line: string | null;
}

/**
 * Which of the ready items start now.
 *
 * Driver-internal: this goes through `core.consult`, not through a `Dispatch`,
 * which is what lets it use structured output at all — and what keeps it out of
 * a workflow's reach.
 *
 * **Every failure lands on the computed wave.** A rejected plan, a Planner that
 * crashed, a provider that never answered: all of them are the same fact — no
 * usable plan — and none of them is worth stopping an unattended run over. What
 * they are worth is a line.
 */
export async function selectWave(
  core: RunCore,
  ready: readonly WorkItem[],
  waveNumber: number,
): Promise<WaveChoice> {
  const computed = computedWave(ready, core.maxParallel);
  if (!needsPlan(ready)) return { wave: computed, line: null };

  let plan: Plan;
  try {
    plan = await core.consult(PLANNER, {
      promptFile: PLAN_PROMPT,
      promptArgs: {
        READY: JSON.stringify(readyRecords(core.scope, ready)),
        MAX_PARALLEL: String(core.maxParallel),
      },
      tag: PLAN_TAG,
      schema: PLAN_SCHEMA,
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message.split("\n")[0] : String(error);
    return {
      wave: computed,
      line: planLine(waveNumber, { kind: "fallback", reason: `the Planner did not answer — ${detail}` }, computed),
    };
  }

  const checked = checkPlan(plan, ready, core.maxParallel);
  if (!checked.ok) {
    return { wave: computed, line: planLine(waveNumber, { kind: "fallback", reason: checked.reason }, computed) };
  }
  return {
    wave: checked.wave,
    line: planLine(waveNumber, { kind: "accepted", deferrals: plan.deferrals }, checked.wave),
  };
}
