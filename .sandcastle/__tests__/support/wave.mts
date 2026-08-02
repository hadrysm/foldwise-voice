// A `RunCore` over a real temporary git repository, with scripted agents.
//
// The split #396 settled: **you only fake what is expensive.** The agents are
// faked because they cost money, minutes and a provider login. Git is real
// because it costs nothing, and because three of the claims the wave topology
// rests on are claims *about git* rather than about this code.
//
// So `openWorktree` here really cuts a worktree, a script really commits into
// it, and the driver's fan-in really merges those branches — while the thing
// standing in for an agent is one function of `(worktree, signal)`. Concurrency
// needs no real timing either: a script resolves when the test says it does, so
// a partial wave and a completion order that differs from run order are both
// deterministic.

import { IMPLEMENTER, PLANNER, REVIEWER } from "../../agents/catalog.mts";
import type { Dispatch, Workflow } from "../../contract.mts";
import type { RunCore } from "../../drivers/core.mts";
import type { WavePayload } from "../../drivers/merger.mts";
import type { ReadyRecord } from "../../drivers/planner.mts";
import { repo } from "../../repo.mts";
import type { WorkItem, WorkScopeSnapshot } from "../../scope/snapshot.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import { fakeIssueReads, type BodyCall, type FakeCoreOptions } from "./core.mts";
import { WORKSPACE_BRANCH, worktreePath, type TempRepo } from "./repo.mts";

/** What a scripted agent may do: exactly what a real one can, in its worktree. */
export interface ScriptContext {
  readonly item: WorkItem;
  readonly path: string;
  /** The driver's own item timeout. A script that never settles waits on this. */
  readonly signal: AbortSignal;
  /** Commit inside this item's worktree. */
  readonly commit: (file: string, contents: string) => void;
}

export type ItemScript = (context: ScriptContext) => Promise<void> | void;

/** The default: one commit, on a file no other item touches. */
export const COMMITS_ONCE: ItemScript = ({ item, commit }) =>
  commit(`item-${item.number}.txt`, `from #${item.number}`);

/** Leaves the worktree exactly as it found it — an implementer that did nothing. */
export const COMMITS_NOTHING: ItemScript = () => {};

/** Never settles. Only its item's timeout ends it. */
export const HANGS: ItemScript = () => new Promise<void>(() => {});

/** Rejects the way a body whose dispatch threw does. */
export function crashesWith(message: string): ItemScript {
  return () => {
    throw new Error(message);
  };
}

/** A signal a script can wait on and another script can open. */
export interface Gate {
  readonly open: () => void;
  readonly opened: Promise<void>;
}

export function gate(): Gate {
  let open = (): void => {};
  const opened = new Promise<void>((resolve) => {
    open = resolve;
  });
  return { open: () => open(), opened };
}

/** How long a hang guard waits before letting the assertion fail instead. */
const HANG_GUARD_MS = 2_000;

/**
 * Wait for a gate, or give up.
 *
 * The bound is a **hang guard, never a timing dependency**: concurrency needs no
 * real timing, so on the passing path the gate is already open and nothing
 * sleeps. It exists because a driver that broke the property under test would
 * otherwise deadlock the suite rather than fail it — and CI does not retry.
 */
export function reached(open: Promise<void>): Promise<unknown> {
  return Promise.race([open, new Promise((resolve) => setTimeout(resolve, HANG_GUARD_MS))]);
}

/** One dispatch the run made, and everything the runner wrote into it. */
export interface WaveDispatch {
  readonly issueNumber: number;
  readonly agentId: string;
  readonly promptArgs: Readonly<Record<string, string>>;
  /** The worktree's HEAD when the dispatch started. */
  readonly baseSha: string;
}

/** One driver-internal consult, and everything the driver wrote into it. */
export interface Consultation {
  readonly agentId: string;
  readonly promptFile: string;
  readonly promptArgs: Readonly<Record<string, string>>;
}

/**
 * What a scripted agent answers with, **before validation**.
 *
 * `unknown` rather than a `Plan` or a `MergeVerdict` on purpose: a test that can
 * only script a well-formed answer cannot reach the path where a model returns
 * something else, which is the path the fallback exists for. The fake runs the
 * real schema over whatever this returns, so a malformed answer fails here
 * exactly where it would fail in production.
 */
export type PlannerScript = (ready: readonly number[]) => unknown;
export type MergerScript = (wave: WavePayload) => unknown;

export interface WaveCoreOptions extends FakeCoreOptions {
  /** What each item's implementer does, by issue number. Unlisted commits once. */
  readonly scripts?: Readonly<Record<number, ItemScript>>;
  readonly maxParallel?: number;
  /** Minutes, as `repo.itemTimeout` carries it. Fractions keep a hang cheap. */
  readonly itemTimeoutMinutes?: number;
  /** What the Planner answers, wave by wave. Unlisted waves plan the computed wave. */
  readonly plans?: readonly PlannerScript[];
  /** What the Merger answers, wave by wave. Unlisted waves come back verified. */
  readonly verdicts?: readonly MergerScript[];
  /** Make a consult reject instead, by agent id — a provider that hung up. */
  readonly consultFails?: Readonly<Record<string, string>>;
}

export interface WaveCore {
  readonly core: RunCore;
  readonly dispatches: WaveDispatch[];
  /** Worktree paths in the order the driver asked for them. */
  readonly opened: string[];
  /** Every Planner and Merger consult, in the order the driver made them. */
  readonly consultations: Consultation[];
}

/** A promise that rejects when the item's timeout fires, and never otherwise. */
function whenAborted(signal: AbortSignal): Promise<never> {
  const rejection = new Promise<never>((_, reject) => {
    if (signal.aborted) reject(signal.reason);
    else signal.addEventListener("abort", () => reject(signal.reason), { once: true });
  });
  // A script that finishes first leaves this rejecting into nobody's hands.
  rejection.catch(() => {});
  return rejection;
}

