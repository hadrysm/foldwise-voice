import type { RunResult } from "@ai-hero/sandcastle";
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { basename, resolve } from "node:path";
import { describe, it, type TestContext } from "node:test";
import type { Agent, Dispatch, DispatchOptions } from "../../contract.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";

interface DispatchCall {
  agent: Agent;
  options: DispatchOptions;
}

/**
 * A `dispatch` that runs no CLI, spawns no provider and touches no git. Each
 * call answers with its own `sha-<n>` base, so the reviewer's REVIEW_BASE
 * identifies exactly which dispatch it was paired with.
 */
function fakeDispatch(commitsPerCall: (call: number) => number): {
  calls: DispatchCall[];
  dispatch: Dispatch;
} {
  const calls: DispatchCall[] = [];
  const dispatch: Dispatch = (agent, options) => {
    calls.push({ agent, options });
    const commits = commitsPerCall(calls.length);
    const result: RunResult & { baseSha: string } = {
      iterations: [],
      stdout: "",
      commits: Array.from({ length: commits }, (_unused, index) => ({ sha: `commit-${index}` })),
      branch: "feature",
      baseSha: `sha-${calls.length}`,
    };
    return Promise.resolve(result);
  };
  return { calls, dispatch };
}

const alwaysCommits = (): number => 1;

/** The loop narrates with `console.log`; the test suite does not need to hear it. */
function silenceNarration(t: TestContext): void {
  t.mock.method(console, "log", () => undefined);
}

function reviewBase(call: DispatchCall): unknown {
  return call.options.promptArgs?.["REVIEW_BASE"];
}

describe("the sequential-reviewer loop", () => {
  it("runs one implement-then-review pair per iteration", async (t) => {
    silenceNarration(t);
    const { calls, dispatch } = fakeDispatch(alwaysCommits);

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 3 } });

    assert.deepEqual(
      calls.map((call) => call.agent.id),
      ["implementer", "reviewer", "implementer", "reviewer", "implementer", "reviewer"],
    );
  });

  it("hands each reviewer the base captured before that iteration's implement", async (t) => {
    silenceNarration(t);
    const { calls, dispatch } = fakeDispatch(alwaysCommits);

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 2 } });

    // Iteration 1 implements on call 1 and iteration 2 on call 3, so a
    // reviewer holding "sha-1" in the second iteration would be re-reviewing
    // work that already passed.
    assert.deepEqual(
      calls.filter((call) => call.agent.id === "reviewer").map(reviewBase),
      ["sha-1", "sha-3"],
    );
  });

  it("stops without reviewing when the implementer makes no commits", async (t) => {
    silenceNarration(t);
    const { calls, dispatch } = fakeDispatch(() => 0);

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 10 } });

    assert.deepEqual(
      calls.map((call) => call.agent.id),
      ["implementer"],
    );
  });

  it("stops mid-run once the backlog empties", async (t) => {
    silenceNarration(t);
    // Calls 1 and 2 are iteration 1; call 3 is iteration 2's implement.
    const { calls, dispatch } = fakeDispatch((call) => (call >= 3 ? 0 : 1));

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 10 } });

    assert.deepEqual(
      calls.map((call) => call.agent.id),
      ["implementer", "reviewer", "implementer"],
    );
  });

  it("sends the implementer no promptArgs", async (t) => {
    silenceNarration(t);
    const { calls, dispatch } = fakeDispatch(() => 0);

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 1 } });

    assert.equal(calls[0]?.options.promptArgs, undefined);
  });

  it("names each agent's prompt by bare filename, for the runner to anchor", async (t) => {
    silenceNarration(t);
    const { calls, dispatch } = fakeDispatch(alwaysCommits);

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 1 } });

    assert.deepEqual(
      calls.map((call) => call.options.promptFile),
      ["implement-prompt.md", "review-prompt.md"],
    );
  });
});

describe("the sequential-reviewer folder", () => {
  it("is the folder the module lives in", () => {
    assert.equal(basename(sequentialReviewer.dir), sequentialReviewer.id);
  });

  it("holds every prompt the loop dispatches", async (t) => {
    silenceNarration(t);
    const { calls, dispatch } = fakeDispatch(alwaysCommits);

    await sequentialReviewer.run({ dispatch, knobs: { maxIterations: 1 } });

    for (const call of calls) {
      const promptPath = resolve(sequentialReviewer.dir, call.options.promptFile);
      assert.ok(existsSync(promptPath), `missing prompt: ${promptPath}`);
    }
  });
});

describe("runShape", () => {
  it("reads as the run it describes", () => {
    assert.equal(
      sequentialReviewer.runShape({ maxIterations: 10 }),
      "implement → review, up to 10 issues",
    );
  });

  it("stays grammatical for a single issue", () => {
    assert.equal(
      sequentialReviewer.runShape({ maxIterations: 1 }),
      "implement → review, up to 1 issue",
    );
  });
});
