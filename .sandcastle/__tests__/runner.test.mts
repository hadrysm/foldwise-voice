import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { IMPLEMENTER, REVIEWER } from "../agents/catalog.mts";
import { findModel, type RunEffort } from "../agents/models.mts";
import type { ResolvedAgent, ResolvedPlan } from "../cli/flow.mts";
import type { Agent } from "../contract.mts";
import { distinctModels, resolveAgents } from "../runner.mts";
import { sequentialReviewer } from "../workflows/sequential-reviewer/workflow.mts";
import { specSnapshot } from "./support/scope.mts";

// No fakes: every provider factory is a plain object literal, so building the
// real ones costs nothing and spawns nothing.
function pick(agent: Agent, modelId: string, effort: RunEffort): ResolvedAgent {
  const model = findModel(modelId);
  assert.ok(model, `fixture names a model that left the catalog: ${modelId}`);
  return { agentId: agent.id, agentLabel: agent.label, model, effort };
}

function planFor(agents: readonly ResolvedAgent[]): ResolvedPlan {
  return {
    workflow: sequentialReviewer,
    agents,
    knobs: {},
    scope: specSnapshot({ number: 418 }, [{ number: 419 }]),
    maxWorkItems: 1,
    maxParallel: 1,
  };
}

describe("resolveAgents", () => {
  it("gives two agents on the same model and effort one provider", () => {
    const providers = resolveAgents(
      planFor([pick(IMPLEMENTER, "claude-opus-5", "high"), pick(REVIEWER, "claude-opus-5", "high")]),
    );
    assert.equal(providers.get(IMPLEMENTER.id), providers.get(REVIEWER.id));
  });

  it("gives two agents differing only in effort a provider each", () => {
    const providers = resolveAgents(
      planFor([pick(IMPLEMENTER, "claude-opus-5", "high"), pick(REVIEWER, "claude-opus-5", "low")]),
    );
    assert.notEqual(providers.get(IMPLEMENTER.id), providers.get(REVIEWER.id));
  });

  it("resolves a provider for every agent in the plan", () => {
    const providers = resolveAgents(
      planFor([pick(IMPLEMENTER, "claude-opus-5", "high"), pick(REVIEWER, "gpt-5.5", "high")]),
    );
    assert.deepEqual([...providers.keys()], [IMPLEMENTER.id, REVIEWER.id]);
  });
});

describe("distinctModels", () => {
  it("checks a model shared by two agents once", () => {
    // The dedupe key here is the model id alone, unlike the provider memo:
    // neither the CLI version nor the login varies by effort.
    const models = distinctModels(
      planFor([pick(IMPLEMENTER, "claude-opus-5", "high"), pick(REVIEWER, "claude-opus-5", "low")]),
    );
    assert.deepEqual(
      models.map((model) => model.id),
      ["claude-opus-5"],
    );
  });

  it("checks both models of a two-provider plan", () => {
    const models = distinctModels(
      planFor([pick(IMPLEMENTER, "claude-opus-5", "high"), pick(REVIEWER, "gpt-5.5", "high")]),
    );
    assert.deepEqual(
      models.map((model) => model.id),
      ["claude-opus-5", "gpt-5.5"],
    );
  });
});
