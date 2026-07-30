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
import { emitKeypressEvents } from "node:readline";
import * as sandcastle from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import { DEFAULT_EFFORT, RUN_MODELS, type ModelID, type RunEffort } from "./agents/models.mts";
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

/** Width that keeps the picker's echoed "<phase> model/effort" values aligned. */
const PHASE_LABEL_WIDTH = "Implementer effort".length;

const EFFORT_LABELS: Readonly<Record<RunEffort, string>> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "Extra High",
  max: "Max",
};

const colors = {
  cyan: "\u001B[36m",
  dim: "\u001B[2m",
  green: "\u001B[32m",
  red: "\u001B[31m",
  reset: "\u001B[0m",
  white: "\u001B[97m",
};

interface SelectOption<T> {
  label: string;
  description?: string;
  value: T;
}

interface Keypress {
  ctrl?: boolean;
  name?: string;
}

function clearRenderedLines(lineCount: number): void {
  if (lineCount > 0) {
    process.stdout.write(`\u001B[${lineCount}A\u001B[0J`);
  }
}

function wrapText(text: string, width: number): string[] {
  const lines: string[] = [];
  let line = "";

  for (const word of text.split(/\s+/)) {
    if (!word) continue;
    if (!line) {
      line = word;
      continue;
    }
    if (line.length + word.length + 1 <= width) {
      line += ` ${word}`;
      continue;
    }
    lines.push(line);
    line = word;
  }

  if (line) lines.push(line);
  return lines;
}

async function selectOption<T>(
  prompt: string,
  options: readonly SelectOption<T>[],
  defaultIndex = 0,
): Promise<T | undefined> {
  let selectedIndex = defaultIndex;
  let renderedLines = 0;

  const render = (): void => {
    clearRenderedLines(renderedLines);
    const terminalWidth = Math.max(process.stdout.columns ?? 80, 24);
    const lines = wrapText(prompt, terminalWidth).map(
      (line) => `${colors.white}${line}${colors.reset}`,
    );
    lines.push("");
    for (const [index, option] of options.entries()) {
      const selected = index === selectedIndex;
      const marker = selected ? `${colors.cyan}❯${colors.reset}` : " ";
      const label = selected ? `${colors.white}${option.label}${colors.reset}` : option.label;
      lines.push(`${marker} ${label}`);
      if (selected && option.description) {
        for (const descriptionLine of wrapText(option.description, terminalWidth - 4)) {
          lines.push(
            `${colors.cyan}│${colors.reset}   ${colors.dim}${descriptionLine}${colors.reset}`,
          );
        }
      }
    }
    lines.push("");
    for (const footerLine of wrapText("↑↓ move  ·  enter select  ·  esc cancel", terminalWidth)) {
      lines.push(`${colors.dim}${footerLine}${colors.reset}`);
    }
    process.stdout.write(`${lines.join("\n")}\n`);
    renderedLines = lines.length;
  };

  render();

  return new Promise((resolve) => {
    const finish = (value: T | undefined): void => {
      process.stdin.off("keypress", onKeypress);
      clearRenderedLines(renderedLines);
      resolve(value);
    };

    const onKeypress = (_input: string, key: Keypress): void => {
      if ((key.ctrl && key.name === "c") || key.name === "escape") {
        finish(undefined);
        return;
      }
      if (key.name === "up") {
        selectedIndex = (selectedIndex - 1 + options.length) % options.length;
        render();
        return;
      }
      if (key.name === "down") {
        selectedIndex = (selectedIndex + 1) % options.length;
        render();
        return;
      }
      if (key.name === "return") {
        finish(options[selectedIndex]?.value);
      }
    };

    process.stdin.on("keypress", onKeypress);
  });
}

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
  const rememberedIndex = RUN_MODELS.findIndex((candidate) => candidate.id === remembered?.model);
  const model = await selectOption(
    `Choose the ${phaseLabel} model`,
    RUN_MODELS.map((candidate) => ({
      label: candidate.label,
      description: `${candidate.providerLabel} · ${candidate.description}`,
      value: candidate,
    })),
    rememberedIndex === -1 ? 0 : rememberedIndex,
  );
  if (!model) return undefined;
  process.stdout.write(
    `${colors.green}◇${colors.reset} ${`${phaseLabel} model`.padEnd(PHASE_LABEL_WIDTH)}  ${model.label}\n`,
  );

  const efforts = availableEfforts(model);
  if (!efforts.length) {
    throw new Error(`${model.providerLabel} reports no supported reasoning efforts.`);
  }
  // Prefer the remembered effort, then the recommended default, then the first
  // the CLI actually advertises.
  const preferred = remembered?.model === model.id ? remembered.effort : DEFAULT_EFFORT;
  const preferredIndex = efforts.indexOf(preferred);
  const defaultIndex = preferredIndex === -1 ? efforts.indexOf(DEFAULT_EFFORT) : preferredIndex;
  const effort = await selectOption(
    `Choose ${phaseLabel} effort for ${model.label}`,
    efforts.map((candidate) => ({
      label: EFFORT_LABELS[candidate],
      description: effortDescription(candidate),
      value: candidate,
    })),
    defaultIndex === -1 ? 0 : defaultIndex,
  );
  if (!effort) return undefined;
  process.stdout.write(
    `${colors.green}◇${colors.reset} ${`${phaseLabel} effort`.padEnd(PHASE_LABEL_WIDTH)}  ${EFFORT_LABELS[effort]}\n`,
  );

  return { model, effort };
}

