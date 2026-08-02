// A sweep, not a behaviour test: its subject is `cli/flow.mts`'s source rather
// than any function's return value.
//
// The picker's whole value is that the exact sequence of screens a run produces
// is an assertion rather than a manual walk — and that property is lost the
// first time the module draws something, spawns something or asks GitHub
// something itself. None of those would fail a test; they would just quietly
// make the flow untestable, which is why the boundary is swept rather than
// trusted.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

const FLOW = fileURLToPath(new URL("../../cli/flow.mts", import.meta.url));

/**
 * Code only. The header has to be able to *say* that this module draws nothing
 * with `@clack/prompts`, and a comment that names the thing it forbids is the
 * documentation, not the offence.
 */
function codeOf(source: string): string {
  return source
    .split("\n")
    .filter((line) => {
      const trimmed = line.trimStart();
      return !(trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("/*"));
    })
    .join("\n");
}

/**
 * Every module reached for its *values*. A `import type` line is erased before
 * anything runs, so it carries none of the imported module's side effects —
 * which is what lets the flow name `ScopeOutcome` without ever being able to go
 * and fetch one.
 */
function valueImports(source: string): readonly string[] {
  return [...source.matchAll(/^import(\s+type)?[^;]*?from "([^"]+)";/gm)]
    .filter((match) => match[1] === undefined)
    .map((match) => match[2]);
}

describe("the picker's pure half", () => {
  const source = readFileSync(FLOW, "utf8");
  const code = codeOf(source);

  it("draws nothing, spawns nothing and writes to no stream", () => {
    for (const marker of [/@clack\/prompts/, /node:child_process/, /process\.(stdout|stderr)/, /\bconsole\./]) {
      assert.equal(marker.test(code), false, `cli/flow.mts must not reach for ${String(marker)}`);
    }
  });

  it("runs code from five pure modules and reaches every other one for types alone", () => {
    // Enumerated rather than pattern-matched: the list is short enough to read,
    // and adding to it is exactly the decision that deserves a second look.
    //
    // `drivers/registry.mts` is on it because the run guard and `MAX_PARALLEL`
    // are asked of a *driver* rather than of a workflow. It stays a safe reach
    // only because every driver is itself pure — a driver that imported the
    // runner for anything but a type would drag Sandcastle in behind it and
    // this whole module would stop being assertable, which is why the driver
    // seam is declared in `drivers/core.mts` rather than in `runner.mts`.
    assert.deepEqual(valueImports(source), [
      "../agents/models.mts",
      "../drivers/registry.mts",
      "../repo.mts",
      "../scope/snapshot.mts",
      "../workflows/registry.mts",
    ]);
  });

  it("reaches Sandcastle through none of the drivers it now imports", () => {
    for (const driver of ["core", "registry", "sequential", "whole-branch"]) {
      const module = readFileSync(
        fileURLToPath(new URL(`../../drivers/${driver}.mts`, import.meta.url)),
        "utf8",
      );
      for (const forbidden of ["@ai-hero/sandcastle", "node:child_process", "../runner.mts"]) {
        assert.equal(
          valueImports(module).includes(forbidden),
          false,
          `drivers/${driver}.mts runs code from ${forbidden}`,
        );
      }
    }
  });
});
