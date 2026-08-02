// The picker's state machine: which step comes next, how an answer folds back
// in, and what plan the answers add up to.
//
// Pure and TTY-free on purpose — no `@clack/prompts`, no spawning, no
// `process.stdout`. The whole picker is `nextStep` → `applyAnswer` →
// `resolvePlan`, which makes the exact sequence of screens a run produces an
// assertion rather than a manual walk. `cli/prompts.mts` is the shell that
// draws it.
//
// **Work scope is the first decision, for every workflow.** The walk is
// scope → target → resolve → fast path → workflow → run guard → `MAX_PARALLEL`
// → models and effort → confirm. Resolving a scope is network I/O, so it is
// *injected* rather than performed here, following the `EffortsFor` precedent —
// but the *point at which* it happens stays in this module, as a third step
// kind. A walk whose resolution point lived in the shell could not have its
// ordering asserted, which is the one property this module exists for.
//
// The output is a `ResolvedPlan` — which scope, which workflow, which model and
// effort per agent, and the two numbers — which is the only thing `runner.mts`
// needs.

import {
  DEFAULT_EFFORT,
  findModel,
  RUN_MODELS,
  type RunEffort,
  type RunModel,
} from "../agents/models.mts";
import type { Agent, Knob, Workflow } from "../contract.mts";
import { repo } from "../repo.mts";
import type { ScopeErrorReason, ScopeOutcome } from "../scope/github.mts";
import {
  runOrder,
  type ExclusionReason,
  type IssueRecord,
  type IssueSnapshot,
  type ScopeKind,
  type WorkItem,
  type WorkScope,
  type WorkScopeSnapshot,
} from "../scope/snapshot.mts";
import { WORKFLOWS } from "../workflows/registry.mts";
import type { StoredPick, StoredRun } from "./store.mts";

/**
 * Which reasoning efforts a model's CLI actually advertises. Injected rather
 * than imported because answering it means spawning `claude --help`, and a flow
 * that spawns cannot have its screen sequence asserted.
 */
export type EffortsFor = (model: RunModel) => readonly RunEffort[];

/**
 * Turn one Work scope into a frozen snapshot, or say why it could not be.
 *
 * The other injected seam, and the reason `ResolveStep` exists: this module
 * decides *when* a scope is resolved, `cli/prompts.mts` performs it because it
 * already owns I/O, and the outcome comes back as an answer like any other.
 */
export type ResolveScope = (scope: WorkScope) => Promise<ScopeOutcome>;

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

/**
 * The three Work scopes, in picker order. Keyed exhaustively for the same
 * reason the effort rows are: a fourth kind cannot ship as a row labelled with
 * its own kebab-case id.
 */
const SCOPE_ROWS: Readonly<
  Record<ScopeKind, { label: string; hint: string; targetPrompt: string | null }>
> = {
  "specific-spec": {
    label: "Specific SPEC",
    hint: "Drain every eligible descendant in one run",
    targetPrompt: "Which SPEC? Enter its issue number or URL",
  },
  "specific-issue": {
    label: "Specific issue",
    hint: "Work on exactly one ready-for-agent issue",
    targetPrompt: "Which issue? Enter its number or URL",
  },
  "all-ready-for-agent": {
    label: "All ready-for-agent issues",
    hint: "Use the repository-wide queue",
    targetPrompt: null,
  },
};

const SCOPE_ORDER: readonly ScopeKind[] = [
  "specific-spec",
  "specific-issue",
  "all-ready-for-agent",
];

/**
 * The run guard. Universal — asked of every scope a draining workflow is
 * pointed at, because it is a brake on an unattended run's token budget rather
 * than a work-selection choice.
 */
const RUN_GUARD = { min: 1, max: 50, defaultValue: 10 };

/**
 * How many work items may run side by side. Ten is a ceiling, not a
 * recommendation: #406 measured throughput on this host peaking at three and
 * *inverting* at four, and `repo.maxParallelDefault` is what the question opens
 * on. It is a question rather than a constant because contention depends on
 * what the Mac is doing right now, which only the human at the keyboard knows.
 */
const PARALLEL_BOUNDS = { min: 1, max: 10 };

// ---------------------------------------------------------------------------
// Steps
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

