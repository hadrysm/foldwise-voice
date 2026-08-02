import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { IMPLEMENTER, REVIEWER } from "../agents/catalog.mts";
import { findModel, type RunEffort } from "../agents/models.mts";
import type { ResolvedAgent, ResolvedPlan } from "../cli/flow.mts";
import type { Agent } from "../contract.mts";
import {
  distinctModels,
  RESERVED_PROMPT_ARGS,
  resolveAgents,
  withScopeArgs,
  workList,
  workspaceProblems,
} from "../runner.mts";
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

describe("the frozen work list", () => {
  const spec = specSnapshot({ number: 418 }, [
    { number: 419 },
    { number: 420, blockedBy: [419] },
    { number: 421 },
  ]);

  it("orders the items topologically, stable on the authored order", () => {
    assert.deepEqual(
      workList(spec, 10).map((item) => item.number),
      [419, 420, 421],
    );
  });

  it("truncates the sorted order, so no item's blocker is ever cut", () => {
    // A prefix of a topological order always contains its own blockers, which
    // any filter applied before the sort could not promise.
    assert.deepEqual(
      workList(spec, 2).map((item) => item.number),
      [419, 420],
    );
  });

  it("refuses a scope with nothing to run rather than driving an empty loop", () => {
    const drained = specSnapshot({ number: 418 }, [{ number: 419, state: "closed" }]);
    assert.throws(() => workList(drained, 10), /nothing to run/);
  });

  it("refuses a dependency cycle, naming the loop", () => {
    const cyclic = specSnapshot({ number: 418 }, [
      { number: 419, blockedBy: [420] },
      { number: 420, blockedBy: [419] },
    ]);
    assert.throws(() => workList(cyclic, 10), /#419 → #420/);
  });
});

describe("the workspace preflight", () => {
  const clean = { status: "", branches: "", worktrees: "" };

  it("passes a clean workspace with no leftovers", () => {
    assert.deepEqual(workspaceProblems(clean), []);
  });

  it("refuses uncommitted changes, because a fan-in merge cannot run over them", () => {
    const problems = workspaceProblems({ ...clean, status: " M Sources/App.swift\n" });
    assert.deepEqual(problems, [
      "the workspace has uncommitted changes, and `git merge` refuses to run over them",
    ]);
  });

  it("names a branch a previous run left behind", () => {
    const problems = workspaceProblems({
      ...clean,
      branches: "  sandcastle/419-the-pure-snapshot\n+ sandcastle/420-github\n",
    });
    assert.deepEqual(problems, [
      "a previous run left sandcastle/419-the-pure-snapshot, sandcastle/420-github behind",
    ]);
  });

  it("names a worktree a previous run left behind", () => {
    const problems = workspaceProblems({
      ...clean,
      worktrees: [
        "worktree /clone",
        "HEAD abc",
        "branch refs/heads/t3code/slice-5",
        "",
        "worktree /clone/.sandcastle/worktrees/419",
        "HEAD def",
        "branch refs/heads/sandcastle/419-the-pure-snapshot",
        "",
      ].join("\n"),
    });
    assert.deepEqual(problems, [
      "a previous run left a worktree on sandcastle/419-the-pure-snapshot",
    ]);
  });

  it("reports every problem at once rather than one screen at a time", () => {
    const problems = workspaceProblems({
      status: "?? junk\n",
      branches: "  sandcastle/419-x\n",
      worktrees: "branch refs/heads/sandcastle/419-x\n",
    });
    assert.equal(problems.length, 3);
  });
});

describe("prompt-arg injection", () => {
  it("writes the runner's args alongside the body's own", () => {
    assert.deepEqual(withScopeArgs({ WORK: "{}" }, { REVIEW_BASE: "sha-1" }), {
      WORK: "{}",
      REVIEW_BASE: "sha-1",
    });
  });

  it("writes its args for a body that sent none", () => {
    assert.deepEqual(withScopeArgs({ ANCHOR: "null" }, undefined), { ANCHOR: "null" });
  });

  it("throws on a reserved name rather than letting either side win silently", () => {
    // The runner winning would drop a `REVIEW_BASE` a body depends on; the body
    // winning would let a workflow tell an agent it is working on something
    // else, which is work selection through the one door left open.
    for (const reserved of RESERVED_PROMPT_ARGS) {
      assert.throws(
        () => withScopeArgs({ WORK: "{}" }, { [reserved]: "mine" }),
        new RegExp(reserved),
        reserved,
      );
    }
  });

  it("names every collision at once", () => {
    assert.throws(
      () => withScopeArgs({ WORK: "{}" }, { WORK: "mine", WAVE: "mine" }),
      /WORK, WAVE/,
    );
  });
});
