// The whole of what a draining run decides, with no network and no git.
//
// Every question a run answers when something goes wrong is a pure function of
// the snapshot and what the driver observed, and this is where that is asserted:
// the two-phase outcomes, the transitive cascade, the drift table, the two
// tracker acts on their different keys, and the `code-review` handoff.
//
// The seven rows of #404's failure-semantics table run through most of it, so
// they are named once here and reused rather than restated per test.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  cascade,
  correctionComment,
  deservesCodeReview,
  driftAction,
  foundationExists,
  itemBranch,
  outcomeLabel,
  runReport,
  SANDCASTLE_BRANCH_PREFIX,
  trackerActs,
  type ItemRecord,
  type Settlement,
} from "../../drivers/outcomes.mts";
import { RUN_REPORT_MARKER, type LiveIssueState } from "../../scope/snapshot.mts";
import { fakeItem, fixtureNodeId, specSnapshot } from "../support/scope.mts";

/** #404's failure-semantics table, as settlements. */
const ROWS = {
  merged: { loop: "committed", merge: "merged", commits: 3, bounced: false },
  bouncedAndMerged: { loop: "committed", merge: "merged", commits: 3, bounced: true },
  noCommits: { loop: "no-commits", merge: null, commits: 0, bounced: false },
  crashed: { loop: "crashed", merge: null, commits: 0, bounced: false },
  timedOut: { loop: "timed-out", merge: null, commits: 1, bounced: false },
  rewound: { loop: "committed", merge: "conflict-rewound", commits: 3, bounced: false },
  bouncedAndRewound: { loop: "committed", merge: "conflict-rewound", commits: 3, bounced: true },
} satisfies Record<string, Settlement>;

function settled(item: number, settlement: Settlement, branch: string | null = null): ItemRecord {
  return { item: fakeItem(item), outcome: { kind: "settled", ...settlement }, branch };
}

describe("the settle predicate", () => {
  it("leaves a foundation only where the code both landed and merged", () => {
    assert.deepEqual(
      Object.entries(ROWS).map(([row, settlement]) => [row, foundationExists(settlement)]),
      [
        ["merged", true],
        // A bounce is an annotation, never an outcome: the code landed and was
        // judged incomplete, so its dependents keep their foundation.
        ["bouncedAndMerged", true],
        ["noCommits", false],
        ["crashed", false],
        ["timedOut", false],
        ["rewound", false],
        ["bouncedAndRewound", false],
      ],
    );
  });

  it("names each outcome the way the report and the tracker comment both read it", () => {
    assert.deepEqual(
      Object.values(ROWS).map(outcomeLabel),
      [
        "completed",
        "bounced",
        "no commits",
        "crashed",
        "timed out",
        "conflict rewound",
        "conflict rewound",
      ],
    );
  });

  it("reads a committed item with no merge phase at all as completed", () => {
    // The sequential driver works in place, so there is no fan-in and `merge`
    // stays null — which must not read as an unmerged item.
    const inPlace: Settlement = { loop: "committed", merge: null, commits: 2, bounced: false };
    assert.equal(outcomeLabel(inPlace), "completed");
    assert.equal(foundationExists(inPlace), true);
  });
});

describe("the transitive cascade", () => {
  // 420 ← 421 ← 422 is a chain; 423 hangs off 420 too; 424 is independent.
  const snapshot = specSnapshot({ number: 418 }, [
    { number: 420 },
    { number: 421, blockedBy: [420] },
    { number: 422, blockedBy: [421] },
    { number: 423, blockedBy: [420] },
    { number: 424 },
  ]);

  it("drops every in-set item blocked by the failure, through a chain", () => {
    assert.deepEqual(
      cascade(snapshot, fixtureNodeId(420), new Set()).map((skip) => skip.nodeId),
      [fixtureNodeId(421), fixtureNodeId(423), fixtureNodeId(422)],
    );
  });

  it("names the blocker each dropped item lost, so no skip is silent", () => {
    assert.deepEqual(
      cascade(snapshot, fixtureNodeId(420), new Set()).map((skip) => skip.reason),
      ["depends on #420", "depends on #420", "depends on #421"],
    );
  });

  it("leaves independent items alone", () => {
    const dropped = cascade(snapshot, fixtureNodeId(421), new Set()).map((skip) => skip.nodeId);
    assert.deepEqual(dropped, [fixtureNodeId(422)]);
    assert.ok(!dropped.includes(fixtureNodeId(424)));
  });

  it("reports only what is newly dropped, so one item is never skipped twice", () => {
    const already = new Set([fixtureNodeId(421), fixtureNodeId(422)]);
    assert.deepEqual(
      cascade(snapshot, fixtureNodeId(420), already).map((skip) => skip.nodeId),
      [fixtureNodeId(423)],
    );
  });
});

