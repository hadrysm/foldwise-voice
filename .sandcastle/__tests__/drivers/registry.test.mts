// The drivers, driven against a fake core.
//
// Nothing here spawns: `RunCore` is the whole of a driver's reach, so a plain
// object with a counting `forItem` is a complete substitute for the runner. That
// is the payoff #405 predicted for moving the loop off the workflow — the loop
// is now observable without a workflow, a network or a git repository.

import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import { IMPLEMENTER } from "../../agents/catalog.mts";
import type { Dispatch, DriverId, Workflow } from "../../contract.mts";
import type { RunCore } from "../../drivers/core.mts";
import { DRIVERS, runnableDriver } from "../../drivers/registry.mts";
import { repo } from "../../repo.mts";
import type { WorkItem } from "../../scope/snapshot.mts";
import { reviewOnly } from "../../workflows/review-only/workflow.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import { fakeItem } from "../support/scope.mts";

/** What the body was handed, in the order the driver handed it over. */
interface BodyCall {
  readonly item: WorkItem | null;
  /** Which dispatch it was given: `item:419`, or `branch`. */
  readonly scope: string;
}

function fakeCore(work: readonly WorkItem[]): { core: RunCore; calls: BodyCall[] } {
  const calls: BodyCall[] = [];
  const scoped = (scope: string): Dispatch => {
    return () => {
      const last = calls[calls.length - 1];
      assert.ok(last, "a dispatch was reached before any body ran");
      assert.equal(last.scope, scope, "a body dispatched through another item's dispatch");
      return Promise.resolve({ commits: [{ sha: "commit-1" }], baseSha: "sha-1" });
    };
  };
  return {
    calls,
    core: {
      work,
      repo,
      forItem: (item) => scoped(`item:${item.number}`),
      forBranch: () => scoped("branch"),
    },
  };
}

/** A workflow that records what its body was given and dispatches once. */
function recording(driver: DriverId, calls: BodyCall[]): Workflow {
  return {
    ...sequentialReviewer,
    id: `recording-${driver}`,
    driver,
    run: async ({ item, dispatch }) => {
      calls.push({ item, scope: item ? `item:${item.number}` : "branch" });
      await dispatch(IMPLEMENTER, { promptFile: "implement-prompt.md" });
    },
  };
}

/** The driver narrates each item; the test suite does not need to hear it. */
function silenceNarration(t: TestContext): void {
  t.mock.method(console, "log", () => undefined);
}

describe("the sequential driver", () => {
  it("runs the body once per work item, in the order it was given them", async (t) => {
    silenceNarration(t);
    const { core, calls } = fakeCore([fakeItem(419), fakeItem(420), fakeItem(421)]);

    await DRIVERS.sequential.drive?.(core, recording("sequential", calls));

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [419, 420, 421],
    );
  });

  it("scopes each body's dispatch to that body's own item", async (t) => {
    // The item is passed to the body to read and never to `dispatch`, so this
    // is what "the driver decided which one before the body ran" comes to: the
    // fake core refuses a dispatch that belongs to a different item.
    silenceNarration(t);
    const { core, calls } = fakeCore([fakeItem(419), fakeItem(420)]);

    await DRIVERS.sequential.drive?.(core, recording("sequential", calls));

    assert.deepEqual(
      calls.map((call) => call.scope),
      ["item:419", "item:420"],
    );
  });

  it("runs nothing when there is nothing to run", async (t) => {
    silenceNarration(t);
    const { core, calls } = fakeCore([]);

    await DRIVERS.sequential.drive?.(core, recording("sequential", calls));

    assert.deepEqual(calls, []);
  });
});

describe("the whole-branch driver", () => {
  it("runs the body once, with no work item and the branch dispatch", async () => {
    const { core, calls } = fakeCore([fakeItem(419), fakeItem(420)]);

    await DRIVERS["whole-branch"].drive?.(core, recording("whole-branch", calls));

    assert.deepEqual(calls, [{ item: null, scope: "branch" }]);
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
