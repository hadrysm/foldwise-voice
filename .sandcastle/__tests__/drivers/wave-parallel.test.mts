// The wave-parallel driver's whole walk, against a real temporary repository.
//
// **You only fake what is expensive.** The agents are faked; git is not. Every
// merge commit, every rewind and every refused deletion below is git's own,
// which is what makes this the only place #404's topology is actually proven
// rather than restated — an injected `Git` port would assert each claim against
// a fake written by whoever wrote the assumption.
//
// **Accepted cost, stated plainly:** this suite spawns processes and touches the
// filesystem, breaking the *spawns nothing* property the rest of `__tests__/`
// has. `drivers/git.test.mts` owns the claims about git in isolation; what is
// left for this file is whether the driver asks the right question at the right
// moment, and acts on the answer.

import assert from "node:assert/strict";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it, type TestContext } from "node:test";
import { driveWaveParallelWith } from "../../drivers/wave-parallel.mts";
import type { Revalidation } from "../../scope/github.mts";
import { RUN_REPORT_MARKER, runOrder } from "../../scope/snapshot.mts";
import {
  captureNarration,
  fakeTracker,
  type BodyCall,
  type TrackerWrite,
} from "../support/core.mts";
import {
  CONTESTED_FILE,
  tempRepo,
  WORKSPACE_BRANCH,
  worktreeExists,
  type TempRepo,
} from "../support/repo.mts";
import { specSnapshot, type FixtureIssue } from "../support/scope.mts";
import {
  COMMITS_NOTHING,
  crashesWith,
  gate,
  HANGS,
  reached,
  waveCore,
  waveWorkflow,
  type ItemScript,
  type ScriptContext,
  type WaveDispatch,
} from "../support/wave.mts";

/** Four mutually independent slices — one level, so `MAX_PARALLEL` is what cuts it. */
const INDEPENDENT: readonly FixtureIssue[] = [
  { number: 419 },
  { number: 420 },
  { number: 421 },
  { number: 422 },
];

/** 419 → 420 with 421 alongside: two levels, and one dependent to strand. */
const CHAINED: readonly FixtureIssue[] = [
  { number: 419 },
  { number: 420, blockedBy: [419] },
  { number: 421 },
];

interface DrivenRun {
  readonly repo: TempRepo;
  readonly calls: BodyCall[];
  readonly dispatches: WaveDispatch[];
  readonly writes: TrackerWrite[];
  readonly printed: string[];
  readonly report: string;
  /** `git log --merges`, oldest first — the only per-item boundary in the diff. */
  readonly merges: readonly string[];
  /**
   * What the run would have exited with. Captured and restored rather than read
   * off `process` afterwards, so one aborting test cannot decide what a later
   * test sees.
   */
  readonly exitCode: number | string | undefined;
}

interface DriveOptions {
  readonly issues?: readonly FixtureIssue[];
  readonly scripts?: Readonly<Record<number, ItemScript>>;
  readonly maxParallel?: number;
  readonly itemTimeoutMinutes?: number;
  readonly openAtSettle?: readonly number[];
  readonly revalidations?: Readonly<Record<number, Revalidation>>;
}

async function drive(t: TestContext, options: DriveOptions = {}): Promise<DrivenRun> {
  const printed = captureNarration(t);
  const repo = tempRepo(t);
  const snapshot = specSnapshot({ number: 418 }, [...(options.issues ?? INDEPENDENT)]);
  const order = runOrder(snapshot);
  assert.ok(order.ok);

  const calls: BodyCall[] = [];
  const { core, dispatches } = waveCore(repo, snapshot, order.items, {
    scripts: options.scripts,
    maxParallel: options.maxParallel ?? 3,
    itemTimeoutMinutes: options.itemTimeoutMinutes,
    openAtSettle: options.openAtSettle,
    revalidations: options.revalidations,
  });
  const { tracker, writes } = fakeTracker();

  const before = process.exitCode;
  process.exitCode = undefined;
  await driveWaveParallelWith(core, waveWorkflow(calls), { repoRoot: repo.root, tracker });
  const exitCode = process.exitCode;
  process.exitCode = before;

  return {
    exitCode,
    repo,
    calls,
    dispatches,
    writes,
    printed,
    report: printed.find((line) => line.includes(RUN_REPORT_MARKER)) ?? "",
    merges: repo.mergeSubjects(),
  };
}

function branchOf(item: number): string {
  return `sandcastle/${item}-issue-${item}`;
}

function mergeOf(item: number): string {
  return `Merge branch '${branchOf(item)}' into ${WORKSPACE_BRANCH}`;
}

