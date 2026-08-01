// Replays the scripted run through one renderer at a chosen speed.
//
//   pnpm --dir .sandcastle prototype:wave-report -- --renderer=ledger
//   pnpm --dir .sandcastle prototype:wave-report -- --renderer=dashboard
//   pnpm --dir .sandcastle prototype:wave-report -- --renderer=report
//
// `report` skips the live view entirely and prints only what #394 fixed as the
// end-of-run artifact, so the two can be read side by side.

import { styleText } from "node:util";
import { type Heartbeat, type Inflight, type Renderer, clock, dashboard, itemLine, ledger, logHint, wantsLog } from "./render.mts";
import { type Event, type Outcome, ITEMS, SCRIPT, SKIPPED, branchOf, titleOf } from "./script.mts";

const arg = (name: string, fallback: string): string =>
  process.argv.find((value) => value.startsWith(`--${name}=`))?.split("=")[1] ?? fallback;

const SPEED = Number(arg("speed", "150"));
const MODE = arg("renderer", "ledger");
const HEARTBEAT = arg("heartbeat", "metronome") as Heartbeat;
const TICK_MS = 80;

const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms));

const stamp = (at: number) => styleText("dim", clock(at));

// ── run state the driver keeps anyway ───────────────────────────────────────

interface Settled {
  readonly number: number;
  readonly loop: Outcome;
  readonly loopDetail: string;
  readonly bounced: boolean;
  merge?: { outcome: Outcome; detail: string };
}

const inflight = new Map<number, Inflight>();
const settled: Settled[] = [];
let header = "";
let selected = 0;
let skippedCount = 0;

const settledCount = () => settled.length + skippedCount;

/**
 * The mid-run equivalent of the confirmation screen's `up to 10 of 30
 * eligible`. The denominator is the frozen selection, which cannot move; a
 * transitive skip increments a counter instead of shrinking the total, so the
 * fraction only ever grows.
 */
const progress = () => styleText("dim", `${settledCount()}/${selected} settled`);

// ── the live view ───────────────────────────────────────────────────────────

const emit = (render: Renderer, event: Event): void => {
  switch (event.kind) {
    case "run start": {
      selected = event.selected;
      const rule = "─".repeat(78);
      header = [
        styleText("dim", rule),
        ` ${styleText("bold", event.workflow)}`,
        ` ${event.scope}`,
        ` ${styleText("bold", String(event.selected))} of ${event.eligible} eligible · MAX_PARALLEL ${event.maxParallel} · logs ${styleText("dim", event.logDir)}`,
        styleText("dim", rule),
      ].join("\n");
      render.event(header);
      return;
    }
    case "planner start":
      render.event(`${stamp(event.at)}  wave ${event.wave}  planning a level of ${event.level.length}`);
      return;
    case "planner done": {
      const deferred = event.deferred
        .map((entry) => `#${entry.number} (${entry.reason})`)
        .join(", ");
      render.event(
        `${stamp(event.at)}  wave ${event.wave}  ${event.picked.length} of ${event.picked.length + event.deferred.length}` +
          (deferred ? ` · ${styleText("dim", `deferred ${deferred}`)}` : ""),
      );
      return;
    }
    case "planner fallback":
      render.event(
        `${stamp(event.at)}  wave ${event.wave}  ${styleText("yellow", "plan rejected")} · ${styleText("dim", event.reason)} · running the computed level`,
      );
      return;
    case "wave start":
      render.event(
        `${stamp(event.at)}  ${styleText("bold", `wave ${event.wave}`)} · ${event.items.length} running · ${progress()}`,
      );
      return;
    case "item start":
      render.event(`${stamp(event.at)}  ▶ #${event.number} ${titleOf(event.number)}  ${styleText("dim", event.branch)}`);
      return;
    case "item phase":
      inflight.set(event.number, {
        number: event.number,
        phase: event.phase,
        startedAt: inflight.get(event.number)?.startedAt ?? event.at,
        tool: "starting",
        spokeAt: event.at,
      });
      if (event.phase === "review") {
        render.event(`${stamp(event.at)}  · #${event.number} implement done, reviewing`);
      }
      return;
    case "activity": {
      const current = inflight.get(event.number);
      if (current) inflight.set(event.number, { ...current, tool: event.tool, spokeAt: event.at });
      return;
    }
    case "item settle":
      inflight.delete(event.number);
      settled.push({
        number: event.number,
        loop: event.outcome,
        loopDetail: event.detail,
        bounced: event.bounced ?? false,
      });
      render.event(
        `${stamp(event.at)}  ${itemLine(event.number, event.outcome, event.detail, { bounced: event.bounced })}  ${progress()}`,
      );
      if (wantsLog(event.outcome)) render.event(logHint(event.number, "implementer"));
      return;
    case "fan-in start":
      render.event(
        `${stamp(event.at)}  ${styleText("bold", `fan-in ${event.wave}`)} · merging ${event.branches.length} branch(es) in run order`,
      );
      return;
    case "fan-in item": {
      const record = settled.find((entry) => entry.number === event.number);
      if (record) record.merge = { outcome: event.outcome, detail: event.detail };
      render.event(`${stamp(event.at)}  ${itemLine(event.number, event.outcome, event.detail)}`);
      if (wantsLog(event.outcome)) render.event(logHint(event.number, "merger"));
      return;
    }
    case "merger":
      render.event(
        `${stamp(event.at)}  merger ${styleText(event.state === "skipped" ? "gray" : "cyan", event.state)} · ${styleText("dim", event.detail)}`,
      );
      return;
    case "cascade":
      skippedCount += event.numbers.length;
      for (const number of event.numbers) {
        render.event(
          `${stamp(event.at)}  ${itemLine(number, "skipped", event.cause)}  ${progress()}`,
        );
      }
      return;
    case "wave done":
      render.event(`${stamp(event.at)}  wave ${event.wave} done · ${progress()}`);
      return;
    case "sandcastle stdout":
      for (const line of event.lines) render.foreign(line);
      return;
    case "run done":
      return;
  }
};

