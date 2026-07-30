// PROTOTYPE — terminal shell for model.mts. Read-only GitHub access; no agent
// dispatch and no persistence.

import { spawnSync } from "node:child_process";
import {
  cancel,
  intro,
  isCancel,
  log,
  note,
  outro,
  select,
  spinner,
  text,
} from "@clack/prompts";
import { RUN_MODELS, type RunModel } from "../agents/models.mts";
import {
  initialState,
  pendingPickTarget,
  scopeLabel,
  stateLines,
  transition,
  workflowLabel,
  type ExcludedCounts,
  type FlowState,
  type IssueSnapshot,
  type ScopeKind,
  type ScopeResolution,
  type ValidationFailure,
} from "./model.mts";

const READY_LABEL = "ready-for-agent";
const SPEC_LABEL = "spec";
const DEMO_INPUTS = new Set([
  "demo:network",
  "demo:valid",
  "demo:empty",
  "demo:closed",
  "demo:labels",
  "demo:blocked",
]);

interface GitHubIssue {
  number: number;
  title: string;
  html_url: string;
  state: "open" | "closed";
  labels: readonly ({ name: string } | string)[];
  pull_request?: unknown;
  issue_dependencies_summary?: { blocked_by?: number };
}

function run(command: string, args: readonly string[]): string {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.status !== 0) {
    const detail = result.stderr.trim() || result.stdout.trim() || `${command} exited ${result.status}`;
    throw new Error(detail);
  }
  return result.stdout.trim();
}

function runJson<T>(command: string, args: readonly string[]): T {
  const output = run(command, args);
  return JSON.parse(output) as T;
}

function repository(): string {
  const remote = run("git", ["remote", "get-url", "origin"]);
  const match = remote.match(/github\.com[/:]([^/]+)\/([^/]+?)(?:\.git)?$/);
  if (!match) throw new Error(`Cannot infer a GitHub repository from origin: ${remote}`);
  return `${match[1]}/${match[2]}`;
}

function labelsOf(issue: GitHubIssue): readonly string[] {
  return issue.labels.map((label) => (typeof label === "string" ? label : label.name));
}

function snapshotOf(issue: GitHubIssue): IssueSnapshot {
  return {
    number: issue.number,
    title: issue.title,
    url: issue.html_url,
    state: issue.state,
    labels: labelsOf(issue),
    blocked: (issue.issue_dependencies_summary?.blocked_by ?? 0) > 0,
  };
}

function issueDetail(repo: string, number: number): GitHubIssue {
  return runJson<GitHubIssue>("gh", ["api", `repos/${repo}/issues/${number}`]);
}

function parseTarget(input: string, repo: string): number {
  const trimmed = input.trim().toLowerCase();
  if (DEMO_INPUTS.has(trimmed)) return -1;
  if (/^\d+$/.test(trimmed)) return Number(trimmed);

  let url: URL;
  try {
    url = new URL(input.trim());
  } catch {
    throw new Error("Enter a bare issue number or a full GitHub issue URL.");
  }

  const match = url.pathname.match(/^\/([^/]+)\/([^/]+)\/issues\/(\d+)\/?$/);
  if (url.hostname !== "github.com" || !match) {
    throw new Error("Enter a bare issue number or a full GitHub issue URL.");
  }
  const targetRepo = `${match[1]}/${match[2]}`.toLowerCase();
  if (targetRepo !== repo.toLowerCase()) {
    throw new Error(`This run can only target issues in ${repo}.`);
  }
  return Number(match[3]);
}

