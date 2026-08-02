// A sweep, not a behaviour test: its subject is `contract.mts`'s source.
//
// The old denylist claimed a workflow could not contradict ADR-0001 because
// `DispatchOptions` omitted `sandbox`, `branchStrategy`, `maxIterations` and
// `hooks`. It could: `Dispatch` returned Sandcastle's `RunResult`, and
// `resume?`/`fork?` take an options type that omits none of those — so the
// omission list was defeated by the return type, and nothing failed.
//
// An allow-list cannot be defeated that way, but only while Sandcastle stays
// entirely below the seam. One `import type` here is all it would take to put a
// Sandcastle shape back in a workflow's hands, quietly, in a diff that compiles.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const CONTRACT = readFileSync(fileURLToPath(new URL("../contract.mts", import.meta.url)), "utf8");

/** Every `from "…"` in the file, type-only lines included. */
function imports(source: string): readonly string[] {
  return [...source.matchAll(/^import(?:\s+type)?[^;]*?from "([^"]+)";/gm)].map(
    (match) => match[1] ?? "",
  );
}

describe("the workflow contract", () => {
  it("names no Sandcastle module at all, type-only included", () => {
    for (const specifier of imports(CONTRACT)) {
      assert.equal(
        specifier.startsWith("@ai-hero/sandcastle"),
        false,
        `contract.mts imports ${specifier}`,
      );
    }
  });

  it("lets a workflow ask for exactly two things", () => {
    // Read off the source rather than off a value, because an interface has no
    // runtime shape to count and this is precisely what must not grow.
    const options = /export interface DispatchOptions \{([\s\S]*?)\n\}/.exec(CONTRACT)?.[1] ?? "";
    assert.deepEqual(
      [...options.matchAll(/^\s*readonly (\w+)\??:/gm)].map((match) => match[1]),
      ["promptFile", "promptArgs"],
    );
  });

  it("hands a workflow back exactly two things", () => {
    const result = /export interface DispatchResult \{([\s\S]*?)\n\}/.exec(CONTRACT)?.[1] ?? "";
    assert.deepEqual(
      [...result.matchAll(/^\s*readonly (\w+)\??:/gm)].map((match) => match[1]),
      ["commits", "baseSha"],
    );
  });

  it("has no `Knob` left to declare", () => {
    assert.equal(/\bKnob\b/.test(CONTRACT), false);
  });
});
