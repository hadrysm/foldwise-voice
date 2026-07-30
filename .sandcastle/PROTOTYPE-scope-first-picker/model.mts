// PROTOTYPE — pure state machine for the universal scope-first picker.
//
// Question: does a walk that resolves Work scope before Workflow make scope
// feedback, conditional issue counts, recovery, and the final run contract feel
// coherent across both current workflows?
//
// This module deliberately owns no terminal or GitHub I/O. The throwaway TUI
// drives it with actions and renders the resulting state.

export type ScopeKind = "spec" | "issue" | "queue";
export type WorkflowId = "implement-review" | "review-only";
export type AgentId = "implementer" | "reviewer";
export type PickTarget = AgentId | "*";

export interface IssueSnapshot {
  number: number;
  title: string;
  url: string;
  state: "open" | "closed";
  labels: readonly string[];
  blocked: boolean;
}

export interface ExcludedCounts {
  closed: number;
  blocked: number;
  unreleased: number;
}

export type ScopeResolution =
  | {
      kind: "spec";
      target: IssueSnapshot;
      eligibleCount: number;
      excluded: ExcludedCounts;
    }
  | {
      kind: "issue";
      target: IssueSnapshot;
      eligibleCount: 1;
    }
  | {
      kind: "queue";
      eligibleCount: number;
      excluded: ExcludedCounts;
    };

export interface ValidationFailure {
  title: string;
  detail: string;
  candidate?: IssueSnapshot;
  retryable: boolean;
}

export interface ModelPick {
  modelId: string;
  modelLabel: string;
  effort?: string;
  effortLabel?: string;
}

export type Stage =
  | "scope"
  | "target"
  | "validating"
  | "validation-error"
  | "workflow"
  | "limit"
  | "model-strategy"
  | "model"
  | "effort"
  | "confirm"
  | "complete"
  | "cancelled";

export interface FlowState {
  stage: Stage;
  scopeKind?: ScopeKind;
  targetInput?: string;
  resolution?: ScopeResolution;
  failure?: ValidationFailure;
  workflowId?: WorkflowId;
  issueLimit?: number;
  sharedModel?: boolean;
  picks: Readonly<Partial<Record<PickTarget, ModelPick>>>;
}

export type Action =
  | { type: "select-scope"; scope: ScopeKind }
  | { type: "submit-target"; input: string }
  | { type: "validation-succeeded"; resolution: ScopeResolution }
  | { type: "validation-failed"; failure: ValidationFailure }
  | { type: "retry-validation" }
  | { type: "enter-another-target" }
  | { type: "choose-another-scope" }
  | { type: "select-workflow"; workflowId: WorkflowId }
  | { type: "set-limit"; value: number }
  | { type: "select-model-strategy"; shared: boolean }
  | { type: "select-model"; target: PickTarget; modelId: string; modelLabel: string }
  | { type: "select-effort"; target: PickTarget; effort: string; effortLabel: string }
  | { type: "confirm" }
  | { type: "cancel" };

export function initialState(): FlowState {
  return { stage: "scope", picks: {} };
}

function beginScope(scope: ScopeKind): FlowState {
  return {
    stage: scope === "queue" ? "validating" : "target",
    scopeKind: scope,
    picks: {},
  };
}

function agentsFor(workflowId: WorkflowId | undefined): readonly AgentId[] {
  return workflowId === "review-only" ? ["reviewer"] : ["implementer", "reviewer"];
}

export function pickTargets(state: FlowState): readonly PickTarget[] {
  if (!state.workflowId) return [];
  const agents = agentsFor(state.workflowId);
  if (agents.length === 1) return agents;
  return state.sharedModel ? ["*"] : agents;
}

export function pendingPickTarget(state: FlowState): PickTarget | undefined {
  return pickTargets(state).find((target) => !state.picks[target]?.effort);
}

function stageAfterWorkflow(state: FlowState, workflowId: WorkflowId): Stage {
  if (workflowId === "implement-review" && state.scopeKind === "queue") return "limit";
  if (workflowId === "implement-review") return "model-strategy";
  return "model";
}

function stageAfterLimit(): Stage {
  return "model-strategy";
}

function stageForPicks(state: FlowState): Stage {
  const target = pendingPickTarget(state);
  if (!target) return "confirm";
  return state.picks[target]?.modelId ? "effort" : "model";
}

