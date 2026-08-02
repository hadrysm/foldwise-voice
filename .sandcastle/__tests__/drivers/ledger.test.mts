// The run display, asserted without a run.
//
// Everything in `drivers/ledger.mts` either returns a string or returns the
// lines it would have printed, which is what makes this file possible: the
// heartbeat is wound by hand rather than by a clock, and the two renderings are
// compared to each other rather than eyeballed in a terminal.
//
// Colour is stripped before every assertion. `styleText` decides on the stream
// it is writing to, so a suite that asserted the styled string would pass under
// `node --test` and say nothing at all about what a maintainer sees in a real
// terminal — the alignment is the part worth pinning, and escapes have length
// without width.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  clock,
  itemLine,
  ledgerOutcome,
  liveness,
  logHint,
  MARKS,
  METRONOME_MS,
  progress,
  SILENCE_MS,
  wantsLog,
  type LedgerItem,
  type LedgerOutcome,
} from "../../drivers/ledger.mts";
import type { ItemOutcome } from "../../drivers/outcomes.mts";

const plain = (line: string): string => line.replace(/\u001b\[[0-9;]*m/g, "");

const OUTCOMES: readonly LedgerOutcome[] = [
  "approved",
  "crashed",
  "timed out",
  "no commits",
  "merged",
  "conflict rewound",
  "skipped",
];

function item(overrides: Partial<LedgerItem> = {}): LedgerItem {
  return {
    number: 427,
    title: "Register the wave-parallel workflow",
    outcome: "merged",
    detail: "3 commits",
    ...overrides,
  };
}

const LIVE = { elapsedMs: 4 * 60_000 + 5_000, settled: 3, total: 10 };

describe("the seven outcomes", () => {
  it("gives each one a mark, and no two of them share a glyph", () => {
    const glyphs = OUTCOMES.map((outcome) => MARKS[outcome].glyph);
    assert.equal(new Set(glyphs).size, OUTCOMES.length);
    assert.equal(Object.keys(MARKS).length, OUTCOMES.length);
  });

  it("never lets a timeout wear a crash's glyph or its colour", () => {
    // They mean opposite things about the item: a crash is evidence the work is
    // wrong, and a hang is evidence of nothing except that nobody was watching.
    assert.notEqual(MARKS["timed out"].glyph, MARKS.crashed.glyph);
    assert.notEqual(MARKS["timed out"].colour, MARKS.crashed.colour);
  });

  it("asks for a log only where there is something to read", () => {
    assert.deepEqual(OUTCOMES.filter(wantsLog), [
      "crashed",
      "timed out",
      "no commits",
      "conflict rewound",
    ]);
  });
});

describe("itemLine, in both renderings", () => {
  for (const outcome of OUTCOMES) {
    it(`names ${outcome} the same way live and in the report`, () => {
      const subject = item({ outcome });
      const live = plain(itemLine(subject, LIVE));
      const report = plain(itemLine(subject));

      for (const rendering of [live, report]) {
        assert.ok(rendering.includes(MARKS[outcome].glyph), rendering);
        assert.ok(rendering.includes(MARKS[outcome].word), rendering);
        assert.ok(rendering.includes("#427"), rendering);
        assert.ok(rendering.includes("3 commits"), rendering);
      }

      // The whole claim behind one `itemLine`: what the two renderings say about
      // the item is one string, and the chrome is the only difference.
      assert.ok(
        live.includes(report.trim()),
        `the live line dropped something the report keeps:\n${live}\n${report}`,
      );
    });
  }

  it("carries the clock and the progress fraction only while the run is moving", () => {
    const live = plain(itemLine(item(), LIVE));
    assert.ok(live.startsWith("04:05"), live);
    assert.ok(live.endsWith("3/10 settled"), live);

    const report = plain(itemLine(item()));
    assert.doesNotMatch(report, /settled/);
    assert.doesNotMatch(report, /\d\d:\d\d/);
  });

  it("aligns every outcome's detail on the same column, in both renderings", () => {
    // The failure this catches is silent and only visible in a terminal: a word
    // or an annotation that overruns its slot shifts the detail column for that
    // one line, and a ten-item report then reads as a ragged list.
    const columns = new Set(
      OUTCOMES.flatMap((outcome) => [
        plain(itemLine(item({ outcome }))).indexOf("3 commits"),
        plain(itemLine(item({ outcome }), LIVE)).indexOf("3 commits"),
      ]),
    );
    assert.equal(columns.size, 2, [...columns].join(", "));
  });
});

describe("the two annotations", () => {
  it("compose on one line rather than replacing each other", () => {
    const both = plain(itemLine(item({ bounced: true, reopened: true })));
    assert.ok(both.includes("↩ bounced"), both);
    assert.ok(both.includes("↻ reopened"), both);
  });

  it("each appears alone when only it is true", () => {
    const bounced = plain(itemLine(item({ bounced: true })));
    assert.ok(bounced.includes("↩ bounced"));
    assert.ok(!bounced.includes("↻ reopened"));

    const reopened = plain(itemLine(item({ reopened: true })));
    assert.ok(reopened.includes("↻ reopened"));
    assert.ok(!reopened.includes("↩ bounced"));
  });

  it("compose in the live rendering too, and shift nothing", () => {
    const live = plain(itemLine(item({ bounced: true, reopened: true }), LIVE));
    assert.ok(live.includes("↩ bounced ↻ reopened"), live);
    assert.equal(
      live.indexOf("3 commits"),
      plain(itemLine(item(), LIVE)).indexOf("3 commits"),
      "an annotated line moved the detail column",
    );
  });
});

describe("what an item's record becomes on the ledger", () => {
  const settled = (over: Partial<Extract<ItemOutcome, { kind: "settled" }>>): ItemOutcome => ({
    kind: "settled",
    loop: "committed",
    merge: "merged",
    commits: 2,
    bounced: false,
    ...over,
  });

  it("reads the loop phase before the merge phase", () => {
    assert.equal(ledgerOutcome(settled({ loop: "crashed", merge: null })).outcome, "crashed");
    assert.equal(ledgerOutcome(settled({ loop: "timed-out", merge: null })).outcome, "timed out");
    assert.equal(
      ledgerOutcome(settled({ loop: "no-commits", merge: null, commits: 0 })).outcome,
      "no commits",
    );
  });

  it("reads a merge phase that ran, and calls its absence approved", () => {
    assert.equal(ledgerOutcome(settled({ merge: "merged" })).outcome, "merged");
    assert.equal(
      ledgerOutcome(settled({ merge: "conflict-rewound" })).outcome,
      "conflict rewound",
    );
    // No fan-in at all is not the same as a merge that did not happen: the
    // sequential driver commits in place, so the loop settling is the answer.
    assert.equal(ledgerOutcome(settled({ merge: null })).outcome, "approved");
  });

  it("calls an item that was never dispatched skipped, whatever stopped it", () => {
    assert.deepEqual(ledgerOutcome({ kind: "skipped", reason: "depends on #421" }), {
      outcome: "skipped",
      detail: "depends on #421",
    });
    assert.equal(ledgerOutcome({ kind: "drift", detail: "#420 was closed" }).outcome, "skipped");
  });

  it("counts commits grammatically, because the line is read by a person", () => {
    assert.match(ledgerOutcome(settled({ commits: 1 })).detail, /\b1 commit\b/);
    assert.match(ledgerOutcome(settled({ commits: 2 })).detail, /\b2 commits\b/);
  });

  it("never leaves an outcome without a detail to explain it", () => {
    for (const outcome of [
      settled({ loop: "crashed", merge: null }),
      settled({ loop: "timed-out", merge: null }),
      settled({ loop: "no-commits", merge: null, commits: 0 }),
      settled({ merge: "merged" }),
      settled({ merge: "conflict-rewound" }),
      settled({ merge: "skipped-upstream" }),
      settled({ merge: null }),
    ] satisfies ItemOutcome[]) {
      assert.notEqual(ledgerOutcome(outcome).detail, "");
    }
  });
});

describe("progress against a frozen selection", () => {
  it("only ever grows, because the denominator cannot move", () => {
    // A transitive skip *settles* an item. Membership was frozen and truncation
    // is a prefix, so the fraction advances for a skipped item exactly as it
    // does for one that ran — which is what makes it readable at a glance.
    const fractions = [1, 2, 5, 6].map((settled) => progress(settled, 10));
    assert.deepEqual(fractions, [
      "1/10 settled",
      "2/10 settled",
      "5/10 settled",
      "6/10 settled",
    ]);
  });

  it("shows elapsed inside the run and nothing else", () => {
    assert.equal(clock(0), "00:00");
    assert.equal(clock(65_000), "01:05");
    assert.equal(clock(60 * 60_000), "60:00");
  });
});

describe("liveness", () => {
  const enter = (beat: ReturnType<typeof liveness>, number: number, at = 0): void =>
    beat.enter({ number, logPath: `.sandcastle/logs/sandcastle-${number}.log` }, at);

  it("says nothing at all while nothing is running", () => {
    const beat = liveness(45 * 60_000);
    assert.deepEqual(beat.tick(METRONOME_MS), []);
    assert.deepEqual(beat.tick(3 * METRONOME_MS), []);
  });

  it("proves the driver has a pulse on a sparse ten-minute grid", () => {
    const beat = liveness(45 * 60_000);
    enter(beat, 427);
    enter(beat, 428);
    // Two healthy agents: an alarm would drown the metronome out otherwise, and
    // the metronome is the half of the signal that has to survive a quiet run.
    const speaking = (at: number): void => {
      beat.spoke(427, "Bash", at);
      beat.spoke(428, "Read", at);
    };

    // A two-minute cadence was rejected: ~120 heartbeat lines against ~50 real
    // ones buries the record it lives in.
    speaking(9 * 60_000);
    assert.deepEqual(beat.tick(9 * 60_000), []);

    speaking(METRONOME_MS);
    const first = beat.tick(METRONOME_MS).map(plain);
    assert.equal(first.length, 1);
    // Elapsed against the item timeout, because that is the only thing that
    // will end a hang.
    assert.match(first[0] ?? "", /2 running · #427 10m00s \/ 45m00s · #428 10m00s \/ 45m00s/);

    speaking(METRONOME_MS + 60_000);
    assert.deepEqual(beat.tick(METRONOME_MS + 60_000), []);

    speaking(2 * METRONOME_MS);
    assert.equal(beat.tick(2 * METRONOME_MS).length, 1);
  });

  it("flags an item that has gone quiet, long before its timeout would", () => {
    const beat = liveness(45 * 60_000);
    enter(beat, 427);
    beat.spoke(427, "Bash", 60_000);

    assert.deepEqual(beat.tick(60_000 + SILENCE_MS - 1_000), []);
    const lines = beat.tick(60_000 + SILENCE_MS).map(plain);

    // The alarm and the one place its log path is worth repeating.
    assert.match(lines[0] ?? "", /⚠ #427 silent for 5m00s · 6m00s \/ 45m00s · last Bash/);
    assert.equal(lines[1], plain(logHint(".sandcastle/logs/sandcastle-427.log")));
  });

  it("flags a wedged item once, not on every tick", () => {
    const beat = liveness(45 * 60_000);
    enter(beat, 427);

    assert.equal(beat.tick(SILENCE_MS).length, 2);
    assert.deepEqual(beat.tick(SILENCE_MS + 30_000), []);
    assert.deepEqual(beat.tick(SILENCE_MS + 60_000), []);
  });

  it("says so when a flagged item starts speaking again", () => {
    // Without this a healthy run that paused once reads as permanently wedged.
    const beat = liveness(45 * 60_000);
    enter(beat, 427);
    assert.equal(beat.tick(SILENCE_MS).length, 2);

    beat.spoke(427, "Edit", SILENCE_MS + 30_000);
    const resumed = beat.tick(SILENCE_MS + 60_000).map(plain);
    assert.equal(resumed.length, 1);
    assert.match(resumed[0] ?? "", /✓ #427 speaking again · Edit/);
  });

  it("forgets an item the moment it settles", () => {
    const beat = liveness(45 * 60_000);
    enter(beat, 427);
    beat.leave(427);

    // A crashed item still in the heartbeat would be reported as silent for the
    // rest of the run.
    assert.deepEqual(beat.tick(SILENCE_MS), []);
    assert.deepEqual(beat.tick(METRONOME_MS), []);
  });

  it("ignores an item it was never told about", () => {
    const beat = liveness(45 * 60_000);
    beat.spoke(999, "Bash", 0);
    assert.deepEqual(beat.tick(METRONOME_MS), []);
  });
});
