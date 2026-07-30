import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { findModel, RUN_MODELS } from "../../agents/models.mts";

const opus5 = findModel("claude-opus-5");

describe("model catalog", () => {
  it("offers Opus 5", () => {
    assert.ok(opus5, "claude-opus-5 should be in the allow list");
    assert.equal(opus5.provider, "claude-code");
  });

  it("lets Opus 5 run at max effort", () => {
    // Verified against Claude Code 2.1.220: `--model claude-opus-5 --effort max`
    // is accepted.
    assert.ok(opus5?.efforts.includes("max"));
  });

  it("has no duplicate model ids", () => {
    const ids = RUN_MODELS.map((model) => model.id);
    assert.equal(new Set(ids).size, ids.length);
  });

  it("gives every model at least one effort", () => {
    for (const model of RUN_MODELS) {
      assert.ok(model.efforts.length > 0, `${model.id} has no efforts`);
    }
  });
});
