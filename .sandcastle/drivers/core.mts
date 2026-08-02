// The driver seam: what `prepare()` hands a driver, and what a driver is.
//
// Types only, with no runtime export at all, and that is what it is for. A
// driver needs to name `RunCore`, `cli/flow.mts` needs to read a driver's shape,
// and `runner.mts` is the module that spawns — so if the drivers imported the
// core's *type* from `runner.mts`, the picker would reach Sandcastle through the
// registry and stop being assertable. Declaring the seam in a leaf breaks that
// chain rather than relying on every import along it staying type-only.
//
// The layering this expresses, from ADR-0010 as amended:
//
//   runner core   providers, model validation, the frozen allow-list, prompt-arg
//                 injection, git primitives            — changes rarely
//   driver        worktrees, concurrency, fan-in, skips, cleanup, the Planner and
//                 Merger dispatches                    — a genuinely new shape
//   workflow      agents, prompts, a driver choice, one body — every new idea
//   repo config   pre-warm, copyToWorktree, MAX_PARALLEL, the item timeout

import type { Agent, Dispatch, DriverId, Workflow } from "../contract.mts";
import type { RepoConfig } from "../repo.mts";
import type { Revalidation } from "../scope/github.mts";
import type {
  HandoffState,
  LiveIssueState,
  WorkItem,
  WorkScopeSnapshot,
} from "../scope/snapshot.mts";
import type { Validator } from "./schema.mts";

/**
 * The tracker reads a driver makes *while it runs*, as opposed to the frozen
 * snapshot it was handed. Three, and each answers a question the snapshot
 * cannot: has this moved under us, was it bounced, and is the SPEC drained?
 *
 * Bound to this run's snapshot by `prepare()` rather than reached for by the
 * driver, which is what keeps a driver testable against a fake core — and what
 * keeps `revalidate` from ever being asked about an item outside the allow-list.
 */
export interface IssueReads {
  /** Immediately before dispatch, so stale or newly ineligible work never runs. */
  readonly revalidate: (item: WorkItem) => Promise<Revalidation>;
  /** At settle. This is where a bounce is observed, and the only place. */
  readonly liveState: (item: WorkItem) => Promise<LiveIssueState>;
  /** At end of run, after every correction has landed. `null` with no anchor. */
  readonly handoff: () => Promise<HandoffState | null>;
}

/**
 * What a driver may ask git about the workspace branch.
 *
 * Deliberately reads only. Git is the one toolchain this runner is allowed to
 * branch on — it is framework-neutral — and these two are how *committed* and
 * *no commits* are observed from outside the workflow, which is what stops a
 * body from holding the transitive skip set.
 */
export interface WorkspaceGit {
  /** The branch every item's work is expected to reach, by name. */
  readonly branch: string;
  readonly headSha: () => string;
  /** `git rev-list --count <sha>..HEAD`. */
  readonly commitsSince: (sha: string) => number;
}

/**
 * One item's own worktree, cut from the workspace branch's tip, and the dispatch
 * that runs inside it.
 *
 * A handle deliberately narrower than Sandcastle's `Worktree`, which carries
 * `.close()`, `.createSandbox()` and `.interactive()` — a driver has no business
 * opening an interactive session, and **closing is not a driver's call either**:
 * cleanup is merge-gated and done with `git worktree remove` and `git branch -d`,
 * so git itself refuses to destroy anything unmerged. `path` and `branch` are
 * here so the driver can hand them to git and name them in the report.
 */
export interface ItemWorktree {
  readonly branch: string;
  readonly path: string;
  /**
   * Where this item's agent output is being written. Concurrency *forces* a log
   * file: Sandcastle's `stdout` logging is a cursor-owning Clack UI, and three
   * dispatches would fight over one cursor. It is also the sole record of an
   * item that timed out, crashed or committed nothing — those leave no git trace
   * at all.
   */
  readonly logPath: string;
  readonly dispatch: Dispatch;
}

/**
 * What a driver asks one of its own agents, on the host.
 *
 * Deliberately not a `DispatchOptions`. `promptArgs` is **required**, because a
 * driver-internal prompt is nothing but its arguments; and `tag`/`schema` have
 * no counterpart on the contract at all — `WorktreeRunOptions` has no `output`,
 * and a workflow that could ask for structured output could branch on what a
 * model said.
 */
export interface ConsultOptions<T> {
  /** A bare filename, resolved against the workflow's own folder. */
  readonly promptFile: string;
  readonly promptArgs: Readonly<Record<string, string>>;
  /** The XML tag the prompt emits its one block in. */
  readonly tag: string;
  readonly schema: Validator<T>;
}