async function choosePlan(): Promise<RunPlan | undefined> {
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.stdin.setRawMode) {
    throw new Error("Sandcastle must be started from an interactive terminal.");
  }

  emitKeypressEvents(process.stdin);
  const wasRaw = process.stdin.isRaw;
  process.stdin.setRawMode(true);
  process.stdin.resume();

  const remembered = readStoredRunPlan();

  try {
    process.stdout.write(
      `\n${colors.cyan}◆${colors.reset} ${colors.white}Sandcastle${colors.reset}\n` +
        `${colors.dim}Pick the model and effort for each phase.${colors.reset}\n` +
        (remembered
          ? `${colors.dim}Defaults are your last run in this repo.${colors.reset}\n\n`
          : "\n"),
    );

    const sameForBoth = await selectOption(
      "Use one model for both phases?",
      [
        {
          label: "Same for both",
          description: "One model and effort drives implement and review",
          value: true,
        },
        {
          label: "Configure separately",
          description: "Pick a different model or effort per phase",
          value: false,
        },
      ],
      remembered?.sameForBoth === false ? 1 : 0,
    );
    if (sameForBoth === undefined) return undefined;

    let implementer: RunConfiguration | undefined;
    let reviewer: RunConfiguration | undefined;

    if (sameForBoth) {
      implementer = await chooseConfiguration("Run", remembered?.implementer);
      if (!implementer) return undefined;
      reviewer = implementer;
    } else {
      implementer = await chooseConfiguration("Implementer", remembered?.implementer);
      if (!implementer) return undefined;
      reviewer = await chooseConfiguration("Reviewer", remembered?.reviewer);
      if (!reviewer) return undefined;
    }

    process.stdout.write(
      `\n${colors.white}Ready to run Sandcastle${colors.reset}\n\n` +
        `  Implement  ${implementer.model.label} · ${EFFORT_LABELS[implementer.effort]}\n` +
        `             ${colors.dim}${implementer.model.providerLabel}${colors.reset}\n` +
        `  Review     ${reviewer.model.label} · ${EFFORT_LABELS[reviewer.effort]}\n` +
        `             ${colors.dim}${reviewer.model.providerLabel}${colors.reset}\n\n`,
    );

    const confirmed = await selectOption(
      "Start workflow?",
      [
        { label: "Start workflow", value: true },
        { label: "Cancel", value: false },
      ],
    );

    return confirmed ? { implementer, reviewer, sameForBoth } : undefined;
  } finally {
    process.stdin.setRawMode(wasRaw);
    process.stdin.pause();
  }
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
    console.log(`${colors.dim}Sandcastle cancelled.${colors.reset}`);
    return;
  }

  validateRunPlan(plan);

  // Remember the picks before the loop starts — well ahead of the first
  // REVIEW_BASE capture, and outside the worktree, so nothing an agent commits
  // can be affected by this write.
  if (!writeStoredRunPlan(plan)) {
    console.log(`${colors.dim}Could not save these picks for next time.${colors.reset}`);
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

  console.log(
    `${colors.green}◆${colors.reset} Implement ${plan.implementer.model.label} · ${EFFORT_LABELS[plan.implementer.effort]}\n` +
      `${colors.green}◆${colors.reset} Review    ${plan.reviewer.model.label} · ${EFFORT_LABELS[plan.reviewer.effort]}\n`,
  );

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
  console.error(`\n${colors.red}Cannot start Sandcastle${colors.reset}\n\n${message}\n`);
  process.exitCode = 1;
});
