// The picker's state machine: which question comes next, how an answer folds
// back in, and what plan the answers add up to.
//
// Pure and TTY-free on purpose — no `@clack/prompts`, no spawning, no
// `process.stdout`. The whole picker is `nextQuestion` → `applyAnswer` →
// `resolvePlan`, which makes the exact sequence of screens a workflow produces
// an assertion rather than a manual walk. `cli/prompts.mts` is the shell that
// draws it.
//
// The output is a `ResolvedPlan` — which workflow, which model and effort per
// agent, and every knob's value — which is the only thing `runner.mts` needs.

import {
  DEFAULT_EFFORT,
  findModel,
  RUN_MODELS,
  type RunEffort,
  type RunModel,
} from "../agents/models.mts";
import type { Agent, Knob, Workflow } from "../contract.mts";
import { WORKFLOWS } from "../workflows/registry.mts";
import type { StoredPick, StoredRun } from "./store.mts";

/**
 * Which reasoning efforts a model's CLI actually advertises. Injected rather
 * than imported because answering it means spawning `claude --help`, and a flow
 * that spawns cannot have its screen sequence asserted.
 */
export type EffortsFor = (model: RunModel) => readonly RunEffort[];

/**
 * How each reasoning tier is described. Keyed exhaustively rather than listed, so
 * a tier added to `RunEffort` cannot ship as a row labelled with its own raw id.
 */
const EFFORT_ROWS: Readonly<Record<RunEffort, { label: string; hint: string }>> = {
  low: { label: "Low", hint: "Fastest, for small and routine changes" },
  medium: { label: "Medium", hint: "Balanced speed and reasoning" },
  high: { label: "High", hint: "Recommended default for implementation work" },
  xhigh: { label: "Extra High", hint: "More time for complex, multi-step work" },
  max: { label: "Max", hint: "Maximum available reasoning budget" },
};

// ---------------------------------------------------------------------------
// Questions
// ---------------------------------------------------------------------------

/**
 * One row of a select. `value` is always a string: it is what the widget matches
 * `initialValue` against with strict `===`, so a remembered pick has to be
 * carried as its own primitive id rather than as the object it names.
 */
export interface FlowOption {
  value: string;
  label: string;
  hint?: string;
}

interface QuestionBase {
  /** Stable, and the whole ordering contract: `model:reviewer`, `knob:maxIterations`. */
  id: string;
  prompt: string;
  /** Lines to show above this question — today, the confirmation summary. */
  note?: readonly string[];
}

/** Pick one of a fixed list. */
export interface SelectQuestion extends QuestionBase {
  kind: "select";
  options: readonly FlowOption[];
  /** Where the cursor opens. A value no row carries lands on the first row. */
  initialValue?: string;
}

/** Type a whole number. Empty input accepts `defaultValue`. */
export interface NumberQuestion extends QuestionBase {
  kind: "number";
  /** `1–50  ·  enter accepts 10`. */
  hint: string;
  defaultValue: number;
  min: number;
  max: number;
}

export type Question = SelectQuestion | NumberQuestion;

/** What a driver hands back: a select's option value, or a typed number. */
export type Answer = string | number;

