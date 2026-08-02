// What a wave-parallel run looks like in one terminal.
//
// **Append-only, never a repainting dashboard.** Three reasons, all found rather
// than preferred. The run is AFK, so what the maintainer needs on return is a
// scrollback they can read top to bottom rather than a block showing only *now*.
// A dashboard cannot own the cursor it needs: `printFileDisplayStartup` writes
// two unsuppressable `console.log` lines per dispatch straight into the middle of
// any pinned block. And it degrades to nothing when piped, which is the obvious
// thing to do with an unattended run.
//
// **Concurrency forces log-to-file mode, and that is what makes any of this
// possible.** Sandcastle 0.12.0's `LoggingOption` has two variants, not three,
// and `stdout` resolves to a Clack UI — spinners and `taskLog`, i.e. cursor
// control — so three concurrent dispatches would fight over one cursor. The
// `file` variant is the only permitted shape, and `onAgentStreamEvent` exists
// only on it: the one live per-agent signal available, in exactly the mode
// concurrency forces.
//
// Three properties this module exists to hold:
//
//   **One `itemLine` serves the live view and the end-of-run report.** A line the
//   maintainer learned to read at 02:00 reads the same in the morning, and
//   nothing is report-only. The two renderings differ in their *chrome* — a live
//   line carries the run clock and the progress fraction — and never in what they
//   say about the item.
//
//   **The denominator does not move.** Progress is `n/10 settled` against the
//   frozen selection. Membership is frozen and truncation is a prefix, so a
//   transitive skip *settles* an item rather than shrinking the total: the
//   fraction only ever grows, which is the property that makes it readable at a
//   glance.
//
//   **Liveness is a sparse metronome plus a silence alarm.** The body dispatches
//   twice, so a healthy item is silent for ten to fifteen minutes and a hang is
//   indistinguishable from work. A ten-minute metronome proves the *driver* has a
//   pulse; a warning after five minutes without a stream event, and a matching
//   line when it resumes, proves the *agents* do. About fourteen lines across an
//   84-minute run. Rejected: a two-minute per-item metronome (~120 heartbeat
//   lines against ~50 real ones buries the record it lives in) and the alarm
//   alone (a healthy run then goes silent for fifteen minutes at a stretch, so
//   frozen and working look identical). The alarm flags a wedged item **thirty
//   minutes before its timeout does**.
//
// Everything here is pure but `console.log`-free: `liveness().tick()` returns the
// lines it would print rather than printing them, so the heartbeat is asserted
// without a clock and the driver owns every write to stdout.

import { styleText } from "node:util";
import { outcomeLabel, type ItemOutcome } from "./outcomes.mts";

type Colour = Parameters<typeof styleText>[0];

/**
 * The seven, and there is no eighth.
 *
 * Two phases, flattened for display only: `approved` / `crashed` / `timed out` /
 * `no commits` settle the loop, `merged` / `conflict rewound` settle the fan-in,
 * and an item that was never dispatched is `skipped`. A bounce and a reopen are
 * **annotations**, not members — listing either here would imply a structural
 * consequence neither has.
 */
export type LedgerOutcome =
  | "approved"
  | "crashed"
  | "timed out"
  | "no commits"
  | "merged"
  | "conflict rewound"
  | "skipped";

interface Mark {
  readonly glyph: string;
  readonly colour: Colour;
  readonly word: string;
}

/**
 * The glyph carries the two-phase split — a hollow mark settled the loop, a
 * solid one settled the merge.
 *
 * **`timed out` shares neither its glyph nor its colour with `crashed`.** They
 * mean opposite things about the item: a crash is evidence the work is wrong, and
 * a hang is evidence of nothing at all except that nobody was watching.
 */
export const MARKS: Readonly<Record<LedgerOutcome, Mark>> = {
  approved: { glyph: "○", colour: "green", word: "approved" },
  crashed: { glyph: "×", colour: "red", word: "crashed" },
  "timed out": { glyph: "⧗", colour: "yellow", word: "timed out" },
  "no commits": { glyph: "∅", colour: "yellow", word: "no commits" },
  merged: { glyph: "●", colour: "green", word: "merged" },
  "conflict rewound": { glyph: "◐", colour: "yellow", word: "conflict" },
  skipped: { glyph: "–", colour: "gray", word: "skipped" },
};

/** Outcomes worth opening a log for. An approved item never gets one. */
export function wantsLog(outcome: LedgerOutcome): boolean {
  return (
    outcome === "crashed" ||
    outcome === "timed out" ||
    outcome === "no commits" ||
    outcome === "conflict rewound"
  );
}

