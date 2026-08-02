// The only module that calls `sandcastle.run()`, and therefore the only place
// ADR-0001's constraint is written down: agents run unsandboxed
// (`noSandbox()`, because this repository's toolchain cannot build in a Linux
// container) and in place on the current branch (`head`, because this runner is
// launched inside Conductor, where the workspace is already an isolated
// worktree on its own branch, so Sandcastle adds no isolation of its own). See
// docs/adr/0001-sandcastle-in-place-not-sandboxed.md. A workflow cannot
// contradict either one, because `DispatchOptions` is a two-key allow-list that
// names neither.
//
// Nothing here knows what this repository is written in. The commands that do
// live in `.sandcastle/repo.mts`, and the runner only ever passes them through
// — it never reads their output and never branches on their exit code.
//
// Split by side effect. `resolveAgents`, `distinctModels`, `workList`,
// `workspaceProblems` and `withScopeArgs` are pure — every provider factory is
// an object literal — so the decisions they carry are testable without a CLI, a
// login or a git repository. `prepare` is the part that spawns, and it is what
// makes eager validation *structural*: it returns the only value a `Dispatch`
// can be obtained from, so no auth failure, no dirty tree and no leftover branch
// can surface at item seven.

import { execSync } from "node:child_process";
import { resolve } from "node:path";
import * as sandcastle from "@ai-hero/sandcastle";
import type { AgentProvider } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import type { RunModel } from "./agents/models.mts";
import type { ResolvedPlan } from "./cli/flow.mts";
import type { Dispatch, DispatchOptions } from "./contract.mts";
import type { IssueReads, RunCore, WorkspaceGit } from "./drivers/core.mts";
import { runnableDriver } from "./drivers/registry.mts";
import { PROVIDERS, validateModel } from "./providers/registry.mts";
import { repo } from "./repo.mts";
import {
  assertGitHubAuth,
  ghTransport,
  readHandoffState,
  readLiveState,
  revalidate,
} from "./scope/github.mts";
import {
  anchorRecord,
  runOrder,
  truncate,
  workRecord,
  type WorkItem,
  type WorkScopeSnapshot,
} from "./scope/snapshot.mts";

// Under `noSandbox()` the "sandbox" *is* the host checkout, so this is where
// `repo.onHostReady` lands. Every command it names is idempotent by contract,
// which is what makes running them once per dispatch harmless.
// `repo.onWorktreeReady` has no site on this path: `createWorktree` executes
// `host.onWorktreeReady`, and that path arrives with the wave-parallel driver.
const HOOKS = {
  sandbox: { onSandboxReady: repo.onHostReady },
};

/**
 * The prompt-arg names the runner and its drivers write. Five, and disjoint from
 * the one key a body writes (`REVIEW_BASE`) — few enough to assert rather than
 * leave to convention.
 */
export const RESERVED_PROMPT_ARGS: readonly string[] = [
  "WORK",
  "ANCHOR",
  "READY",
  "MAX_PARALLEL",
  "WAVE",
];

/**
 * Build one provider per agent, reusing a single provider object when two
 * agents match on model *and* effort — which is how the old "same for both"
 * behaviour generalises to any number of agents.
 */
export function resolveAgents(plan: ResolvedPlan): Map<string, AgentProvider> {
  const byModelAndEffort = new Map<string, AgentProvider>();
  const byAgentId = new Map<string, AgentProvider>();

  for (const resolved of plan.agents) {
    const key = `${resolved.model.id}:${resolved.effort}`;
    let provider = byModelAndEffort.get(key);
    if (!provider) {
      provider = PROVIDERS[resolved.model.provider].createAgent(resolved.model.id, resolved.effort);
      byModelAndEffort.set(key, provider);
    }
    byAgentId.set(resolved.agentId, provider);
  }

  return byAgentId;
}

/**
 * The models to check, one entry per distinct model id. Deduped by id *alone*,
 * unlike the provider memo above: neither the CLI's version nor its login
 * varies by effort, so two efforts of one model are one check. Merging the two
 * dedupe keys would mean checking too much or too little.
 */
export function distinctModels(plan: ResolvedPlan): readonly RunModel[] {
  const models = new Map<string, RunModel>();
  for (const resolved of plan.agents) {
    if (!models.has(resolved.model.id)) models.set(resolved.model.id, resolved.model);
  }
  return [...models.values()];
}