describe("the drift table", () => {
  it("aborts on the anchor, skips a closed item alone, and skips a deregulated one transitively", () => {
    assert.equal(driftAction("anchor-changed"), "abort-run");
    // Someone did the work, so the foundation exists and dependents proceed.
    assert.equal(driftAction("item-closed"), "skip-item");
    // The work will not happen, so nothing may be built on it.
    assert.equal(driftAction("item-deregulated"), "skip-transitively");
  });
});

describe("the two tracker acts", () => {
  /** `merged` is the driver's reading of *did any of this reach the branch*. */
  function acts(closed: boolean, commits: number, merged: boolean) {
    const { reopen, comment } = trackerActs({ closed, commits, merged });
    return [reopen, comment];
  }

  it("reopens on closed-and-unmerged and comments on commits-and-unmerged", () => {
    assert.deepEqual(acts(true, 3, false), [true, true]);
  });

  it("gives a merged-but-bounced item neither act", () => {
    // Open claims *unfinished*, which is exactly the reviewer's ruling. It never
    // claimed that no code exists.
    assert.deepEqual(acts(false, 3, true), [false, false]);
  });

  it("comments without reopening on a bounced-and-rewound item", () => {
    // The case that forces the split: already open, so no reopen fires, and its
    // branch would otherwise be named in no durable place at all.
    assert.deepEqual(acts(false, 3, false), [false, true]);
  });

  it("reopens without commenting when a closed item produced nothing", () => {
    // The sequential driver's whole shape: unmerged *is* zero commits, so this
    // is the only act it can ever fire.
    assert.deepEqual(acts(true, 0, false), [true, false]);
  });

  it("touches nothing that merged, whatever the issue's state", () => {
    assert.deepEqual(acts(true, 3, true), [false, false]);
    assert.deepEqual(acts(false, 0, true), [false, false]);
  });

  it("answers every row of #404's failure-semantics table", () => {
    // The whole predicate at once, under a driver that has a fan-in phase — so
    // `merged` reads from the merge outcome rather than from *commits exist*.
    // `closed` is the issue's live state at settle: the implementer closes what
    // it finished, and the reviewer reopens what it bounced.
    const table = Object.entries(ROWS).map(([row, settlement]) => {
      const closed = !settlement.bounced;
      const merged = settlement.merge === "merged";
      const { reopen, comment } = trackerActs({ closed, commits: settlement.commits, merged });
      return [row, reopen, comment];
    });

    assert.deepEqual(table, [
      ["merged", false, false],
      // Neither act: open claims *unfinished*, which is the reviewer's ruling.
      ["bouncedAndMerged", false, false],
      // Reopen alone — there are no commits and so no branch worth naming.
      ["noCommits", true, false],
      ["crashed", true, false],
      // Both, as one reopen carrying the comment.
      ["timedOut", true, true],
      ["rewound", true, true],
      // The case that forces the split: already open, so only the comment fires.
      ["bouncedAndRewound", false, true],
    ]);
  });
});

describe("the correction comment", () => {
  const base = {
    workspaceBranch: "t3code/some-workspace",
    outcome: "conflict rewound",
    branch: "sandcastle/374-extract-the-pane-store",
    commits: 3,
    logPath: ".sandcastle/logs/374.log",
  };

  it("opens with the marker, so the run never reads its own bookkeeping back", () => {
    const body = correctionComment({ ...base, reopened: true });
    assert.equal(body.split("\n", 1)[0], RUN_REPORT_MARKER);
  });

  it("claims the reopen only when it reopened something", () => {
    assert.match(correctionComment({ ...base, reopened: true }), /^Reopened by Sandcastle/m);
    assert.doesNotMatch(correctionComment({ ...base, reopened: false }), /Reopened by Sandcastle/);
  });

  it("names the branch, its commit count and its log", () => {
    const body = correctionComment({ ...base, reopened: true });
    assert.match(body, /sandcastle\/374-extract-the-pane-store {2}\(3 commits, unmerged\)/);
    assert.match(body, /\.sandcastle\/logs\/374\.log/);
    assert.match(body, /no force flag/);
  });

  it("says there is nothing to salvage when the item worked in place and left nothing", () => {
    const body = correctionComment({
      ...base,
      reopened: true,
      outcome: "no commits",
      branch: null,
      commits: 0,
      logPath: null,
    });
    assert.doesNotMatch(body, /Branch:/);
    assert.doesNotMatch(body, /Log:/);
    assert.match(body, /no branch to salvage/);
  });
});