interface StepBase {
  /** Stable, and the whole ordering contract: `model:reviewer`, `run-guard`. */
  id: string;
  prompt: string;
  /** Lines to show above this step — the confirmation, or a failed resolution. */
  note?: readonly string[];
  /** The heading those lines sit under. */
  noteTitle?: string;
}

/** Pick one of a fixed list. */
export interface SelectQuestion extends StepBase {
  kind: "select";
  options: readonly FlowOption[];
  /** Where the cursor opens. A value no row carries lands on the first row. */
  initialValue?: string;
}

/** Type a whole number. Empty input accepts `defaultValue`. */
export interface NumberQuestion extends StepBase {
  kind: "number";
  /** `1–50  ·  enter accepts 10`. */
  hint: string;
  defaultValue: number;
  min: number;
  max: number;
}

/**
 * The one step that is not a question: go and ask GitHub.
 *
 * `needsTarget` distinguishes the two ways this step is reached. On the way in,
 * and after *Enter another target*, the shell asks for a target first. After
 * *Try GitHub again* it does not — the same target is resolved again, which is
 * what "keep this Work scope and target" means.
 *
 * `initialValue` carries that target either way: it pre-fills the field when
 * one is asked for, and *is* the target when one is not.
 */
export interface ResolveStep extends StepBase {
  kind: "resolve";
  scope: ScopeKind;
  needsTarget: boolean;
  initialValue?: string;
}

export type Step = SelectQuestion | NumberQuestion | ResolveStep;

/** What a resolve step hands back: what was typed, and what GitHub said. */
export interface ScopeResolution {
  /** The string that was typed, when this step asked for one. */
  readonly target?: string;
  readonly outcome: ScopeOutcome;
}

/** What a shell hands back: a select's option value, a number, or a resolution. */
export type Answer = string | number | ScopeResolution;

function isScopeResolution(value: Answer): value is ScopeResolution {
  return typeof value === "object" && value !== null && "outcome" in value;
}

function select(
  id: string,
  prompt: string,
  options: readonly FlowOption[],
  initialValue?: string,
): SelectQuestion {
  return { kind: "select", id, prompt, options, initialValue };
}

// ---------------------------------------------------------------------------
// Work scope
// ---------------------------------------------------------------------------

function needsTargetFor(kind: ScopeKind): boolean {
  return SCOPE_ROWS[kind].targetPrompt !== null;
}

/** The scope a resolve step describes, once the shell has a target for it. */
export function toWorkScope(kind: ScopeKind, target: string): WorkScope {
  return kind === "all-ready-for-agent" ? { kind } : { kind, target };
}

/** A resolution the flow accepted: the frozen snapshot, and the order it implies. */
export interface ResolvedScope {
  readonly snapshot: WorkScopeSnapshot;
  /** The whole topological order. The run guard truncates it, later and elsewhere. */
  readonly items: readonly WorkItem[];
  /** The target, when the scope named one. */
  readonly anchor?: IssueSnapshot;
}

/**
 * Why a resolution did not produce work. A value rather than a throw, because
 * the recovery it offers is the thing worth testing.
 */
export interface ScopeFailure {
  readonly title: string;
  readonly detail: string;
  /** The resolved target, when there is one to show number, title and labels for. */
  readonly anchor?: IssueRecord;
  /** Whether *Try GitHub again* is one of the recovery options. */
  readonly retryable: boolean;
}

/**
 * What each failure is called. Keyed exhaustively so a reason added to
 * `ScopeErrorReason` cannot reach a maintainer as its own kebab-case id.
 */
const FAILURE_TITLES: Readonly<Record<ScopeErrorReason, string>> = {
  "invalid-target": "That is not a target for this repository",
  "not-found": "GitHub could not read that target",
  "not-an-issue": "That target is not an issue",
  "cross-repository": "That tree leaves this repository",
  "malformed-tree": "That tree cannot be ordered",
  "malformed-response": "GitHub answered in a shape this runner cannot read",
  denied: "GitHub refused the read",
  unavailable: "GitHub could not be reached",
  "target-rejected": "That target cannot be run",
};

