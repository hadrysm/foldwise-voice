// Sequential Reviewer — in-place implement-then-review loop
//
// This template drives a two-phase workflow per issue:
//   Phase 1 (Implement): An agent picks the next open issue, commits the
//                        changes, and signals completion.
//   Phase 2 (Review):    A second agent reviews that iteration's commits and
//                        either approves them or corrects them in place.
//
// Both phases run directly on the CURRENT branch via the `head` branch
// strategy — no per-cycle branch, no host worktree. This runner is launched
// inside Conductor, where the workspace is already an isolated git worktree on
// its own branch, so Sandcastle adds no isolation of its own: the agents'
// commits land straight on the workspace branch for review
// (see docs/adr/0001-sandcastle-in-place-not-sandboxed.md).
//
// The outer loop repeats up to MAX_ITERATIONS times, processing one issue per
// iteration and stopping early once the backlog is exhausted (an implement
// phase that produces no commits).
//
// Agents run directly on the macOS host via noSandbox() because the app cannot
// build in a Linux container (see the same ADR).
//
// Usage (from the repo root — Sandcastle resolves prompt files and git
// against process.cwd()):
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts

import { execSync } from "node:child_process";
import * as sandcastle from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { cancel, intro, log, note } from "@clack/prompts";
import {
  DEFAULT_EFFORT,
  findModel,
  RUN_MODELS,
  type ModelID,
  type RunEffort,
} from "./agents/models.mts";
import { chooseOne, wasCancelled } from "./cli/prompts.mts";
import {
  readStoredRunPlan,
  writeStoredRunPlan,
  type RunConfiguration,
  type RunPlan,
  type StoredSelection,
} from "./cli/store.mts";
import { availableEfforts, PROVIDERS, validateModel } from "./providers/registry.mts";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Maximum number of implement→review cycles to run before stopping.
// Each cycle works on one issue. Raise this to process more issues per run.
const MAX_ITERATIONS = 10;

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

/**
 * Ask for one phase's model and effort. `remembered` only moves the initial
 * cursor — the prompt is always shown, so replaying the last run is
 * enter-enter rather than a silent skip.
 */
async function chooseConfiguration(
  phaseLabel: string,
  remembered: StoredSelection | undefined,
): Promise<RunConfiguration | undefined> {
  const modelId = await chooseOne(
    `Choose the ${phaseLabel} model`,
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
    `Choose ${phaseLabel} effort for ${model.label}`,
    efforts.map((candidate) => ({
      value: candidate,
      label: EFFORT_LABELS[candidate],
      hint: effortDescription(candidate),
    })),
    initialEffort,
  );
  if (wasCancelled(effort)) return undefined;

  return { model, effort };
}

async function choosePlan(): Promise<RunPlan | undefined> {
  // Clack drives the terminal in raw mode, so it needs a real TTY just as the
  // widget it replaced did. It calls `setRawMode` optionally, so without this
  // guard a stdin that lacks it would render a picker whose arrow keys do
  // nothing rather than say why.
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.stdin.setRawMode) {
    throw new Error("Sandcastle must be started from an interactive terminal.");
  }

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

  const implementer = await chooseConfiguration(
    sameForBoth ? "Run" : "Implementer",
    remembered?.implementer,
  );
  if (!implementer) return undefined;
  const reviewer = sameForBoth
    ? implementer
    : await chooseConfiguration("Reviewer", remembered?.reviewer);
  if (!reviewer) return undefined;

  note(
    [
      `Implement  ${implementer.model.label} · ${EFFORT_LABELS[implementer.effort]}`,
      `           ${implementer.model.providerLabel}`,
      `Review     ${reviewer.model.label} · ${EFFORT_LABELS[reviewer.effort]}`,
      `           ${reviewer.model.providerLabel}`,
    ].join("\n"),
    "Ready to run Sandcastle",
  );

  const confirmed = await chooseOne("Start workflow?", [
    { value: true, label: "Start workflow" },
    { value: false, label: "Cancel" },
  ]);
  if (wasCancelled(confirmed) || !confirmed) return undefined;

  return { implementer, reviewer, sameForBoth };
}

/**
 * Validate every distinct model in the plan — the two phases may run different
 * models, and even different providers. Checking by model id rather than by
 * phase keeps the common "same for both" case to a single pass.
 */
