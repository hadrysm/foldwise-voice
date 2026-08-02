import type { RunResult } from "@ai-hero/sandcastle";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { basename, resolve } from "node:path";
import { describe, it } from "node:test";
import type { Agent, Dispatch, DispatchOptions } from "../../contract.mts";
import { reviewOnly } from "../../workflows/review-only/workflow.mts";

interface DispatchCall {
  agent: Agent;
  options: DispatchOptions;
}

/**
 * A `dispatch` that runs no CLI, spawns no provider and touches no git. It
 * answers with no commits and a base SHA this workflow has no use for, which is
 * how "it ignores both" is asserted rather than assumed.
 */
function fakeDispatch(): { calls: DispatchCall[]; dispatch: Dispatch } {
  const calls: DispatchCall[] = [];
  const dispatch: Dispatch = (agent, options) => {
    calls.push({ agent, options });
    const result: RunResult & { baseSha: string } = {
      iterations: [],
      stdout: "",
      commits: [],
      branch: "feature",
      baseSha: "sha-1",
    };
    return Promise.resolve(result);
  };
  return { calls, dispatch };
}

describe("the review-only run", () => {
  it("dispatches the reviewer exactly once", async () => {
    const { calls, dispatch } = fakeDispatch();

    await reviewOnly.run({ dispatch, knobs: {}, maxWorkItems: 1 });

    assert.deepEqual(
      calls.map((call) => call.agent.id),
      ["reviewer"],
    );
  });

  it("sends no promptArgs key at all, not an empty object", async () => {
    // The prompt writes `origin/main...HEAD` literally, so there is no base to
    // substitute. An empty `promptArgs` would imply there is one and none was
    // filled in.
    const { calls, dispatch } = fakeDispatch();

    await reviewOnly.run({ dispatch, knobs: {}, maxWorkItems: 1 });

    const options = calls[0]?.options;
    assert.ok(options);
    assert.equal("promptArgs" in options, false);
  });

  it("names its prompt by bare filename, for the runner to anchor", async () => {
    const { calls, dispatch } = fakeDispatch();

    await reviewOnly.run({ dispatch, knobs: {}, maxWorkItems: 1 });

    assert.deepEqual(
      calls.map((call) => call.options.promptFile),
      ["review-prompt.md"],
    );
  });
});

describe("the review-only folder", () => {
  it("is the folder the module lives in", () => {
    assert.equal(basename(reviewOnly.dir), reviewOnly.id);
  });

  it("holds the prompt the run dispatches", async () => {
    const { calls, dispatch } = fakeDispatch();

    await reviewOnly.run({ dispatch, knobs: {}, maxWorkItems: 1 });

    for (const call of calls) {
      const promptPath = resolve(reviewOnly.dir, call.options.promptFile);
      assert.ok(existsSync(promptPath), `missing prompt: ${promptPath}`);
    }
  });
});

describe("what review-only declares", () => {
  it("drives one agent and declares no knobs", () => {
    assert.deepEqual(
      reviewOnly.agents.map((agent) => agent.id),
      ["reviewer"],
    );
    assert.deepEqual(reviewOnly.knobs, []);
  });

  it("reads as the run it describes, whatever it is handed", () => {
    // It walks no work items, so the one number `runShape` now takes says
    // nothing about this workflow and appears nowhere in its line.
    assert.equal(reviewOnly.runShape(0), "review once, origin/main...HEAD");
    assert.equal(reviewOnly.runShape(12), "review once, origin/main...HEAD");
  });

  it("neither drains work items nor runs them side by side", () => {
    assert.equal(reviewOnly.drains, false);
    assert.equal(reviewOnly.concurrent, false);
  });
});
