// The prompt-side sweeps, enumerated from `WORKFLOWS` and from the drivers.
//
// Beside `__tests__/workflows/prompt-includes.test.mts` and in its shape, but
// asking different questions. That one asks whether a shell block is well
// formed and whether its include resolves — *hygiene*. These ask what a block
// does to the world, whether two workflows that share a body still share their
// prompts, and whether a prompt says the thing its dispatch reads back.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { RESERVED_PROMPT_ARGS } from "../../runner.mts";
import { everyPrompt, promptArgUse, sweptModules, workflowPrompts } from "../support/corpus.mts";
import {
  consultations,
  consultTagsAppearInPrompts,
  describeViolations,
  knownDefects,
  promptArgNamesAreDisjoint,
  reconcileKnownDefects,
  sharedPromptsMatch,
  shellBlocksLeaveGitAlone,
  type Violation,
} from "../support/sweeps.mts";

function assertClean(found: readonly Violation[]): void {
  assert.equal(found.length, 0, describeViolations(found));
}

describe("every shipped prompt", () => {
  it("leaves git state alone at the end of a shell block", () => {
    // `preprocessPrompt` expands every block with `{ concurrency: "unbounded" }`,
    // so a block that mutates and stops there is a block something else is
    // racing — and the race is silent, because the reviewer completes normally
    // against whatever base it happened to get.
    //
    // Reconciled against the defects the prompts declare for themselves rather
    // than asserted flat. One prompt is #417, which slice 12 of this SPEC fixes:
    // this slice owns the rule and that one owns the instance, so the rule ships
    // reconciled rather than either reaching over to fix the file or going in
    // red. The reconciliation is two-way, so the fix cannot leave the
    // declaration behind.
    const prompts = everyPrompt();
    assertClean(reconcileKnownDefects(shellBlocksLeaveGitAlone(prompts), knownDefects(prompts)));
  });

  it("expands only prompt arguments something writes", () => {
    // Five reserved names against the one key a body writes. A collision is
    // silent either way it resolves, and a `{{NAME}}` nobody writes reaches the
    // agent verbatim as prose.
    assertClean(promptArgNamesAreDisjoint(promptArgUse(RESERVED_PROMPT_ARGS)));
  });
});

describe("a workflow that copies another workflow's body", () => {
  it("ships byte-identical prompts for every file they share", () => {
    // Keyed on the body rather than on a pair of names, so a third copy is
    // covered the day it lands. The claim is the seam's strongest: the shape a
    // run takes belongs entirely to the driver, so the same six lines run one
    // item at a time on the host checkout under one declaration and three items
    // in three worktrees under another.
    assertClean(sharedPromptsMatch(workflowPrompts()));
  });
});

describe("a prompt a driver consults", () => {
  it("shows the tag its dispatch reads the answer out of", () => {
    // The Planner's failure mode is invisible by construction — a plan that
    // never parses falls back to the computed wave, the run completes and every
    // item merges — so the one thing that makes the tag reach the agent is
    // worth asserting rather than trusting.
    assertClean(consultTagsAppearInPrompts(consultations(sweptModules()), everyPrompt()));
  });
});