describe("the wave-parallel driver's waves", () => {
  it("runs a whole level at once, bounded by MAX_PARALLEL", async (t) => {
    // Every script waits until all three siblings have entered, so a driver
    // running them one at a time never gets past the first — and a driver
    // running four at once would let #422 in before the barrier opened.
    const entered: number[] = [];
    const barrier = gate();
    const waitForSiblings: ItemScript = async ({ item, commit }) => {
      entered.push(item.number);
      if (entered.length === 3) barrier.open();
      await reached(barrier.opened);
      commit(`item-${item.number}.txt`, `from #${item.number}`);
    };

    const run = await drive(t, {
      maxParallel: 3,
      scripts: Object.fromEntries([419, 420, 421, 422].map((n) => [n, waitForSiblings])),
    });

    assert.deepEqual(entered.slice(0, 3), [419, 420, 421]);
    // The fourth is a second wave, cut only after the first three merged.
    assert.deepEqual(entered, [419, 420, 421, 422]);
    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(420), mergeOf(421), mergeOf(422)]);
  });

  it("cuts the next wave from the tip the previous one merged into", async (t) => {
    const run = await drive(t, { maxParallel: 3 });

    const baseOf = (item: number): string =>
      run.dispatches.find((dispatch) => dispatch.issueNumber === item)?.baseSha ?? "";
    // Wave one shares one base; wave two's is downstream of all three merges.
    assert.equal(baseOf(419), baseOf(420));
    assert.equal(baseOf(419), baseOf(421));
    assert.notEqual(baseOf(422), baseOf(419));
    assert.equal(
      run.repo.git(["merge-base", "--is-ancestor", baseOf(419), baseOf(422)]).trim(),
      "",
    );
  });

  it("holds a dependent back until the item it is blocked by has merged", async (t) => {
    const run = await drive(t, { issues: CHAINED, maxParallel: 3 });

    // 419 and 421 are one level; 420 is a level of its own behind 419.
    assert.deepEqual(
      run.calls.map((call) => call.item?.number),
      [419, 421, 420],
    );
    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(421), mergeOf(420)]);
  });
});

describe("the wave-parallel driver's fan-in", () => {
  it("merges in run order rather than completion order, once per item", async (t) => {
    // Completion runs backwards, and by a gate rather than by a clock: each
    // item finishes only once the item *after* it in run order has, so the
    // completion order is 421, 420, 419 on every machine. The merge commits
    // must still read 419, 420, 421.
    const afterLast = gate();
    const afterMiddle = gate();
    const commitOnce = ({ item, commit }: ScriptContext): void =>
      commit(`item-${item.number}.txt`, `from #${item.number}`);

    const run = await drive(t, {
      maxParallel: 3,
      scripts: {
        419: async (context) => {
          await reached(afterMiddle.opened);
          commitOnce(context);
        },
        420: async (context) => {
          await reached(afterLast.opened);
          commitOnce(context);
          afterMiddle.open();
        },
        421: (context) => {
          commitOnce(context);
          afterLast.open();
        },
      },
    });

    assert.deepEqual(run.merges.slice(0, 3), [mergeOf(419), mergeOf(420), mergeOf(421)]);
  });

  it("names every item's own branch, and merges nothing twice", async (t) => {
    const run = await drive(t, { maxParallel: 3 });

    assert.equal(run.merges.length, 4);
    assert.deepEqual(new Set(run.merges).size, 4);
  });

  it("gives each item's reviewer that item's own base, inside its own worktree", async (t) => {
    const run = await drive(t, { maxParallel: 3 });

    for (const item of [419, 420, 421, 422]) {
      const forItem = run.dispatches.filter((dispatch) => dispatch.issueNumber === item);
      const [implement, review] = forItem;
      assert.equal(forItem.length, 2, `#${item}`);
      assert.equal(review?.promptArgs["REVIEW_BASE"], implement?.baseSha, `#${item}`);
    }
    // Wave one's three reviewers each got a different base only in the sense
    // that each diffs its own branch — the base is shared, the commits are not.
    const reviews = run.dispatches.filter((dispatch) => dispatch.agentId === "reviewer");
    assert.equal(reviews.length, 4);
  });
});