/**
 * Ask a driver-internal agent for a structured answer.
 *
 * **This is why the two layers need different dispatch types.** The Planner and
 * the Merger are not `Dispatch` calls: they are made by the driver, through the
 * runner core, on the host — which is what lets them use `output`, and what
 * keeps a workflow from ever reaching one. A workflow declares which agents a
 * run resolves; it never decides when one of these two speaks.
 *
 * The runner fixes `maxRetries` at 1 for every consult rather than exposing it:
 * a *shape* retry resumes the agent's own session and costs one round trip,
 * while a *semantic* retry is the thing `planner.mts` exists to keep impossible.
 * One knob fewer is one fewer way to blur them.
 */
export type Consult = <T>(agent: Agent, options: ConsultOptions<T>) => Promise<T>;

/**
 * Everything a driver may reach, and the only value from which a `Dispatch` can
 * be obtained. `prepare()` is the sole producer, and it returns nothing until
 * every preflight has passed — which is what makes eager validation structural
 * rather than conventional: no auth failure can surface at item seven, because
 * there was no way to dispatch item one without the checks having run.
 */
export interface RunCore {
  /**
   * The frozen, ordered, truncated list this run may work — a topological sort
   * of the `blocked_by` edges, stable on the maintainer's authored order, cut by
   * the run guard *after* the sort so no item's blocker was ever cut out from
   * under it. Empty is impossible: `prepare()` refuses a run with no work.
   */
  readonly work: readonly WorkItem[];
  /**
   * The frozen snapshot `work` was cut from — the dependency edges, the
   * membership and the anchor.
   *
   * A driver may read this and a workflow may not, and that is the whole of the
   * split: the driver owns the skip set, the levels and the order, so it is the
   * one component that has to see an edge. Everything it does with them lives in
   * `drivers/outcomes.mts`, where it is pure and asserted.
   */
  readonly scope: WorkScopeSnapshot;
  /**
   * This repository's shape. A driver passes these commands through and never
   * reads their output — it may run a command whose result it discards, and
   * never one whose exit code it branches on, git excepted.
   */
  readonly repo: RepoConfig;
  /**
   * How many work items a concurrent driver may run at once, and therefore how
   * wide a wave may be — **wave size *is* concurrency; there is no semaphore.**
   * A semaphore would silently undo the Planner's one real power, since two
   * items it deliberately separated could still overlap while a wide plan
   * drains. One for a driver the picker never asked the question of.
   */
  readonly maxParallel: number;
  readonly issues: IssueReads;
  readonly git: WorkspaceGit;
  /**
   * A dispatch on the host checkout already scoped to one work item, with
   * `{{WORK}}` written for it. `item` must be one of `work`.
   */
  readonly forItem: (item: WorkItem) => Dispatch;
  /**
   * A dispatch on the host checkout for a driver that has no work items, with
   * `{{ANCHOR}}` written — literally `null` under a repository-wide scope.
   */
  readonly forBranch: () => Dispatch;
  /**
   * A driver's own agents, on the host, answering in a shape the runner can
   * read. Two callers, both in this folder: the Planner and the Merger.
   */
  readonly consult: Consult;
  /**
   * Cut `branch` as a worktree of its own and hand back a dispatch that runs
   * inside it, with `{{WORK}}` written for `item`.
   *
   * `signal` is the item's wall-clock bound, and it arrives **here** rather than
   * on `DispatchOptions` — a workflow that could reach the signal could defeat
   * the one thing that ends a hang. Sandcastle's own `Timeouts` covers lifecycle
   * steps only (copy, git setup, commit collection), never the agent run, so
   * without this a wedged item stalls its wave until the 600-second idle timeout
   * kills a silent agent, and orphaned test processes may outlive even that.
   */
  readonly openWorktree: (
    item: WorkItem,
    branch: string,
    signal: AbortSignal,
  ) => Promise<ItemWorktree>;
}

/** How a driver runs one workflow to completion. */
export type Drive = (core: RunCore, workflow: Workflow) => Promise<void>;

/**
 * One execution shape. `drains` and `concurrent` are what the picker reads to
 * decide whether the run guard and `MAX_PARALLEL` are decisions at all, which is
 * why they live here and not on `Workflow`: a workflow that declared its own
 * concurrency could contradict the driver that actually runs it.
 */
export interface Driver {
  readonly id: DriverId;
  /** Whether this driver works through a list of work items. */
  readonly drains: boolean;
  /** Whether it works more than one of them at a time. */
  readonly concurrent: boolean;
  /**
   * Run a workflow, or `null` for a shape that is decided but not yet built.
   *
   * Nullable because `drains` and `concurrent` are what the picker reads, and a
   * shape can be settled — and therefore describable — a slice before it can
   * run. All three are built today. `prepare()` refuses a plan whose driver
   * cannot run, so this is never `null` by the time anything is dispatched.
   */
  readonly drive: Drive | null;
}
