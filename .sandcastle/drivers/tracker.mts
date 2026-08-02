// The three writes a run makes to the issue tracker, and nothing else.
//
// Every decision behind them is in `drivers/outcomes.mts`, which is pure — so
// this module has no branches worth testing and one property worth asserting:
// **there are exactly three of them, and none of them closes an issue.** A
// runner that could close a SPEC would be making the judgment
// `docs/agents/triage-labels.md` reserves for a human, and a wrongly-closed SPEC
// is far harder to notice than a wrongly-labelled open one.
//
// `gh` subcommands, never REST paths: `scope/github.mts` is the module that owns
// the endpoint vocabulary, and a second module building a path of its own is
// exactly what the boundary sweep exists to catch.
//
// A failed write **warns and does not stop the run.** These are corrections to
// bookkeeping, and losing item seven's implement→review pair because a label
// write failed would trade the expensive thing for the cheap one. The warning
// lands in the run's own scrollback, so nothing here is silent.

import { execFileSync } from "node:child_process";

/**
 * What a run may do to an issue. Three methods, deliberately named for the acts
 * rather than for `gh` — a driver holding this cannot compose a fourth.
 */
export interface Tracker {
  /** `closed ∧ unmerged`: the work never reached the workspace branch. */
  reopen: (issueNumber: number, comment: string) => void;
  /** `commits ∧ unmerged`: name the branch the work actually lives on. */
  comment: (issueNumber: number, body: string) => void;
  /** The handoff, and the only label this runner ever writes. */
  addLabel: (issueNumber: number, label: string) => void;
}

function warn(act: string, issueNumber: number, error: unknown): void {
  const detail = error instanceof Error ? error.message.split("\n")[0] : String(error);
  console.log(`  ! could not ${act} #${issueNumber}: ${detail}`);
}

/** The real tracker: `gh`, with each write reported rather than thrown. */
export function ghTracker(): Tracker {
  const gh = (act: string, issueNumber: number, args: readonly string[]): void => {
    try {
      execFileSync("gh", [...args], { stdio: ["ignore", "ignore", "pipe"] });
    } catch (error) {
      warn(act, issueNumber, error);
    }
  };

  return {
    reopen: (issueNumber, comment) =>
      gh("reopen", issueNumber, ["issue", "reopen", String(issueNumber), "--comment", comment]),
    comment: (issueNumber, body) =>
      gh("comment on", issueNumber, ["issue", "comment", String(issueNumber), "--body", body]),
    addLabel: (issueNumber, label) =>
      gh("label", issueNumber, ["issue", "edit", String(issueNumber), "--add-label", label]),
  };
}