describe("a wave that does not all settle", () => {
  it("merges the survivors, strands the dependents, and does not abort", async (t) => {
    const run = await drive(t, {
      issues: CHAINED,
      maxParallel: 3,
      scripts: { 419: crashesWith("the provider hung up") },
    });

    // 421 was independent and lands; 419 crashed; 420 was built on 419.
    assert.deepEqual(run.merges, [mergeOf(421)]);
    assert.match(run.report, /skipped {4}2 {2}#419 crashed; #420 depends on #419/);
    assert.doesNotMatch(run.report, /aborted/);
    assert.equal(run.exitCode, undefined);
    // Nothing of the crashed item is destroyed, and its dependent never ran.
    assert.ok(run.repo.branchExists(branchOf(419)));
    assert.equal(run.calls.some((call) => call.item?.number === 420), false);
  });

  it("rewinds a conflicting item alone and keeps its branch", async (t) => {
    const contest: ItemScript = ({ item, commit }) =>
      commit(CONTESTED_FILE, `rewritten by #${item.number}`);

    const run = await drive(t, {
      maxParallel: 3,
      scripts: { 419: contest, 420: contest },
    });

    // #419 merged first, so #420 is the one git could not reconcile — and it is
    // the only one: #421 and #422 are untouched by the rewind.
    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(421), mergeOf(422)]);
    assert.match(run.report, /#420 conflict rewound/);
    assert.ok(run.repo.branchExists(branchOf(420)));
    assert.ok(worktreeExists(run.repo.root, branchOf(420)));
    assert.equal(run.repo.git(["status", "--porcelain"]).trim(), "");
  });

  it("tells a timed-out item from one that simply committed nothing", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      itemTimeoutMinutes: 0.005,
      scripts: { 419: HANGS, 420: COMMITS_NOTHING },
    });

    // Two different failures, two different words — a hang is not evidence
    // about the work, and a suite that failed would be a third thing again.
    assert.match(run.report, /#419 timed out/);
    assert.match(run.report, /#420 no commits/);
    assert.deepEqual(run.merges, [mergeOf(421), mergeOf(422)]);
    assert.equal(run.repo.branchExists(branchOf(419)), true);
  });
});

describe("what a wave-parallel run leaves behind", () => {
  it("deletes a merged item's worktree and branch, and keeps an unmerged one's", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      scripts: { 419: crashesWith("nothing to show") },
    });

    for (const merged of [420, 421, 422]) {
      assert.equal(run.repo.branchExists(branchOf(merged)), false, `#${merged}`);
      assert.equal(worktreeExists(run.repo.root, branchOf(merged)), false, `#${merged}`);
    }
    assert.ok(run.repo.branchExists(branchOf(419)));
    assert.ok(worktreeExists(run.repo.root, branchOf(419)));
  });

  it("reports a refused deletion rather than throwing or forcing it", async (t) => {
    const leavesLitter: ItemScript = ({ item, path, commit }) => {
      commit(`item-${item.number}.txt`, `from #${item.number}`);
      // Untracked work the agent never committed. Merged or not, `git worktree
      // remove` refuses it, and the whole safety argument is that the run has
      // no flag with which to insist.
      writeFileSync(join(path, "left-behind.txt"), "half a thought");
    };
    const run = await drive(t, { maxParallel: 1, scripts: { 419: leavesLitter } });

    assert.deepEqual(run.merges.length, 4);
    assert.ok(
      run.printed.some((line) => line.includes("! kept") && line.includes(branchOf(419))),
      run.printed.join("\n"),
    );
    assert.ok(run.repo.branchExists(branchOf(419)));
  });

  it("reopens an item that closed its issue without merging anything", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      scripts: { 419: COMMITS_NOTHING },
    });

    assert.deepEqual(
      run.writes.filter((write) => write.act === "reopen").map((write) => write.issueNumber),
      [419],
    );
  });

  it("comments on a bounced-and-rewound item, naming the branch its work lives on", async (t) => {
    const contest: ItemScript = ({ item, commit }) =>
      commit(CONTESTED_FILE, `rewritten by #${item.number}`);

    const run = await drive(t, {
      maxParallel: 3,
      scripts: { 419: contest, 420: contest },
      openAtSettle: [420],
    });

    const comment = run.writes.find(
      (write) => write.act === "comment" && write.issueNumber === 420,
    );
    // Already open, so no reopen fires — and without this comment the branch
    // its work lives on would be named in no durable place at all.
    assert.ok(comment, JSON.stringify(run.writes));
    assert.match(comment.body, new RegExp(branchOf(420)));
    assert.equal(
      run.writes.some((write) => write.act === "reopen"),
      false,
    );
  });
});

describe("a wave-parallel run that aborts", () => {
  it("leaves every worktree and branch in place, and cleans nothing up", async (t) => {
    const run = await drive(t, {
      maxParallel: 2,
      scripts: { 419: crashesWith("the provider hung up") },
      revalidations: {
        421: { status: "anchor-changed", detail: "#418 is closed" },
      },
    });

    assert.match(run.report, /aborted/);
    assert.match(run.report, /#418 is closed/);
    // An unattended run that stopped on a changed contract did not do what it
    // was asked, and whatever launched it has to be able to tell.
    assert.equal(run.exitCode, 1);
    // #419 crashed in wave one and #420 merged; the abort adds no cleanup of
    // its own, and takes none away.
    assert.ok(run.repo.branchExists(branchOf(419)));
    assert.ok(worktreeExists(run.repo.root, branchOf(419)));
    assert.equal(
      run.calls.some((call) => call.item?.number === 421),
      false,
    );
  });
});

describe("what a wave-parallel run reports", () => {
  it("counts a clean sweep against the frozen selection", async (t) => {
    const run = await drive(t, { maxParallel: 3 });

    assert.match(run.report, /Run summary — SPEC #418, 4 of 4 eligible/);
    assert.match(run.report, /completed {2}4/);
  });
});
