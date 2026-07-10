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

import { execSync, spawnSync } from "node:child_process";
import { emitKeypressEvents } from "node:readline";
import * as sandcastle from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Maximum number of implement→review cycles to run before stopping.
// Each cycle works on one issue. Raise this to process more issues per run.
const MAX_ITERATIONS = 10;

type RunEffort = "low" | "medium" | "high" | "xhigh" | "max";
type Provider = "claude-code" | "codex";
type VersionComponents = readonly [number, number, number];
type ModelID =
  | "claude-fable-5"
  | "claude-opus-4-8"
  | "claude-sonnet-4-6"
  | "gpt-5.6-sol"
  | "gpt-5.5";

interface MinimumVersion {
  components: VersionComponents;
  label: string;
}

interface RunModel {
  id: ModelID;
  label: string;
  provider: Provider;
  providerLabel: string;
  description: string;
  efforts: readonly RunEffort[];
  minimumCliVersion?: MinimumVersion;
}

interface RunConfiguration {
  model: RunModel;
  effort: RunEffort;
}

const COMMON_EFFORTS = ["low", "medium", "high", "xhigh"] as const;

const PROVIDERS = {
  "claude-code": {
    executable: "claude",
    helpArgs: ["--help"],
    authArgs: ["auth", "status"],
    authHint: "Run `claude auth login` and try again.",
    isAuthenticated: (output: string) => /"loggedIn"\s*:\s*true/.test(output),
    createAgent: (model: ModelID, effort: RunEffort) =>
      sandcastle.claudeCode(model, { effort }),
  },
  codex: {
    executable: "codex",
    helpArgs: ["exec", "--help"],
    authArgs: ["login", "status"],
    authHint: "Run `codex login` and try again.",
    isAuthenticated: (output: string) => /logged in/i.test(output),
    createAgent: (model: ModelID, effort: RunEffort) => {
      if (effort === "max") {
        throw new Error("Max effort is not supported by the installed Sandcastle Codex adapter.");
      }
      return sandcastle.codex(model, { effort });
    },
  },
} as const;

const RUN_MODELS: readonly RunModel[] = [
  {
    id: "claude-fable-5",
    label: "Claude Fable 5",
    provider: "claude-code",
    providerLabel: "Anthropic · Claude Code",
    description: "Current default · strong general-purpose coding",
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

function executeProviderCommand(
  provider: Provider,
  args: readonly string[],
  failureMessage: string,
): string {
  const result = spawnSync(PROVIDERS[provider].executable, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error || result.status !== 0) throw new Error(failureMessage);
  return `${result.stdout}\n${result.stderr}`.trim();
}

function availableEfforts(model: RunModel): readonly RunEffort[] {
  const provider = PROVIDERS[model.provider];
  const help = executeProviderCommand(
    model.provider,
    provider.helpArgs,
    `${model.providerLabel} is not installed or is unavailable in PATH.`,
  );

  if (model.provider !== "claude-code") return model.efforts;

  const advertised = help.match(/Effort level[^\n]*\n?[^\n]*\(([^)]+)\)/)?.[1];
  if (!advertised) return model.efforts.filter((effort) => effort !== "max");
  const supported = new Set(advertised.split(",").map((effort) => effort.trim()));
  return model.efforts.filter((effort) => supported.has(effort));
}

async function chooseRunConfiguration(): Promise<RunConfiguration | undefined> {
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.stdin.setRawMode) {
    throw new Error("Sandcastle must be started from an interactive terminal.");
  }

  emitKeypressEvents(process.stdin);
  const wasRaw = process.stdin.isRaw;
  process.stdin.setRawMode(true);
  process.stdin.resume();

  try {
    process.stdout.write(
      `\n${colors.cyan}◆${colors.reset} ${colors.white}Sandcastle${colors.reset}\n` +
        `${colors.dim}One model for implement → review.${colors.reset}\n\n`,
    );

    const model = await selectOption(
      "Choose a Run model",
      RUN_MODELS.map((candidate) => ({
        label: candidate.label,
        description: `${candidate.providerLabel} · ${candidate.description}`,
        value: candidate,
      })),
    );
    if (!model) return undefined;
    process.stdout.write(`${colors.green}◇${colors.reset} Model   ${model.label}\n`);

    const efforts = availableEfforts(model);
    if (!efforts.length) {
      throw new Error(`${model.providerLabel} reports no supported reasoning efforts.`);
    }
    const highIndex = efforts.indexOf("high");
    const effort = await selectOption(
      `Choose effort for ${model.label}`,
      efforts.map((candidate) => ({
        label: EFFORT_LABELS[candidate],
        description: effortDescription(candidate),
        value: candidate,
      })),
      highIndex === -1 ? 0 : highIndex,
    );
    if (!effort) return undefined;
    process.stdout.write(`${colors.green}◇${colors.reset} Effort  ${EFFORT_LABELS[effort]}\n\n`);

    process.stdout.write(
      `${colors.white}Ready to run Sandcastle${colors.reset}\n\n` +
        `  Model     ${model.label}\n` +
        `  Provider  ${model.providerLabel}\n` +
        `  Effort    ${EFFORT_LABELS[effort]}\n` +
        "  Workflow  Implement → Review\n\n",
    );

    const confirmed = await selectOption(
      "Start workflow?",
      [
        { label: "Start workflow", value: true },
        { label: "Cancel", value: false },
      ],
    );

    return confirmed ? { model, effort } : undefined;
  } finally {
    process.stdin.setRawMode(wasRaw);
    process.stdin.pause();
  }
}

