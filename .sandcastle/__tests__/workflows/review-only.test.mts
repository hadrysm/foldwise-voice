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
    return Promise.resolve({ commits: [], baseSha: "sha-1" });
  };
  return { calls, dispatch };
}

/** The body, run the way `whole-branch` runs it: once, with no work item. */
async function runBody(): Promise<DispatchCall[]> {
  const { calls, dispatch } = fakeDispatch();
  await reviewOnly.run({ dispatch, item: null });
  return calls;
}

describe("the review-only body", () => {
  it("dispatches the reviewer exactly once", async () => {
    assert.deepEqual(
      (await runBody()).map((call) => call.agent.id),
      ["reviewer"],
    );
  });

  it("sends no promptArgs key at all, not an empty object", async () => {
    // `{{ANCHOR}}` is the runner's to write, and there is nothing else to
    // substitute: an empty `promptArgs` would imply a key this body owns.
    const options = (await runBody())[0]?.options;
    assert.ok(options);
    assert.equal("promptArgs" in options, false);
  });

  it("names its prompt by bare filename, for the runner to anchor", async () => {
    assert.deepEqual(
      (await runBody()).map((call) => call.options.promptFile),
      ["review-prompt.md"],
    );
  });
});

describe("the review-only folder", () => {
  it("is the folder the module lives in", () => {
    assert.equal(basename(reviewOnly.dir), reviewOnly.id);
  });

  it("holds the prompt the body dispatches", async () => {
    for (const call of await runBody()) {
      const promptPath = resolve(reviewOnly.dir, call.options.promptFile);
      assert.ok(existsSync(promptPath), `missing prompt: ${promptPath}`);
    }
  });
});

describe("what review-only declares", () => {
  it("drives one agent, on the driver that walks no work items", () => {
    assert.deepEqual(
      reviewOnly.agents.map((agent) => agent.id),
      ["reviewer"],
    );
    assert.equal(reviewOnly.driver, "whole-branch");
  });

  it("reads as the run it describes, whatever it is handed", () => {
    // It walks no work items, so the one number `runShape` takes says nothing
    // about this workflow and appears nowhere in its line.
    assert.equal(reviewOnly.runShape(0), "review once, origin/main...HEAD");
    assert.equal(reviewOnly.runShape(12), "review once, origin/main...HEAD");
  });
});