function validateExplicitTarget(scope: ScopeKind, candidate: IssueSnapshot): ValidationFailure | undefined {
  if (candidate.state === "closed") {
    return {
      title: "That issue is closed",
      detail: "Sandcastle only starts work that is still open.",
      candidate,
      retryable: false,
    };
  }
  if (!candidate.labels.includes(READY_LABEL)) {
    return {
      title: `Missing ${READY_LABEL}`,
      detail: "Release the issue for an AFK agent, or choose a different target.",
      candidate,
      retryable: false,
    };
  }
  if (scope === "spec" && !candidate.labels.includes(SPEC_LABEL)) {
    return {
      title: `Missing ${SPEC_LABEL}`,
      detail: "Specific SPEC accepts only a SPEC that is also ready-for-agent.",
      candidate,
      retryable: false,
    };
  }
  if (candidate.blocked) {
    return {
      title: "That issue is blocked",
      detail: "Resolve its open GitHub dependency before asking Sandcastle to run it.",
      candidate,
      retryable: false,
    };
  }
  return undefined;
}

function listSubIssues(repo: string, number: number): readonly GitHubIssue[] {
  const pages = runJson<readonly (readonly GitHubIssue[])[]>("gh", [
    "api",
    "--paginate",
    "--slurp",
    `repos/${repo}/issues/${number}/sub_issues?per_page=100`,
  ]);
  return pages.flat();
}

function classify(issues: readonly IssueSnapshot[]): {
  eligible: readonly IssueSnapshot[];
  excluded: ExcludedCounts;
} {
  const eligible: IssueSnapshot[] = [];
  const excluded: ExcludedCounts = { closed: 0, blocked: 0, unreleased: 0 };
  for (const issue of issues) {
    if (issue.state === "closed") excluded.closed++;
    else if (issue.blocked) excluded.blocked++;
    else if (!issue.labels.includes(READY_LABEL)) excluded.unreleased++;
    else eligible.push(issue);
  }
  return { eligible, excluded };
}

function descendantsOf(repo: string, root: number): readonly IssueSnapshot[] {
  const descendants: IssueSnapshot[] = [];
  const pending = [root];
  const seen = new Set<number>(pending);
  while (pending.length) {
    const parent = pending.shift();
    if (parent === undefined) break;
    for (const child of listSubIssues(repo, parent)) {
      if (seen.has(child.number)) continue;
      seen.add(child.number);
      const detailed = issueDetail(repo, child.number);
      if (detailed.pull_request) continue;
      descendants.push(snapshotOf(detailed));
      pending.push(child.number);
    }
  }
  return descendants;
}

function queueOf(repo: string): readonly IssueSnapshot[] {
  const rows = runJson<readonly { number: number }[]>("gh", [
    "issue",
    "list",
    "--repo",
    repo,
    "--state",
    "open",
    "--label",
    READY_LABEL,
    "--limit",
    "1000",
    "--json",
    "number",
  ]);
  return rows.map((row) => snapshotOf(issueDetail(repo, row.number)));
}

function demoIssue(
  title: string,
  overrides: Partial<IssueSnapshot> = {},
): IssueSnapshot {
  return {
    number: 999,
    title,
    url: "https://github.com/example/prototype/issues/999",
    state: "open",
    labels: [READY_LABEL, SPEC_LABEL],
    blocked: false,
    ...overrides,
  };
}

