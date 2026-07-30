// The picker: the questions, the confirmation screen and the pre-run header.
// Everything the maintainer answers happens here, and nothing here knows how a
// workflow runs.
//
// The output is a `ResolvedPlan` — which workflow, which model and effort per
// agent, and every knob's value — which is the only thing `runner.mts` needs.

import { intro, log, note } from "@clack/prompts";
import { IMPLEMENTER, REVIEWER } from "../agents/catalog.mts";
import {
  DEFAULT_EFFORT,
  findModel,
  RUN_MODELS,
  type RunEffort,
  type RunModel,
} from "../agents/models.mts";
import type { Agent, Workflow } from "../contract.mts";
import { availableEfforts } from "../providers/registry.mts";
import { WORKFLOWS } from "../workflows/registry.mts";
import { chooseOne, wasCancelled } from "./prompts.mts";
import {
  readStoredRunPlan,
  writeStoredRunPlan,
  type RunPlan,
  type StoredSelection,
} from "./store.mts";

const EFFORT_LABELS: Readonly<Record<RunEffort, string>> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "Extra High",
  max: "Max",
};

function effortDescription(effort: RunEffort): string {
  switch (effort) {
    case "low":
      return "Fastest, for small and routine changes";
    case "medium":
      return "Balanced speed and reasoning";
    case "high":
      return "Recommended default for implementation work";
    case "xhigh":
      return "More time for complex, multi-step work";
    case "max":
      return "Maximum available reasoning budget";
  }
}

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
 * Ask for one agent's model and effort. `remembered` only moves the initial
 * cursor — the prompt is always shown, so replaying the last run is
 * enter-enter rather than a silent skip. `promptLabel` is separate from the
 * agent's own label because "same for both" asks once, about neither agent in
 * particular.
 */
async function chooseAgent(
  agent: Agent,
  promptLabel: string,
  remembered: StoredSelection | undefined,
): Promise<ResolvedAgent | undefined> {
  const modelId = await chooseOne(
    `Choose the ${promptLabel} model`,
    RUN_MODELS.map((candidate) => ({
      value: candidate.id,
      label: candidate.label,
      hint: `${candidate.providerLabel} · ${candidate.description}`,
    })),
    remembered?.model,
  );
  if (wasCancelled(modelId)) return undefined;

  // The id came straight out of `RUN_MODELS`, so this lookup cannot miss. It
  // throws rather than asserting non-null so a future catalog change is loud.
  const model = findModel(modelId);
  if (!model) throw new Error(`Unknown model: ${modelId}`);

  const efforts = availableEfforts(model);
  if (!efforts.length) {
    throw new Error(`${model.providerLabel} reports no supported reasoning efforts.`);
  }
  // Prefer the remembered effort, then the recommended default, then the first
  // the CLI actually advertises — which is where clack's cursor lands when
  // `initialValue` matches nothing.
  const rememberedEffort = remembered?.model === model.id ? remembered.effort : undefined;
  const initialEffort = [rememberedEffort, DEFAULT_EFFORT].find(
    (candidate) => candidate !== undefined && efforts.includes(candidate),
  );
  const effort = await chooseOne(
    `Choose ${promptLabel} effort for ${model.label}`,
    efforts.map((candidate) => ({
      value: candidate,
      label: EFFORT_LABELS[candidate],
      hint: effortDescription(candidate),
    })),
    initialEffort,
  );
  if (wasCancelled(effort)) return undefined;

  return { agentId: agent.id, agentLabel: agent.label, model, effort };
}

/** `Claude Opus 5 · High` — one agent's pick on a single line. */
function describeAgent(resolved: ResolvedAgent): string {
  return `${resolved.model.label} · ${EFFORT_LABELS[resolved.effort]}`;
}

/** Left-align every agent label to the same column, whatever the workflow. */
function labelColumn(agents: readonly ResolvedAgent[]): number {
  return Math.max(0, ...agents.map((resolved) => resolved.agentLabel.length)) + 2;
}

/**
 * The picked plan plus the flow's own "same for both" answer, which only the
 * v1 store still needs. `sameForBoth` retires with `rememberRunV1`.
 */
