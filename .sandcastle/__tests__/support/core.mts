// A `RunCore` and a `Tracker` with nothing behind them.
//
// `RunCore` is the whole of a driver's reach and `Tracker` is the whole of what
// it may write, so a plain object for each is a complete substitute for the
// runner — no network, no login, no git repository, no agent. That is the payoff
// #405 predicted for moving the loop off the workflow and #423 for moving the
// judgment into `drivers/outcomes.mts`: the loop, the cascade, the drift table
// and the handoff are all observable without any of the expensive parts.
//
// You only fake what is expensive. Everything these stand in for costs money, a
// provider login or a live tracker; the decisions themselves are pure and are
// asserted directly in `__tests__/drivers/outcomes.test.mts`.

import assert from "node:assert/strict";
import type { Dispatch } from "../../contract.mts";
import type { RunCore } from "../../drivers/core.mts";
import type { Tracker } from "../../drivers/tracker.mts";
import { repo } from "../../repo.mts";
import type { Revalidation } from "../../scope/github.mts";
import {
  issueByNodeId,
  type HandoffState,
  type WorkItem,
  type WorkScopeSnapshot,
} from "../../scope/snapshot.mts";

export const FAKE_WORKSPACE_BRANCH = "t3code/fake-workspace";

/** One write the run made to the tracker. */
export interface TrackerWrite {
  readonly act: "reopen" | "comment" | "addLabel";
  readonly issueNumber: number;
  readonly body: string;
}

export function fakeTracker(): { tracker: Tracker; writes: TrackerWrite[] } {
  const writes: TrackerWrite[] = [];
  return {
    writes,
    tracker: {
      reopen: (issueNumber, body) => writes.push({ act: "reopen", issueNumber, body }),
      comment: (issueNumber, body) => writes.push({ act: "comment", issueNumber, body }),
      addLabel: (issueNumber, body) => writes.push({ act: "addLabel", issueNumber, body }),
    },
  };
}

/** One dispatch the run made, and which item it was scoped to. */
export interface DispatchCall {
  readonly issueNumber: number;
  readonly agentId: string;
}

export interface FakeCoreOptions {
  /** Scripted pre-dispatch answers, by issue number. Anything unlisted is `ok`. */
  readonly revalidations?: Readonly<Record<number, Revalidation>>;
  /** Issues still open when their item settled — i.e. the bounces. */
  readonly openAtSettle?: readonly number[];
  /** Commits each item's body leaves behind. Anything unlisted leaves one. */
  readonly commits?: Readonly<Record<number, number>>;
  /** What the end-of-run handoff read finds, or `null` for no anchor. */
  readonly handoff?: HandoffState | null;
  /** Make that read fail instead, the way a rate limit would. */
  readonly handoffFails?: string;
}

export interface FakeRunCore {
  readonly core: RunCore;
  readonly dispatches: DispatchCall[];
}

/**
 * A core over a hand-authored snapshot.
 *
 * `commitsSince` answers for whichever item the driver most recently asked a
 * dispatch for, which holds because a driver captures its base SHA and then
 * scopes its dispatch before running anything — the assertion below is there so
 * a driver that ever stops doing that fails loudly rather than silently
 * attributing one item's commits to another.
 */
export function fakeCore(
  scope: WorkScopeSnapshot,
  work: readonly WorkItem[],
  options: FakeCoreOptions = {},
): FakeRunCore {
  const dispatches: DispatchCall[] = [];
  let current: WorkItem | null = null;

  const scoped = (item: WorkItem | null): Dispatch => {
    return (agent) => {
      dispatches.push({ issueNumber: item?.number ?? 0, agentId: agent.id });
      return Promise.resolve({ commits: [{ sha: "commit-1" }], baseSha: "sha-1" });
    };
  };

  return {
    dispatches,
    core: {
      work,
      scope,
      repo,
      forItem: (item) => {
        current = item;
        return scoped(item);
      },
      forBranch: () => scoped(null),
      git: {
        branch: FAKE_WORKSPACE_BRANCH,
        headSha: () => "base-sha",
        commitsSince: () => {
          assert.ok(current, "a driver counted commits before scoping a dispatch to an item");
          return options.commits?.[current.number] ?? 1;
        },
      },
      issues: {
        revalidate: (item) => {
          const scripted = options.revalidations?.[item.number];
          if (scripted) return Promise.resolve(scripted);
          const frozen = issueByNodeId(scope, item.nodeId);
          assert.ok(frozen, `revalidated an item outside the snapshot: #${item.number}`);
          return Promise.resolve({ status: "ok", issue: frozen });
        },
        liveState: (item) =>
          Promise.resolve({
            number: item.number,
            // Closed by default: the implementer closes its own issue, so an
            // open one at settle is the reviewer's bounce.
            state: options.openAtSettle?.includes(item.number) ? "open" : "closed",
            labels: ["ready-for-agent"],
          }),
        handoff: () =>
          options.handoffFails === undefined
            ? Promise.resolve(options.handoff ?? null)
            : Promise.reject(new Error(options.handoffFails)),
      },
    },
  };
}
