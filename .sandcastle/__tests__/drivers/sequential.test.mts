// The sequential driver's whole walk, against a fake core and a counting tracker.
//
// Nothing here spawns: `RunCore` is the whole of a driver's reach and `Tracker`
// the whole of what it may write, so the loop, the transitive cascade, the drift
// table, the per-item corrections and the handoff are all observable without a
// workflow, a network, a login or a git repository. That is the payoff #405
// predicted for moving the loop off the workflow and #423 for moving the
// judgment into `drivers/outcomes.mts`.
//
// The decisions themselves are asserted directly in `outcomes.test.mts`. What is
// left for this file is whether the driver asks the right question at the right
// moment, and acts on the answer.

import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import type { Workflow } from "../../contract.mts";
import { driveSequentialWith } from "../../drivers/sequential.mts";
import { RUN_REPORT_MARKER, runOrder, type WorkItem } from "../../scope/snapshot.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import {
  captureNarration,
  fakeCore,
  fakeTracker,
  recording,
  type BodyCall,
  type FakeCoreOptions,
} from "../support/core.mts";
import { specSnapshot } from "../support/scope.mts";

// 419 → 420 → 421 is a chain, and 422 is independent of all three.
const CHAIN = specSnapshot({ number: 418 }, [
  { number: 419 },
  { number: 420, blockedBy: [419] },
  { number: 421, blockedBy: [420] },
  { number: 422 },
]);

function chainWork(): readonly WorkItem[] {
  const order = runOrder(CHAIN);
  assert.ok(order.ok);
  return order.items;
}

/** Drive the whole chain, and hand back everything the run touched. */
async function driveChain(t: TestContext, options: FakeCoreOptions = {}) {
  const printed = captureNarration(t);
  const calls: BodyCall[] = [];
  const { core, dispatches } = fakeCore(CHAIN, chainWork(), options);
  const { tracker, writes } = fakeTracker();

  await driveSequentialWith(core, recording("sequential", calls), tracker);

  const report = printed.find((line) => line.includes(RUN_REPORT_MARKER)) ?? "";
  return { calls, dispatches, writes, printed, report };
}

describe("the sequential driver", () => {
  it("runs the body once per work item, in the order it was given them", async (t) => {
    const { calls } = await driveChain(t);

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [419, 420, 421, 422],
    );
  });

  it("scopes each body's dispatch to that body's own item", async (t) => {
    // The item is passed to the body to read and never to `dispatch`, so this
    // is what "the driver decided which one before the body ran" comes to.
    const { dispatches } = await driveChain(t);

    assert.deepEqual(
      dispatches.map((dispatch) => dispatch.issueNumber),
      [419, 420, 421, 422],
    );
  });

  it("runs nothing when there is nothing to run", async (t) => {
    captureNarration(t);
    const calls: BodyCall[] = [];
    const { core } = fakeCore(CHAIN, []);
    const { tracker } = fakeTracker();

    await driveSequentialWith(core, recording("sequential", calls), tracker);

    assert.deepEqual(calls, []);
  });
});

describe("an item that leaves no foundation", () => {
  it("takes every item blocked by it, transitively, and leaves the independent one alone", async (t) => {
    const { calls, report } = await driveChain(t, { commits: { 419: 0 } });

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [419, 422],
    );
    assert.match(report, /#419 no commits; #420 depends on #419; #421 depends on #420/);
  });

  it("never touches a transitively skipped item on the tracker", async (t) => {
    const { writes } = await driveChain(t, { commits: { 419: 0 } });

    assert.deepEqual(
      writes.filter((write) => write.issueNumber === 420 || write.issueNumber === 421),
      [],
    );
  });

  it("reopens a closed item whose work never landed, and names no branch", async (t) => {
    const { writes } = await driveChain(t, { commits: { 419: 0 } });
    const reopen = writes.find((write) => write.act === "reopen");

    assert.ok(reopen, "a closed item that committed nothing was left claiming to be done");
    assert.equal(reopen.issueNumber, 419);
    assert.equal(reopen.body.split("\n", 1)[0], RUN_REPORT_MARKER);
    assert.match(reopen.body, /no branch to salvage/);
  });

  it("skips dependents when the body throws, and says so rather than crashing the run", async (t) => {
    const printed = captureNarration(t);
    const { core } = fakeCore(CHAIN, chainWork());
    const { tracker } = fakeTracker();
    const exploding: Workflow = {
      ...sequentialReviewer,
      run: ({ item }) =>
        item?.number === 419
          ? Promise.reject(new Error("the provider went away"))
          : Promise.resolve(),
    };

    await driveSequentialWith(core, exploding, tracker);

    assert.ok(printed.some((line) => line.includes("crashed: the provider went away")));
    assert.ok(printed.some((line) => line.includes("#420 skipped — depends on #419")));
  });
});