describe("the code-review handoff", () => {
  const anchor: LiveIssueState = {
    number: 418,
    state: "open",
    labels: ["ready-for-agent", "spec"],
  };
  const closedSlice: LiveIssueState = { number: 419, state: "closed", labels: ["ready-for-agent"] };

  it("labels an open SPEC whose every released descendant is closed", () => {
    assert.equal(deservesCodeReview({ anchor, descendants: [closedSlice] }), true);
  });

  it("never labels a closed anchor", () => {
    assert.equal(
      deservesCodeReview({ anchor: { ...anchor, state: "closed" }, descendants: [closedSlice] }),
      false,
    );
  });

  it("never labels an anchor that is not a SPEC", () => {
    assert.equal(
      deservesCodeReview({ anchor: { ...anchor, labels: ["ready-for-agent"] }, descendants: [] }),
      false,
    );
  });

  it("refuses while any released descendant is still open", () => {
    // A truncated list and a bounce both land here, and neither needs a case of
    // its own: a reopen lands before this is evaluated against live state.
    assert.equal(
      deservesCodeReview({
        anchor,
        descendants: [closedSlice, { number: 420, state: "open", labels: ["ready-for-agent"] }],
      }),
      false,
    );
  });

  it("ignores a descendant nobody released to an agent", () => {
    assert.equal(
      deservesCodeReview({
        anchor,
        descendants: [closedSlice, { number: 421, state: "open", labels: ["ready-for-human"] }],
      }),
      true,
    );
  });

  it("refuses when there was no anchor to judge", () => {
    assert.equal(deservesCodeReview(null), false);
  });
});

describe("the run report", () => {
  const records: readonly ItemRecord[] = [
    settled(419, ROWS.merged),
    settled(420, ROWS.bouncedAndMerged),
    settled(421, ROWS.noCommits),
    { item: fakeItem(422), outcome: { kind: "skipped", reason: "depends on #421" }, branch: null },
    {
      item: fakeItem(423),
      outcome: { kind: "drift", detail: "#423 now carries `ready-for-human`" },
      branch: null,
    },
  ];

  it("leads with the marker and the anchor, and states truncation rather than implying it", () => {
    const report = runReport({
      anchor: { number: 418, isSpec: true },
      records,
      selected: 5,
      eligible: 12,
      aborted: null,
    });

    assert.equal(report.split("\n", 1)[0], RUN_REPORT_MARKER);
    assert.match(report, /Run summary — SPEC #418, 5 of 12 eligible/);
    assert.match(report, /excluded {3}7 {2}truncated by the run guard/);
  });

  it("counts each group and names every item that did not simply complete", () => {
    const report = runReport({
      anchor: { number: 418, isSpec: true },
      records,
      selected: 5,
      eligible: 5,
      aborted: null,
    });

    assert.match(report, /completed {2}1$/m);
    assert.match(report, /bounced {4}1 {2}#420$/m);
    assert.match(report, /skipped {4}2 {2}#421 no commits; #422 depends on #421$/m);
    assert.match(report, /drift {6}1 {2}#423 now carries `ready-for-human`$/m);
    // Nothing was cut, so the row that would say so is absent rather than zero.
    assert.doesNotMatch(report, /excluded/);
  });

  it("leads with the abort and counts what stopping cost", () => {
    const report = runReport({
      anchor: { number: 418, isSpec: true },
      records: records.slice(0, 2),
      selected: 5,
      eligible: 5,
      aborted: "#418 is closed",
    });

    assert.match(report, /aborted {4}3 {2}#418 is closed/);
    assert.ok(report.indexOf("aborted") < report.indexOf("completed"));
  });

  it("drops the anchor from the heading when the scope named none", () => {
    const report = runReport({ anchor: null, records, selected: 5, eligible: 5, aborted: null });
    assert.match(report, /Run summary — 5 of 5 eligible/);
  });

  it("calls a non-SPEC anchor by its number alone", () => {
    const report = runReport({
      anchor: { number: 419, isSpec: false },
      records: records.slice(0, 1),
      selected: 1,
      eligible: 1,
      aborted: null,
    });
    assert.match(report, /Run summary — #419, 1 of 1 eligible/);
  });
});

describe("the branch one work item's commits land on", () => {
  it("names the issue and slugs its title", () => {
    assert.equal(
      itemBranch({ number: 425, title: "Add the wave-parallel driver's worktrees" }),
      "sandcastle/425-add-the-wave-parallel-drivers-worktrees",
    );
  });

  it("carries the prefix the workspace preflight refuses a leftover of", () => {
    // One definition, so the branch a run cuts and the branch the next run's
    // `prepare()` refuses to start over cannot drift apart.
    assert.ok(itemBranch({ number: 419, title: "Anything" }).startsWith(SANDCASTLE_BRANCH_PREFIX));
  });

  it("collapses every run of non-alphanumerics into one dash", () => {
    assert.equal(
      itemBranch({ number: 1, title: "  Fix `main.mts`: the — bare  'All done.' " }),
      "sandcastle/1-fix-main-mts-the-bare-all-done",
    );
  });

  it("truncates a long title without leaving a trailing dash", () => {
    const branch = itemBranch({
      number: 418,
      title: "Give the runner Work scope and the driver the loop, across fifteen slices",
    });

    assert.equal(branch, "sandcastle/418-give-the-runner-work-scope-and-the-driver-the");
    assert.ok(!branch.endsWith("-"));
  });

  it("falls back to the number alone when a title slugs to nothing", () => {
    assert.equal(itemBranch({ number: 420, title: "— … —" }), "sandcastle/420");
  });
});
