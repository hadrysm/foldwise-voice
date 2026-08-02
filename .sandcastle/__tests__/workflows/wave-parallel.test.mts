// What the parallel workflow declares, and the two claims its folder rests on.
//
// The claims are the interesting part, and both are file comparisons rather than
// prose. The pair of item prompts are copies of the sequential pair — a copy
// keeps ADR-0010's folder seam absolute at the cost of a fix applied twice, and
// that cost is only payable if the divergence is *detectable*. The body is a
// copy for a stronger reason: if the same six lines run one item at a time under
// one driver and three at a time under another, then the execution shape is
// entirely the driver's, which is the whole claim of the seam.

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { describe, it } from "node:test";
import { MERGER, PLANNER } from "../../agents/catalog.mts";
import type { Agent, Dispatch, DispatchOptions, Workflow } from "../../contract.mts";
import { MERGE_PROMPT, MERGE_TAG } from "../../drivers/merger.mts";
import { PLAN_PROMPT, PLAN_TAG } from "../../drivers/planner.mts";
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

describe("the wave-parallel folder", () => {
  it("holds a byte-identical copy of the sequential pair", () => {
    for (const file of ["implement-prompt.md", "review-prompt.md"]) {
      assert.equal(
        promptIn(waveParallelReviewer, file),
        promptIn(sequentialReviewer, file),
        `${file} has drifted from the sequential-reviewer copy it was lifted from`,
      );
    }
  });

  it("holds the two prompts the driver consults, and each emits its own tag", () => {
    // `run()` throws `output tag <x> not found in the resolved prompt`, an hour
    // into a wave, so the literal tag is asserted here instead.
    for (const [file, tag] of [
      [PLAN_PROMPT, PLAN_TAG],
      [MERGE_PROMPT, MERGE_TAG],
    ] as const) {
      const promptPath = resolve(waveParallelReviewer.dir, file);
      assert.ok(existsSync(promptPath), `missing prompt: ${promptPath}`);
      assert.ok(
        promptIn(waveParallelReviewer, file).includes(`<${tag}>`),
        `${file} never opens the <${tag}> block its dispatch reads`,
      );
    }
  });

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