function validateModels(plan: ResolvedPlan): void {
  for (const model of distinctModels(plan)) validateModel(model);
}

// ---------------------------------------------------------------------------
// The frozen work list
// ---------------------------------------------------------------------------

/**
 * The ordered, truncated list this run may work, or a refusal.
 *
 * The picker has already refused a cycle and an empty scope, and this asks
 * again anyway: the list is the value a driver cannot be invoked without, so
 * where it comes from must not be the only place it is checked. Truncation is a
 * prefix of the sort and never a filter applied before it — a prefix of a
 * topological order always contains its own blockers.
 */
export function workList(scope: WorkScopeSnapshot, maxWorkItems: number): readonly WorkItem[] {
  const order = runOrder(scope);
  if (!order.ok) {
    throw new Error(
      `These work items block each other in a cycle: ${order.cycle.map((number) => `#${number}`).join(" → ")}.`,
    );
  }
  const items = truncate(order.items, maxWorkItems);
  if (items.length === 0) {
    throw new Error("This Work scope holds nothing to run. Resolve it again before starting.");
  }
  return items;
}

// ---------------------------------------------------------------------------
// The workspace
// ---------------------------------------------------------------------------

/** The three git reads the workspace preflight is decided from. */
export interface WorkspaceState {
  /** `git status --porcelain`. */
  readonly status: string;
  /** `git branch --list sandcastle/*`. */
  readonly branches: string;
  /** `git worktree list --porcelain`. */
  readonly worktrees: string;
}

const SANDCASTLE_BRANCH_PREFIX = "sandcastle/";
const WORKTREE_BRANCH_LINE = `branch refs/heads/${SANDCASTLE_BRANCH_PREFIX}`;

/**
 * Everything about this workspace that would break a run, found before the run
 * starts rather than at a fan-in three waves in — which is the whole of what
 * eager validation is worth.
 *
 * Pure over the three command outputs, so the wording a maintainer reads is
 * assertable without a git repository in a broken state.
 */
export function workspaceProblems(state: WorkspaceState): readonly string[] {
  const problems: string[] = [];

  if (state.status.trim() !== "") {
    problems.push(
      "the workspace has uncommitted changes, and `git merge` refuses to run over them",
    );
  }

  const branches = state.branches
    .split("\n")
    .map((line) => line.replace(/^[*+]?\s*/, "").trim())
    .filter((line) => line.startsWith(SANDCASTLE_BRANCH_PREFIX));
  if (branches.length > 0) {
    problems.push(`a previous run left ${branches.join(", ")} behind`);
  }

  const worktrees = state.worktrees
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith(WORKTREE_BRANCH_LINE))
    .map((line) => line.slice("branch refs/heads/".length));
  if (worktrees.length > 0) {
    problems.push(`a previous run left a worktree on ${worktrees.join(", ")}`);
  }

  return problems;
}

