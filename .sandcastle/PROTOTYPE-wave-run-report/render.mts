// Two rival renderings of the same run, plus the one piece they share.
//
// `ledger` is append-only: every line is written once and never rewritten, so
// Sandcastle's own `console.log` output lands between our lines instead of on
// top of them, and the scrollback *is* the record.
//
// `dashboard` pins one line per in-flight item to the bottom of the terminal
// and repaints it. It is here to be compared against, not to be adopted
// blind — it owns the cursor, and it shares that cursor with a library that
// prints two lines per dispatch without asking.

import { styleText } from "node:util";
import { ITEM_TIMEOUT_MS, type Outcome, titleOf } from "./script.mts";

export interface Inflight {
  readonly number: number;
  readonly phase: "implement" | "review";
  readonly startedAt: number;
  readonly tool: string;
  /** When this item last produced an `onAgentStreamEvent`. */
  readonly spokeAt: number;
}

export interface Renderer {
  /** A line that belongs in the permanent record. */
  event(line: string): void;
  /** Called on every replay tick with the current in-flight set. */
  tick(now: number, inflight: readonly Inflight[]): void;
  /** A line Sandcastle wrote to stdout that we do not control. */
  foreign(line: string): void;
  close(): void;
}

// ── shared vocabulary ───────────────────────────────────────────────────────

/** Elapsed inside the run, the only clock either renderer shows. */
export const clock = (ms: number): string => {
  const total = Math.floor(ms / 1000);
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
};

const duration = (ms: number): string => {
  const total = Math.floor(ms / 1000);
  return `${Math.floor(total / 60)}m${String(total % 60).padStart(2, "0")}s`;
};

/**
 * One outcome, rendered identically live and in the end-of-run report. The
 * glyph carries the two-phase split — a hollow mark settled the loop, a solid
 * one settled the merge — and "timed out" never shares a glyph or a colour
 * with a failure the tests produced.
 */
export const OUTCOME: Record<Outcome, { glyph: string; colour: Parameters<typeof styleText>[0]; word: string }> = {
  approved: { glyph: "○", colour: "green", word: "approved" },
  crashed: { glyph: "×", colour: "red", word: "crashed" },
  "timed out": { glyph: "⧗", colour: "yellow", word: "timed out" },
  "no commits": { glyph: "∅", colour: "yellow", word: "no commits" },
  merged: { glyph: "●", colour: "green", word: "merged" },
  "conflict rewound": { glyph: "◐", colour: "yellow", word: "conflict" },
  skipped: { glyph: "–", colour: "gray", word: "skipped" },
};

/**
 * The per-item line. One function, called live when an item settles and again
 * when the report is written — so the two can never drift, and a line the
 * maintainer learned to read at 02:00 reads the same in the morning.
 */
export const itemLine = (
  number: number,
  outcome: Outcome,
  detail: string,
  options: { bounced?: boolean; width?: number } = {},
): string => {
  const mark = OUTCOME[outcome];
  const head = styleText(mark.colour, `${mark.glyph} #${number}`.padEnd(options.width ?? 7));
  const title = titleOf(number).padEnd(34).slice(0, 34);
  const word = styleText(mark.colour, mark.word.padEnd(10));
  const bounce = options.bounced ? styleText("magenta", "↩ bounced ") : "          ";
  return `${head} ${styleText("dim", title)} ${word} ${bounce} ${styleText("dim", detail)}`;
};

/** The in-flight line: elapsed against the timeout that will end it. */
const inflightLine = (now: number, item: Inflight): string => {
  const elapsed = now - item.startedAt;
  const share = elapsed / ITEM_TIMEOUT_MS;
  const colour = share > 0.85 ? "red" : share > 0.6 ? "yellow" : "cyan";
  return [
    `  #${item.number}`.padEnd(8),
    item.phase.padEnd(10),
    styleText(colour, `${duration(elapsed)} / ${duration(ITEM_TIMEOUT_MS)}`.padEnd(16)),
    styleText("dim", item.tool),
  ].join("");
};

// ── ledger ──────────────────────────────────────────────────────────────────

const HEARTBEAT_MS = 2 * 60_000;
const STALE_MS = 5 * 60_000;