export interface ChosenRun {
  plan: ResolvedPlan;
  sameForBoth: boolean;
}

export async function choosePlan(): Promise<ChosenRun | undefined> {
  // Clack drives the terminal in raw mode, so it needs a real TTY just as the
  // widget it replaced did. It calls `setRawMode` optionally, so without this
  // guard a stdin that lacks it would render a picker whose arrow keys do
  // nothing rather than say why.
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.stdin.setRawMode) {
    throw new Error("Sandcastle must be started from an interactive terminal.");
  }

  // Position 0 is the default workflow; choosing between them is a later slice.
  const workflow = WORKFLOWS[0];
  if (!workflow) throw new Error("No workflows are registered.");

  const remembered = readStoredRunPlan();

  const introLines = ["Pick the model and effort for each phase."];
  if (remembered) introLines.push("Defaults are your last run in this repo.");

  intro("Sandcastle");
  log.message(introLines);

  const sameForBoth = await chooseOne(
    "Use one model for both phases?",
    [
      {
        value: true,
        label: "Same for both",
        hint: "One model and effort drives implement and review",
      },
      {
        value: false,
        label: "Configure separately",
        hint: "Pick a different model or effort per phase",
      },
    ],
    remembered?.sameForBoth ?? true,
  );
  if (wasCancelled(sameForBoth)) return undefined;

  const implementer = await chooseAgent(
    IMPLEMENTER,
    sameForBoth ? "Run" : IMPLEMENTER.label,
    remembered?.implementer,
  );
  if (!implementer) return undefined;
  // "Same for both" is one answer covering two agents: same model and effort,
  // still two entries, because the runner keys its providers by agent id.
  const reviewer = sameForBoth
    ? { ...implementer, agentId: REVIEWER.id, agentLabel: REVIEWER.label }
    : await chooseAgent(REVIEWER, REVIEWER.label, remembered?.reviewer);
  if (!reviewer) return undefined;

  const agents = [implementer, reviewer];
  const column = labelColumn(agents);
  note(
    agents
      .flatMap((resolved) => [
        `${resolved.agentLabel.padEnd(column)}${describeAgent(resolved)}`,
        `${" ".repeat(column)}${resolved.model.providerLabel}`,
      ])
      .join("\n"),
    "Ready to run Sandcastle",
  );

  const confirmed = await chooseOne("Start workflow?", [
    { value: true, label: "Start workflow" },
    { value: false, label: "Cancel" },
  ]);
  if (wasCancelled(confirmed) || !confirmed) return undefined;

  return {
    plan: {
      workflow,
      agents,
      // Every declared knob at its default, so a workflow never reads a
      // missing key. Asking about knobs is a later slice.
      knobs: Object.fromEntries(workflow.knobs.map((knob) => [knob.id, knob.defaultValue])),
    },
    sameForBoth,
  };
}

/** The last thing printed before the first agent starts. */
export function printRunHeader(plan: ResolvedPlan): void {
  const column = labelColumn(plan.agents);
  for (const resolved of plan.agents) {
    log.step(`${resolved.agentLabel.padEnd(column)}${describeAgent(resolved)}`);
  }
}

/**
 * THROWAWAY: adapts a `ResolvedPlan` back to the v1 store's two-role shape so
 * the picks survive this slice. The v2 store — agent ids and knobs, written as
 * upserts — deletes this function and `ChosenRun.sameForBoth` with it.
 */
export function rememberRunV1(chosen: ChosenRun): boolean {
  const find = (agentId: string): ResolvedAgent | undefined =>
    chosen.plan.agents.find((resolved) => resolved.agentId === agentId);
  const implementer = find(IMPLEMENTER.id);
  const reviewer = find(REVIEWER.id);
  if (!implementer || !reviewer) return false;

  const plan: RunPlan = {
    implementer: { model: implementer.model, effort: implementer.effort },
    reviewer: { model: reviewer.model, effort: reviewer.effort },
    sameForBoth: chosen.sameForBoth,
  };
  return writeStoredRunPlan(plan);
}
