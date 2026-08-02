// What the runner does with a plan, which is the half of the Planner nothing
// else can test.
//
// **Tier 2 proves the validator, never the model.** Nothing here — and nothing
// anywhere — can show that a real Planner produces a good plan; that is one of
// the three claims #418 hands to the maintainer's single acceptance run. What is
// provable is that every bad plan lands on the computed wave, that it does so
// with no retry and no abort, and that the fallback says so out loud.
//
// The last one is the point of this file. The Planner's failure mode was
// designed to be invisible: a silent fallback, a prompt that never mentions it,
// and seven outcomes that are all per-*item*. Without the wave-level line, every
// wave could silently become the computed wave, the run completes, the ledger
// looks perfect, and the one genuinely new component has never worked.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  checkPlan,
  computedWave,
  needsPlan,
  planLine,
  PLAN_SCHEMA,
  readyRecords,
  type Plan,
} from "../../drivers/planner.mts";
import { specSnapshot } from "../support/scope.mts";
import { runOrder, type WorkItem } from "../../scope/snapshot.mts";

const TREE = specSnapshot({ number: 418 }, [
  { number: 419, title: "Move repo-shaped configuration", body: "the pure move" },
  { number: 420, title: "Add the snapshot" },
  { number: 421, title: "Resolve Work scope" },
  { number: 422, title: "Make the picker scope-first" },
]);

function ready(...numbers: readonly number[]): readonly WorkItem[] {
  const order = runOrder(TREE);
  assert.ok(order.ok);
  return order.items.filter((item) => numbers.includes(item.number));
}

function plan(wave: readonly number[]): Plan {
  return { wave, deferrals: [] };
}

function numbers(items: readonly WorkItem[]): readonly number[] {
  return items.map((item) => item.number);
}

describe("whether the Planner is asked at all", () => {
  it("is skipped at a one-item level, where the only valid plan is that item", () => {
    assert.equal(needsPlan(ready(419)), false);
  });

  it("is asked at a two-item level even when MAX_PARALLEL would fit both", () => {
    // Not skipped merely because the level fits: at MAX_PARALLEL = 3 a two-item
    // level can still hold two items that must not run together, which is the
    // one judgment the dependency edges do not encode.
    assert.equal(needsPlan(ready(419, 420)), true);
  });
});

describe("the wave the runner computes for itself", () => {
  it("is the first MAX_PARALLEL of the ready level, in settled order", () => {
    assert.deepEqual(numbers(computedWave(ready(419, 420, 421, 422), 3)), [419, 420, 421]);
  });

  it("is what every invalid plan falls back to, so the fallback is valid by construction", () => {
    const fallback = computedWave(ready(419, 420), 3);

    assert.deepEqual(numbers(fallback), [419, 420]);
    assert.ok(checkPlan(plan(numbers(fallback)), ready(419, 420), 3).ok);
  });
});

describe("what the runner checks after the schema has passed", () => {
  const level = ready(419, 420, 421, 422);

  it("checks nothing the schema could have checked, and the schema knows no wave", () => {
    // The structural half of *no semantic retry*. `PLAN_SCHEMA` is one module
    // constant rather than a validator composed per wave, so a plan naming work
    // that is not ready passes shape and fails only here — where `maxRetries`
    // cannot reach it however many times it resumes the agent's session.
    const shape = PLAN_SCHEMA["~standard"].validate({ wave: [999], deferrals: [] });

    assert.ok("value" in shape);
    assert.equal(checkPlan(plan([999]), level, 3).ok, false);
  });

  it("accepts a strict subset, because omitting ready items is the whole power", () => {
    const checked = checkPlan(plan([422, 419]), level, 3);

    assert.ok(checked.ok);
    // Order inside `wave` carries no meaning, so the runner re-reads it in the
    // order it settled — the order the fan-in merges in.
    assert.deepEqual(numbers(checked.wave), [419, 422]);
  });

  it("accepts a plan that is the whole level", () => {
    const checked = checkPlan(plan([419, 420, 421]), ready(419, 420, 421), 3);

    assert.ok(checked.ok);
  });

  it("rejects a zero-item plan, which can only mean defer everything", () => {
    const checked = checkPlan(plan([]), level, 3);

    assert.equal(checked.ok, false);
    assert.match(checked.ok ? "" : checked.reason, /no items/);
  });

  it("rejects a wave wider than MAX_PARALLEL rather than draining it through a semaphore", () => {
    const checked = checkPlan(plan([419, 420, 421, 422]), level, 3);

    assert.equal(checked.ok, false);
    assert.match(checked.ok ? "" : checked.reason, /at most 3/);
  });

  it("rejects a number that is not ready in this wave", () => {
    const checked = checkPlan(plan([419, 999]), level, 3);

    assert.equal(checked.ok, false);
    assert.match(checked.ok ? "" : checked.reason, /#999/);
  });

  it("rejects a duplicate, which would otherwise dispatch one item twice", () => {
    const checked = checkPlan(plan([419, 419]), level, 3);

    assert.equal(checked.ok, false);
    assert.match(checked.ok ? "" : checked.reason, /#419/);
  });

  it("does not cross-check the deferrals against what was left out", () => {
    // Advisory prose, deliberately: a level splitter whose deferrals are
    // unexplained is unauditable, and a deferral the runner policed would
    // become a second place a plan can fail for a reason nobody reads.
    const checked = checkPlan(
      { wave: [419], deferrals: [{ number: 422, reason: "rewrites runner.mts, as does #419" }] },
      ready(419, 420),
      3,
    );

    assert.ok(checked.ok);
  });
});

describe("the wave-level ledger line", () => {
  it("says a plan was accepted, and names what it deferred and why", () => {
    const line = planLine(
      2,
      { kind: "accepted", deferrals: [{ number: 421, reason: "rewrites runner.mts, as does #419" }] },
      ready(419, 420),
    );

    assert.match(line, /wave 2/);
    assert.match(line, /#419, #420/);
    assert.match(line, /#421 — rewrites runner\.mts, as does #419/);
  });

  it("says a plan was rejected, why, and what ran instead", () => {
    // Telling the human after the run is not telling the agent during it:
    // `plan-prompt.md` stays silent about the fallback, and this line is the
    // only place a maintainer learns the Planner never worked.
    const line = planLine(3, { kind: "fallback", reason: "#999 is not ready" }, ready(419, 420));

    assert.match(line, /wave 3/);
    assert.match(line, /#999 is not ready/);
    assert.match(line, /#419, #420/);
  });
});

describe("what the Planner is handed", () => {
  it("is number, title and body — never a label, a comment or an edge", () => {
    assert.deepEqual(readyRecords(TREE, ready(419, 420)), [
      { number: 419, title: "Move repo-shaped configuration", body: "the pure move" },
      { number: 420, title: "Add the snapshot", body: "" },
    ]);
  });
});