/**
 * Which failures *Try GitHub again* is offered for: the ones about reaching
 * GitHub or about a login, which a maintainer can fix in another terminal and
 * retry into. A failure about the string that was typed, or about the tree it
 * named, answers the same way every time — for those, the other three recovery
 * options are the honest ones.
 */
const RETRYABLE: ReadonlySet<ScopeErrorReason> = new Set<ScopeErrorReason>([
  "not-found",
  "denied",
  "unavailable",
  "malformed-response",
]);

function anchorOf(snapshot: WorkScopeSnapshot): IssueSnapshot | undefined {
  if (snapshot.anchorNodeId === null) return undefined;
  return snapshot.issues.find((issue) => issue.nodeId === snapshot.anchorNodeId);
}

/**
 * What an empty scope is called. Not an error — GitHub answered, and the answer
 * was *nothing to do* — but not a run either, so it lands in the same recovery
 * as a failure with the resolved context still on screen.
 */
function emptyScope(snapshot: WorkScopeSnapshot): ScopeFailure {
  return {
    title: "No work is eligible right now",
    detail:
      snapshot.scopeKind === "all-ready-for-agent"
        ? "The repository-wide queue holds no open, unblocked `ready-for-agent` issue."
        : "Nothing in this scope is open, released to an agent and unblocked from outside it.",
    anchor: anchorOf(snapshot),
    // Retryable: this is the one failure a maintainer routinely fixes by
    // labelling an issue in the browser and asking again.
    retryable: true,
  };
}

/** A resolution, judged: work to do, or a screen explaining why there is none. */
type Judgement =
  | { readonly ok: true; readonly resolved: ResolvedScope }
  | { readonly ok: false; readonly failure: ScopeFailure };

function judge(outcome: ScopeOutcome): Judgement {
  if (!outcome.ok) {
    return {
      ok: false,
      failure: {
        title: FAILURE_TITLES[outcome.reason],
        detail: outcome.message,
        anchor: outcome.anchor,
        retryable: RETRYABLE.has(outcome.reason),
      },
    };
  }

  const snapshot = outcome.snapshot;
  // A cycle aborts *before* confirmation rather than at the first wave
  // boundary: a run that deadlocks on its own ordering has already been
  // launched, and this is the last place it can be refused for free.
  const order = runOrder(snapshot);
  if (!order.ok) {
    return {
      ok: false,
      failure: {
        title: "These work items block each other in a cycle",
        detail: `No order can satisfy ${order.cycle.map((number) => `#${number}`).join(" → ")}. Break the dependency and resolve again.`,
        anchor: anchorOf(snapshot),
        retryable: false,
      },
    };
  }
  if (order.items.length === 0) return { ok: false, failure: emptyScope(snapshot) };

  return { ok: true, resolved: { snapshot, items: order.items, anchor: anchorOf(snapshot) } };
}

// ---------------------------------------------------------------------------
// Describing a scope
// ---------------------------------------------------------------------------

/** `Specific SPEC · #418 Universal Work scope …`, or just the label. */
function scopeLine(snapshot: WorkScopeSnapshot): string {
  const label = SCOPE_ROWS[snapshot.scopeKind].label;
  const anchor = anchorOf(snapshot);
  return anchor ? `${label} · #${anchor.number} ${anchor.title}` : label;
}

/**
 * How much of the eligible work this run will reach. The truncated case is
 * stated rather than implied — a partially drained SPEC that read `10 issues`
 * would hide the twenty it is leaving behind.
 */
function eligibleLine(snapshot: WorkScopeSnapshot, maxWorkItems: number): string {
  const total = snapshot.executableNodeIds.length;
  if (snapshot.scopeKind === "specific-issue") return "exactly 1 issue";
  if (maxWorkItems < total) return `up to ${maxWorkItems} of ${total} eligible`;
  return `${total} eligible issue${total === 1 ? "" : "s"}`;
}

/** Every excluded work item, counted under the first reason that applies. */
function exclusionCounts(snapshot: WorkScopeSnapshot): readonly [ExclusionReason, number][] {
  const counts = new Map<ExclusionReason, number>();
  for (const issue of snapshot.issues) {
    if (issue.role !== "work-item" || issue.eligibility.status !== "excluded") continue;
    const reason = issue.eligibility.reasons[0];
    if (reason === undefined) continue;
    counts.set(reason, (counts.get(reason) ?? 0) + 1);
  }
  return [...counts];
}

