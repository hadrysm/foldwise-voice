// The driver registry, and the shape that walks no work items.
//
// A registry rather than a literal list at each use site, because the sweeps
// that keep this tool framework-agnostic have to enumerate from one. The
// sequential driver's own walk is `sequential.test.mts`'s.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { DRIVERS, runnableDriver } from "../../drivers/registry.mts";
import { runOrder, type WorkItem } from "../../scope/snapshot.mts";
import { reviewOnly } from "../../workflows/review-only/workflow.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import {
  captureNarration,
  fakeCore,
  fakeTracker,
  recording,
  type BodyCall,
} from "../support/core.mts";
import { specSnapshot } from "../support/scope.mts";

const SPEC_TREE = specSnapshot({ number: 418 }, [{ number: 419 }, { number: 420 }]);

function specWork(): readonly WorkItem[] {
  const order = runOrder(SPEC_TREE);
  assert.ok(order.ok);
  return order.items;
}

describe("the whole-branch driver", () => {
  it("runs the body once, with no work item and the branch dispatch", async (t) => {
    captureNarration(t);
    const calls: BodyCall[] = [];
    const { core, dispatches } = fakeCore(SPEC_TREE, specWork());
    const { tracker, writes } = fakeTracker();

    await DRIVERS["whole-branch"].drive?.(core, recording("whole-branch", calls));

    assert.deepEqual(calls, [{ item: null }]);
    assert.deepEqual(dispatches, [{ issueNumber: 0, agentId: "implementer" }]);
    // It drains nothing, so it corrects nothing and hands nothing off — the
    // tracker it never received could not have been written to anyway.
    assert.deepEqual(writes, []);
  });
});

describe("the driver registry", () => {
  it("describes every execution shape SPEC #418 decided", () => {
    assert.deepEqual(Object.keys(DRIVERS), ["sequential", "wave-parallel", "whole-branch"]);
    for (const [id, driver] of Object.entries(DRIVERS)) assert.equal(driver.id, id);
  });

  it("says which shapes drain work items and which run them side by side", () => {
    assert.deepEqual(
      Object.values(DRIVERS).map((driver) => [driver.id, driver.drains, driver.concurrent]),
      [
        ["sequential", true, false],
        ["wave-parallel", true, true],
        ["whole-branch", false, false],
      ],
    );
  });

  it("refuses a workflow whose shape this build cannot run yet", () => {
    // Registered so the picker can ask `MAX_PARALLEL`, unbuilt until slices
    // 8–10 — and refused before `prepare()` reaches anything that dispatches.
    assert.equal(DRIVERS["wave-parallel"].drive, null);
    assert.throws(
      () => runnableDriver({ ...sequentialReviewer, driver: "wave-parallel" }),
      /cannot run yet/,
    );
  });

  it("hands every shipped workflow a driver that runs", () => {
    for (const workflow of [sequentialReviewer, reviewOnly]) {
      assert.equal(typeof runnableDriver(workflow), "function", workflow.id);
    }
  });
});
