import assert from "node:assert/strict";
import { execSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { after, describe, it } from "node:test";
import { findModel, type ModelID, type RunEffort } from "../../agents/models.mts";
import {
  mergeStoredRun,
  parseStoredRun,
  runStorePath,
  serializeStoredRun,
  worktreeOrigin,
  writeStoredRun,
} from "../../cli/store.mts";

const sonnet = findModel("claude-sonnet-4-6");

/** A well-formed v2 file, with one field at a time swapped for the bad input. */
function storedJson(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    version: 2,
    lastWorkflowId: "sequential-reviewer",
    lastScope: { kind: "specific-spec", target: "418", origin: "/clone/.git/worktrees/perth" },
    maxWorkItems: 10,
    maxParallel: 3,
    agents: {
      implementer: { model: "claude-opus-5", effort: "xhigh" },
      reviewer: { model: "claude-sonnet-4-6", effort: "high" },
    },
    knobs: { "sequential-reviewer": { maxIterations: 5 } },
    ...overrides,
  });
}

/** A v1 file exactly as shipped: both roles, both efforts, and `sameForBoth`. */
function v1Json(): string {
  return JSON.stringify({
    version: 1,
    sameForBoth: false,
    implementer: { model: "claude-opus-5", effort: "xhigh" },
    reviewer: { model: "claude-sonnet-4-6", effort: "high" },
  });
}

/** What the picker hands the store. Structural, so no `ResolvedPlan` needed. */
function run(
  workflowId: string,
  agents: readonly { agentId: string; modelId: ModelID; effort: RunEffort }[],
  overrides: Partial<{
    scope: { kind: string; target?: string };
    maxWorkItems: number;
    maxParallel: number;
  }> = {},
) {
  return {
    workflow: { id: workflowId },
    scope: { kind: "specific-spec", target: "418" },
    maxWorkItems: 10,
    maxParallel: 1,
    agents: agents.map((agent) => {
      const model = findModel(agent.modelId);
      assert.ok(model, `fixture model ${agent.modelId} must exist`);
      return { agentId: agent.agentId, model, effort: agent.effort };
    }),
    ...overrides,
  };
}

/** A store path in a directory this file owns and removes when it is done. */
const tempDirs: string[] = [];

function tempStoreDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "sandcastle-store-"));
  tempDirs.push(dir);
  return dir;
}

