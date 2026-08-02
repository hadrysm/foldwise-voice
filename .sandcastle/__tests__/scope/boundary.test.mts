// A sweep, not a behaviour test: its subject is this tool's source rather than
// any function's return value.
//
// `scope/github.mts` is *the* module that talks to GitHub, and that claim rots
// the moment a second module builds a path of its own — quietly, because the
// second one works. So the rule is enumerated from the filesystem rather than
// from a list of today's modules, which is what makes it cover a module nobody
// has written yet.

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

const SANDCASTLE = fileURLToPath(new URL("../../", import.meta.url));

/**
 * Skipped wholesale:
 *
 * - `node_modules/` — not ours.
 * - `__tests__/` — a test that fakes GitHub has to be able to spell GitHub.
 * - `PROTOTYPE-*` — throwaway by name and by ADR-0010; deleted, not maintained.
 */
function isSkipped(entry: string): boolean {
  return entry === "node_modules" || entry === "__tests__" || entry.startsWith("PROTOTYPE-");
}

function modules(directory: string = SANDCASTLE): readonly string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (isSkipped(entry.name)) return [];
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return modules(path);
    return entry.isFile() && entry.name.endsWith(".mts") ? [path] : [];
  });
}

/**
 * What "names GitHub" means here: a github.com URL, or a REST path. Deliberately
 * not `gh` itself — the drivers legitimately shell out to `gh issue reopen`, and
 * a CLI subcommand is not an endpoint this module owns.
 */
const NAMES_GITHUB: readonly RegExp[] = [
  /github\.com/,
  /\brepos\/[^\s"'`]/,
  /\bsub_issues\b/,
  /\bblocked_by\b/,
];

/**
 * Code only. Prose about `blocked_by` is domain vocabulary — `scope/snapshot.mts`
 * has to be able to explain *why* it never re-derives a blocker — while a path
 * in code is the thing that must not exist twice.
 *
 * Whole comment lines are dropped rather than trailing ones, because a naive
 * `//` strip would cut a `https://github.com/…` literal in half and hide the
 * exact offender this sweep is for.
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

describe("the GitHub boundary", () => {
  it("finds the modules to sweep", () => {
    const found = modules().map((path) => relative(SANDCASTLE, path));
    assert.ok(found.includes("scope/github.mts"));
    assert.ok(found.includes("runner.mts"));
    assert.ok(found.length > 8, `only found ${found.length} modules`);
  });

  it("is crossed by exactly one module", () => {
    const offenders = modules()
      .filter((path) => {
        const code = codeOf(readFileSync(path, "utf8"));
        return NAMES_GITHUB.some((marker) => marker.test(code));
      })
      .map((path) => relative(SANDCASTLE, path));

    assert.deepEqual(offenders, ["scope/github.mts"]);
  });
});
