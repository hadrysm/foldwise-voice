// What the parallel workflow declares, and the claim its body rests on.
//
// The claim is the interesting part, and it is a comparison rather than prose:
// the body is a copy of the sequential one, and if the same six lines run one
// item at a time under one driver and three at a time under another, then the
// execution shape is entirely the driver's — which is the whole claim of the
// seam. The matching claim about the *prompts* is the same shape one level up,
// and it is enumerated from `WORKFLOWS` in `__tests__/sweeps/prompts.test.mts`
// rather than asserted here about two filenames.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { describe, it } from "node:test";
import { MERGER, PLANNER } from "../../agents/catalog.mts";
import type { Agent, Dispatch, DispatchOptions, Workflow } from "../../contract.mts";
import { MERGE_PROMPT } from "../../drivers/merger.mts";
import { PLAN_PROMPT } from "../../drivers/planner.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import { waveParallelReviewer } from "../../workflows/wave-parallel/workflow.mts";
import { fakeItem } from "../support/scope.mts";

interface DispatchCall {
  agent: Agent;
  options: DispatchOptions;
}

async function runBody(workflow: Workflow): Promise<DispatchCall[]> {
  const calls: DispatchCall[] = [];
  const dispatch: Dispatch = (agent, options) => {
    calls.push({ agent, options });
    return Promise.resolve({ commits: [{ sha: "commit-1" }], baseSha: `sha-${calls.length}` });
  };
  await workflow.run({ dispatch, item: fakeItem(427) });
  return calls;
}

function promptIn(workflow: Workflow, file: string): string {
  return readFileSync(resolve(workflow.dir, file), "utf8");
}

describe("the wave-parallel workflow", () => {
  it("declares the wave-parallel driver rather than a shape of its own", () => {
    assert.equal(waveParallelReviewer.driver, "wave-parallel");
  });

  it("is the folder the module lives in", () => {
    assert.equal(basename(waveParallelReviewer.dir), waveParallelReviewer.id);
  });

  it("declares the driver's two agents so the preflight checks their CLIs", () => {
    // Never dispatched from the body — they are `core.consult` calls the driver
    // makes. Declared anyway, because `agents` is what the picker asks models
    // for: without them a run reaches wave one and discovers the Planner is
    // logged out.
    const ids = waveParallelReviewer.agents.map((agent) => agent.id);
    assert.ok(ids.includes(PLANNER.id));
    assert.ok(ids.includes(MERGER.id));
  });

  it("reads as the run it describes, and stays grammatical for one issue", () => {
    assert.equal(
      waveParallelReviewer.runShape(10),
      "plan → implement → review in waves, up to 10 issues",
    );
    assert.equal(
      waveParallelReviewer.runShape(1),
      "plan → implement → review in waves, up to 1 issue",
    );
  });
});

describe("the wave-parallel body", () => {
  it("dispatches the same pair, in the same order, as the sequential body", async () => {
    const parallel = await runBody(waveParallelReviewer);
    const sequential = await runBody(sequentialReviewer);

    assert.deepEqual(
      parallel.map((call) => [call.agent.id, call.options.promptFile, call.options.promptArgs]),
      sequential.map((call) => [call.agent.id, call.options.promptFile, call.options.promptArgs]),
    );
  });

  it("names no work item, because the dispatch already is one", async () => {
    // Structural on one side — `withScopeArgs` throws on `WORK` — and asserted
    // on the other: the implement dispatch carries no args at all.
    const [implement] = await runBody(waveParallelReviewer);
    assert.equal(implement?.options.promptArgs, undefined);
  });
});

// Two claims this folder used to make for itself now belong to
// `__tests__/sweeps/prompts.test.mts`, and the move is the point rather than a
// tidy-up: *this pair is a byte-identical copy* and *each consulted prompt
// emits its tag* were written here as two literal lists — the pair of
// filenames, and the pair of `(prompt, tag)` constants. Written that way they
// stop covering the third copy and the third consult the day either is added,
// while the suite stays green. Enumerated from `WORKFLOWS` and from the
// `core.consult` calls themselves, they cover both today and whatever lands
// next. What stays below is what is genuinely about *this* workflow.
describe("the wave-parallel folder", () => {
  it("asks the Planner for exactly the two arguments the driver writes", () => {
    const plan = promptIn(waveParallelReviewer, PLAN_PROMPT);
    assert.match(plan, /\{\{READY\}\}/);
    assert.match(plan, /\{\{MAX_PARALLEL\}\}/);
  });

  it("asks the Merger for the one argument the driver writes", () => {
    assert.match(promptIn(waveParallelReviewer, MERGE_PROMPT), /\{\{WAVE\}\}/);
  });

  it("never tells an implementer that a sibling exists", () => {
    // It is alone in its worktree and can observe nothing. A footprint warning
    // that names no other work is still a hint that something else is touching
    // those files, and it is unfalsifiable prose no test can check — so the
    // check is the absence of the vocabulary.
    const implement = promptIn(waveParallelReviewer, "implement-prompt.md").toLowerCase();
    for (const word of ["wave", "parallel", "concurrent", "fan-in", "sibling", "merger"]) {
      assert.ok(!implement.includes(word), `implement-prompt.md mentions "${word}"`);
    }
  });
});