/**
 * The two driver-internal agents, scripted, with the real schemas in front of
 * them.
 *
 * The defaults are deliberately the answers a *working* Planner and Merger give
 * — the whole ready level up to `MAX_PARALLEL`, and a verified tree — so a test
 * that says nothing about them exercises the accepted path rather than the
 * fallback. A test that wants the fallback has to ask for it, which is the right
 * way round: the fallback is what a bug looks like.
 */
function scriptedConsult(options: WaveCoreOptions, consultations: Consultation[]): RunCore["consult"] {
  const asked = new Map<string, number>();

  return (agent, consultOptions) => {
    consultations.push({
      agentId: agent.id,
      promptFile: consultOptions.promptFile,
      promptArgs: { ...consultOptions.promptArgs },
    });

    const failure = options.consultFails?.[agent.id];
    if (failure) return Promise.reject(new Error(failure));

    const turn = asked.get(agent.id) ?? 0;
    asked.set(agent.id, turn + 1);

    let answer: unknown;
    if (agent.id === PLANNER.id) {
      const ready = (JSON.parse(consultOptions.promptArgs["READY"] ?? "[]") as ReadyRecord[]).map(
        (record) => record.number,
      );
      const scripted = options.plans?.[turn];
      answer = scripted
        ? scripted(ready)
        : { wave: ready.slice(0, Number(consultOptions.promptArgs["MAX_PARALLEL"])), deferrals: [] };
    } else {
      const wave = JSON.parse(consultOptions.promptArgs["WAVE"] ?? "null") as WavePayload;
      const scripted = options.verdicts?.[turn];
      answer = scripted
        ? scripted(wave)
        : { verified: true, unresolved: [], notes: "the fake tree builds" };
    }

    // The real validator, so a scripted answer of the wrong shape fails the way
    // Sandcastle's own extraction does — after its one retry, as a rejection.
    const validated = consultOptions.schema["~standard"].validate(answer);
    if ("issues" in validated) {
      return Promise.reject(
        new Error(`structured output <${consultOptions.tag}> did not validate: ${validated.issues[0]?.message}`),
      );
    }
    return Promise.resolve(validated.value);
  };
}

export function waveCore(
  temp: TempRepo,
  scope: WorkScopeSnapshot,
  work: readonly WorkItem[],
  options: WaveCoreOptions = {},
): WaveCore {
  const dispatches: WaveDispatch[] = [];
  const opened: string[] = [];
  const consultations: Consultation[] = [];

  return {
    dispatches,
    opened,
    consultations,
    core: {
      consult: scriptedConsult(options, consultations),
      work,
      scope,
      repo: {
        ...repo,
        // Nothing to pre-warm and nothing to copy: the fixture repo has no
        // toolchain, which is the point — a driver that named one would not
        // work here at all.
        onWorktreeReady: [],
        copyToWorktree: [],
        itemTimeout: { minutes: options.itemTimeoutMinutes ?? 45 },
      },
      maxParallel: options.maxParallel ?? repo.maxParallelDefault,
      issues: fakeIssueReads(scope, options),
      git: {
        branch: WORKSPACE_BRANCH,
        headSha: () => temp.headSha(),
        commitsSince: (sha) => Number(temp.git(["rev-list", "--count", `${sha}..HEAD`]).trim()),
      },
      forItem: () => {
        throw new Error("a concurrent driver dispatched against the host checkout");
      },
      forBranch: () => {
        throw new Error("a draining driver dispatched against the whole branch");
      },
      openWorktree: (item, branch, signal) => {
        const path = worktreePath(temp.root, branch);
        temp.git(["worktree", "add", "-b", branch, path, "HEAD"]);
        opened.push(path);

        const dispatch: Dispatch = async (agent, dispatchOptions) => {
          // Sandcastle rejects at entry on an already-aborted signal, and the
          // driver's reading of `timed out` depends on that.
          signal.throwIfAborted();
          const baseSha = temp.git(["rev-parse", "HEAD"], path).trim();
          dispatches.push({
            issueNumber: item.number,
            agentId: agent.id,
            promptArgs: { ...dispatchOptions.promptArgs },
            baseSha,
          });

          if (agent.id === IMPLEMENTER.id) {
            const script = options.scripts?.[item.number] ?? COMMITS_ONCE;
            await Promise.race([
              (async () =>
                script({
                  item,
                  path,
                  signal,
                  commit: (file, contents) => temp.commit(file, contents, path),
                }))(),
              whenAborted(signal),
            ]);
          }

          const commits = temp
            .git(["rev-list", `${baseSha}..HEAD`], path)
            .split("\n")
            .filter(Boolean)
            .map((sha) => ({ sha }));
          return { commits, baseSha };
        };

        return Promise.resolve({ branch, path, logPath: `${path}.log`, dispatch });
      },
    },
  };
}

/**
 * The implement→review body SPEC #418 specifies, verbatim, recording what it
 * was handed. Real rather than a stub: `REVIEW_BASE` coming from the
 * implementer's own `baseSha` is one of the things under test.
 */
export function waveWorkflow(calls: BodyCall[]): Workflow {
  return {
    ...sequentialReviewer,
    id: "recording-wave-parallel",
    driver: "wave-parallel",
    run: async ({ item, dispatch }) => {
      calls.push({ item });
      const implement = await dispatch(IMPLEMENTER, { promptFile: "implement-prompt.md" });
      if (!implement.commits.length) return;
      await dispatch(REVIEWER, {
        promptFile: "review-prompt.md",
        promptArgs: { REVIEW_BASE: implement.baseSha },
      });
    },
  };
}
