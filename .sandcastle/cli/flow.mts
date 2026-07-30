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
import { readStoredRun, type StoredPick, type StoredRun } from "./store.mts";

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
  remembered: StoredPick | undefined,
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
 * Whether every remembered agent was pointed at the same model and effort — the
 * initial answer to "one model for both?", derived rather than stored, because
 * the answer is a shape the picks already have. A pick the store dropped counts
 * as a mismatch, which lands on "configure separately" and so shows every
 * prompt rather than silently copying a surviving pick onto both agents.
 */
function remembersOneModelForAll(remembered: StoredRun, agents: readonly Agent[]): boolean {
  const picks = agents.map((agent) => remembered.agents[agent.id]);
  const [first] = picks;
  if (!first) return false;
  return picks.every((pick) => pick?.model === first.model && pick?.effort === first.effort);
}

export async function choosePlan(): Promise<ResolvedPlan | undefined> {
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

  const remembered = readStoredRun();

  const introLines = ["Pick the model and effort for each phase."];
  if (remembered) introLines.push("Defaults are your last run in this repo.");

  intro("Sandcastle");
  log.message(introLines);

  const oneModelForBoth = await chooseOne(
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
    remembered ? remembersOneModelForAll(remembered, workflow.agents) : true,
  );
  if (wasCancelled(oneModelForBoth)) return undefined;

  const implementer = await chooseAgent(
    IMPLEMENTER,
    oneModelForBoth ? "Run" : IMPLEMENTER.label,
    remembered?.agents[IMPLEMENTER.id],
  );
  if (!implementer) return undefined;
  // "Same for both" is one answer covering two agents: same model and effort,
  // still two entries, because the runner keys its providers by agent id — and
  // because the store remembers one entry per agent, not one shared pick.
  const reviewer = oneModelForBoth
    ? { ...implementer, agentId: REVIEWER.id, agentLabel: REVIEWER.label }
    : await chooseAgent(REVIEWER, REVIEWER.label, remembered?.agents[REVIEWER.id]);
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
    workflow,
    agents,
    // Every declared knob at its default, so a workflow never reads a missing
    // key. Asking about knobs is a later slice.
    knobs: Object.fromEntries(workflow.knobs.map((knob) => [knob.id, knob.defaultValue])),
  };
}

/** The last thing printed before the first agent starts. */
export function printRunHeader(plan: ResolvedPlan): void {
  const column = labelColumn(plan.agents);
  for (const resolved of plan.agents) {
    log.step(`${resolved.agentLabel.padEnd(column)}${describeAgent(resolved)}`);
  }
}