function parseVersion(output: string): VersionComponents | undefined {
  const match = output.match(/(\d+)\.(\d+)\.(\d+)/);
  if (!match?.[1] || !match[2] || !match[3]) return undefined;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

function versionIsAtLeast(actual: VersionComponents, minimum: VersionComponents): boolean {
  for (let index = 0; index < minimum.length; index++) {
    const difference = (actual[index] ?? 0) - (minimum[index] ?? 0);
    if (difference !== 0) return difference > 0;
  }
  return true;
}

function validateRunConfiguration(configuration: RunConfiguration): void {
  const provider = PROVIDERS[configuration.model.provider];
  const versionOutput = executeProviderCommand(
    configuration.model.provider,
    ["--version"],
    `${configuration.model.providerLabel} is not installed or is unavailable in PATH.`,
  );
  const minimum = configuration.model.minimumCliVersion;
  if (minimum) {
    const installed = parseVersion(versionOutput);
    if (!installed || !versionIsAtLeast(installed, minimum.components)) {
      throw new Error(
        `${configuration.model.label} requires ${configuration.model.providerLabel} ${minimum.label} or newer.\nInstalled: ${versionOutput}`,
      );
    }
  }

  const authOutput = executeProviderCommand(
    configuration.model.provider,
    provider.authArgs,
    `Could not verify the ${configuration.model.providerLabel} login. ${provider.authHint}`,
  );
  if (!provider.isAuthenticated(authOutput)) {
    throw new Error(`No active ${configuration.model.providerLabel} login. ${provider.authHint}`);
  }
}

function createRunAgent(configuration: RunConfiguration) {
  return PROVIDERS[configuration.model.provider].createAgent(
    configuration.model.id,
    configuration.effort,
  );
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
  const configuration = await chooseRunConfiguration();
  if (!configuration) {
    console.log(`${colors.dim}Sandcastle cancelled.${colors.reset}`);
    return;
  }

  validateRunConfiguration(configuration);
  const runAgent = createRunAgent(configuration);
  console.log(
    `${colors.green}◆${colors.reset} Starting ${configuration.model.label} · ${EFFORT_LABELS[configuration.effort]}\n`,
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
      agent: runAgent,
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
      agent: runAgent,
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
