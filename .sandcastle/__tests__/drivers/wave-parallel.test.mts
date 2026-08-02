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
import { RESERVED_PROMPT_ARGS } from "../../runner.mts";
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
  type Consultation,
  type ItemScript,
  type MergerScript,
  type PlannerScript,
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
  readonly consultations: Consultation[];
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
  readonly plans?: readonly PlannerScript[];
  readonly verdicts?: readonly MergerScript[];
  readonly consultFails?: Readonly<Record<string, string>>;
  /** Supply the repository when a script has to reach it — a Merger merging by hand. */
  readonly repo?: TempRepo;
}

async function drive(t: TestContext, options: DriveOptions = {}): Promise<DrivenRun> {
  const printed = captureNarration(t);
  const repo = options.repo ?? tempRepo(t);
  const snapshot = specSnapshot({ number: 418 }, [...(options.issues ?? INDEPENDENT)]);
  const order = runOrder(snapshot);
  assert.ok(order.ok);

  const calls: BodyCall[] = [];
  const { core, dispatches, consultations } = waveCore(repo, snapshot, order.items, {
    scripts: options.scripts,
    maxParallel: options.maxParallel ?? 3,
    itemTimeoutMinutes: options.itemTimeoutMinutes,
    openAtSettle: options.openAtSettle,
    revalidations: options.revalidations,
    plans: options.plans,
    verdicts: options.verdicts,
    consultFails: options.consultFails,
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
    consultations,
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

describe("the Planner, as the driver uses it", () => {
  it("is asked once per multi-item level and not at all at a one-item one", async (t) => {
    // 419 and 421 are one level and 420 is a level of its own behind 419 — so
    // wave one is a plan worth asking for and wave two is not, because a
    // zero-item plan being invalid makes that item the only valid plan.
    const run = await drive(t, { issues: CHAINED, maxParallel: 3 });

    assert.deepEqual(
      run.consultations.filter((consult) => consult.agentId === "planner").length,
      1,
    );
  });

  it("is handed the ready level and MAX_PARALLEL, and no dependency edge", async (t) => {
    const run = await drive(t, { issues: CHAINED, maxParallel: 3 });
    const plan = run.consultations.find((consult) => consult.agentId === "planner");

    assert.ok(plan);
    assert.equal(plan.promptFile, "plan-prompt.md");
    assert.equal(plan.promptArgs["MAX_PARALLEL"], "3");
    assert.deepEqual(JSON.parse(plan.promptArgs["READY"] ?? "[]"), [
      { number: 419, title: "Issue 419", body: "" },
      { number: 421, title: "Issue 421", body: "" },
    ]);
    // A level splitter has the edges already applied; one that could see them
    // would start second-guessing an order the runner already settled.
    assert.doesNotMatch(plan.promptArgs["READY"] ?? "", /block|depends/i);
  });

  it("runs the wave it chose, and offers what it deferred to the next one", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      plans: [() => ({ wave: [419], deferrals: [{ number: 420, reason: "both rewrite runner.mts" }] })],
    });

    // Deferring is not dropping: everything left out is offered again, so all
    // four still run and the merge order is still run order.
    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(420), mergeOf(421), mergeOf(422)]);
    assert.ok(
      run.printed.some((line) => line.includes("the Planner chose #419")),
      run.printed.join("\n"),
    );
  });

  it("falls back to the computed wave on a plan it cannot use, with no retry and no abort", async (t) => {
    const rejected: readonly PlannerScript[] = [
      () => ({ wave: [999], deferrals: [] }),
      () => ({ wave: [], deferrals: [] }),
    ];
    // Five independent items, so wave two is a level worth planning too.
    const run = await drive(t, {
      issues: [...INDEPENDENT, { number: 423 }],
      maxParallel: 3,
      plans: rejected,
    });

    // Wave one's plan names work that is not ready and wave two's is empty;
    // both run the computed wave anyway, and the run finishes.
    assert.deepEqual(run.merges, [
      mergeOf(419),
      mergeOf(420),
      mergeOf(421),
      mergeOf(422),
      mergeOf(423),
    ]);
    assert.doesNotMatch(run.report, /aborted/);
    assert.equal(run.exitCode, undefined);
    // Exactly one consult per wave. A semantic retry would show up here as two,
    // and it is kept impossible by the schema not knowing the ready set.
    assert.equal(run.consultations.filter((consult) => consult.agentId === "planner").length, 2);
  });

  it("says out loud that it fell back, which is the only way that failure is visible", async (t) => {
    // The Planner's failure mode was designed to be invisible: a silent
    // fallback, a prompt that never mentions it, and seven outcomes that are all
    // per-item. Without this line every wave could quietly become the computed
    // wave and the ledger would look perfect.
    const run = await drive(t, {
      maxParallel: 3,
      plans: [() => ({ wave: [419, 420, 421, 422], deferrals: [] })],
    });

    const line = run.printed.find((printed) => printed.includes("the plan was rejected"));
    assert.ok(line, run.printed.join("\n"));
    assert.match(line, /wave 1/);
    assert.match(line, /at most 3/);
    assert.match(line, /#419, #420, #421/);
  });

  it("falls back the same way when the Planner never answers at all", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      consultFails: { planner: "the provider hung up" },
    });

    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(420), mergeOf(421), mergeOf(422)]);
    assert.ok(
      run.printed.some((line) => line.includes("the Planner did not answer")),
      run.printed.join("\n"),
    );
    assert.equal(run.exitCode, undefined);
  });

  it("refuses a plan whose shape is wrong before it ever reaches the runner", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      plans: [() => ({ wave: ["419"], deferrals: [] })],
    });

    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(420), mergeOf(421), mergeOf(422)]);
    assert.ok(
      run.printed.some((line) => line.includes("the Planner did not answer")),
      run.printed.join("\n"),
    );
  });
});

