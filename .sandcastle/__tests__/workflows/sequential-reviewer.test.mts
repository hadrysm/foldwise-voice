import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { describe, it } from "node:test";
import type { Agent, Dispatch, DispatchOptions } from "../../contract.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import { fakeItem } from "../support/scope.mts";

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
    return Promise.resolve({
      commits: Array.from({ length: commits }, (_unused, index) => ({ sha: `commit-${index}` })),
      baseSha: `sha-${calls.length}`,
    });
  };
  return { calls, dispatch };
}

const alwaysCommits = (): number => 1;

/** One item's body, run the way its driver runs it. */
async function runBody(commitsPerCall: (call: number) => number): Promise<DispatchCall[]> {
  const { calls, dispatch } = fakeDispatch(commitsPerCall);
  await sequentialReviewer.run({ dispatch, item: fakeItem(419) });
  return calls;
}

function reviewBase(call: DispatchCall): unknown {
  return call.options.promptArgs?.["REVIEW_BASE"];
}

function promptText(call: DispatchCall): string {
  return readFileSync(resolve(sequentialReviewer.dir, call.options.promptFile), "utf8");
}

describe("the sequential-reviewer body", () => {
  it("implements one item, then reviews it", async () => {
    const calls = await runBody(alwaysCommits);

    assert.deepEqual(
      calls.map((call) => call.agent.id),
      ["implementer", "reviewer"],
    );
  });

  it("hands the reviewer the base captured before the implement it is paired with", async () => {
    const calls = await runBody(alwaysCommits);

    assert.deepEqual(calls.filter((call) => call.agent.id === "reviewer").map(reviewBase), [
      "sha-1",
    ]);
  });

  it("does not review an item the implementer left no commits for", async () => {
    const calls = await runBody(() => 0);

    assert.deepEqual(
      calls.map((call) => call.agent.id),
      ["implementer"],
    );
  });

  it("runs exactly one pair, however many items the run has", async () => {
    // The body has no loop and no count to loop over: the run guard, the list
    // and the stopping belong to the driver, and a body that could count items
    // could bound a second loop inside the one the driver owns.
    const calls = await runBody(alwaysCommits);
    assert.equal(calls.filter((call) => call.agent.id === "implementer").length, 1);
  });

  it("leaves the work item to the runner, and every prompt asks for it", async () => {
    // Half of this is structural already: `withScopeArgs` throws on a reserved
    // key, so a body that wrote `WORK` could not run at all, and the implement
    // dispatch carries no args of its own.
    //
    // The other half is not, and only fails one way. Sandcastle throws at
    // startup on a `{{WORK}}` it has no value for, but an arg written into a
    // prompt that never names it is substituted nowhere and reported by nobody
    // — leaving an agent with the assignment it was selected for and no way to
    // read it, which is the one condition under which it goes looking.
    const calls = await runBody(alwaysCommits);

    assert.equal(calls[0]?.options.promptArgs, undefined);
    for (const call of calls) {
      assert.match(
        promptText(call),
        /\{\{WORK\}\}/,
        `${call.options.promptFile} never asks for the work item the runner writes`,
      );
    }
  });

  it("names each agent's prompt by bare filename, for the runner to anchor", async () => {
    const calls = await runBody(alwaysCommits);

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

  it("holds every prompt the body dispatches", async () => {
    for (const call of await runBody(alwaysCommits)) {
      const promptPath = resolve(sequentialReviewer.dir, call.options.promptFile);
      assert.ok(existsSync(promptPath), `missing prompt: ${promptPath}`);
    }
  });
});

describe("runShape", () => {
  it("reads as the run it describes", () => {
    assert.equal(sequentialReviewer.runShape(10), "implement → review, up to 10 issues");
  });

  it("stays grammatical for a single issue", () => {
    assert.equal(sequentialReviewer.runShape(1), "implement → review, up to 1 issue");
  });
});

describe("the work this workflow declares it does", () => {
  it("declares a driver rather than a shape of its own", () => {
    // Whether the run drains and whether it is concurrent are the *driver's*
    // properties, read by the picker from `DRIVERS` — a workflow that declared
    // them could contradict the driver that actually runs it.
    assert.equal(sequentialReviewer.driver, "sequential");
  });
});