after(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

describe("parseStoredRun", () => {
  it("reads a well-formed store", () => {
    assert.deepEqual(parseStoredRun(storedJson()), {
      lastWorkflowId: "sequential-reviewer",
      lastScope: { kind: "specific-spec", target: "418", origin: "/clone/.git/worktrees/perth" },
      maxWorkItems: 10,
      maxParallel: 3,
      agents: {
        implementer: { model: "claude-opus-5", effort: "xhigh" },
        reviewer: { model: "claude-sonnet-4-6", effort: "high" },
      },
      // `knobs` is no longer parsed: `Knob` is gone, so the key retires into
      // passthrough with no special case and is carried for whichever branch
      // still writes one.
      passthrough: { knobs: { "sequential-reviewer": { maxIterations: 5 } } },
    });
  });

  it("drops the whole file when it is not JSON", () => {
    assert.equal(parseStoredRun("{ not json"), undefined);
    assert.equal(parseStoredRun(""), undefined);
  });

  it("drops the whole file when it is not an object", () => {
    assert.equal(parseStoredRun("null"), undefined);
    assert.equal(parseStoredRun("[]"), undefined);
    assert.equal(parseStoredRun('"a string"'), undefined);
    assert.equal(parseStoredRun("42"), undefined);
  });

  it("drops the whole file when the version is neither 1 nor 2", () => {
    assert.equal(parseStoredRun(storedJson({ version: 3 })), undefined);
    assert.equal(parseStoredRun(storedJson({ version: "2" })), undefined);
    assert.equal(parseStoredRun(storedJson({ version: undefined })), undefined);
  });

  it("drops a lastWorkflowId that is not a string, keeping the rest", () => {
    const stored = parseStoredRun(storedJson({ lastWorkflowId: 7 }));
    assert.equal(stored?.lastWorkflowId, undefined);
    assert.deepEqual(stored?.agents.implementer, { model: "claude-opus-5", effort: "xhigh" });
  });

  it("keeps a lastWorkflowId no registry knows", () => {
    // Another worktree's branch may know a workflow this one does not; the flow
    // falls back to registry index 0 rather than the store pruning it.
    assert.equal(parseStoredRun(storedJson({ lastWorkflowId: "review-only" }))?.lastWorkflowId, "review-only");
  });

  it("drops an agent entry that is not a usable object", () => {
    for (const bad of [null, 42, "claude-opus-5", [], {}, { effort: "high" }, { model: 42 }]) {
      const stored = parseStoredRun(
        storedJson({ agents: { implementer: bad, reviewer: { model: "gpt-5.5" } } }),
      );
      assert.equal(stored?.agents.implementer, undefined, `expected ${JSON.stringify(bad)} dropped`);
      // One bad entry must not take its neighbour with it.
      assert.deepEqual(stored?.agents.reviewer, { model: "gpt-5.5" });
    }
  });

  it("drops an agent entry whose model has left the catalog", () => {
    const stored = parseStoredRun(
      storedJson({
        agents: {
          implementer: { model: "claude-opus-3-7", effort: "high" },
          reviewer: { model: "claude-sonnet-4-6", effort: "high" },
        },
      }),
    );
    assert.equal(stored?.agents.implementer, undefined);
    assert.deepEqual(stored?.agents.reviewer, { model: "claude-sonnet-4-6", effort: "high" });
  });

  it("drops a stale effort but keeps its model", () => {
    assert.ok(!sonnet?.efforts.includes("max"), "fixture assumes Sonnet lacks max");
    const stored = parseStoredRun(
      storedJson({
        agents: {
          implementer: { model: "claude-sonnet-4-6", effort: "max" },
          reviewer: { model: "claude-sonnet-4-6", effort: 9 },
        },
      }),
    );
    assert.deepEqual(stored?.agents.implementer, { model: "claude-sonnet-4-6" });
    assert.deepEqual(stored?.agents.reviewer, { model: "claude-sonnet-4-6" });
  });

  it("keeps an agent id the catalog does not declare", () => {
    const stored = parseStoredRun(
      storedJson({ agents: { critic: { model: "gpt-5.6-sol", effort: "high" } } }),
    );
    assert.deepEqual(stored?.agents.critic, { model: "gpt-5.6-sol", effort: "high" });
  });

  it("drops an agents field that is not an object", () => {
    for (const bad of [null, 42, [], "implementer"]) {
      assert.deepEqual(parseStoredRun(storedJson({ agents: bad }))?.agents, {});
    }
  });

  it("carries a knob bucket of any shape at all, now that nothing reads one", () => {
    // Retired, not validated: a key this version does not interpret has no
    // shape it could be wrong about, and pruning it would mean this branch
    // garbage-collecting a sibling worktree's memory.
    for (const bucket of [{ "sequential-reviewer": { maxIterations: 9999 } }, 42, null, []]) {
      assert.deepEqual(parseStoredRun(storedJson({ knobs: bucket }))?.passthrough, {
        knobs: bucket,
      });
    }
  });

  it("drops a lastScope that is not a usable object, keeping the rest", () => {
    for (const bad of [null, 42, [], "specific-spec", {}, { target: "418" }, { kind: 7 }]) {
      const stored = parseStoredRun(storedJson({ lastScope: bad }));
      assert.equal(stored?.lastScope, undefined, `expected ${JSON.stringify(bad)} dropped`);
      assert.equal(stored?.lastWorkflowId, "sequential-reviewer");
    }
  });

  it("keeps a scope kind no picker declares", () => {
    // Another worktree's branch may offer a scope this one does not. The picker
    // looks up only the kinds it declares, so an unknown one is inert.
    const stored = parseStoredRun(storedJson({ lastScope: { kind: "specific-milestone" } }));
    assert.deepEqual(stored?.lastScope, { kind: "specific-milestone" });
  });

  it("drops a target or origin that is not a string, keeping the kind", () => {
    const stored = parseStoredRun(
      storedJson({ lastScope: { kind: "specific-issue", target: 418, origin: [] } }),
    );
    assert.deepEqual(stored?.lastScope, { kind: "specific-issue" });
  });

  it("drops either number when it is not an integer", () => {
    for (const bad of [null, "10", 2.5, []]) {
      const stored = parseStoredRun(storedJson({ maxWorkItems: bad, maxParallel: bad }));
      assert.equal(stored?.maxWorkItems, undefined, `expected ${JSON.stringify(bad)} dropped`);
      assert.equal(stored?.maxParallel, undefined);
    }
  });

  it("keeps a number outside the question's bounds", () => {
    // The bounds belong to the question, which this module cannot see; an
    // out-of-range value is dropped at the point of use.
    assert.equal(parseStoredRun(storedJson({ maxWorkItems: 9999 }))?.maxWorkItems, 9999);
  });
});

describe("top-level passthrough", () => {
  it("carries a key this version does not interpret", () => {
    const stored = parseStoredRun(storedJson({ lastPlanner: "opus", waves: [1, 2] }));
    assert.deepEqual(stored?.passthrough, {
      lastPlanner: "opus",
      waves: [1, 2],
      knobs: { "sequential-reviewer": { maxIterations: 5 } },
    });
  });

  it("carries none of the keys it writes for itself", () => {
    // `knobs` is the exception that proves it: this version stopped writing it,
    // so it stopped being one of its own keys and became one to carry.
    assert.deepEqual(Object.keys(parseStoredRun(storedJson())?.passthrough ?? {}), ["knobs"]);
  });

  it("re-emits an unknown key on the next write, beside the known ones", () => {
    const first = parseStoredRun(storedJson({ lastPlanner: "opus" }));
    assert.ok(first);
    const raw = serializeStoredRun(
      mergeStoredRun(
        first,
        run("review-only", [{ agentId: "reviewer", modelId: "gpt-5.5", effort: "low" }]),
      ),
    );
    assert.equal(JSON.parse(raw).lastPlanner, "opus");
    assert.equal(JSON.parse(raw).lastWorkflowId, "review-only");
  });

  it("round-trips a v2 fixture holding `knobs` with `knobs` intact", () => {
    // The retirement, now that it has happened: `knobs` is an unrecognised
    // top-level key and passthrough carries it with no special case.
    const stored = parseStoredRun(storedJson());
    assert.ok(stored);
    const rewritten = serializeStoredRun(
      mergeStoredRun(
        stored,
        run("review-only", [{ agentId: "reviewer", modelId: "gpt-5.5", effort: "low" }]),
      ),
    );
    assert.deepEqual(JSON.parse(rewritten).knobs, {
      "sequential-reviewer": { maxIterations: 5 },
    });
  });
});

describe("the v1 read-side adapter", () => {
  it("reads v1's two roles as v2 agent entries", () => {
    // v1's field names already are the v2 agent ids, which is the whole
    // adapter; `sameForBoth` is simply not carried over.
    assert.deepEqual(parseStoredRun(v1Json()), {
      agents: {
        implementer: { model: "claude-opus-5", effort: "xhigh" },
        reviewer: { model: "claude-sonnet-4-6", effort: "high" },
      },
      // v1's own keys are interpreted rather than carried: they *are* the v2
      // agent entries, so passing them through would duplicate them forever.
      passthrough: {},
    });
  });

  it("emits version 2 on the next write", () => {
    const stored = parseStoredRun(v1Json());
    assert.ok(stored);
    const merged = mergeStoredRun(
      stored,
      run("sequential-reviewer", [{ agentId: "implementer", modelId: "claude-opus-5", effort: "xhigh" }]),
    );
    assert.match(serializeStoredRun(merged), /"version": 2/);
  });
});

describe("mergeStoredRun", () => {
  it("upserts only what this run touched", () => {
    const existing = parseStoredRun(storedJson());
    assert.ok(existing);
    const merged = mergeStoredRun(
      existing,
      // A one-agent run of a different workflow: under v1's wholesale replace
      // this erased the implementer and every key this version does not write.
      run(
        "review-only",
        [{ agentId: "reviewer", modelId: "gpt-5.5", effort: "low" }],
        { scope: { kind: "all-ready-for-agent" }, maxWorkItems: 4, maxParallel: 2 },
      ),
      "/clone/.git",
    );
    assert.deepEqual(merged, {
      lastWorkflowId: "review-only",
      lastScope: { kind: "all-ready-for-agent", origin: "/clone/.git" },
      maxWorkItems: 4,
      maxParallel: 2,
      agents: {
        implementer: { model: "claude-opus-5", effort: "xhigh" },
        reviewer: { model: "gpt-5.5", effort: "low" },
      },
      passthrough: { knobs: { "sequential-reviewer": { maxIterations: 5 } } },
    });
  });

  it("writes a store from nothing", () => {
    const merged = mergeStoredRun(
      undefined,
      run("sequential-reviewer", [{ agentId: "implementer", modelId: "claude-opus-5", effort: "max" }]),
      "/clone/.git/worktrees/perth",
    );
    assert.deepEqual(merged, {
      lastWorkflowId: "sequential-reviewer",
      lastScope: {
        kind: "specific-spec",
        target: "418",
        origin: "/clone/.git/worktrees/perth",
      },
      maxWorkItems: 10,
      maxParallel: 1,
      agents: { implementer: { model: "claude-opus-5", effort: "max" } },
      passthrough: {},
    });
  });

  it("stamps the writing worktree as the scope's origin, and nothing else", () => {
    // `origin` is the only part of the remembered scope that does not come from
    // the run. It gates the *target* alone, everywhere it is read.
    const merged = mergeStoredRun(undefined, run("review-only", []), undefined);
    assert.deepEqual(merged.lastScope, { kind: "specific-spec", target: "418" });
  });

  it("leaves unknown keys intact through a read-modify-write round trip", () => {
    const raw = storedJson({
      agents: {
        implementer: { model: "claude-opus-5", effort: "xhigh" },
        critic: { model: "gpt-5.5", effort: "low" },
      },
      knobs: {
        "sequential-reviewer": { maxIterations: 5, timeoutMinutes: 30 },
        "some-other-workflow": { depth: 3 },
      },
    });
    const first = parseStoredRun(raw);
    assert.ok(first);
    const rewritten = serializeStoredRun(
      mergeStoredRun(
        first,
        run("sequential-reviewer", [{ agentId: "implementer", modelId: "claude-opus-5", effort: "high" }]),
      ),
    );
    const second = parseStoredRun(rewritten);
    assert.deepEqual(second?.agents.critic, { model: "gpt-5.5", effort: "low" });
    assert.deepEqual(second?.passthrough.knobs, {
      "sequential-reviewer": { maxIterations: 5, timeoutMinutes: 30 },
      "some-other-workflow": { depth: 3 },
    });
  });
});

describe("writeStoredRun", () => {
  const plan = run(
    "sequential-reviewer",
    [
      { agentId: "implementer", modelId: "claude-opus-5", effort: "xhigh" },
      { agentId: "reviewer", modelId: "claude-sonnet-4-6", effort: "high" },
    ],
  );

  it("stamps this worktree's git dir as the origin by default", () => {
    const path = join(tempStoreDir(), "sandcastle-run.json");
    writeStoredRun(plan, path);
    assert.equal(parseStoredRun(readFileSync(path, "utf8"))?.lastScope?.origin, worktreeOrigin());
  });

  it("migrates a v1 file on disk to v2, preserving both picks", () => {
    const path = join(tempStoreDir(), "sandcastle-run.json");
    writeFileSync(path, v1Json(), "utf8");
    assert.equal(writeStoredRun(plan, path), true);

    const stored = parseStoredRun(readFileSync(path, "utf8"));
    assert.ok(stored);
    assert.match(readFileSync(path, "utf8"), /"version": 2/);
    assert.deepEqual(stored.agents, {
      implementer: { model: "claude-opus-5", effort: "xhigh" },
      reviewer: { model: "claude-sonnet-4-6", effort: "high" },
    });
    assert.equal(stored.lastWorkflowId, "sequential-reviewer");
  });

  it("overwrites a present file it cannot read", () => {
    // Write-only and unparseable: the read half of read-modify-write fails
    // whichever way the process's permissions fall, and the write proceeds
    // regardless — one corrupt file must not freeze the store forever.
    const path = join(tempStoreDir(), "sandcastle-run.json");
    writeFileSync(path, "{ not json", "utf8");
    chmodSync(path, 0o200);
    assert.equal(writeStoredRun(plan, path), true);
    chmodSync(path, 0o600);
    assert.match(readFileSync(path, "utf8"), /"version": 2/);
  });

  it("returns false when the write itself fails, without throwing", () => {
    const path = join(tempStoreDir(), "missing", "run.json");
    assert.equal(writeStoredRun(plan, path), false);
  });

  it("ends the file with a newline", () => {
    const path = join(tempStoreDir(), "sandcastle-run.json");
    writeStoredRun(plan, path);
    assert.ok(readFileSync(path, "utf8").endsWith("}\n"));
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