/**
 * One column for every labelled row the picker draws, so the scope summary, the
 * recovery note and the confirmation all line up as one table read top to
 * bottom rather than as three that nearly agree.
 */
const SUMMARY_COLUMN = 13;

function summaryRow(label: string, value: string): string {
  return `${label.padEnd(SUMMARY_COLUMN)}${value}`;
}

/**
 * What resolving a scope found, for the shell to show once. Scope-specific by
 * design: a SPEC states eligible against excluded descendants, a single issue
 * states that exactly one thing will run, and the repository-wide queue states
 * its own size.
 */
export function scopeSummary(resolved: ResolvedScope): readonly string[] {
  const { snapshot, anchor } = resolved;
  const lines = [summaryRow("Work scope", SCOPE_ROWS[snapshot.scopeKind].label)];

  if (anchor) {
    lines.push(summaryRow("Target", `#${anchor.number} · ${anchor.title}`));
    lines.push(summaryRow("Labels", anchor.labels.join(", ") || "none"));
  }

  const eligible = resolved.items.length;
  lines.push(
    summaryRow(
      "Eligible",
      snapshot.scopeKind === "specific-issue"
        ? "exactly 1 issue"
        : `${eligible} open, unblocked issue${eligible === 1 ? "" : "s"}`,
    ),
  );

  const excluded = exclusionCounts(snapshot);
  if (excluded.length) {
    lines.push(
      summaryRow("Not run", excluded.map(([reason, count]) => `${count} ${reason}`).join(" · ")),
    );
  }

  return lines;
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
  /** This worktree's git dir. The gate on pre-filling a remembered target. */
  origin?: string;
  scopeKind?: ScopeKind;
  /** The last target string this scope was given; pre-fills the field again on recovery. */
  target?: string;
  /** Set by *Enter another target*: the next resolve step asks before resolving. */
  retypeTarget?: boolean;
  resolved?: ResolvedScope;
  failure?: ScopeFailure;
  cancelled?: boolean;
  repeatLastRun?: boolean;
  workflowId?: string;
  maxWorkItems?: number;
  maxParallel?: number;
  sameModelForEveryAgent?: boolean;
  picks: Readonly<Record<string, Pick>>;
  knobs: Readonly<Record<string, number>>;
  confirmed?: boolean;
}

export function initialState(store?: StoredRun, origin?: string): FlowState {
  return { store, origin, picks: {}, knobs: {} };
}

function findWorkflow(
  id: string | undefined,
  workflows: readonly Workflow[],
): Workflow | undefined {
  return workflows.find((workflow) => workflow.id === id);
}

