// Hand-authored Work scope snapshots, for the tests that need a *resolved*
// scope but are not testing resolution.
//
// `__tests__/scope/snapshot.test.mts` owns the question "does this tree of
// edges produce this order"; everything here exists so the picker, the store and
// the runner can be asserted against a scope without going near GitHub. Not a
// `.test.mts` file, so the runner's glob leaves it alone.

import {
  buildSnapshot,
  type IssueRecord,
  type WorkItem,
  type WorkScopeSnapshot,
} from "../../scope/snapshot.mts";

export const FIXTURE_REPOSITORY = "hadrysm/foldwise-voice";

export function fixtureNodeId(issueNumber: number): string {
  return `I_${issueNumber}`;
}

/** The item a driver would hand a body, for the tests that only need one. */
export function fakeItem(issueNumber: number): WorkItem {
  return {
    nodeId: fixtureNodeId(issueNumber),
    number: issueNumber,
    title: `Issue ${issueNumber}`,
    url: `https://github.com/${FIXTURE_REPOSITORY}/issues/${issueNumber}`,
  };
}

/** One issue of a literal. Everything unstated takes an open, released default. */
export interface FixtureIssue {
  number: number;
  title?: string;
  labels?: readonly string[];
  state?: "open" | "closed";
  /** Open blockers, by issue number. A number no fixture issue carries is out of scope. */
  blockedBy?: readonly number[];
  /** Authored sub-issue order. */
  children?: readonly number[];
  parent?: number;
}

export function fixtureRecord(issue: FixtureIssue): IssueRecord {
  return {
    databaseId: issue.number * 1000,
    nodeId: fixtureNodeId(issue.number),
    number: issue.number,
    repository: FIXTURE_REPOSITORY,
    url: `https://github.com/${FIXTURE_REPOSITORY}/issues/${issue.number}`,
    title: issue.title ?? `Issue ${issue.number}`,
    body: "",
    state: issue.state ?? "open",
    stateReason: null,
    labels: issue.labels ?? ["ready-for-agent"],
    updatedAt: "2026-08-02T00:00:00Z",
    comments: [],
    parentNodeId: issue.parent === undefined ? null : fixtureNodeId(issue.parent),
    childNodeIds: (issue.children ?? []).map(fixtureNodeId),
    openBlockers: (issue.blockedBy ?? []).map((blocker) => ({
      nodeId: fixtureNodeId(blocker),
      repository: FIXTURE_REPOSITORY,
      number: blocker,
      url: `https://github.com/${FIXTURE_REPOSITORY}/issues/${blocker}`,
      title: `Issue ${blocker}`,
    })),
  };
}

/** A SPEC and its descendants, with the anchor's authored order filled in. */
export function specSnapshot(
  anchor: FixtureIssue,
  descendants: readonly FixtureIssue[],
): WorkScopeSnapshot {
  return buildSnapshot({
    scopeKind: "specific-spec",
    repository: FIXTURE_REPOSITORY,
    anchorNodeId: fixtureNodeId(anchor.number),
    issues: [
      fixtureRecord({
        labels: ["ready-for-agent", "spec"],
        ...anchor,
        children: anchor.children ?? descendants.map((issue) => issue.number),
      }),
      ...descendants.map((issue) => fixtureRecord({ parent: anchor.number, ...issue })),
    ],
  });
}

export function issueSnapshot(issue: FixtureIssue): WorkScopeSnapshot {
  return buildSnapshot({
    scopeKind: "specific-issue",
    repository: FIXTURE_REPOSITORY,
    anchorNodeId: fixtureNodeId(issue.number),
    issues: [fixtureRecord(issue)],
  });
}

export function queueSnapshot(issues: readonly FixtureIssue[]): WorkScopeSnapshot {
  return buildSnapshot({
    scopeKind: "all-ready-for-agent",
    repository: FIXTURE_REPOSITORY,
    anchorNodeId: null,
    issues: issues.map(fixtureRecord),
  });
}
