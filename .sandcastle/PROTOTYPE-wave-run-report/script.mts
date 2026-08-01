// The scripted run. Pure data: no agent, no worktree, no git.
//
// One 10-item run over three waves against SPEC #371, written to exercise
// every outcome the wave-parallel driver can produce — including the ones a
// happy-path demo would never show. `at` is milliseconds into the simulated
// run; the replay in `run.mts` sorts on it and sleeps the gaps.
//
// The `sandcastleStdout` events are not ours. They are the two lines
// `printFileDisplayStartup` writes to `console.log` on every `run()` in
// log-to-file mode (`dist/index.js:904`, `:1076`, `:2468`), reproduced
// verbatim so the prototype shows what a driver-rendered display actually has
// to live alongside.

export type Outcome =
  | "approved"
  | "crashed"
  | "timed out"
  | "no commits"
  | "merged"
  | "conflict rewound"
  | "skipped";

export interface Item {
  readonly number: number;
  readonly title: string;
  readonly slug: string;
}

export type Event =
  /** Run header: what the confirmation screen agreed to. */
  | {
      readonly kind: "run start";
      readonly at: number;
      readonly workflow: string;
      readonly scope: string;
      readonly selected: number;
      readonly eligible: number;
      readonly maxParallel: number;
      readonly logDir: string;
    }
  | { readonly kind: "planner start"; readonly at: number; readonly wave: number; readonly level: readonly number[] }
  | {
      readonly kind: "planner done";
      readonly at: number;
      readonly wave: number;
      readonly picked: readonly number[];
      readonly deferred: readonly { readonly number: number; readonly reason: string }[];
    }
  | { readonly kind: "planner fallback"; readonly at: number; readonly wave: number; readonly reason: string }
  | { readonly kind: "wave start"; readonly at: number; readonly wave: number; readonly items: readonly number[] }
  | { readonly kind: "item start"; readonly at: number; readonly number: number; readonly branch: string }
  | { readonly kind: "item phase"; readonly at: number; readonly number: number; readonly phase: "implement" | "review" }
  /** One `onAgentStreamEvent` toolCall, the only live signal the driver gets. */
  | { readonly kind: "activity"; readonly at: number; readonly number: number; readonly tool: string }
  | {
      readonly kind: "item settle";
      readonly at: number;
      readonly number: number;
      readonly outcome: Outcome;
      readonly detail: string;
      readonly bounced?: boolean;
    }
  | { readonly kind: "fan-in start"; readonly at: number; readonly wave: number; readonly branches: readonly number[] }
  | {
      readonly kind: "fan-in item";
      readonly at: number;
      readonly number: number;
      readonly outcome: Outcome;
      readonly detail: string;
    }
  | { readonly kind: "merger"; readonly at: number; readonly wave: number; readonly state: "dispatched" | "clean" | "repaired" | "skipped"; readonly detail: string }
  | { readonly kind: "cascade"; readonly at: number; readonly numbers: readonly number[]; readonly cause: string }
  | { readonly kind: "wave done"; readonly at: number; readonly wave: number }
  | { readonly kind: "sandcastle stdout"; readonly at: number; readonly lines: readonly string[] }
  | { readonly kind: "run done"; readonly at: number };

export const ITEM_TIMEOUT_MS = 45 * 60_000;

export const ITEMS: readonly Item[] = [
  { number: 372, title: "Add .sandcastle/repo.mts", slug: "add-repo-mts" },
  { number: 373, title: "Move MAX_PARALLEL to repo config", slug: "move-max-parallel" },
  { number: 374, title: "Delete drainsWorkItems", slug: "delete-drainsworkitems" },
  { number: 375, title: "Scope dispatch to one work item", slug: "scope-dispatch" },
  { number: 376, title: "Two-field DispatchResult", slug: "two-field-dispatchresult" },
  { number: 377, title: "Enlarge prepare() preflight", slug: "enlarge-prepare-preflight" },
  { number: 378, title: "Wave-parallel driver skeleton", slug: "wave-parallel-driver" },
  { number: 379, title: "Per-item wall-clock timeout", slug: "per-item-timeout" },
  { number: 380, title: "Fan-in merge in run order", slug: "fan-in-merge" },
  { number: 381, title: "Register the parallel workflow", slug: "register-parallel-workflow" },
];

