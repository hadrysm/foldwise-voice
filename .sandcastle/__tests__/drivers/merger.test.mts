// What the runner does with a verdict, and when it asks for one at all.
//
// The Merger is the only thing in a run that sees a wave's items in one tree,
// and the only thing allowed to run this repository's verify loop — the runner
// may not, because a verify's exit code has to be interpreted and repaired,
// which is judgment. So what is testable here is not whether the tree builds. It
// is the pair of readings of `verified: false` that must never blur.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { mergeLine, mergerAction, type MergeVerdict } from "../../drivers/merger.mts";
import { mergerSkip } from "../../drivers/outcomes.mts";

function verdict(overrides: Partial<MergeVerdict> = {}): MergeVerdict {
  return { verified: true, unresolved: [], notes: "Full verify loop green.", ...overrides };
}

describe("whether the Merger is dispatched at all", () => {
  it("is skipped when exactly one branch merged cleanly into an unmoved base", () => {
    // The merged tree is then identical to that branch's tree, which the item's
    // own implement→review loop already gated. A git fact, not a guess about
    // the toolchain — and on a narrow SPEC, or any wave the Planner splits to
    // one, it is the common case.
    assert.equal(mergerSkip(["merged"]), true);
  });

  it("is skipped when a wave left the tip untouched, for the same reason twice over", () => {
    assert.equal(mergerSkip([null, null]), true);
  });

  it("is dispatched when two branches merged, because nothing gated the combination", () => {
    assert.equal(mergerSkip(["merged", "merged"]), false);
  });

  it("is dispatched when a branch is left conflicted, however few merged", () => {
    // The runner rewound it and will not try again; merging by hand is the
    // Merger's first job, and skipping here would abandon the branch silently.
    assert.equal(mergerSkip(["merged", "conflict-rewound"]), false);
    assert.equal(mergerSkip(["conflict-rewound"]), false);
  });

  it("ignores items that never reached a merge at all", () => {
    // A crash, a timeout and an empty branch leave nothing in the tree, so they
    // change neither what is there to verify nor what is there to merge.
    assert.equal(mergerSkip(["merged", null, null]), true);
  });
});

describe("the two readings of an unverified tree", () => {
  it("carries on when the tree is verified", () => {
    assert.deepEqual(mergerAction(verdict(), []), { kind: "carry-on" });
  });

  it("carries on when a conflict is what is left unmerged", () => {
    // A conflict belongs to exactly one branch. That branch is already rewound
    // and its dependents already skip, so there is nothing further to decide —
    // and cancelling the rest of a SPEC over one branch would be the wrong
    // trade by an order of magnitude.
    const action = mergerAction(verdict({ verified: false, unresolved: [420] }), [420]);

    assert.deepEqual(action, { kind: "carry-on" });
  });

  it("aborts when everything merged and the tree still fails", () => {
    // A tree that merged cleanly and then does not build is a semantic conflict
    // belonging to no branch: every item's own loop passed in isolation, so
    // there is nobody to leave out and nothing to rewind. The asymmetry is
    // attribution, and it is why this one stops the run.
    const action = mergerAction(
      verdict({ verified: false, notes: "#419 renamed what #420 calls." }),
      [],
    );

    assert.equal(action.kind, "abort");
    assert.match(action.kind === "abort" ? action.detail : "", /#419 renamed what #420 calls/);
  });
});

describe("the wave-level verdict line", () => {
  it("reports the Merger's own account beside what it did", () => {
    const line = mergeLine(2, verdict({ verified: false, unresolved: [420], notes: "both rewrote the recorder" }));

    assert.match(line, /wave 2/);
    assert.match(line, /#420/);
    assert.match(line, /both rewrote the recorder/);
  });

  it("says a clean wave was verified", () => {
    const line = mergeLine(1, verdict());

    assert.match(line, /verified/);
    assert.doesNotMatch(line, /unresolved/);
  });
});
