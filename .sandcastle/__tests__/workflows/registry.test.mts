// The registry's order is the picker's default, so it is pinned rather than
// merely present: position 0 is what a clone with no store lands on.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { WORKFLOWS } from "../../workflows/registry.mts";

describe("the workflow registry", () => {
  it("offers Implement & Review first and Review Only second", () => {
    assert.deepEqual(
      WORKFLOWS.map((workflow) => workflow.id),
      ["sequential-reviewer", "review-only"],
    );
  });
});
