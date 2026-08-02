// The hand-rolled Standard Schema validator, and the two schemas that use it.
//
// The reason this file exists at all is a dependency decision: `.sandcastle`
// has exactly two dependencies, and both structured-output schemas are two
// fields, so a validator is cheaper to write than zod is to add. What that
// trades away is zod's own test suite — so the shape rules below are asserted
// here rather than assumed.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { MERGE_SCHEMA, MERGE_TAG } from "../../drivers/merger.mts";
import { PLAN_SCHEMA, PLAN_TAG } from "../../drivers/planner.mts";
import { validator, type Validator } from "../../drivers/schema.mts";

function check<T>(schema: Validator<T>, value: unknown): { value?: T; problem?: string } {
  const result = schema["~standard"].validate(value);
  if ("issues" in result) return { problem: result.issues.map((issue) => issue.message).join("; ") };
  return { value: result.value };
}

describe("the hand-rolled validator", () => {
  it("declares itself a version 1 Standard Schema", () => {
    const schema = validator<number>("test", () => 1);

    assert.equal(schema["~standard"].version, 1);
    assert.equal(schema["~standard"].vendor, "test");
  });

  it("turns a reader's refusal into issues rather than a throw", () => {
    const schema = validator<number>("test", () => {
      throw new Error("not a number");
    });

    // Sandcastle feeds `issues` back to the agent as a token-efficient
    // description and resumes its session; a thrown error would kill the run
    // instead of asking for a corrected tag.
    assert.deepEqual(schema["~standard"].validate("x"), {
      issues: [{ message: "not a number" }],
    });
  });
});

describe("the plan schema", () => {
  it("reads a well-formed plan", () => {
    const { value } = check(PLAN_SCHEMA, {
      wave: [12, 15],
      deferrals: [{ number: 18, reason: "rewrites runner.mts, as does #12" }],
    });

    assert.deepEqual(value, {
      wave: [12, 15],
      deferrals: [{ number: 18, reason: "rewrites runner.mts, as does #12" }],
    });
  });

  it("is extracted from the tag the prompt emits", () => {
    assert.equal(PLAN_TAG, "plan");
  });

  it("accepts an empty wave and an empty deferral list", () => {
    // Shape only. A zero-item wave is a *semantic* failure, and it has to stay
    // one: the runner composes this schema per wave, so a schema that knew the
    // ready set would get semantic retries free from `maxRetries` — which is
    // exactly the thing "no semantic retry" promises does not happen.
    const { value } = check(PLAN_SCHEMA, { wave: [], deferrals: [] });

    assert.deepEqual(value, { wave: [], deferrals: [] });
  });

  it("refuses anything that is not a plan", () => {
    for (const bad of [
      null,
      [],
      "wave",
      { deferrals: [] },
      { wave: {}, deferrals: [] },
      { wave: ["12"], deferrals: [] },
      { wave: [1.5], deferrals: [] },
      { wave: [12] },
      { wave: [12], deferrals: [{ number: 18 }] },
      { wave: [12], deferrals: [{ number: 18, reason: 4 }] },
    ]) {
      const { problem } = check(PLAN_SCHEMA, bad);
      assert.ok(problem, JSON.stringify(bad));
    }
  });

  it("names the field it refused, so the retry knows what to fix", () => {
    const { problem } = check(PLAN_SCHEMA, { wave: ["12"], deferrals: [] });

    assert.match(problem ?? "", /wave/);
  });
});

describe("the merge schema", () => {
  it("reads a well-formed verdict", () => {
    const { value } = check(MERGE_SCHEMA, {
      verified: true,
      unresolved: [],
      notes: "Full verify loop green.",
    });

    assert.deepEqual(value, { verified: true, unresolved: [], notes: "Full verify loop green." });
  });

  it("is extracted from the tag the prompt emits", () => {
    assert.equal(MERGE_TAG, "merge");
  });

  it("refuses anything that is not a verdict", () => {
    for (const bad of [
      null,
      { unresolved: [], notes: "" },
      { verified: "true", unresolved: [], notes: "" },
      { verified: false, notes: "" },
      { verified: false, unresolved: ["420"], notes: "" },
      { verified: false, unresolved: [] },
    ]) {
      const { problem } = check(MERGE_SCHEMA, bad);
      assert.ok(problem, JSON.stringify(bad));
    }
  });
});