/**
 * The three rival heartbeats, all append-only.
 *
 * `metronome` and `plain` are metronomes — a fixed cadence that proves the
 * *driver* is alive. `plain` says nothing about the agents, so it needs no
 * `onAgentStreamEvent` at all; `metronome` adds the last tool call, which is
 * the only per-agent signal available in log-to-file mode.
 *
 * `alarm` inverts it: no cadence, and a line only when an item has produced no
 * stream event for five minutes. It proves the *agents* are alive, at the cost
 * of a fully silent healthy run.
 */
export type Heartbeat = "metronome" | "plain" | "alarm" | "both";

export const ledger = (heartbeat: Heartbeat = "metronome", heartbeatMs = HEARTBEAT_MS): Renderer => {
  // A sparse cadence when the alarm carries the agent-level signal: the
  // metronome is then only proving the driver still has a pulse.
  const cadence = heartbeat === "both" ? 10 * 60_000 : heartbeatMs;
  let nextBeat = cadence;
  const flagged = new Set<number>();

  const metronome = (now: number, inflight: readonly Inflight[]) => {
    if (now < nextBeat) return;
    nextBeat = Math.ceil((now + 1) / cadence) * cadence;
    if (inflight.length === 0) return;
    if (heartbeat === "plain" || heartbeat === "both") {
      const summary = inflight
        .map((item) => `#${item.number} ${item.phase} ${duration(now - item.startedAt)}`)
        .join(" · ");
      console.log(`${styleText("dim", clock(now))}  ${styleText("dim", `─ ${inflight.length} running · ${summary}`)}`);
      return;
    }
    console.log(`${styleText("dim", clock(now))}  ${styleText("dim", `─ ${inflight.length} running`)}`);
    for (const item of inflight) console.log(`       ${inflightLine(now, item)}`);
  };

  const alarm = (now: number, inflight: readonly Inflight[]) => {
    const live = new Set(inflight.map((item) => item.number));
    for (const number of [...flagged]) if (!live.has(number)) flagged.delete(number);
    for (const item of inflight) {
      const silent = now - item.spokeAt;
      if (silent >= STALE_MS && !flagged.has(item.number)) {
        flagged.add(item.number);
        console.log(
          `${styleText("dim", clock(now))}  ${styleText("yellow", "⚠")} #${item.number} silent for ${duration(silent)} · ${item.phase} ${duration(now - item.startedAt)} / ${duration(ITEM_TIMEOUT_MS)} · last ${styleText("dim", item.tool)}`,
        );
      }
      if (silent < STALE_MS && flagged.has(item.number)) {
        flagged.delete(item.number);
        console.log(`${styleText("dim", clock(now))}  ${styleText("green", "✓")} #${item.number} speaking again · ${styleText("dim", item.tool)}`);
      }
    }
  };

  return {
    event: (line) => console.log(line),
    foreign: (line) => console.log(styleText("dim", line)),
    tick: (now, inflight) => {
      if (heartbeat !== "metronome" && heartbeat !== "plain") alarm(now, inflight);
      if (heartbeat !== "alarm") metronome(now, inflight);
    },
    close: () => {},
  };
};

// ── dashboard ───────────────────────────────────────────────────────────────

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

/**
 * A pinned, repainting block. Degrades to the ledger when stdout is not a TTY,
 * because cursor escapes in a piped log are worse than no live view at all.
 */
export const dashboard = (): Renderer => {
  if (!process.stdout.isTTY) return ledger();

  let painted = 0;
  let frame = 0;

  const erase = () => {
    if (painted === 0) return;
    process.stdout.write(`\u001b[${painted}A\u001b[0J`);
    painted = 0;
  };

  const paint = (now: number, inflight: readonly Inflight[]) => {
    if (inflight.length === 0) return;
    const spin = SPINNER[frame++ % SPINNER.length];
    const lines = [
      `${styleText("dim", clock(now))}  ${spin} ${inflight.length} running`,
      ...inflight.map((item) => inflightLine(now, item)),
    ];
    process.stdout.write(`${lines.join("\n")}\n`);
    painted = lines.length;
  };

  let last: readonly Inflight[] = [];
  let lastNow = 0;

  return {
    event: (line) => {
      erase();
      console.log(line);
      paint(lastNow, last);
    },
    // Sandcastle does not erase our block before writing, so this is what the
    // real terminal sees: its two lines land *inside* the pinned block.
    foreign: (line) => console.log(styleText("dim", line)),
    tick: (now, inflight) => {
      lastNow = now;
      last = inflight;
      erase();
      paint(now, inflight);
    },
    close: () => erase(),
  };
};
