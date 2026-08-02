// What a workflow is, and the only thing a workflow is allowed to do.
//
// This module is a runtime leaf: its Sandcastle imports are type-only, so a
// workflow that imports it pulls in no provider, no sandbox and no process
// spawning. A workflow holds control flow and nothing else — it receives
// `dispatch` and calls it (see docs/adr/0010-sandcastle-workflows-are-folders-
// driven-by-injected-dispatch.md).

import type { RunOptions, RunResult } from "@ai-hero/sandcastle";

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
 * A run parameter the workflow declares and the picker renders generically. A
 * typed integer: `min`/`max` are rejection bounds shown to the picker, not
 * clamps.
 */
export interface Knob {
  id: string;
  prompt: string;
  summaryLabel: string;
  defaultValue: number;
  min: number;
  max: number;
}

/**
 * What a workflow may ask of a dispatch. The omitted keys are the point:
 * `sandbox` and `branchStrategy` are unreachable so no workflow can contradict
 * ADR-0001, and `maxIterations` and `hooks` are unreachable so no workflow can
 * start a second loop competing with Sandcastle's pinned `maxIterations: 1` —
 * the loop is the workflow's `for`. Everything else in `RunOptions`
 * (`promptArgs`, `completionSignal`, `output`, `signal`, the timeouts) still
 * passes through, so this type need not chase Sandcastle's.
 *
 * The field is `promptFile`, not `prompt`: Sandcastle's `prompt` means an
 * inline string, and shell-block includes expand only for a file. The value is
 * a bare filename, resolved by the runner against `Workflow.dir`.
 */
export type DispatchOptions = Omit<
  RunOptions,
  | "agent"
  | "sandbox"
  | "cwd"
  | "prompt"
  | "promptFile"
  | "branchStrategy"
  | "maxIterations"
  | "hooks"
  | "name"
  | "logging"
> & { promptFile: string };

/**
 * Run one agent once. The result is Sandcastle's `RunResult` — `commits.length`
 * is still what tells a workflow the backlog is empty — extended with
 * `baseSha`, the SHA captured immediately before this dispatch. Handing the
 * base back from the dispatch that preceded it is what makes "the reviewer
 * diffed the wrong range" impossible to write, rather than merely tested.
 */
export type Dispatch = (
  agent: Agent,
  options: DispatchOptions,
) => Promise<RunResult & { baseSha: string }>;

/**
 * Everything a workflow gets. Deliberately no resolved agents: a workflow that
 * can read the winning model id will eventually branch on it, and *who* runs a
 * step is the axis the picker owns.
 */
export interface WorkflowContext {
  dispatch: Dispatch;
  /** Every declared knob, defaults already filled — never a missing key. */
  knobs: Readonly<Record<string, number>>;
  /**
   * The run guard: how many work items this run may drain. Interim — the loop
   * belongs to a driver from slice 5 of SPEC #418 onward, and this field goes
   * with it. It exists now so the guard can replace `maxIterations` in the same
   * slice that deletes that knob: two number questions for one parameter must
   * never both be on screen.
   */
  maxWorkItems: number;
}

export interface Workflow {
  id: string;
  label: string;
  description: string;
  /** Always `import.meta.dirname`, which is what makes the folder relocatable. */
  dir: string;
  agents: readonly Agent[];
  knobs: readonly Knob[];
  /**
   * Whether this workflow works through a list of work items, and whether it
   * works through more than one at a time.
   *
   * Interim. Both are *driver* properties from slice 5 of SPEC #418 onward, and
   * both die with `Workflow.driver` — but the picker needs them one slice
   * earlier, because the run guard is asked only of a workflow that drains and
   * `MAX_PARALLEL` only of one that runs items side by side.
   */
  drains: boolean;
  concurrent: boolean;
  /**
   * The one line the confirmation screen leads with, e.g.
   * `implement → review, up to 10 issues`. One number, because the anchor, the
   * scope kind and the eligible counts belong to `cli/flow.mts` — a workflow
   * that could read them would eventually branch on them.
   */
  runShape: (workItems: number) => string;
  run: (context: WorkflowContext) => Promise<void>;
}