function select(
  id: string,
  prompt: string,
  options: readonly FlowOption[],
  initialValue?: string,
): SelectQuestion {
  return { kind: "select", id, prompt, options, initialValue };
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/** Key a model/effort pick is filed under: an agent id, or `*` when shared. */
const SHARED = "*";

/**
 * The one target the shared question asks about. Its label is deliberately not
 * an agent's: "same for every agent" asks once, about none of them in
 * particular.
 */
const SHARED_TARGET: Agent = { id: SHARED, label: "Run" };

interface Pick {
  model?: RunModel;
  effort?: RunEffort;
}

/** Every answer given so far. Plain data, so folding one in is a copy. */
export interface FlowState {
  store?: StoredRun;
  repeatLastRun?: boolean;
  workflowId?: string;
  sameModelForEveryAgent?: boolean;
  picks: Readonly<Record<string, Pick>>;
  knobs: Readonly<Record<string, number>>;
  confirmed?: boolean;
}

export function initialState(store?: StoredRun): FlowState {
  return { store, picks: {}, knobs: {} };
}

function findWorkflow(id: string | undefined): Workflow | undefined {
  return WORKFLOWS.find((workflow) => workflow.id === id);
}

/** Which keys the model/effort pass runs over: every agent, or one shared row. */
function pickTargets(state: FlowState): readonly Agent[] {
  const workflow = findWorkflow(state.workflowId);
  if (!workflow) return [];
  if (workflow.agents.length === 1) return workflow.agents;
  return state.sameModelForEveryAgent ? [SHARED_TARGET] : workflow.agents;
}

/**
 * The pick a model question should open on. The shared target names no agent, so
 * it falls back to the first of this workflow's agents the store still
 * remembers — first wins, because any of them is a better cursor than index 0.
 */
export function rememberedFor(
  store: StoredRun | undefined,
  workflow: Workflow,
  targetId: string,
): StoredPick | undefined {
  if (!store) return undefined;
  if (targetId !== SHARED) return store.agents[targetId];
  for (const agent of workflow.agents) {
    const remembered: StoredPick | undefined = store.agents[agent.id];
    if (remembered) return remembered;
  }
  return undefined;
}

/**
 * Whether every remembered agent was pointed at the same model *and* effort —
 * the initial answer to "one model for every agent?", derived rather than
 * stored, because stored it was one global boolean carried over from a possibly
 * different workflow. A pick the store dropped counts as a mismatch, which lands
 * on "configure separately" and so shows every prompt rather than silently
 * copying a surviving pick onto every agent.
 */
function remembersOneModelForAll(store: StoredRun, agents: readonly Agent[]): boolean {
  const picks = agents.map((agent): StoredPick | undefined => store.agents[agent.id]);
  const [first] = picks;
  if (!first) return false;
  return picks.every((pick) => pick?.model === first.model && pick?.effort === first.effort);
}

/**
 * A knob's remembered value if it is still one this workflow accepts, else its
 * declared default. Checked here rather than in the store because the store is
 * registry-blind and never holds a `Knob`. Out of range drops to the default and
 * never clamps: a stale answer is not a nearly-right one, and a silent clamp
 * would run a number nobody chose.
 */
function resolveKnob(knob: Knob, bucket: Record<string, number> | undefined): number {
  const stored = bucket?.[knob.id];
  if (stored === undefined || stored < knob.min || stored > knob.max) return knob.defaultValue;
  return stored;
}

function knobsFor(workflow: Workflow, store: StoredRun | undefined): Record<string, number> {
  const bucket = store?.knobs[workflow.id];
  return Object.fromEntries(workflow.knobs.map((knob) => [knob.id, resolveKnob(knob, bucket)]));
}

/** The first knob this workflow declares that has no answer yet. */
export function knobQuestion(state: FlowState, workflow: Workflow): NumberQuestion | undefined {
  const pending = workflow.knobs.find((knob) => state.knobs[knob.id] === undefined);
  if (!pending) return undefined;
  const preferred = resolveKnob(pending, state.store?.knobs[workflow.id]);
  return {
    kind: "number",
    id: `knob:${pending.id}`,
    prompt: pending.prompt,
    hint: `${pending.min}–${pending.max}  ·  enter accepts ${preferred}`,
    defaultValue: preferred,
    min: pending.min,
    max: pending.max,
  };
}

/**
 * Whether the store holds a run that can be replayed in one keystroke. Every
 * agent needs a *complete* pick: `StoredPick.effort` is dropped on its own when
 * a tier leaves the catalog, and a run missing one is not the run that happened.
 * The fast path simply vanishes for that one run, and the next write fills the
 * gap back in.
 */
export function storeIsReplayable(store: StoredRun | undefined): store is StoredRun {
  if (!store) return false;
  const workflow = findWorkflow(store.lastWorkflowId);
  if (!workflow) return false;
  return workflow.agents.every((agent) => {
    const pick: StoredPick | undefined = store.agents[agent.id];
    return pick?.effort !== undefined;
  });
}

// ---------------------------------------------------------------------------
// The plan
// ---------------------------------------------------------------------------

/** One agent's picks: who it is, and what will run it. */
export interface ResolvedAgent {
  agentId: string;
  agentLabel: string;
  model: RunModel;
  effort: RunEffort;
}

/** Everything the picker decided. The runner needs nothing else. */
export interface ResolvedPlan {
  workflow: Workflow;
  agents: readonly ResolvedAgent[];
  knobs: Readonly<Record<string, number>>;
}

/**
 * The plan the walk adds up to, or `undefined` while any pick or knob is still
 * missing. A shared pick fans out here into one entry per agent, which is why
 * `*` cannot reach the runner or the store.
 */
function planFromWalk(state: FlowState, workflow: Workflow): ResolvedPlan | undefined {
  const shared: Pick | undefined = state.picks[SHARED];
  const agents: ResolvedAgent[] = [];
  for (const agent of workflow.agents) {
    const pick: Pick | undefined = shared ?? state.picks[agent.id];
    if (!pick?.model || !pick.effort) return undefined;
    agents.push({
      agentId: agent.id,
      agentLabel: agent.label,
      model: pick.model,
      effort: pick.effort,
    });
  }

  const knobs: Record<string, number> = {};
  for (const knob of workflow.knobs) {
    const value = state.knobs[knob.id];
    if (value === undefined) return undefined;
    knobs[knob.id] = value;
  }

  return { workflow, agents, knobs };
}

/** The remembered run as a plan, or `undefined` when it cannot be replayed. */
function replayPlan(store: StoredRun | undefined): ResolvedPlan | undefined {
  if (!storeIsReplayable(store)) return undefined;
  const workflow = findWorkflow(store.lastWorkflowId);
  if (!workflow) return undefined;

  const agents: ResolvedAgent[] = [];
  for (const agent of workflow.agents) {
    const pick: StoredPick | undefined = store.agents[agent.id];
    const model = pick ? findModel(pick.model) : undefined;
    if (!model || !pick?.effort) return undefined;
    agents.push({
      agentId: agent.id,
      agentLabel: agent.label,
      model,
      effort: pick.effort,
    });
  }

  return { workflow, agents, knobs: knobsFor(workflow, store) };
}

/** `Claude Opus 5 · High` — one agent's pick on a single line. */
function describeAgent(resolved: ResolvedAgent): string {
  return `${resolved.model.label} · ${EFFORT_ROWS[resolved.effort].label}`;
}

const RUNS_LABEL = "Runs";

/** Left-align every row to the same column, whatever the workflow's labels. */
function labelColumn(agents: readonly ResolvedAgent[]): number {
  return Math.max(RUNS_LABEL.length, ...agents.map((resolved) => resolved.agentLabel.length)) + 2;
}

/**
 * The confirmation: one row per agent, then one line from `runShape`. Not the
 * phases in run order — that repeats what the agent rows already say, and would
 * force every workflow to declare its phase sequence, which is exactly what
 * `runShape` exists to avoid.
 */
export function summaryByAgent(plan: ResolvedPlan): readonly string[] {
  const column = labelColumn(plan.agents);
  return [
    ...plan.agents.map(
      (resolved) => `${resolved.agentLabel.padEnd(column)}${describeAgent(resolved)}`,
    ),
    `${RUNS_LABEL.padEnd(column)}${plan.workflow.runShape(plan.knobs)}`,
  ];
}

/** The fast path's own option line, which is why it needs no confirm screen. */
function summariseReplay(plan: ResolvedPlan): string {
  const models = plan.agents.map(describeAgent).join(" / ");
  const knobs = plan.workflow.knobs
    .map((knob) => `${knob.summaryLabel.toLowerCase()} ${plan.knobs[knob.id]}`)
    .join(", ");
  return [plan.workflow.label, models, knobs].filter(Boolean).join(" · ");
}

// ---------------------------------------------------------------------------
// The walk
// ---------------------------------------------------------------------------

/**
 * The first question still unanswered, or `undefined` once the answers settle
 * the run. Knobs sit immediately after the workflow because "which workflow, how
 * many issues" is one thought: asking last would separate a workflow from its
 * own parameter with four model screens in between.
 */
export function nextQuestion(state: FlowState, effortsFor: EffortsFor): Question | undefined {
  // 0. Replay a remembered run in one keystroke. The option's own line is the
  //    confirmation, so accepting it starts the run rather than opening a
  //    confirm screen.
  if (state.repeatLastRun === undefined) {
    const replay = replayPlan(state.store);
    if (replay) {
      return select(
        "fast-path",
        "Repeat your last run?",
        [
          { value: "repeat", label: "Repeat last run", hint: summariseReplay(replay) },
          { value: "change", label: "Change something", hint: "Walk through every question" },
        ],
        "repeat",
      );
    }
  }
  if (state.repeatLastRun) return undefined;

  // 1. Which workflow. Always asked, even while the registry holds one: a list
  //    of one is honest, and it is also what a `lastWorkflowId` no registry
  //    knows falls back to — nothing is silently substituted.
  if (!state.workflowId) {
    return select(
      "workflow",
      "Which workflow should run?",
      WORKFLOWS.map((workflow) => ({
        value: workflow.id,
        label: workflow.label,
        hint: workflow.description,
      })),
      state.store?.lastWorkflowId,
    );
  }

  const workflow = findWorkflow(state.workflowId);
  if (!workflow) return undefined;

  // 2. The workflow's own knobs, if it declares any.
  const knob = knobQuestion(state, workflow);
  if (knob) return knob;

  // 3. One model for every agent? Never asked of a single-agent workflow.
  if (workflow.agents.length > 1 && state.sameModelForEveryAgent === undefined) {
    return select(
      "same-model",
      "Use one model for every agent?",
      [
        {
          value: "shared",
          label: "Same for every agent",
          hint: `One model and effort drives all ${workflow.agents.length}`,
        },
        {
          value: "separate",
          label: "Configure separately",
          hint: "Pick a different model or effort per agent",
        },
      ],
      state.store && !remembersOneModelForAll(state.store, workflow.agents) ? "separate" : "shared",
    );
  }

  // 4. Model, then effort, once per target.
  for (const target of pickTargets(state)) {
    const pick: Pick | undefined = state.picks[target.id];
    const remembered = rememberedFor(state.store, workflow, target.id);

    if (!pick?.model) {
      return select(
        `model:${target.id}`,
        `Choose the ${target.label} model`,
        RUN_MODELS.map((model) => ({
          value: model.id,
          label: model.label,
          hint: `${model.providerLabel} · ${model.description}`,
        })),
        remembered?.model,
      );
    }

    if (!pick.effort) {
      const model = pick.model;
      const efforts = effortsFor(model);
      if (!efforts.length) {
        throw new Error(`${model.providerLabel} reports no supported reasoning efforts.`);
      }
      // Prefer the remembered effort, then the recommended default, then let the
      // cursor land on the first tier the CLI actually advertises.
      const rememberedEffort = remembered?.model === model.id ? remembered.effort : undefined;
      const initial = [rememberedEffort, DEFAULT_EFFORT].find(
        (candidate) => candidate !== undefined && efforts.includes(candidate),
      );
      return select(
        `effort:${target.id}`,
        `Choose ${target.label} effort for ${model.label}`,
        efforts.map((effort) => ({
          value: effort,
          label: EFFORT_ROWS[effort].label,
          hint: EFFORT_ROWS[effort].hint,
        })),
        initial,
      );
    }
  }

  // 5. Confirm, with the plan the answers came to.
  const plan = planFromWalk(state, workflow);
  if (plan && state.confirmed === undefined) {
    return {
      ...select("confirm", `Start ${workflow.label}?`, [
        { value: "start", label: `Start ${workflow.label}` },
        { value: "cancel", label: "Cancel" },
      ]),
      note: summaryByAgent(plan),
    };
  }

  return undefined;
}

/** `model:reviewer` → `["model", "reviewer"]`; `confirm` → `["confirm", ""]`. */
function splitId(id: string): readonly [string, string] {
  const separator = id.indexOf(":");
  if (separator === -1) return [id, ""];
  return [id.slice(0, separator), id.slice(separator + 1)];
}

/** Fold one answer in, leaving the state it was given untouched. */
export function applyAnswer(state: FlowState, question: Question, value: Answer): FlowState {
  const [kind, key] = splitId(question.id);

  switch (kind) {
    case "fast-path":
      return { ...state, repeatLastRun: value === "repeat" };
    case "workflow":
      return { ...state, workflowId: String(value) };
    case "same-model":
      return { ...state, sameModelForEveryAgent: value === "shared" };
    case "model": {
      // The id came out of `RUN_MODELS`, so this cannot miss. It throws rather
      // than dropping the answer because a dropped answer would re-ask the same
      // question forever.
      const model = findModel(String(value));
      if (!model) throw new Error(`Unknown model: ${String(value)}`);
      return { ...state, picks: { ...state.picks, [key]: { model } } };
    }
    case "effort": {
      // Narrowed against the model already picked for this target, which is both
      // cast-free and stricter: a tier that model does not accept is refused.
      const pick: Pick | undefined = state.picks[key];
      const effort = pick?.model?.efforts.find((candidate) => candidate === value);
      if (!effort) throw new Error(`Unknown ${key} effort: ${String(value)}`);
      return { ...state, picks: { ...state.picks, [key]: { ...pick, effort } } };
    }
    case "knob": {
      if (typeof value !== "number") throw new Error(`${question.id} needs a number`);
      return { ...state, knobs: { ...state.knobs, [key]: value } };
    }
    case "confirm":
      return { ...state, confirmed: value === "start" };
    default:
      throw new Error(`Unhandled question: ${question.id}`);
  }
}

/**
 * What the answers came to, or `undefined` when the run was declined. Two ways
 * in: the fast path replays the store outright, and the walk resolves what was
 * confirmed.
 */
export function resolvePlan(state: FlowState): ResolvedPlan | undefined {
  if (state.repeatLastRun) return replayPlan(state.store);
  if (!state.confirmed) return undefined;
  const workflow = findWorkflow(state.workflowId);
  if (!workflow) return undefined;
  return planFromWalk(state, workflow);
}