function demoResolution(scope: ScopeKind, input: string): ScopeResolution {
  switch (input.trim().toLowerCase()) {
    case "demo:network":
      throw new Error("simulated: unable to connect to api.github.com");
    case "demo:valid":
      return scope === "spec"
        ? {
            kind: "spec",
            target: demoIssue("Prototype universal Work scope SPEC"),
            eligibleCount: 4,
            excluded: { closed: 2, blocked: 1, unreleased: 3 },
          }
        : {
            kind: "issue",
            target: demoIssue("Prototype ready issue", { labels: [READY_LABEL] }),
            eligibleCount: 1,
          };
    case "demo:empty":
      if (scope !== "spec") {
        throw new Error("demo:empty is a Specific SPEC scenario.");
      }
      return {
        kind: "spec",
        target: demoIssue("Prototype SPEC with no runnable descendants"),
        eligibleCount: 0,
        excluded: { closed: 2, blocked: 1, unreleased: 3 },
      };
    case "demo:closed":
      return {
        kind: scope === "spec" ? "spec" : "issue",
        target: demoIssue("Prototype closed target", { state: "closed" }),
        eligibleCount: scope === "spec" ? 2 : 1,
        ...(scope === "spec" ? { excluded: { closed: 0, blocked: 0, unreleased: 0 } } : {}),
      } as ScopeResolution;
    case "demo:labels":
      return {
        kind: scope === "spec" ? "spec" : "issue",
        target: demoIssue("Prototype unreleased target", {
          labels: scope === "spec" ? [SPEC_LABEL] : ["bug"],
        }),
        eligibleCount: scope === "spec" ? 2 : 1,
        ...(scope === "spec" ? { excluded: { closed: 0, blocked: 0, unreleased: 0 } } : {}),
      } as ScopeResolution;
    case "demo:blocked":
      return {
        kind: scope === "spec" ? "spec" : "issue",
        target: demoIssue("Prototype blocked target", { blocked: true }),
        eligibleCount: scope === "spec" ? 2 : 1,
        ...(scope === "spec" ? { excluded: { closed: 0, blocked: 0, unreleased: 0 } } : {}),
      } as ScopeResolution;
    default:
      throw new Error(`Unknown prototype scenario: ${input}`);
  }
}

function resolveScope(state: FlowState): ScopeResolution {
  const scope = state.scopeKind;
  if (!scope) throw new Error("No Work scope selected.");
  const repo = repository();

  if (scope === "queue") {
    const classified = classify(queueOf(repo));
    return {
      kind: "queue",
      eligibleCount: classified.eligible.length,
      excluded: classified.excluded,
    };
  }

  const input = state.targetInput ?? "";
  const demo = DEMO_INPUTS.has(input.trim().toLowerCase())
    ? demoResolution(scope, input)
    : undefined;
  const candidate =
    demo && demo.kind !== "queue"
      ? demo.target
      : snapshotOf(issueDetail(repo, parseTarget(input, repo)));
  const invalid = validateExplicitTarget(scope, candidate);
  if (invalid) throw invalid;

  if (demo) return demo;
  if (scope === "issue") return { kind: "issue", target: candidate, eligibleCount: 1 };

  const classified = classify(descendantsOf(repo, candidate.number));
  return {
    kind: "spec",
    target: candidate,
    eligibleCount: classified.eligible.length,
    excluded: classified.excluded,
  };
}

function failureFrom(error: unknown): ValidationFailure {
  if (
    typeof error === "object" &&
    error !== null &&
    "title" in error &&
    "detail" in error &&
    "retryable" in error
  ) {
    return error as ValidationFailure;
  }
  const detail = error instanceof Error ? error.message : String(error);
  return {
    title: "GitHub validation failed",
    detail,
    retryable: true,
  };
}

function render(state: FlowState): void {
  console.clear();
  intro("Sandcastle · scope-first picker prototype");
  const lines = stateLines(state);
  if (lines.length) note(lines.join("\n"), "Plan so far");
  if (state.failure) log.error(`${state.failure.title}\n${state.failure.detail}`);
}

function cancelled<Value>(value: Value | symbol): value is symbol {
  return isCancel(value);
}

async function askSelect<Value extends string>(
  message: string,
  options: readonly { value: Value; label: string; hint?: string }[],
  initialValue?: Value,
): Promise<Value | symbol> {
  return select<string>({
    message,
    options: options.map((option) =>
      option.hint
        ? { value: option.value, label: option.label, hint: option.hint }
        : { value: option.value, label: option.label },
    ),
    initialValue,
  }) as Promise<Value | symbol>;
}

async function validate(state: FlowState): Promise<FlowState> {
  render(state);
  const progress = spinner();
  progress.start("Validating with GitHub");
  try {
    const resolution = resolveScope(state);
    if (resolution.eligibleCount === 0) {
      progress.stop("GitHub target resolved");
      return transition(state, {
        type: "validation-failed",
        failure: {
          title: "No work is eligible right now",
          detail:
            resolution.kind === "spec"
              ? "This SPEC has no open, unblocked ready-for-agent descendants."
              : "The repository-wide queue has no open, unblocked ready-for-agent issues.",
          candidate: resolution.kind === "spec" ? resolution.target : undefined,
          retryable: true,
        },
      });
    }
    progress.stop("GitHub target resolved");
    return transition(state, { type: "validation-succeeded", resolution });
  } catch (error) {
    const failure = failureFrom(error);
    progress.stop(failure.candidate ? "GitHub target rejected" : "Could not validate Work scope");
    return transition(state, { type: "validation-failed", failure });
  }
}