function git(command: string): string {
  return execSync(`git ${command}`, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

function assertWorkspaceIsClean(): void {
  const problems = workspaceProblems({
    status: git("status --porcelain"),
    branches: git(`branch --list "${SANDCASTLE_BRANCH_PREFIX}*"`),
    worktrees: git("worktree list --porcelain"),
  });
  if (problems.length > 0) {
    throw new Error(`This workspace is not ready for a run: ${problems.join("; ")}.`);
  }
}

// ---------------------------------------------------------------------------
// What a driver may read while it runs
// ---------------------------------------------------------------------------

/**
 * The workspace branch, and the two commit counts that turn *did anything
 * happen* into a fact.
 *
 * Git's exit code is the one this runner is allowed to branch on, because git
 * is framework-neutral — it says nothing about what language this repository is
 * written in. Everything about the toolchain is `repo.mts`'s, and it is passed
 * through rather than interpreted.
 */
function workspaceGit(): WorkspaceGit {
  return {
    branch: git("rev-parse --abbrev-ref HEAD").trim(),
    headSha: () => git("rev-parse HEAD").trim(),
    commitsSince: (sha) => Number(git(`rev-list --count ${sha}..HEAD`).trim()),
  };
}

/**
 * The three live tracker reads, each bound to this run's frozen snapshot.
 *
 * Bound here rather than reached for by the driver, so an item outside the
 * allow-list cannot be revalidated into one — and so the whole of a driver's
 * GitHub access is a value a test can substitute.
 */
function issueReads(scope: WorkScopeSnapshot): IssueReads {
  const transport = ghTransport();
  return {
    revalidate: (item) => revalidate(scope, item.nodeId, transport),
    liveState: (item) => readLiveState(item.number, transport),
    handoff: () => readHandoffState(scope, transport),
  };
}

// ---------------------------------------------------------------------------
// Prompt args
// ---------------------------------------------------------------------------

/**
 * The args one dispatch is sent: what the runner wrote, plus whatever the body
 * added.
 *
 * A collision **throws and never overrides**. Silently winning either way is the
 * defect: the runner winning would drop a `REVIEW_BASE` a body depends on, and
 * the body winning would let a workflow tell an agent it is working on something
 * else entirely — which is work selection, through the one door that was left
 * open.
 */
export function withScopeArgs(
  reserved: Readonly<Record<string, string>>,
  fromBody: Readonly<Record<string, string>> | undefined,
): Record<string, string> {
  const collisions = Object.keys(fromBody ?? {}).filter((key) =>
    RESERVED_PROMPT_ARGS.includes(key),
  );
  if (collisions.length > 0) {
    throw new Error(
      `A workflow set the reserved prompt argument${collisions.length === 1 ? "" : "s"} ${collisions.join(", ")}. Those are written by the runner, and the scope is not a workflow's to name.`,
    );
  }
  return { ...fromBody, ...reserved };
}

// ---------------------------------------------------------------------------
// Preparing a run
// ---------------------------------------------------------------------------

/**
 * Check everything knowable before the first dispatch, then hand back the only
 * value a driver — and so a workflow — can reach an agent through.
 *
 * Pure refusals first, so a plan that cannot run never spawns a CLI to find out.
 * Everything here throws rather than reporting, because the caller has nothing
 * to do with a half-checked run.
 */
export function prepare(plan: ResolvedPlan): RunCore {
  // Called for its refusal, not for its value: `main.mts` asks again once the
  // core exists. A shape the picker can describe but this build cannot run has
  // to fail here, before a CLI is spawned or a provider is built.
  runnableDriver(plan.workflow);

  const work = workList(plan.scope, plan.maxWorkItems);

  validateModels(plan);
  assertGitHubAuth();
  assertWorkspaceIsClean();

  const providers = resolveAgents(plan);

  const dispatchWith = (reserved: Readonly<Record<string, string>>): Dispatch => {
    return async (agent, options: DispatchOptions) => {
      const provider = providers.get(agent.id);
      if (!provider) {
        throw new Error(
          `The ${plan.workflow.label} workflow drives an unresolved agent: ${agent.id}`,
        );
      }

      // Captured here, immediately before the run, so the SHA a workflow gets
      // back cannot be older or newer than the dispatch it came from.
      const baseSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();

      const result = await sandcastle.run({
        promptArgs: withScopeArgs(reserved, options.promptArgs),
        name: agent.id,
        agent: provider,
        sandbox: noSandbox(),
        branchStrategy: { type: "head" },
        // Pinned at 1: the loop over work items belongs to the driver, and a
        // second Sandcastle iteration would let one dispatch drain the backlog.
        maxIterations: 1,
        hooks: HOOKS,
        // Sandcastle resolves `promptFile` against `process.cwd()`, so anchoring
        // on the workflow's own folder is what lets that folder move.
        promptFile: resolve(plan.workflow.dir, options.promptFile),
      });

      // Narrowed to the contract's two fields on the way out. `stdout`,
      // `resume` and `fork` stop here: a workflow that could resume its own
      // dispatch could pick a branch strategy ADR-0001 forbids.
      return { commits: result.commits, baseSha };
    };
  };

  return {
    work,
    scope: plan.scope,
    repo,
    issues: issueReads(plan.scope),
    git: workspaceGit(),
    // JSON, never markdown: an item body containing a fenced block would break
    // straight out of a markdown splice, while JSON escapes every newline and
    // can never start a line with a fence.
    forItem: (item) =>
      dispatchWith({ WORK: JSON.stringify(workRecord(plan.scope, item.nodeId)) }),
    forBranch: () => dispatchWith({ ANCHOR: JSON.stringify(anchorRecord(plan.scope)) }),
  };
}