// ── the end-of-run report ───────────────────────────────────────────────────

const report = (): string => {
  const rule = "─".repeat(78);
  const byNumber = new Map(settled.map((entry) => [entry.number, entry]));
  const merged = settled.filter((entry) => entry.merge?.outcome === "merged").length;
  const bounced = settled.filter((entry) => entry.bounced).length;

  const lines = [
    "",
    styleText("dim", rule),
    ` ${styleText("bold", "Run report")} — Implement & Review (parallel) — SPEC #371`,
    styleText("dim", rule),
    ` ${merged} merged · ${bounced} bounced · ${settled.length - merged} not merged · ${skippedCount} skipped · 3 waves · 83m54s`,
    "",
  ];

  for (const item of ITEMS) {
    const record = byNumber.get(item.number);
    if (!record) {
      const skip = SKIPPED.find((entry) => entry.number === item.number);
      lines.push(` ${itemLine(item.number, "skipped", skip?.cause ?? "never dispatched")}`);
      continue;
    }
    const shown = record.merge ?? { outcome: record.loop, detail: record.loopDetail };
    const detail =
      record.merge && record.merge.outcome === "merged"
        ? `${record.loopDetail} · ${branchOf(item.number)}`
        : shown.detail;
    lines.push(` ${itemLine(item.number, shown.outcome, detail, { bounced: record.bounced })}`);
    if (wantsLog(shown.outcome)) lines.push(logHint(item.number, "implementer"));
  }

  lines.push(
    "",
    styleText("dim", " Bounced items were reopened on GitHub and are not a gate — review them on this branch."),
    styleText("dim", " Nothing was pushed. The workspace branch holds every merged item behind a --no-ff commit."),
    styleText("dim", rule),
    "",
  );
  return lines.join("\n");
};

// ── replay ──────────────────────────────────────────────────────────────────

const main = async (): Promise<void> => {
  const render = MODE === "dashboard" ? dashboard() : ledger(HEARTBEAT);
  const events = [...SCRIPT].sort((a, b) => a.at - b.at);

  if (MODE === "report") {
    for (const event of events) {
      if (event.kind === "run start") selected = event.selected;
      if (event.kind === "item settle") {
        settled.push({
          number: event.number,
          loop: event.outcome,
          loopDetail: event.detail,
          bounced: event.bounced ?? false,
        });
      }
      if (event.kind === "fan-in item") {
        const record = settled.find((entry) => entry.number === event.number);
        if (record) record.merge = { outcome: event.outcome, detail: event.detail };
      }
      if (event.kind === "cascade") skippedCount += event.numbers.length;
    }
    console.log(report());
    return;
  }

  const end = events[events.length - 1]!.at;
  let cursor = 0;

  for (let now = 0; now <= end; now += TICK_MS * SPEED) {
    while (cursor < events.length && events[cursor]!.at <= now) emit(render, events[cursor++]!);
    render.tick(now, [...inflight.values()]);
    await sleep(TICK_MS);
  }
  while (cursor < events.length) emit(render, events[cursor++]!);
  render.close();
  console.log(report());
};

await main();