const EFFORT_LABELS: Readonly<Record<string, string>> = {
  low: "Low",
  medium: "Medium",
  high: "High",
  xhigh: "Extra High",
  max: "Max",
};

function modelFor(state: FlowState): RunModel | undefined {
  const target = pendingPickTarget(state);
  const modelId = target ? state.picks[target]?.modelId : undefined;
  return RUN_MODELS.find((candidate) => candidate.id === modelId);
}

async function main(): Promise<void> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    throw new Error("Run this prototype from an interactive terminal.");
  }

  let state = initialState();
  for (;;) {
    if (state.stage === "validating") {
      state = await validate(state);
      continue;
    }

    render(state);

    if (state.stage === "scope") {
      const answer = await askSelect("What should this run work on?", [
        {
          value: "spec",
          label: "Specific SPEC",
          hint: "Drain every eligible descendant in one run",
        },
        {
          value: "issue",
          label: "Specific issue",
          hint: "Work on exactly one ready-for-agent issue",
        },
        {
          value: "queue",
          label: "All ready-for-agent issues",
          hint: "Use the repository-wide queue",
        },
      ]);
      state = cancelled(answer)
        ? transition(state, { type: "cancel" })
        : transition(state, { type: "select-scope", scope: answer });
      continue;
    }

    if (state.stage === "target") {
      const answer = await text({
        message: `Enter the ${scopeLabel(state.scopeKind!)} URL or issue number`,
        placeholder: "391 or https://github.com/owner/repo/issues/391",
        validate: (value) => {
          const entered = value?.trim() ?? "";
          if (!entered) return "Enter an issue URL or number.";
          try {
            parseTarget(entered, repository());
            return undefined;
          } catch (error) {
            return error instanceof Error ? error.message : String(error);
          }
        },
      });
      state = cancelled(answer)
        ? transition(state, { type: "cancel" })
        : transition(state, { type: "submit-target", input: answer });
      continue;
    }

    if (state.stage === "validation-error") {
      const options: { value: string; label: string; hint?: string }[] = [];
      if (state.failure?.retryable) {
        options.push({
          value: "retry",
          label: "Try GitHub again",
          hint: "Keep this Work scope and target",
        });
      }
      if (state.scopeKind !== "queue") {
        options.push({ value: "target", label: "Enter another target" });
      } else if (state.failure?.title === "No work is eligible right now") {
        options.push({
          value: "demo-queue",
          label: "Continue with demo queue",
          hint: "Prototype-only · pretend 7 issues are eligible",
        });
      }
      options.push(
        { value: "scope", label: "Choose another Work scope" },
        { value: "cancel", label: "Cancel" },
      );
      const answer = await askSelect("How should Sandcastle recover?", options);
      if (cancelled(answer) || answer === "cancel") {
        state = transition(state, { type: "cancel" });
      } else if (answer === "retry") {
        state = transition(state, { type: "retry-validation" });
      } else if (answer === "target") {
        state = transition(state, { type: "enter-another-target" });
      } else if (answer === "demo-queue") {
        state = transition(state, {
          type: "validation-succeeded",
          resolution: {
            kind: "queue",
            eligibleCount: 7,
            excluded: { closed: 4, blocked: 2, unreleased: 5 },
          },
        });
      } else {
        state = transition(state, { type: "choose-another-scope" });
      }
      continue;
    }

    if (state.stage === "workflow") {
      const answer = await askSelect("Which workflow should run?", [
        {
          value: "implement-review",
          label: "Implement & Review",
          hint: "One implement → review loop per work item",
        },
        {
          value: "review-only",
          label: "Review Only",
          hint: "One branch review using this Work scope as its anchor",
        },
      ]);
      state = cancelled(answer)
        ? transition(state, { type: "cancel" })
        : transition(state, { type: "select-workflow", workflowId: answer });
      continue;
    }

    if (state.stage === "limit") {
      const answer = await text({
        message: "How many repository-wide issues should this run work through?",
        placeholder: "1–50 · enter accepts 10",
        defaultValue: "10",
        validate: (value) => {
          const entered = value?.trim() ?? "";
          if (!/^\d+$/.test(entered)) return "Enter a whole number.";
          const count = Number(entered);
          return count < 1 || count > 50 ? "Enter a number between 1 and 50." : undefined;
        },
      });
      state = cancelled(answer)
        ? transition(state, { type: "cancel" })
        : transition(state, { type: "set-limit", value: Number(answer) });
      continue;
    }

    if (state.stage === "model-strategy") {
      const answer = await askSelect("Use one model for every agent?", [
        {
          value: "shared",
          label: "Same for every agent",
          hint: "One model and effort drives both",
        },
        {
          value: "separate",
          label: "Configure separately",
          hint: "Pick a different model or effort per agent",
        },
      ]);
      state = cancelled(answer)
        ? transition(state, { type: "cancel" })
        : transition(state, { type: "select-model-strategy", shared: answer === "shared" });
      continue;
    }

    if (state.stage === "model") {
      const target = pendingPickTarget(state);
      if (!target) throw new Error("Prototype entered model stage without a target.");
      const targetLabel =
        target === "*" ? "Run" : target === "implementer" ? "Implementer" : "Reviewer";
      const answer = await askSelect(
        `Choose the ${targetLabel} model`,
        RUN_MODELS.map((model) => ({
          value: model.id,
          label: model.label,
          hint: `${model.providerLabel} · ${model.description}`,
        })),
      );
      if (cancelled(answer)) {
        state = transition(state, { type: "cancel" });
      } else {
        const model = RUN_MODELS.find((candidate) => candidate.id === answer);
        if (!model) throw new Error(`Unknown model ${answer}`);
        state = transition(state, {
          type: "select-model",
          target,
          modelId: model.id,
          modelLabel: model.label,
        });
      }
      continue;
    }

    if (state.stage === "effort") {
      const target = pendingPickTarget(state);
      const model = modelFor(state);
      if (!target || !model) throw new Error("Prototype entered effort stage without a model.");
      const targetLabel =
        target === "*" ? "Run" : target === "implementer" ? "Implementer" : "Reviewer";
      const answer = await askSelect(
        `Choose ${targetLabel} effort for ${model.label}`,
        model.efforts.map((effort) => ({
          value: effort,
          label: EFFORT_LABELS[effort],
        })),
        "high",
      );
      state = cancelled(answer)
        ? transition(state, { type: "cancel" })
        : transition(state, {
            type: "select-effort",
            target,
            effort: answer,
            effortLabel: EFFORT_LABELS[answer],
          });
      continue;
    }

    if (state.stage === "confirm") {
      const answer = await askSelect(`Start ${workflowLabel(state.workflowId!)}?`, [
        {
          value: "start",
          label: `Start ${workflowLabel(state.workflowId!)}`,
          hint: "Prototype only — no agent will be dispatched",
        },
        { value: "cancel", label: "Cancel" },
      ]);
      state =
        !cancelled(answer) && answer === "start"
          ? transition(state, { type: "confirm" })
          : transition(state, { type: "cancel" });
      continue;
    }

    if (state.stage === "complete") {
      log.success("Plan accepted. This prototype would now hand it to the runner.");
      outro("No agent was dispatched and nothing was saved.");
      return;
    }

    cancel("Sandcastle cancelled. Nothing was saved.");
    return;
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`\nCannot start scope-picker prototype\n\n${message}\n`);
  process.exitCode = 1;
});