/**
 * How the driver's own record of an item becomes a ledger outcome and its
 * detail.
 *
 * One place rather than a `switch` at each print site: the live line and the
 * end-of-run block are the same function called twice, and they can only stay
 * that way if what an outcome *is* is decided once.
 *
 * `outcomeLabel` still owns the words the tracker comment uses — a display glyph
 * has no business in a GitHub comment — so this reads it rather than restating
 * it wherever the two agree.
 */
export function ledgerOutcome(outcome: ItemOutcome): {
  readonly outcome: LedgerOutcome;
  readonly detail: string;
} {
  if (outcome.kind === "skipped") return { outcome: "skipped", detail: outcome.reason };
  // Drift is a skip whose cause is the tracker rather than a sibling: the item
  // was never dispatched, which is the whole of what the glyph claims.
  if (outcome.kind === "drift") return { outcome: "skipped", detail: outcome.detail };

  const commits = `${outcome.commits} commit${outcome.commits === 1 ? "" : "s"}`;
  switch (outcome.loop) {
    case "crashed":
      return { outcome: "crashed", detail: `the loop threw after ${commits}` };
    case "timed-out":
      return { outcome: "timed out", detail: `no answer before the item timeout, ${commits}` };
    case "no-commits":
      return { outcome: "no commits", detail: "the implementer left the tree as it found it" };
    case "committed":
      break;
  }
  switch (outcome.merge) {
    case "merged":
      return { outcome: "merged", detail: commits };
    case "conflict-rewound":
      return { outcome: "conflict rewound", detail: `${commits}, kept on its own branch` };
    case "skipped-upstream":
      return { outcome: "skipped", detail: outcomeLabel(outcome) };
    default:
      // No fan-in phase at all — the sequential driver commits in place, so the
      // loop settling is the whole answer.
      return { outcome: "approved", detail: commits };
  }
}

// ---------------------------------------------------------------------------
// The one per-item line
// ---------------------------------------------------------------------------

/** How wide `#12345` plus a glyph sits before the title starts. */
const HEAD_WIDTH = 9;
const TITLE_WIDTH = 34;
/** Wide enough for `no commits`, the longest word a mark carries. */
const WORD_WIDTH = 10;
/** Wide enough for both annotations at once — they compose rather than replace. */
const ANNOTATION_WIDTH = 21;

export interface LedgerItem {
  readonly number: number;
  readonly title: string;
  readonly outcome: LedgerOutcome;
  readonly detail: string;
  /** The issue was still open when the item settled: the reviewer sent it back. */
  readonly bounced?: boolean;
  /** The run reopened it: closed, yet nothing of it reached the workspace branch. */
  readonly reopened?: boolean;
}

/**
 * The live rendering's extra chrome, and the only thing that differs between the
 * two renderings.
 */
export interface LiveContext {
  /** Milliseconds since the run started, which is the only clock the ledger shows. */
  readonly elapsedMs: number;
  readonly settled: number;
  /** The frozen selection. Never recomputed, which is what makes the fraction grow. */
  readonly total: number;
}

/** Elapsed inside the run, as `MM:SS`. */
export function clock(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const minutes = String(Math.floor(total / 60)).padStart(2, "0");
  return `${minutes}:${String(total % 60).padStart(2, "0")}`;
}

export function duration(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(total / 60)}m${String(total % 60).padStart(2, "0")}s`;
}

/** `n/10 settled`, against a denominator nothing may move. */
export function progress(settled: number, total: number): string {
  return `${settled}/${total} settled`;
}

/**
 * One item, rendered the same way live and in the end-of-run block.
 *
 * `↩ bounced` and `↻ reopened` **compose** on one line rather than being one
 * optional suffix: they are independent facts about different things — the
 * reviewer's ruling and where the code ended up — and a bounced-and-rewound item
 * is genuinely both.
 */
export function itemLine(item: LedgerItem, live?: LiveContext): string {
  const mark = MARKS[item.outcome];
  const head = styleText(mark.colour, `${mark.glyph} #${item.number}`.padEnd(HEAD_WIDTH));
  const title = styleText("dim", item.title.padEnd(TITLE_WIDTH).slice(0, TITLE_WIDTH));
  const word = styleText(mark.colour, mark.word.padEnd(WORD_WIDTH));

  const notes = [
    ...(item.bounced ? ["↩ bounced"] : []),
    ...(item.reopened ? ["↻ reopened"] : []),
  ].join(" ");
  // Measured and padded before it is styled: an escape sequence has a length and
  // no width, so padding the styled string would misalign every coloured line by
  // exactly the size of its escapes.
  const pad = " ".repeat(Math.max(0, ANNOTATION_WIDTH - notes.length));
  const annotations = notes === "" ? " ".repeat(ANNOTATION_WIDTH) : styleText("magenta", notes) + pad;

  const body = `${head} ${title} ${word} ${annotations} ${styleText("dim", item.detail)}`.trimEnd();
  if (!live) return `  ${body}`;
  return `${styleText("dim", clock(live.elapsedMs))}  ${body}  ${styleText("dim", progress(live.settled, live.total))}`;
}

