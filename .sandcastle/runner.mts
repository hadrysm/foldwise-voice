// The only module that calls `sandcastle.run()`, and therefore the only place
// ADR-0001's constraint is written down: agents run unsandboxed
// (`noSandbox()`, because this repository's toolchain cannot build in a Linux
// container) and in place on the current branch (`head`, because this runner is
// launched inside Conductor, where the workspace is already an isolated
// worktree on its own branch, so Sandcastle adds no isolation of its own). See
// docs/adr/0001-sandcastle-in-place-not-sandboxed.md. A workflow cannot
// contradict either one, because `DispatchOptions` omits the keys that could.
//
// Nothing here knows what this repository is written in. The commands that do
// live in `.sandcastle/repo.mts`, and the runner only ever passes them through
// — it never reads their output and never branches on their exit code.
//
// Split by side effect. `resolveAgents` is pure — every provider factory is an
// object literal — so the memoisation that makes "same model for both agents"
// reuse one provider is testable without a CLI. `validateModels` is the part
// that spawns. `prepare` runs the second and returns the closure the first
// feeds, which is what makes eager validation structural: `dispatch` does not
// exist until the CLIs have been checked, so no auth failure can surface at
// iteration 7.

import { execSync } from "node:child_process";
import { resolve } from "node:path";
import * as sandcastle from "@ai-hero/sandcastle";
import type { AgentProvider } from "@ai-hero/sandcastle";
import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";
import type { RunModel } from "./agents/models.mts";
import type { ResolvedPlan } from "./cli/flow.mts";
import type { Dispatch } from "./contract.mts";
import { PROVIDERS, validateModel } from "./providers/registry.mts";
import { repo } from "./repo.mts";

// Under `noSandbox()` the "sandbox" *is* the host checkout, so this is where
// `repo.onHostReady` lands. Every command it names is idempotent by contract,
// which is what makes running them once per dispatch harmless.
// `repo.onWorktreeReady` has no site on this path: `createWorktree` executes
// `host.onWorktreeReady`, and that path arrives with the wave-parallel driver.
const HOOKS = {
  sandbox: { onSandboxReady: repo.onHostReady },
};

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

/**
 * Check every CLI this plan needs, then hand back the workflow's only way to
 * reach an agent. Throws if any check fails, so the caller never gets a
 * `dispatch` it cannot use.
 */
export function prepare(plan: ResolvedPlan): Dispatch {
  validateModels(plan);
  const providers = resolveAgents(plan);

  return async (agent, options) => {
    const provider = providers.get(agent.id);
    if (!provider) {
      throw new Error(`The ${plan.workflow.label} workflow drives an unresolved agent: ${agent.id}`);
    }

    // Captured here, immediately before the run, so the SHA a workflow gets
    // back cannot be older or newer than the dispatch it came from.
    const baseSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();

    const result = await sandcastle.run({
      ...options,
      name: agent.id,
      agent: provider,
      sandbox: noSandbox(),
      branchStrategy: { type: "head" },
      // Pinned at 1: the outer loop is the workflow's `for`, and a second
      // Sandcastle iteration would let one dispatch drain the whole backlog.
      maxIterations: 1,
      hooks: HOOKS,
      // Sandcastle resolves `promptFile` against `process.cwd()`, so anchoring
      // on the workflow's own folder is what lets that folder move.
      promptFile: resolve(plan.workflow.dir, options.promptFile),
    });

    return { ...result, baseSha };
  };
}
