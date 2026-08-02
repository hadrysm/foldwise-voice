// What a workflow is, and the only thing a workflow is allowed to do.
//
// **An allow-list, not a denylist.** `DispatchOptions` used to be
// `Omit<RunOptions, …ten keys>`, on the claim that the omissions made ADR-0001
// unwritable. They did not: `Dispatch` returned Sandcastle's `RunResult`, whose
// `resume?`/`fork?` options type omits neither `branchStrategy`, `cwd` nor
// `hooks`, so a workflow could resume its own dispatch onto a forbidden branch
// strategy. **The omission list was defeated by the return type.** Two keys in,
// two fields out closes that: an allow-list cannot be defeated by a return type,
// and it cannot silently widen when Sandcastle adds an option — which the
// denylist would have, on every upgrade.
//
// So this module exports **no Sandcastle type at all**, not even a type-only
// one. Sandcastle is an implementation detail *below* the contract, and an
// upgrade that changes `RunResult` is a runner-side edit. `stdout` stops
// crossing the seam with it: a workflow that can read agent output can branch on
// what a model said, which is the same leak as reading the winning model id.
//
// A workflow holds control flow and nothing else — it declares a driver and
// supplies that driver's loop body. See
// docs/adr/0010-sandcastle-workflows-are-folders-driven-by-injected-dispatch.md.

import type { WorkItem } from "./scope/snapshot.mts";

/**
 * Who runs a step. Identity only: no prompt path, because both workflows drive
 * the same reviewer with different prompts, and no default model or effort,
 * because the store overwrites those after the first run.
 */
export interface Agent {
  id: string;
  label: string;
}

/**
 * Every execution shape a workflow may declare. A driver owns how work becomes
 * dispatches — worktrees, concurrency, fan-in, skips, cleanup — and a workflow
 * receives the context *that* driver grants.
 *
 * Extending Sandcastle means **reusing a driver, never reaching further**:
 * adding a workflow is a new folder and zero contract change, and adding an
 * execution shape is a new driver and zero change to existing workflows.
 */
export type DriverId = "sequential" | "wave-parallel" | "whole-branch";

/**
 * What one dispatch produces. `commits.length` is still what tells a body
 * whether anything happened; `baseSha` is the SHA captured immediately before
 * that dispatch, which is what makes "the reviewer diffed the wrong range"
 * impossible to write rather than merely tested.
 */
export interface DispatchResult {
  readonly commits: readonly { readonly sha: string }[];
  readonly baseSha: string;
}

/**
 * What a workflow may ask of a dispatch, in full. Decided by arithmetic rather
 * than taste: across both shipped workflows the entire use of Sandcastle's
 * `RunOptions` is these two keys, and it is also the only shape both `run()` and
 * `Worktree.run()` can satisfy — `WorktreeRunOptions` has no `output`, no `cwd`,
 * no `branchStrategy`, no `copyToWorktree` and no `timeouts`.
 *
 * The field is `promptFile`, not `prompt`: Sandcastle's `prompt` means an inline
 * string, and shell-block includes expand only for a file. The value is a bare
 * filename, resolved by the runner against `Workflow.dir`.
 *
 * A `promptArgs` key that collides with a name the runner or a driver writes —
 * `WORK`, `ANCHOR`, `READY`, `MAX_PARALLEL`, `WAVE` — throws rather than
 * overriding. The only key a body writes is `REVIEW_BASE`.
 */
export interface DispatchOptions {
  readonly promptFile: string;
  readonly promptArgs?: Readonly<Record<string, string>>;
}

/**
 * Run one agent once, against the work the driver already chose.
 *
 * There is no work-item parameter, and that is the guarantee: *"a dispatch that
 * names no work item does not compile"* has become *"a dispatch cannot name a
 * work item at all; the driver decided which one before the body ran."* It also
 * removes a race the required-key shape permitted — two concurrent bodies
 * dispatching against the same item.
 */
export type Dispatch = (agent: Agent, options: DispatchOptions) => Promise<DispatchResult>;

/**
 * Everything a body gets.
 *
 * Deliberately no resolved agents: a workflow that can read the winning model id
 * will eventually branch on it, and *who* runs a step is the axis the picker
 * owns. Deliberately no worktree handle either — Sandcastle's `Worktree` carries
 * `.close()`, `.createSandbox()` and `.interactive()`.
 *
 * `item` is there to *read* — number, title, url — and is `null` under a driver
 * that has no work items at all. It is never passed to `dispatch`, because the
 * dispatch already **is** that item.
 */
export interface WorkflowContext {
  readonly dispatch: Dispatch;
  readonly item: WorkItem | null;
}

export interface Workflow {
  id: string;
  label: string;
  description: string;
  /** Always `import.meta.dirname`, which is what makes the folder relocatable. */
  dir: string;
  agents: readonly Agent[];
  /**
   * How this workflow's work becomes dispatches. Whether a run drains work items
   * and whether it runs them side by side are properties of the driver, which is
   * why the picker reads them from the driver registry rather than from here —
   * a workflow declaring its own concurrency shape could contradict the driver
   * that actually runs it.
   */
  driver: DriverId;
  /**
   * The one line the confirmation screen leads with, e.g.
   * `implement → review, up to 10 issues`. One number, because the anchor, the
   * scope kind and the eligible counts belong to `cli/flow.mts` — a workflow
   * that could read them would eventually branch on them.
   */
  runShape: (workItems: number) => string;
  /**
   * One item's sequence, or the whole branch's. Called once per work item by a
   * draining driver and exactly once by `whole-branch`; it can neither create a
   * loop nor bound one.
   */
  run: (context: WorkflowContext) => Promise<void>;
}