function validateRunPlan(plan: RunPlan): void {
  const validated = new Set<ModelID>();
  for (const configuration of [plan.implementer, plan.reviewer]) {
    if (validated.has(configuration.model.id)) continue;
    validated.add(configuration.model.id);
    validateModel(configuration.model);
  }
}

// Hooks run on the host checkout before the agent starts each phase.
// Pre-resolving Swift dependencies keeps the agent's first build fast; the
// command is idempotent, so running it once per phase is harmless.
const hooks = {
  sandbox: { onSandboxReady: [{ command: "swift package resolve" }] },
};

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const plan = await choosePlan();
  if (!plan) {
    cancel("Sandcastle cancelled.");
    return;
  }

  validateRunPlan(plan);

  // Remember the picks before the loop starts — well ahead of the first
  // REVIEW_BASE capture, and outside the worktree, so nothing an agent commits
  // can be affected by this write.
  if (!writeStoredRunPlan(plan)) {
    log.warn("Could not save these picks for next time.");
  }

  const implementAgent = PROVIDERS[plan.implementer.model.provider].createAgent(
    plan.implementer.model.id,
    plan.implementer.effort,
  );
  // Reuse the one agent when both phases match, so "same for both" behaves
  // exactly as it did before the split.
  const reviewAgent =
    plan.implementer.model.id === plan.reviewer.model.id &&
    plan.implementer.effort === plan.reviewer.effort
      ? implementAgent
      : PROVIDERS[plan.reviewer.model.provider].createAgent(
          plan.reviewer.model.id,
          plan.reviewer.effort,
        );

  log.step(
    `Implement  ${plan.implementer.model.label} · ${EFFORT_LABELS[plan.implementer.effort]}`,
  );
  log.step(`Review     ${plan.reviewer.model.label} · ${EFFORT_LABELS[plan.reviewer.effort]}`);

  for (let iteration = 1; iteration <= MAX_ITERATIONS; iteration++) {
    console.log(`\n=== Iteration ${iteration}/${MAX_ITERATIONS} ===\n`);

    // Capture HEAD before the implementer runs. In `head` mode the implementer
    // and reviewer both work on the current branch, so Sandcastle's built-in
    // TARGET_BRANCH equals HEAD and can't delimit this iteration's work. We hand
    // the reviewer this SHA as REVIEW_BASE so it diffs exactly the commits this
    // iteration produced.
    const reviewBase = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();

    // -------------------------------------------------------------------------
    // Phase 1: Implement
    //
    // The agent picks the next open issue, writes the implementation (using
    // RGR: Red → Green → Refactor), and commits the result. maxIterations: 1
    // keeps it to a single issue so the reviewer sees one issue's diff; a higher
    // value would let one pass drain the whole backlog and defeat per-issue
    // review. The agent signals completion via <promise>COMPLETE</promise>.
    // -------------------------------------------------------------------------
    const implement = await sandcastle.run({
      name: "implementer",
      sandbox: noSandbox(),
      branchStrategy: { type: "head" },
      agent: implementAgent,
      maxIterations: 1,
      hooks,
      promptFile: "./.sandcastle/implement-prompt.md",
    });

    if (!implement.commits.length) {
      // No commits means the backlog is empty or every remaining issue is
      // blocked — there is nothing left to implement or review, so stop.
      console.log("Implementation agent made no commits. Stopping.");
      break;
    }

    console.log(`\nImplementation complete. Commits: ${implement.commits.length}`);

    // -------------------------------------------------------------------------
    // Phase 2: Review
    //
    // A second agent reviews this iteration's commits (everything since
    // REVIEW_BASE on the current branch) and either approves or corrects them in
    // place.
    // -------------------------------------------------------------------------
    await sandcastle.run({
      name: "reviewer",
      sandbox: noSandbox(),
      branchStrategy: { type: "head" },
      agent: reviewAgent,
      maxIterations: 1,
      hooks,
      promptFile: "./.sandcastle/review-prompt.md",
      promptArgs: {
        REVIEW_BASE: reviewBase,
      },
    });

    console.log("\nReview complete.");
  }

  console.log("\nAll done.");
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`\nCannot start Sandcastle\n\n${message}\n`);
  process.exitCode = 1;
});