/**
 * Where to look next, on the one line that follows a failure or an alarm.
 *
 * Sandcastle prints this path once, at dispatch — an hour before the moment
 * anyone wants it — so the driver repeats it exactly where it becomes useful and
 * nowhere else.
 */
export function logHint(logPath: string): string {
  return styleText("dim", `              tail -f ${logPath}`);
}

// ---------------------------------------------------------------------------
// Liveness
// ---------------------------------------------------------------------------

/** How often the metronome speaks. Sparse, because the alarm carries the detail. */
export const METRONOME_MS = 10 * 60_000;
/** How long an item may produce no stream event before it is flagged. */
export const SILENCE_MS = 5 * 60_000;

interface Running {
  readonly number: number;
  readonly logPath: string;
  readonly startedAt: number;
  spokeAt: number;
  tool: string;
  flagged: boolean;
}

/**
 * The heartbeat, as a value that answers rather than prints.
 *
 * `tick` returns the lines it *would* write, so the cadence, the alarm and the
 * resume are asserted against a hand-wound clock instead of against a timer —
 * and the driver keeps sole ownership of stdout.
 */
export interface Liveness {
  /** An item entered the wave. */
  readonly enter: (item: { number: number; logPath: string }, at: number) => void;
  /** That item's agent produced a stream event. */
  readonly spoke: (number: number, tool: string, at: number) => void;
  /** It settled, one way or another. */
  readonly leave: (number: number) => void;
  readonly tick: (now: number) => readonly string[];
}

export function liveness(timeoutMs: number): Liveness {
  const running = new Map<number, Running>();
  let nextBeat = METRONOME_MS;

  const metronome = (now: number): readonly string[] => {
    if (now < nextBeat) return [];
    // Snapped to the cadence rather than advanced from `now`, so a slow tick
    // never drifts the whole run's heartbeat off the ten-minute grid.
    nextBeat = Math.ceil((now + 1) / METRONOME_MS) * METRONOME_MS;
    if (running.size === 0) return [];
    // Elapsed against the item timeout, because the timeout is the only thing
    // that will end a hang — so how far off it is is the one number worth
    // showing beside an item that has said nothing for ten minutes.
    const summary = [...running.values()]
      .map((item) => `#${item.number} ${duration(now - item.startedAt)} / ${duration(timeoutMs)}`)
      .join(" · ");
    return [
      `${styleText("dim", clock(now))}  ${styleText("dim", `─ ${running.size} running · ${summary}`)}`,
    ];
  };

  const alarm = (now: number): readonly string[] => {
    const lines: string[] = [];
    for (const item of running.values()) {
      const silent = now - item.spokeAt;
      if (silent >= SILENCE_MS && !item.flagged) {
        item.flagged = true;
        lines.push(
          `${styleText("dim", clock(now))}  ${styleText("yellow", "⚠")} #${item.number} silent for ${duration(silent)} · ${duration(now - item.startedAt)} / ${duration(timeoutMs)} · last ${styleText("dim", item.tool)}`,
          logHint(item.logPath),
        );
      }
      if (silent < SILENCE_MS && item.flagged) {
        item.flagged = false;
        lines.push(
          `${styleText("dim", clock(now))}  ${styleText("green", "✓")} #${item.number} speaking again · ${styleText("dim", item.tool)}`,
        );
      }
    }
    return lines;
  };

  return {
    enter: (item, at) =>
      void running.set(item.number, {
        number: item.number,
        logPath: item.logPath,
        startedAt: at,
        spokeAt: at,
        tool: "starting",
        flagged: false,
      }),
    spoke: (number, tool, at) => {
      const item = running.get(number);
      if (!item) return;
      item.spokeAt = at;
      item.tool = tool;
    },
    leave: (number) => void running.delete(number),
    // The alarm first: a wedged item is the thing worth reading, and burying it
    // under the metronome's summary of the same wave reads as noise.
    tick: (now) => [...alarm(now), ...metronome(now)],
  };
}
