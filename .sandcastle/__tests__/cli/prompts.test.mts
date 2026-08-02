import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { validateInteger } from "../../cli/prompts.mts";

// The run guard's bounds, which is the widest typed number the picker asks for.
const bounds = { min: 1, max: 50 };

describe("the typed number field", () => {
  it("accepts an empty field, which is how enter accepts the default", () => {
    // Clack substitutes `defaultValue` after validation runs, so validation sees
    // the empty string and must not treat it as a missing answer.
    assert.equal(validateInteger("", bounds), undefined);
    assert.equal(validateInteger("   ", bounds), undefined);
    assert.equal(validateInteger(undefined, bounds), undefined);
  });

  it("accepts a whole number inside the bounds", () => {
    for (const typed of ["1", "10", "50", " 7 "]) {
      assert.equal(validateInteger(typed, bounds), undefined, typed);
    }
  });

  it("refuses anything that is not a whole number", () => {
    for (const typed of ["abc", "2.5", "1/2", "ten", "5 issues", "-"]) {
      assert.equal(validateInteger(typed, bounds), "Enter a whole number.", typed);
    }
  });

  it("refuses a value below the minimum rather than clamping it", () => {
    assert.equal(validateInteger("0", bounds), "Enter a number between 1 and 50.");
    assert.equal(validateInteger("-3", bounds), "Enter a number between 1 and 50.");
  });

  it("refuses a value above the maximum rather than clamping it", () => {
    assert.equal(validateInteger("51", bounds), "Enter a number between 1 and 50.");
    assert.equal(validateInteger("9999", bounds), "Enter a number between 1 and 50.");
  });
});