describe("a bounced item", () => {
  it("merges like a success, so its dependents still run", async (t) => {
    const { calls, report } = await driveChain(t, { openAtSettle: [419] });

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [419, 420, 421, 422],
    );
    assert.match(report, /bounced {4}1 {2}#419/);
  });

  it("receives neither a reopen nor a comment", async (t) => {
    // Open claims *unfinished*, which is exactly the reviewer's ruling. It never
    // claimed no code exists.
    const { writes } = await driveChain(t, { openAtSettle: [419] });

    assert.deepEqual(writes.filter((write) => write.issueNumber === 419), []);
  });
});

describe("mid-run drift", () => {
  it("skips a closed item alone, because someone did the work", async (t) => {
    const { calls, report } = await driveChain(t, {
      revalidations: { 419: { status: "item-closed", detail: "#419 was closed during the run" } },
    });

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [420, 421, 422],
    );
    assert.match(report, /drift {6}1 {2}#419 was closed during the run/);
  });

  it("skips a deregulated item and everything built on it", async (t) => {
    const { calls } = await driveChain(t, {
      revalidations: {
        419: { status: "item-deregulated", detail: "#419 now carries `ready-for-human`" },
      },
    });

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [422],
    );
  });

  it("aborts the whole run when the anchor changed, and labels nothing", async (t) => {
    const before = process.exitCode;
    const { calls, writes, report } = await driveChain(t, {
      revalidations: { 420: { status: "anchor-changed", detail: "#418 is closed" } },
      // A handoff that *would* have labelled, so the refusal is the abort's and
      // not the condition's.
      handoff: {
        anchor: { number: 418, state: "open", labels: ["spec", "ready-for-agent"] },
        descendants: [],
      },
    });

    assert.deepEqual(
      calls.map((call) => call.item?.number),
      [419],
    );
    assert.match(report, /aborted {4}3 {2}#418 is closed/);
    // The report still goes onto the anchor; the label does not.
    assert.deepEqual(
      writes.map((write) => write.act),
      ["comment"],
    );
    // An unattended run that stopped on a changed contract has to tell whatever
    // launched it.
    assert.equal(process.exitCode, 1);
    process.exitCode = before;
  });
});

describe("the handoff", () => {
  const drained = {
    anchor: { number: 418, state: "open", labels: ["spec", "ready-for-agent"] },
    descendants: [{ number: 419, state: "closed", labels: ["ready-for-agent"] }],
  } as const;

  it("comments the report on the anchor and labels a drained SPEC", async (t) => {
    const { writes } = await driveChain(t, { handoff: drained });

    assert.deepEqual(
      writes.map((write) => [write.act, write.issueNumber]),
      [
        ["comment", 418],
        ["addLabel", 418],
      ],
    );
    assert.equal(writes[1]?.body, "code-review");
    assert.equal(writes[0]?.body.split("\n", 1)[0], RUN_REPORT_MARKER);
  });

  it("leaves a SPEC with an open released slice unlabelled", async (t) => {
    const { writes } = await driveChain(t, {
      handoff: {
        ...drained,
        descendants: [{ number: 419, state: "open", labels: ["ready-for-agent"] }],
      },
    });

    assert.deepEqual(
      writes.map((write) => write.act),
      ["comment"],
    );
  });

  it("reports a handoff read it could not make, rather than failing a finished run", async (t) => {
    // Everything the run was launched to do has already happened and its report
    // is already out, so a rate limit here must not make a completed run look
    // like a failed one.
    const before = process.exitCode;
    const { writes, printed, report } = await driveChain(t, {
      handoffFails: "GitHub returned 429",
    });

    assert.match(report, /completed {2}4/);
    assert.ok(printed.some((line) => line.includes("GitHub returned 429")));
    assert.deepEqual(
      writes.map((write) => write.act),
      ["comment"],
    );
    assert.equal(process.exitCode, before);
  });

  it("writes no durable report at all when the scope named no anchor", async (t) => {
    const printed = captureNarration(t);
    const { core } = fakeCore({ ...CHAIN, anchorNodeId: null }, chainWork());
    const { tracker, writes } = fakeTracker();

    await driveSequentialWith(core, recording("sequential", []), tracker);

    assert.deepEqual(writes, []);
    assert.ok(printed.some((line) => line.includes("Run summary — 4 of 4 eligible")));
  });
});
