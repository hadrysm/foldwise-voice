import assert from "node:assert/strict";
import { execSync } from "node:child_process";
import { resolve } from "node:path";
import { describe, it } from "node:test";
import { findModel } from "../../agents/models.mts";
import {
  parseStoredRunPlan,
  runStorePath,
  serializeRunPlan,
  type RunPlan,
} from "../../cli/store.mts";

const opus5 = findModel("claude-opus-5");
const sonnet = findModel("claude-sonnet-4-6");

function storedJson(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    version: 1,
    sameForBoth: false,
    implementer: { model: "claude-opus-5", effort: "xhigh" },
    reviewer: { model: "claude-sonnet-4-6", effort: "high" },
    ...overrides,
  });
}

describe("parseStoredRunPlan", () => {
  it("reads a well-formed plan", () => {
    const plan = parseStoredRunPlan(storedJson());
    assert.deepEqual(plan, {
      sameForBoth: false,
      implementer: { model: "claude-opus-5", effort: "xhigh" },
      reviewer: { model: "claude-sonnet-4-6", effort: "high" },
    });
  });

  it("survives malformed JSON", () => {
    assert.equal(parseStoredRunPlan("{ not json"), undefined);
    assert.equal(parseStoredRunPlan(""), undefined);
  });

  it("rejects non-objects", () => {
    assert.equal(parseStoredRunPlan("null"), undefined);
    assert.equal(parseStoredRunPlan("[]"), undefined);
    assert.equal(parseStoredRunPlan('"a string"'), undefined);
    assert.equal(parseStoredRunPlan("42"), undefined);
  });

  it("ignores a plan from another schema version", () => {
    assert.equal(parseStoredRunPlan(storedJson({ version: 2 })), undefined);
    assert.equal(parseStoredRunPlan(storedJson({ version: undefined })), undefined);
  });

  it("drops a role whose model has left the catalog", () => {
    const plan = parseStoredRunPlan(
      storedJson({ implementer: { model: "claude-opus-3-7", effort: "high" } }),
    );
    assert.equal(plan?.implementer, undefined);
    // The surviving role is kept — one stale pick should not discard the other.
    assert.deepEqual(plan?.reviewer, { model: "claude-sonnet-4-6", effort: "high" });
  });

  it("drops a role whose effort that model does not support", () => {
    assert.ok(!sonnet?.efforts.includes("max"), "fixture assumes Sonnet lacks max");
    const plan = parseStoredRunPlan(
      storedJson({ reviewer: { model: "claude-sonnet-4-6", effort: "max" } }),
    );
    assert.equal(plan?.reviewer, undefined);
    assert.deepEqual(plan?.implementer, { model: "claude-opus-5", effort: "xhigh" });
  });

  it("drops a malformed role", () => {
    for (const bad of [null, 42, "claude-opus-5", {}, { model: "claude-opus-5" }]) {
      const plan = parseStoredRunPlan(storedJson({ implementer: bad }));
      assert.equal(plan?.implementer, undefined, `expected ${JSON.stringify(bad)} to be dropped`);
    }
  });

  it("defaults sameForBoth to true when absent or not a boolean", () => {
    assert.equal(parseStoredRunPlan(storedJson({ sameForBoth: undefined }))?.sameForBoth, true);
    assert.equal(parseStoredRunPlan(storedJson({ sameForBoth: "yes" }))?.sameForBoth, true);
    assert.equal(parseStoredRunPlan(storedJson({ sameForBoth: false }))?.sameForBoth, false);
  });
});

describe("serializeRunPlan", () => {
  it("round-trips through the parser", () => {
    assert.ok(opus5 && sonnet);
    const plan: RunPlan = {
      sameForBoth: false,
      implementer: { model: opus5, effort: "max" },
      reviewer: { model: sonnet, effort: "low" },
    };
    assert.deepEqual(parseStoredRunPlan(serializeRunPlan(plan)), {
      sameForBoth: false,
      implementer: { model: "claude-opus-5", effort: "max" },
      reviewer: { model: "claude-sonnet-4-6", effort: "low" },
    });
  });
});

describe("runStorePath", () => {
  it("lands in the git common dir, not the worktree", () => {
    const commonDir = execSync("git rev-parse --git-common-dir", { encoding: "utf8" }).trim();
    assert.equal(runStorePath(), resolve(process.cwd(), commonDir, "sandcastle-run.json"));
  });

  it("is shared by every worktree of the clone", () => {
    // The store must not live under the worktree, or each Conductor workspace
    // would start from scratch.
    const worktreeRoot = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
    const gitDir = execSync("git rev-parse --absolute-git-dir", { encoding: "utf8" }).trim();
    const storePath = runStorePath();
    assert.ok(
      !storePath.startsWith(`${worktreeRoot}/.sandcastle`),
      "store must not sit in the tracked worktree",
    );
    // In a linked worktree the per-worktree git dir is deeper than the common
    // dir, so a store placed there would not be shared.
    assert.ok(!storePath.startsWith(`${gitDir}/`), "store must not sit in the per-worktree git dir");
  });
});