/** Which keys the model/effort pass runs over: every agent, or one shared row. */
function pickTargets(state: FlowState, workflow: Workflow): readonly Agent[] {
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
 * A remembered number if it is still one this question accepts, else the
 * fallback. Out of range drops to the fallback and never clamps: a stale answer
 * is not a nearly-right one, and a silent clamp would run a number nobody chose.
 */
function boundedOr(
  stored: number | undefined,
  bounds: { min: number; max: number },
  fallback: number,
): number {
  if (stored === undefined || stored < bounds.min || stored > bounds.max) return fallback;
  return stored;
}

/**
 * A knob's remembered value if it is still one this workflow accepts, else its
 * declared default. Checked here rather than in the store because the store is
 * registry-blind and never holds a `Knob`.
 */
function resolveKnob(knob: Knob, bucket: Record<string, number> | undefined): number {
  return boundedOr(bucket?.[knob.id], knob, knob.defaultValue);
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
 * Whether the run guard is a decision at all here. Asked whenever the driver
 * drains **and** more than one work item is eligible: with one item the guard
 * has exactly one meaningful value, and a Specific issue therefore never sees
 * that screen.
 *
 * One predicate, two callers — the question, and what the store is allowed to
 * remember. Two spellings of it would let the store keep a number the
 * maintainer was never shown.
 */
function guardIsAsked(workflow: Workflow, eligible: number): boolean {
  return workflow.drains && eligible > 1;
}

/** The run guard, or nothing when there is no choice to make. */
export function runGuardQuestion(state: FlowState, workflow: Workflow): NumberQuestion | undefined {
  if (state.maxWorkItems !== undefined) return undefined;
  if (!guardIsAsked(workflow, state.resolved?.items.length ?? 0)) return undefined;
  const preferred = boundedOr(state.store?.maxWorkItems, RUN_GUARD, RUN_GUARD.defaultValue);
  return {
    kind: "number",
    id: "run-guard",
    prompt: "How many work items may this run drain?",
    hint: `${RUN_GUARD.min}–${RUN_GUARD.max}  ·  enter accepts ${preferred}`,
    defaultValue: preferred,
    min: RUN_GUARD.min,
    max: RUN_GUARD.max,
  };
}

/** How wide a wave may be, asked only of a workflow that runs items side by side. */
export function maxParallelQuestion(
  state: FlowState,
  workflow: Workflow,
): NumberQuestion | undefined {
  if (!workflow.concurrent || state.maxParallel !== undefined) return undefined;
  const preferred = boundedOr(
    state.store?.maxParallel,
    PARALLEL_BOUNDS,
    repo.maxParallelDefault,
  );
  return {
    kind: "number",
    id: "max-parallel",
    prompt: "How many work items should run at the same time?",
    hint: `${PARALLEL_BOUNDS.min}–${PARALLEL_BOUNDS.max}  ·  enter accepts ${preferred}`,
    defaultValue: preferred,
    min: PARALLEL_BOUNDS.min,
    max: PARALLEL_BOUNDS.max,
  };
}

/**
 * Whether the store holds a run that can be replayed in one keystroke. Every
 * agent needs a *complete* pick: `StoredPick.effort` is dropped on its own when
 * a tier leaves the catalog, and a run missing one is not the run that happened.
 * A draining workflow additionally needs its guard and a concurrent one its wave
 * width, for the same reason — a replay that silently invented either would not
 * be a replay. The fast path simply vanishes for that one run, and the next
 * write fills the gap back in.
 *
 * The Work scope is deliberately *not* among the requirements: scope is
 * pre-fill, not replay, and by the time this is asked the scope has already been
 * resolved in this walk.
 */
export function storeIsReplayable(
  store: StoredRun | undefined,
  workflows: readonly Workflow[] = WORKFLOWS,
): store is StoredRun {
  if (!store) return false;
  const workflow = findWorkflow(store.lastWorkflowId, workflows);
  if (!workflow) return false;
  if (workflow.drains && store.maxWorkItems === undefined) return false;
  if (workflow.concurrent && store.maxParallel === undefined) return false;
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
  /** The frozen scope. The runner orders and truncates it; the picker never does. */
  scope: WorkScopeSnapshot;
  maxWorkItems: number;
  maxParallel: number;
}

/**
 * The two numbers a plan carries, for a workflow that was never asked for one.
 * A workflow that does not drain is bounded by the eligible set it will never
 * walk, and one that does not run items side by side runs exactly one at a time
 * — both are no-ops rather than invented answers.
 */
function numbersFor(
  workflow: Workflow,
  resolved: ResolvedScope,
  chosen: { maxWorkItems?: number; maxParallel?: number },
): { maxWorkItems: number; maxParallel: number } {
  return {
    maxWorkItems: workflow.drains ? (chosen.maxWorkItems ?? resolved.items.length) : resolved.items.length,
    maxParallel: workflow.concurrent ? (chosen.maxParallel ?? 1) : 1,
  };
}

/**
 * The plan the walk adds up to, or `undefined` while any pick or knob is still
 * missing. A shared pick fans out here into one entry per agent, which is why
 * `*` cannot reach the runner or the store.
 */
function planFromWalk(
  state: FlowState,
  workflow: Workflow,
  resolved: ResolvedScope,
): ResolvedPlan | undefined {
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

  return { workflow, agents, knobs, scope: resolved.snapshot, ...numbersFor(workflow, resolved, state) };
}

/** The remembered run as a plan, or `undefined` when it cannot be replayed. */
function replayPlan(
  store: StoredRun | undefined,
  resolved: ResolvedScope,
  workflows: readonly Workflow[],
): ResolvedPlan | undefined {
  if (!storeIsReplayable(store, workflows)) return undefined;
  const workflow = findWorkflow(store.lastWorkflowId, workflows);
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

  return {
    workflow,
    agents,
    knobs: knobsFor(workflow, store),
    scope: resolved.snapshot,
    ...numbersFor(workflow, resolved, store),
  };
}

/** `Claude Opus 5 · High` — one agent's pick on a single line. */
function describeAgent(resolved: ResolvedAgent): string {
  return `${resolved.model.label} · ${EFFORT_ROWS[resolved.effort].label}`;
}

const RUNS_LABEL = "Runs";
const SCOPE_LABEL = "Work scope";
const ELIGIBLE_LABEL = "Eligible";

/** The shared column, widened if some workflow's agent label overruns it. */
function labelColumn(agents: readonly ResolvedAgent[]): number {
  return Math.max(SUMMARY_COLUMN, ...agents.map((resolved) => resolved.agentLabel.length + 2));
}

/** How many work items this plan will actually hand over. */
function workItemCount(plan: ResolvedPlan): number {
  return Math.min(plan.maxWorkItems, plan.scope.executableNodeIds.length);
}

/**
 * The confirmation: the scope, what it will reach, one row per agent, then one
 * line from `runShape`. The scope and eligible rows are this module's rather
 * than the workflow's, which is what keeps `runShape` down to a single number
 * and the anchor out of every workflow.
 */
export function summaryByAgent(plan: ResolvedPlan): readonly string[] {
  const column = labelColumn(plan.agents);
  const pad = (label: string, value: string): string => `${label.padEnd(column)}${value}`;
  return [
    pad(SCOPE_LABEL, scopeLine(plan.scope)),
    pad(ELIGIBLE_LABEL, eligibleLine(plan.scope, plan.maxWorkItems)),
    ...plan.agents.map((resolved) => pad(resolved.agentLabel, describeAgent(resolved))),
    pad(RUNS_LABEL, plan.workflow.runShape(workItemCount(plan))),
  ];
}

/** The fast path's own option line, which is why it needs no confirm screen. */
function summariseReplay(plan: ResolvedPlan): string {
  const models = plan.agents.map(describeAgent).join(" / ");
  const knobs = plan.workflow.knobs
    .map((knob) => `${knob.summaryLabel.toLowerCase()} ${plan.knobs[knob.id]}`)
    .join(", ");
  // Eligibility is stated here rather than left to a confirm screen the fast
  // path does not have — which is exactly what moving it after resolution buys.
  return [plan.workflow.label, models, knobs, eligibleLine(plan.scope, plan.maxWorkItems)]
    .filter(Boolean)
    .join(" · ");
}

/**
 * This run as the store should remember it: **answers only, never outcomes.**
 *
 * Two fields are filtered rather than copied, and for the same reason. A guard
 * a draining workflow was never asked for is `resolved.items.length`, and a
 * wave width a sequential workflow was never asked for is `1` — both are facts
 * about what was resolved, and remembering either would pre-fill the next run's
 * question with a number nobody chose. Left out, the store keeps whatever the
 * last run that *was* asked put there.
 *
 * The scope is remembered as the anchor's number rather than the string that
 * was typed: a number and the URL a maintainer pasted resolve to the same
 * issue, and the number is the one that still reads as a target next month.
 */
export function runToRemember(plan: ResolvedPlan): {
  workflow: { id: string };
  scope: { kind: ScopeKind; target?: string };
  maxWorkItems?: number;
  maxParallel?: number;
  agents: readonly ResolvedAgent[];
  knobs: Readonly<Record<string, number>>;
} {
  const anchor = anchorOf(plan.scope);
  const eligible = plan.scope.executableNodeIds.length;
  return {
    workflow: plan.workflow,
    scope: anchor
      ? { kind: plan.scope.scopeKind, target: String(anchor.number) }
      : { kind: plan.scope.scopeKind },
    maxWorkItems: guardIsAsked(plan.workflow, eligible) ? plan.maxWorkItems : undefined,
    maxParallel: plan.workflow.concurrent ? plan.maxParallel : undefined,
    agents: plan.agents,
    knobs: plan.knobs,
  };
}

// ---------------------------------------------------------------------------
// The walk
// ---------------------------------------------------------------------------

/**
 * The target this scope should be resolved against: the one already given, or
 * the one the store remembers.
 *
 * `origin` gates the target and nothing else. The store lives in the git common
 * dir, so a target written by a sibling Conductor workspace is a different piece
 * of work — and unlike a wrong `kind`, which costs one arrow key, a wrong target
 * is a number you might not read.
 */
function rememberedTarget(state: FlowState): string | undefined {
  if (state.target !== undefined) return state.target;
  const last = state.store?.lastScope;
  if (!last || last.kind !== state.scopeKind) return undefined;
  if (last.origin === undefined || last.origin !== state.origin) return undefined;
  return last.target;
}

function resolveStep(state: FlowState, kind: ScopeKind): ResolveStep {
  const row = SCOPE_ROWS[kind];
  const needsTarget =
    row.targetPrompt !== null && (state.target === undefined || state.retypeTarget === true);
  return {
    kind: "resolve",
    id: "resolve",
    prompt: row.targetPrompt ?? `Reading ${row.label.toLowerCase()} from GitHub`,
    scope: kind,
    needsTarget,
    initialValue: row.targetPrompt === null ? undefined : rememberedTarget(state),
  };
}

/**
 * What to do about a scope that produced no work. Only the relevant options are
 * offered — a retry that cannot help is worse than not being offered — and
 * every one of them keeps the resolved context on screen.
 */
function recoveryStep(kind: ScopeKind, failure: ScopeFailure): SelectQuestion {
  const options: FlowOption[] = [];
  if (failure.retryable) {
    options.push({ value: "retry", label: "Try GitHub again", hint: "Keep this Work scope and target" });
  }
  if (needsTargetFor(kind)) {
    options.push({ value: "target", label: "Enter another target" });
  }
  options.push(
    { value: "scope", label: "Choose another Work scope" },
    { value: "cancel", label: "Cancel" },
  );

  const anchor = failure.anchor;
  return {
    ...select("recovery", "How should Sandcastle recover?", options),
    noteTitle: failure.title,
    note: [
      failure.detail,
      ...(anchor
        ? [
            summaryRow("Resolved", `#${anchor.number} · ${anchor.title}`),
            summaryRow("Labels", anchor.labels.join(", ") || "none"),
          ]
        : []),
    ],
  };
}

/**
 * The first step still outstanding, or `undefined` once the answers settle the
 * run.
 *
 * Work scope leads, and the fast path follows *resolution* rather than
 * preceding it. Three properties come out of that one ordering: the fast path's
 * hint can state eligibility, accepting it always starts a run, and staleness
 * needs no representation at all — a target that has been drained, closed or
 * deregulated since the last run simply fails in place and lands in the
 * recovery that already exists.
 */
export function nextStep(
  state: FlowState,
  effortsFor: EffortsFor,
  workflows: readonly Workflow[] = WORKFLOWS,
): Step | undefined {
  if (state.cancelled) return undefined;

  // 1. What should this run work on? Asked before anything else, for every
  //    workflow, so a run cannot start without a resolved scope.
  const scopeKind = state.scopeKind;
  if (!scopeKind) {
    return select(
      "scope",
      "What should this run work on?",
      SCOPE_ORDER.map((kind) => ({
        value: kind,
        label: SCOPE_ROWS[kind].label,
        hint: SCOPE_ROWS[kind].hint,
      })),
      state.store?.lastScope?.kind,
    );
  }

  // 2. A scope that produced no work, and what can be done about it.
  if (state.failure) return recoveryStep(scopeKind, state.failure);

  // 3. Ask GitHub. Not a question — the shell resolves and folds the outcome
  //    back in — but a step, so that *when* it happens is asserted here.
  if (!state.resolved) return resolveStep(state, scopeKind);
  const resolved = state.resolved;

  // 4. Replay a remembered run in one keystroke. The option's own line is the
  //    confirmation, so accepting it starts the run rather than opening a
  //    confirm screen.
  if (state.repeatLastRun === undefined) {
    const replay = replayPlan(state.store, resolved, workflows);
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

  // 5. Which workflow. Always asked, even while the registry holds one: a list
  //    of one is honest, and it is also what a `lastWorkflowId` no registry
  //    knows falls back to — nothing is silently substituted.
  if (!state.workflowId) {
    return select(
      "workflow",
      "Which workflow should run?",
      workflows.map((workflow) => ({
        value: workflow.id,
        label: workflow.label,
        hint: workflow.description,
      })),
      state.store?.lastWorkflowId,
    );
  }

  const workflow = findWorkflow(state.workflowId, workflows);
  if (!workflow) return undefined;

  // 6. The two numbers, then whatever knobs the workflow still declares.
  const guard = runGuardQuestion(state, workflow);
  if (guard) return guard;

  const parallel = maxParallelQuestion(state, workflow);
  if (parallel) return parallel;

  const knob = knobQuestion(state, workflow);
  if (knob) return knob;

  // 7. One model for every agent? Never asked of a single-agent workflow.
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

  // 8. Model, then effort, once per target.
  for (const target of pickTargets(state, workflow)) {
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

  // 9. Confirm, with the plan the answers came to.
  const plan = planFromWalk(state, workflow, resolved);
  if (plan && state.confirmed === undefined) {
    return {
      ...select("confirm", `Start ${workflow.label}?`, [
        { value: "start", label: `Start ${workflow.label}` },
        { value: "cancel", label: "Cancel" },
      ]),
      noteTitle: "Ready to run Sandcastle",
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

function asNumber(id: string, value: Answer): number {
  if (typeof value !== "number") throw new Error(`${id} needs a number`);
  return value;
}

/** Fold one answer in, leaving the state it was given untouched. */
export function applyAnswer(state: FlowState, step: Step, value: Answer): FlowState {
  const [kind, key] = splitId(step.id);

  switch (kind) {
    case "scope": {
      const chosen = SCOPE_ORDER.find((candidate) => candidate === value);
      if (!chosen) throw new Error(`Unknown Work scope: ${String(value)}`);
      return { ...initialState(state.store, state.origin), scopeKind: chosen };
    }
    case "resolve": {
      if (!isScopeResolution(value)) throw new Error("A resolve step needs a resolution");
      if (!state.scopeKind) throw new Error("A scope was resolved before one was chosen");
      const target = value.target ?? state.target;
      const base: FlowState = { ...state, target, retypeTarget: undefined, failure: undefined };
      const judged = judge(value.outcome);
      return judged.ok ? { ...base, resolved: judged.resolved } : { ...base, failure: judged.failure };
    }
    case "recovery":
      switch (value) {
        case "retry":
          return { ...state, failure: undefined };
        case "target":
          // The target is kept, not cleared: it is what the field pre-fills
          // with, which is the difference between correcting a number and
          // typing one from scratch.
          return { ...state, failure: undefined, retypeTarget: true };
        case "scope":
          return initialState(state.store, state.origin);
        default:
          return { ...state, cancelled: true };
      }
    case "fast-path":
      return { ...state, repeatLastRun: value === "repeat" };
    case "workflow":
      return { ...state, workflowId: String(value) };
    case "run-guard":
      return { ...state, maxWorkItems: asNumber(step.id, value) };
    case "max-parallel":
      return { ...state, maxParallel: asNumber(step.id, value) };
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
    case "knob":
      return { ...state, knobs: { ...state.knobs, [key]: asNumber(step.id, value) } };
    case "confirm":
      return { ...state, confirmed: value === "start" };
    default:
      throw new Error(`Unhandled step: ${step.id}`);
  }
}

/**
 * What the answers came to, or `undefined` when the run was declined. Two ways
 * in: the fast path replays the store outright, and the walk resolves what was
 * confirmed. Neither exists without a resolved Work scope.
 */
export function resolvePlan(
  state: FlowState,
  workflows: readonly Workflow[] = WORKFLOWS,
): ResolvedPlan | undefined {
  const resolved = state.resolved;
  if (!resolved) return undefined;
  if (state.repeatLastRun) return replayPlan(state.store, resolved, workflows);
  if (!state.confirmed) return undefined;
  const workflow = findWorkflow(state.workflowId, workflows);
  if (!workflow) return undefined;
  return planFromWalk(state, workflow, resolved);
}