describe("what a driver may write into a prompt", () => {
  it("writes only names the runner reserved, so a body can never collide with one", async (t) => {
    const contest: ItemScript = ({ item, commit }) =>
      commit(CONTESTED_FILE, `rewritten by #${item.number}`);
    // A run that reaches both agents: a multi-item level plans, and a wave with
    // a conflict in it dispatches the Merger.
    const run = await drive(t, { maxParallel: 3, scripts: { 419: contest, 420: contest } });

    assert.ok(run.consultations.length > 1);
    for (const consult of run.consultations) {
      for (const name of Object.keys(consult.promptArgs)) {
        assert.ok(RESERVED_PROMPT_ARGS.includes(name), `${consult.agentId} wrote ${name}`);
      }
    }
  });
});

describe("the Merger, as the driver uses it", () => {
  it("is dispatched once per settled wave and skipped when one branch merged alone", async (t) => {
    const run = await drive(t, { maxParallel: 3 });
    const merges = run.consultations.filter((consult) => consult.agentId === "merger");

    // Wave one merged three branches, which nothing has ever built together.
    // Wave two merged one, and its tree is identical to a tree that item's own
    // implement→review loop already gated.
    assert.equal(merges.length, 1);
    assert.equal(merges[0]?.promptFile, "merge-prompt.md");
  });

  it("is handed the base it started from, what merged and what conflicted", async (t) => {
    const contest: ItemScript = ({ item, commit }) =>
      commit(CONTESTED_FILE, `rewritten by #${item.number}`);
    const run = await drive(t, { maxParallel: 3, scripts: { 419: contest, 420: contest } });

    const wave = JSON.parse(
      run.consultations.find((consult) => consult.agentId === "merger")?.promptArgs["WAVE"] ?? "null",
    );
    assert.equal(wave.branch, WORKSPACE_BRANCH);
    assert.deepEqual(
      wave.merged.map((item: { number: number }) => item.number),
      [419, 421],
    );
    assert.deepEqual(wave.unmerged, [
      { number: 420, branch: branchOf(420), paths: [CONTESTED_FILE] },
    ]);
    // The precondition the prompt states: each failed merge is already rewound,
    // so the tree the Merger stands on holds exactly the merged items.
    assert.ok(wave.merged.every((item: { commit: string }) => item.commit.length > 0));
  });

  it("records what git says it merged, not what its verdict claimed", async (t) => {
    const repo = tempRepo(t);
    const contest: ItemScript = ({ item, commit }) =>
      commit(CONTESTED_FILE, `rewritten by #${item.number}`);

    const run = await drive(t, {
      repo,
      maxParallel: 3,
      scripts: { 419: contest, 420: contest },
      verdicts: [
        (wave) => {
          // What a Merger does to a rewound branch: finish the merge by hand.
          for (const item of wave.unmerged) {
            repo.git(["merge", "--no-ff", "--no-edit", "-X", "ours", item.branch]);
          }
          return { verified: true, unresolved: [], notes: "reconciled #420 by hand" };
        },
      ],
    });

    // #420's branch conflicted, and after the Merger it is on the workspace
    // branch — so it merged, and the run says so.
    assert.match(run.report, /completed {2}4/);
    assert.doesNotMatch(run.report, /conflict rewound/);
    assert.equal(run.repo.branchExists(branchOf(420)), false);
  });

  it("carries on when a conflict is what it could not resolve", async (t) => {
    const contest: ItemScript = ({ item, commit }) =>
      commit(CONTESTED_FILE, `rewritten by #${item.number}`);

    const run = await drive(t, {
      issues: CHAINED,
      maxParallel: 3,
      scripts: { 419: contest, 421: contest },
      verdicts: [() => ({ verified: false, unresolved: [421], notes: "genuinely contradictory" })],
    });

    // A conflict belongs to exactly one branch: #421 is the cost, #419 merged,
    // and #420 — which is blocked by #419 — still runs.
    assert.doesNotMatch(run.report, /aborted/);
    assert.equal(run.exitCode, undefined);
    assert.deepEqual(run.merges, [mergeOf(419), mergeOf(420)]);
    assert.match(run.report, /#421 conflict rewound/);
  });

  it("aborts when a tree that merged cleanly does not hold together", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      verdicts: [() => ({ verified: false, unresolved: [], notes: "#419 renamed what #420 calls" })],
    });

    // A broken tree belongs to no branch — every item merged and every item's
    // own loop passed — so there is nobody to leave out and nothing to rewind.
    assert.match(run.report, /aborted/);
    assert.match(run.report, /#419 renamed what #420 calls/);
    assert.equal(run.exitCode, 1);
    // Nothing is ever auto-cleaned on an abort, however cleanly it merged.
    assert.ok(run.repo.branchExists(branchOf(419)));
    assert.ok(worktreeExists(run.repo.root, branchOf(419)));
    assert.equal(
      run.calls.some((call) => call.item?.number === 422),
      false,
    );
  });

  it("aborts when the Merger never answers, rather than building on an unverified tree", async (t) => {
    const run = await drive(t, {
      maxParallel: 3,
      consultFails: { merger: "the provider hung up" },
    });

    // Unlike a rejected plan there is no safe fallback: wave two would be cut
    // from a tree nothing ever verified, and every later item inherits that.
    assert.match(run.report, /never verified/);
    assert.equal(run.exitCode, 1);
  });
});

describe("what a wave-parallel run reports", () => {
  it("counts a clean sweep against the frozen selection", async (t) => {
    const run = await drive(t, { maxParallel: 3 });

    assert.match(run.report, /Run summary — SPEC #418, 4 of 4 eligible/);
    assert.match(run.report, /completed {2}4/);
  });
});