export const branchOf = (number: number): string => {
  const item = ITEMS.find((candidate) => candidate.number === number);
  return `sandcastle/${number}-${item?.slug ?? "unknown"}`;
};

export const titleOf = (number: number): string =>
  ITEMS.find((candidate) => candidate.number === number)?.title ?? `#${number}`;

const min = (m: number, s = 0) => m * 60_000 + s * 1000;

/** The two lines Sandcastle prints per dispatch in log-to-file mode. */
const started = (at: number, agent: string, number: number): Event => ({
  kind: "sandcastle stdout",
  at,
  lines: [
    `[${agent}] Started on branch ${branchOf(number)}`,
    `  tail -f .sandcastle/logs/${branchOf(number).replace(/\//g, "-")}-${agent}.log`,
  ],
});

export const SCRIPT: readonly Event[] = [
  {
    kind: "run start",
    at: 0,
    workflow: "Implement & Review (parallel)",
    scope: "SPEC #371 — Sandcastle workflows are folders",
    selected: 10,
    eligible: 23,
    maxParallel: 3,
    logDir: ".sandcastle/logs/",
  },

  // ── Wave 1 ────────────────────────────────────────────────────────────────
  { kind: "planner start", at: min(0, 2), wave: 1, level: [372, 373, 374, 375] },
  {
    kind: "planner done",
    at: min(0, 38),
    wave: 1,
    picked: [372, 373, 374],
    deferred: [{ number: 375, reason: "rewrites contract.mts, same file as #373" }],
  },
  { kind: "wave start", at: min(0, 40), wave: 1, items: [372, 373, 374] },
  { kind: "item start", at: min(0, 40), number: 372, branch: branchOf(372) },
  { kind: "item start", at: min(0, 41), number: 373, branch: branchOf(373) },
  { kind: "item start", at: min(0, 42), number: 374, branch: branchOf(374) },
  { kind: "item phase", at: min(0, 44), number: 372, phase: "implement" },
  started(min(0, 44), "implementer", 372),
  { kind: "item phase", at: min(0, 45), number: 373, phase: "implement" },
  started(min(0, 45), "implementer", 373),
  { kind: "item phase", at: min(0, 46), number: 374, phase: "implement" },
  started(min(0, 46), "implementer", 374),

  { kind: "activity", at: min(1, 10), number: 372, tool: "Read(.sandcastle/runner.mts)" },
  { kind: "activity", at: min(1, 20), number: 373, tool: "Grep(MAX_PARALLEL)" },
  { kind: "activity", at: min(1, 25), number: 374, tool: "Read(.sandcastle/contract.mts)" },
  { kind: "activity", at: min(3, 5), number: 372, tool: "Write(.sandcastle/repo.mts)" },
  { kind: "activity", at: min(3, 40), number: 373, tool: "Edit(.sandcastle/cli/prompts.mts)" },
  { kind: "activity", at: min(4, 0), number: 374, tool: "Bash(swift build --build-tests)" },
  { kind: "activity", at: min(6, 12), number: 372, tool: "Bash(swift test)" },
  { kind: "activity", at: min(7, 30), number: 373, tool: "Bash(pnpm --dir .sandcastle test)" },
  { kind: "activity", at: min(8, 15), number: 374, tool: "Bash(swift build --build-tests)" },

  { kind: "item phase", at: min(9, 12), number: 372, phase: "review" },
  started(min(9, 12), "reviewer", 372),
  { kind: "activity", at: min(9, 50), number: 372, tool: "Bash(git diff)" },
  { kind: "item settle", at: min(12, 4), number: 372, outcome: "approved", detail: "4 commits · 11m24s" },

  { kind: "item phase", at: min(12, 40), number: 373, phase: "review" },
  started(min(12, 40), "reviewer", 373),
  { kind: "activity", at: min(13, 10), number: 373, tool: "Read(.sandcastle/cli/store.mts)" },
  {
    kind: "item settle",
    at: min(16, 2),
    number: 373,
    outcome: "approved",
    detail: "6 commits · 15m21s",
    bounced: true,
  },

  { kind: "activity", at: min(20, 0), number: 374, tool: "Bash(swift test)" },
  { kind: "activity", at: min(31, 40), number: 374, tool: "Bash(swift test)" },
  {
    kind: "item settle",
    at: min(45, 46),
    number: 374,
    outcome: "timed out",
    detail: "no commits · 45m00s wall clock",
  },

  { kind: "fan-in start", at: min(45, 50), wave: 1, branches: [372, 373] },
  { kind: "fan-in item", at: min(45, 54), number: 372, outcome: "merged", detail: "--no-ff" },
  { kind: "fan-in item", at: min(45, 58), number: 373, outcome: "merged", detail: "--no-ff" },
  { kind: "merger", at: min(46, 0), wave: 1, state: "dispatched", detail: "2 branches merged" },
  started(min(46, 0), "merger", 372),
  { kind: "activity", at: min(46, 30), number: 372, tool: "Bash(swift build --build-tests)" },
  { kind: "merger", at: min(48, 20), wave: 1, state: "clean", detail: "merged tree builds, 447 tests pass" },
  { kind: "cascade", at: min(48, 22), numbers: [379], cause: "#374 timed out" },
  { kind: "wave done", at: min(48, 24), wave: 1 },

  // ── Wave 2 ────────────────────────────────────────────────────────────────
  { kind: "planner start", at: min(48, 26), wave: 2, level: [375, 376, 377] },
  { kind: "planner fallback", at: min(48, 58), wave: 2, reason: "plan named #382, not in the ready level" },
  { kind: "wave start", at: min(49, 0), wave: 2, items: [375, 376, 377] },
  { kind: "item start", at: min(49, 0), number: 375, branch: branchOf(375) },
  { kind: "item start", at: min(49, 1), number: 376, branch: branchOf(376) },
  { kind: "item start", at: min(49, 2), number: 377, branch: branchOf(377) },
  { kind: "item phase", at: min(49, 4), number: 375, phase: "implement" },
  started(min(49, 4), "implementer", 375),
  { kind: "item phase", at: min(49, 5), number: 376, phase: "implement" },
  started(min(49, 5), "implementer", 376),
  { kind: "item phase", at: min(49, 6), number: 377, phase: "implement" },
  started(min(49, 6), "implementer", 377),

  { kind: "activity", at: min(50, 0), number: 375, tool: "Read(.sandcastle/contract.mts)" },
  { kind: "activity", at: min(50, 10), number: 376, tool: "Read(.sandcastle/contract.mts)" },
  { kind: "activity", at: min(50, 20), number: 377, tool: "Read(.sandcastle/runner.mts)" },
  {
    kind: "item settle",
    at: min(51, 30),
    number: 376,
    outcome: "crashed",
    detail: "provider exited 1: context window exceeded · 2m25s",
  },
  { kind: "activity", at: min(53, 0), number: 375, tool: "Edit(.sandcastle/contract.mts)" },
  { kind: "activity", at: min(55, 20), number: 377, tool: "Bash(gh auth status)" },
  { kind: "item phase", at: min(58, 10), number: 375, phase: "review" },
  started(min(58, 10), "reviewer", 375),
  { kind: "item settle", at: min(61, 5), number: 375, outcome: "approved", detail: "3 commits · 12m05s" },
  { kind: "item phase", at: min(62, 0), number: 377, phase: "review" },
  started(min(62, 0), "reviewer", 377),
  { kind: "item settle", at: min(64, 40), number: 377, outcome: "approved", detail: "5 commits · 15m38s" },

  { kind: "fan-in start", at: min(64, 44), wave: 2, branches: [375, 377] },
  { kind: "fan-in item", at: min(64, 48), number: 375, outcome: "merged", detail: "--no-ff" },
  {
    kind: "fan-in item",
    at: min(64, 52),
    number: 377,
    outcome: "conflict rewound",
    detail: "both modified .sandcastle/runner.mts",
  },
  { kind: "merger", at: min(64, 55), wave: 2, state: "dispatched", detail: "1 merged, 1 conflicted" },
  started(min(64, 55), "merger", 377),
  { kind: "activity", at: min(65, 20), number: 377, tool: "Bash(git status)" },
  {
    kind: "merger",
    at: min(69, 30),
    wave: 2,
    state: "repaired",
    detail: "#377 conflict resolved and merged · tree builds",
  },
  { kind: "fan-in item", at: min(69, 31), number: 377, outcome: "merged", detail: "conflict resolved by merger" },
  { kind: "wave done", at: min(69, 32), wave: 2 },

  // ── Wave 3 ────────────────────────────────────────────────────────────────
  { kind: "planner start", at: min(69, 34), wave: 3, level: [378, 380, 381] },
  { kind: "planner done", at: min(70, 2), wave: 3, picked: [378, 380, 381], deferred: [] },
  { kind: "wave start", at: min(70, 4), wave: 3, items: [378, 380, 381] },
  { kind: "item start", at: min(70, 4), number: 378, branch: branchOf(378) },
  { kind: "item start", at: min(70, 5), number: 380, branch: branchOf(380) },
  { kind: "item start", at: min(70, 6), number: 381, branch: branchOf(381) },
  { kind: "item phase", at: min(70, 8), number: 378, phase: "implement" },
  started(min(70, 8), "implementer", 378),
  { kind: "item phase", at: min(70, 9), number: 380, phase: "implement" },
  started(min(70, 9), "implementer", 380),
  { kind: "item phase", at: min(70, 10), number: 381, phase: "implement" },
  started(min(70, 10), "implementer", 381),
  { kind: "activity", at: min(71, 0), number: 378, tool: "Read(docs/adr/0010-...md)" },
  { kind: "activity", at: min(71, 30), number: 380, tool: "Read(.sandcastle/runner.mts)" },
  { kind: "activity", at: min(72, 0), number: 381, tool: "Read(.sandcastle/workflows/registry.mts)" },
  {
    kind: "item settle",
    at: min(74, 20),
    number: 378,
    outcome: "no commits",
    detail: "agent reported blocked on #374 · 4m12s",
  },
  { kind: "item phase", at: min(78, 0), number: 380, phase: "review" },
  started(min(78, 0), "reviewer", 380),
  { kind: "item settle", at: min(81, 15), number: 380, outcome: "approved", detail: "2 commits · 11m06s" },
  {
    kind: "item settle",
    at: min(83, 40),
    number: 381,
    outcome: "crashed",
    detail: "idle timeout: no output for 600s · 13m30s",
  },

  { kind: "fan-in start", at: min(83, 44), wave: 3, branches: [380] },
  { kind: "fan-in item", at: min(83, 48), number: 380, outcome: "merged", detail: "--no-ff" },
  {
    kind: "merger",
    at: min(83, 50),
    wave: 3,
    state: "skipped",
    detail: "one branch merged cleanly into an unmoved base",
  },
  { kind: "wave done", at: min(83, 52), wave: 3 },
  { kind: "run done", at: min(83, 54) },
];

/** Items never dispatched, and why. Reported, never rendered live. */
export const SKIPPED: readonly { readonly number: number; readonly cause: string }[] = [
  { number: 379, cause: "blocked by #374, which timed out" },
];
