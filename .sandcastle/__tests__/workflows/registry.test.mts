// The registry's order is the picker's default, so it is pinned rather than
// merely present: position 0 is what a clone with no store lands on.
//
// It stays `sequential-reviewer` now that a parallel sibling exists. Waves cost
// three worktrees, two extra agents and a fan-in, which is the wrong thing for a
// clone that has never run this tool to land on by accident — the parallel
// workflow is chosen, never defaulted into.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { DRIVERS } from "../../drivers/registry.mts";
import { WORKFLOWS } from "../../workflows/registry.mts";

describe("the workflow registry", () => {
  it("offers Implement & Review first, its parallel sibling second, Review Only last", () => {
    assert.deepEqual(
      WORKFLOWS.map((workflow) => workflow.id),
      ["sequential-reviewer", "wave-parallel", "review-only"],
    );
  });

  it("declares only drivers this build can run", () => {
    for (const workflow of WORKFLOWS) {
      assert.ok(
        DRIVERS[workflow.driver].drive,
        `${workflow.id} declares the ${workflow.driver} driver, which cannot run`,
      );
    }
  });

  it("gives every workflow a distinct id and folder", () => {
    assert.equal(new Set(WORKFLOWS.map((workflow) => workflow.id)).size, WORKFLOWS.length);
    assert.equal(new Set(WORKFLOWS.map((workflow) => workflow.dir)).size, WORKFLOWS.length);
  });
});