export function transition(state: FlowState, action: Action): FlowState {
  switch (action.type) {
    case "select-scope":
      return beginScope(action.scope);
    case "submit-target":
      return { ...state, stage: "validating", targetInput: action.input, failure: undefined };
    case "validation-succeeded":
      return {
        ...state,
        stage: "workflow",
        resolution: action.resolution,
        failure: undefined,
      };
    case "validation-failed":
      return { ...state, stage: "validation-error", failure: action.failure };
    case "retry-validation":
      return { ...state, stage: "validating", failure: undefined };
    case "enter-another-target":
      return {
        stage: "target",
        scopeKind: state.scopeKind,
        picks: {},
      };
    case "choose-another-scope":
      return initialState();
    case "select-workflow": {
      const next = { ...state, workflowId: action.workflowId };
      return { ...next, stage: stageAfterWorkflow(next, action.workflowId) };
    }
    case "set-limit":
      return { ...state, issueLimit: action.value, stage: stageAfterLimit() };
    case "select-model-strategy": {
      const next = { ...state, sharedModel: action.shared, picks: {} };
      return { ...next, stage: stageForPicks(next) };
    }
    case "select-model": {
      const next = {
        ...state,
        picks: {
          ...state.picks,
          [action.target]: {
            modelId: action.modelId,
            modelLabel: action.modelLabel,
          },
        },
      };
      return { ...next, stage: stageForPicks(next) };
    }
    case "select-effort": {
      const pick = state.picks[action.target];
      if (!pick) throw new Error(`No model selected for ${action.target}`);
      const next = {
        ...state,
        picks: {
          ...state.picks,
          [action.target]: {
            ...pick,
            effort: action.effort,
            effortLabel: action.effortLabel,
          },
        },
      };
      return { ...next, stage: stageForPicks(next) };
    }
    case "confirm":
      return { ...state, stage: "complete" };
    case "cancel":
      return { ...state, stage: "cancelled" };
  }
}

export function scopeLabel(scope: ScopeKind): string {
  switch (scope) {
    case "spec":
      return "Specific SPEC";
    case "issue":
      return "Specific issue";
    case "queue":
      return "All ready-for-agent issues";
  }
}

export function workflowLabel(workflow: WorkflowId): string {
  return workflow === "implement-review" ? "Implement & Review" : "Review Only";
}

function targetLine(resolution: ScopeResolution): string | undefined {
  if (resolution.kind === "queue") return undefined;
  return `Target       #${resolution.target.number} · ${resolution.target.title}`;
}

function workLine(state: FlowState): string | undefined {
  const resolution = state.resolution;
  const workflow = state.workflowId;
  if (!resolution || !workflow) return undefined;

  if (workflow === "review-only") {
    return resolution.kind === "queue"
      ? "Runs         review once · origin/main...HEAD · commit anchor"
      : `Runs         review once · #${resolution.target.number} is the Spec anchor`;
  }

  if (resolution.kind === "spec") {
    return `Runs         implement → review · drain ${resolution.eligibleCount} eligible descendant${
      resolution.eligibleCount === 1 ? "" : "s"
    }`;
  }
  if (resolution.kind === "issue") {
    return "Runs         implement → review · exactly 1 issue";
  }
  return state.issueLimit === undefined
    ? "Runs         implement → review · issue count not chosen"
    : `Runs         implement → review · up to ${state.issueLimit} issues`;
}

function resolvedPicks(state: FlowState): readonly [AgentId, ModelPick][] {
  if (!state.workflowId) return [];
  const agents = agentsFor(state.workflowId);
  const shared = state.picks["*"];
  return agents.flatMap((agent): readonly [AgentId, ModelPick][] => {
    const pick = shared ?? state.picks[agent];
    return pick ? [[agent, pick]] : [];
  });
}

export function stateLines(state: FlowState): readonly string[] {
  const lines: string[] = [];

  if (state.scopeKind) lines.push(`Work scope   ${scopeLabel(state.scopeKind)}`);
  if (state.targetInput && !state.resolution) lines.push(`Entered      ${state.targetInput}`);

  if (state.resolution) {
    const target = targetLine(state.resolution);
    if (target) lines.push(target);
    if (state.resolution.kind !== "queue") {
      lines.push(`Labels       ${state.resolution.target.labels.join(", ") || "none"}`);
    }
    if (state.resolution.kind === "spec") {
      lines.push(`Eligible     ${state.resolution.eligibleCount} open, unblocked descendants`);
      const skipped = state.resolution.excluded;
      lines.push(
        `Not run      ${skipped.closed} closed · ${skipped.blocked} blocked · ${skipped.unreleased} unreleased`,
      );
    }
    if (state.resolution.kind === "queue") {
      lines.push(`Eligible     ${state.resolution.eligibleCount} repository-wide issues`);
      const skipped = state.resolution.excluded;
      lines.push(
        `Not run      ${skipped.closed} closed · ${skipped.blocked} blocked · ${skipped.unreleased} unreleased`,
      );
    }
  }

  if (state.failure?.candidate) {
    const candidate = state.failure.candidate;
    lines.push(`Resolved     #${candidate.number} · ${candidate.title}`);
    lines.push(`Labels       ${candidate.labels.join(", ") || "none"}`);
  }

  if (state.workflowId) lines.push(`Workflow     ${workflowLabel(state.workflowId)}`);
  const run = workLine(state);
  if (run) lines.push(run);

  for (const [agent, pick] of resolvedPicks(state)) {
    const label = agent === "implementer" ? "Implementer" : "Reviewer";
    lines.push(`${label.padEnd(12)}${pick.modelLabel}${pick.effortLabel ? ` · ${pick.effortLabel}` : ""}`);
  }

  return lines;
}
