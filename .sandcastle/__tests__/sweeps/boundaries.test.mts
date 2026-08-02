// The framework-agnostic and safety boundaries, swept over the source.
//
// Tier 3, and the only tier that covers code nobody has written yet — which is
// what *"no toolchain command reaches a driver, in every current and future
// workflow"* actually requires. No compiler and no behaviour test can deliver
// that; both only see what has been written.
//
// Every sweep here enumerates from `DRIVERS` or from `readdir`, never from a
// list of today's drivers, and the rules themselves live in
// `__tests__/support/sweeps.mts` so `planted.test.mts` can show each one
// failing. What this file owns is the corpus and the assertion.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { correctionComment, runReport } from "../../drivers/outcomes.mts";
import { RUN_REPORT_MARKER } from "../../scope/snapshot.mts";
import { driversAreCovered, sweptModules } from "../support/corpus.mts";
import { importClosure } from "../support/source.mts";
import {
  cleanupIsUnforced,
  commandsAreFrameworkNeutral,
  commentComposers,
  composedBodiesCarryTheMarker,
  describeViolations,
  nothingReachesSandcastle,
  trackerOnlyCorrects,
  type Violation,
} from "../support/sweeps.mts";

function assertClean(found: readonly Violation[]): void {
  assert.equal(found.length, 0, describeViolations(found));
}

/**
 * One sample body per composer the marker sweep discovers.
 *
 * Composed here rather than asserted here: the rule is *every* body the run
 * writes opens with the marker, and a suite that listed the two it knows about
 * would stop covering the third. `composedBodiesCarryTheMarker` reports a
 * discovered composer this map has no entry for, so adding one is a failing
 * test rather than a forgotten one.
 */
const COMPOSED_BODIES: ReadonlyMap<string, string> = new Map([
  [
    "runReport",
    runReport({
      anchor: { number: 418, isSpec: true },
      records: [],
      selected: 1,
      eligible: 1,
      aborted: null,
    }),
  ],
  [
    "correctionComment",
    correctionComment({
      reopened: true,
      workspaceBranch: "t3code/workspace",
      outcome: "no commits",
      branch: null,
      commits: 0,
      logPath: null,
    }),
  ],
]);

describe("the runner and every driver", () => {
  it("has a module for every driver the registry names", () => {
    assertClean(driversAreCovered(sweptModules()));
  });

  it("runs no command but git and gh", () => {
    // The rule: the runner may run a command whose output it discards, and
    // never one whose exit code it branches on — git excepted, because git says
    // nothing about what language this repository is written in. Anything the
    // toolchain owns belongs in `repo.mts`, passed through as configuration.
    assertClean(commandsAreFrameworkNeutral(sweptModules()));
  });

  it("uses no force flag anywhere", () => {
    // The whole of the no-force-flag safety argument, and the reason cleanup is
    // allowed to run at all: `git worktree remove` refuses a dirty worktree and
    // `git branch -d` refuses an unmerged branch, so git itself is what stops a
    // run destroying work a human has never seen.
    assertClean(cleanupIsUnforced(sweptModules()));
  });

  it("writes only the three tracker corrections, and never closes an issue", () => {
    assertClean(trackerOnlyCorrects(sweptModules()));
  });

  it("opens every comment body it composes with the run-report marker", () => {
    const composers = commentComposers(sweptModules());
    assertClean(composedBodiesCarryTheMarker(composers, COMPOSED_BODIES, RUN_REPORT_MARKER));
  });
});

describe("the contract's import closure", () => {
  it("reaches no Sandcastle type, not even a type-only one", () => {
    // Over the closure rather than over `contract.mts` alone: a re-export one
    // module along is the same leak by a longer route. Imports none is also
    // what makes exports none structural — a module that never names the
    // package has no Sandcastle type to export, so the two-key allow-list
    // cannot be widened by an upgrade the way the old `Omit<…>` denylist was.
    assertClean(nothingReachesSandcastle(importClosure("contract.mts")));
  });
});
