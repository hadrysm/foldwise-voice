// Hand-authored topology literals, not recorded GitHub responses.
//
// The question under test is *does this tree of edges produce this order*, not
// *does GitHub's JSON look like this* — and the two cases that matter most, a
// dependency cycle and a blocker sitting outside the scope, cannot be recorded
// at all without manufacturing them on the real tracker (#396). A literal also
// states its edges where a reader can see them, which a captured fixture does
// not.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  anchorRecord,
  ancestorSpec,
  buildSnapshot,
  canonicalJson,
  issueByNodeId,
  levels,
  RUN_REPORT_MARKER,
  runOrder,
  transitiveSkip,
  truncate,
  workRecord,
  type ExclusionReason,
  type IssueRecord,
  type ScopeKind,
  type WorkItem,
  type WorkScopeSnapshot,
} from "../../scope/snapshot.mts";

const REPOSITORY = "hadrysm/foldwise-voice";

function nodeIdFor(issueNumber: number): string {
  return `I_${issueNumber}`;
}

/** One node of a literal. Everything not stated takes an open, released default. */
interface Node {
  number: number;
  title?: string;
  body?: string;
  labels?: readonly string[];
  state?: "open" | "closed";
  /** Open blockers, by issue number. A number no node carries is out of scope. */
  blockedBy?: readonly number[];
  comments?: readonly { id: number; body: string }[];
  /** Authored sub-issue order. Filled in by `flatten` for a tree literal. */
  children?: readonly number[];
  parent?: number;
}

function record(node: Node): IssueRecord {
  return {
    databaseId: node.number * 1000,
    nodeId: nodeIdFor(node.number),
    number: node.number,
    repository: REPOSITORY,
    url: `https://github.com/${REPOSITORY}/issues/${node.number}`,
    title: node.title ?? `Issue ${node.number}`,
    body: node.body ?? "",
    state: node.state ?? "open",
    stateReason: null,
    labels: node.labels ?? ["ready-for-agent"],
    updatedAt: "2026-08-02T00:00:00Z",
    comments: (node.comments ?? []).map((comment) => ({
      databaseId: comment.id,
      nodeId: `IC_${comment.id}`,
      authorLogin: "hadrysm",
      body: comment.body,
      createdAt: "2026-08-02T00:00:00Z",
      updatedAt: "2026-08-02T00:00:00Z",
    })),
    parentNodeId: node.parent === undefined ? null : nodeIdFor(node.parent),
    childNodeIds: (node.children ?? []).map(nodeIdFor),
    openBlockers: (node.blockedBy ?? []).map((blocker) => ({
      nodeId: nodeIdFor(blocker),
      repository: REPOSITORY,
      number: blocker,
      url: `https://github.com/${REPOSITORY}/issues/${blocker}`,
      title: `Issue ${blocker}`,
    })),
  };
}

/** A tree literal: children nest, so the authored order is where a reader sees it. */
interface TreeNode extends Node {
  kids?: readonly TreeNode[];
}

/** Both directions of every native edge, filled in from one nesting. */
function flatten(node: TreeNode, parent?: number): Node[] {
  const kids = node.kids ?? [];
  return [
    { ...node, parent, children: kids.map((kid) => kid.number) },
    ...kids.flatMap((kid) => flatten(kid, node.number)),
  ];
}

function snapshotOf(scopeKind: ScopeKind, anchor: number | null, nodes: readonly Node[]) {
  return buildSnapshot({
    scopeKind,
    repository: REPOSITORY,
    anchorNodeId: anchor === null ? null : nodeIdFor(anchor),
    issues: nodes.map(record),
  });
}

function specSnapshot(tree: TreeNode): WorkScopeSnapshot {
  return snapshotOf("specific-spec", tree.number, flatten(tree));
}

function queueSnapshot(nodes: readonly Node[]): WorkScopeSnapshot {
  return snapshotOf("all-ready-for-agent", null, nodes);
}

/** The numbers a snapshot would actually hand a driver, in run order. */
function ordered(snapshot: WorkScopeSnapshot): readonly number[] {
  const order = runOrder(snapshot);
  assert.ok(order.ok, "expected an acyclic work list");
  return order.items.map((item) => item.number);
}

function itemsOf(snapshot: WorkScopeSnapshot): readonly WorkItem[] {
  const order = runOrder(snapshot);
  assert.ok(order.ok, "expected an acyclic work list");
  return order.items;
}

function numbersOf(snapshot: WorkScopeSnapshot, nodeIds: readonly string[]): readonly number[] {
  return nodeIds.map((nodeId) => {
    const issue = issueByNodeId(snapshot, nodeId);
    assert.ok(issue, `${nodeId} must be a member`);
    return issue.number;
  });
}

function reasonsFor(snapshot: WorkScopeSnapshot, issueNumber: number): readonly ExclusionReason[] {
  const issue = issueByNodeId(snapshot, nodeIdFor(issueNumber));
  assert.ok(issue, `#${issueNumber} must be a member`);
  return issue.eligibility.status === "eligible" ? [] : issue.eligibility.reasons;
}

// ---------------------------------------------------------------------------

describe("descendant discovery", () => {
  it("recurses through an ineligible intermediate", () => {
    // A closed or unreleased parent is still a real parent: an eligible
    // descendant can sit below it, so discovery must not prune while it walks.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, state: "closed", kids: [{ number: 420 }] },
        { number: 421, labels: [], kids: [{ number: 422 }] },
      ],
    });

    assert.deepEqual(numbersOf(snapshot, snapshot.memberNodeIds), [418, 419, 420, 421, 422]);
    assert.deepEqual(numbersOf(snapshot, snapshot.executableNodeIds), [420, 422]);
  });

  it("visits a node's own children before its next sibling", () => {
    // Depth-first pre-order, which is what makes a slice's sub-slices land with
    // the slice rather than after every sibling.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 430, kids: [{ number: 431 }, { number: 432 }] },
        { number: 419 },
      ],
    });

    assert.deepEqual(ordered(snapshot), [430, 431, 432, 419]);
  });

  it("never offers the SPEC anchor as work", () => {
    // The anchor is the controlling contract, not a work item — an agent handed
    // the SPEC itself would implement fifteen slices in one dispatch.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [{ number: 419 }],
    });

    assert.equal(snapshot.anchorNodeId, nodeIdFor(418));
    assert.ok(snapshot.memberNodeIds.includes(nodeIdFor(418)));
    assert.ok(!snapshot.executableNodeIds.includes(nodeIdFor(418)));
    assert.equal(issueByNodeId(snapshot, nodeIdFor(418))?.role, "anchor");
    assert.equal(issueByNodeId(snapshot, nodeIdFor(419))?.role, "work-item");
  });
});

describe("eligibility", () => {
  it("keeps an excluded descendant visible with its reason", () => {
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, state: "closed" },
        { number: 420, labels: [] },
        { number: 421, labels: ["ready-for-agent", "ready-for-human"] },
        { number: 422 },
      ],
    });

    assert.deepEqual(reasonsFor(snapshot, 419), ["closed"]);
    assert.deepEqual(reasonsFor(snapshot, 420), ["unreleased"]);
    assert.deepEqual(reasonsFor(snapshot, 421), ["ready-for-human"]);
    assert.deepEqual(reasonsFor(snapshot, 422), []);
    // No exclusion ever removes a node from membership; it removes it from the
    // allow-list, so the picker can still say what it is not running.
    assert.equal(snapshot.memberNodeIds.length, 5);
    assert.deepEqual(numbersOf(snapshot, snapshot.executableNodeIds), [422]);
  });

  it("lets ready-for-human override ready-for-agent rather than the reverse", () => {
    const snapshot = queueSnapshot([
      { number: 419, labels: ["ready-for-agent", "ready-for-human"] },
    ]);
    assert.deepEqual(reasonsFor(snapshot, 419), ["ready-for-human"]);
    assert.deepEqual(snapshot.executableNodeIds, []);
  });

  it("retains every reason that applies, in a fixed precedence order", () => {
    const snapshot = queueSnapshot([{ number: 419, state: "closed", labels: [] }]);
    assert.deepEqual(reasonsFor(snapshot, 419), ["closed", "unreleased"]);
  });

  it("isolates a Specific issue to its anchor", () => {
    const snapshot = snapshotOf("specific-issue", 419, [{ number: 419 }]);
    assert.deepEqual(numbersOf(snapshot, snapshot.executableNodeIds), [419]);
    assert.equal(issueByNodeId(snapshot, nodeIdFor(419))?.role, "anchor");
    assert.deepEqual(ordered(snapshot), [419]);
  });

  it("refuses a Specific issue with an open blocker", () => {
    // A single-issue scope has no set for a blocker to be inside, so every open
    // blocker is out of scope and excludes.
    const snapshot = snapshotOf("specific-issue", 419, [{ number: 419, blockedBy: [418] }]);
    assert.deepEqual(reasonsFor(snapshot, 419), ["blocked"]);
    assert.deepEqual(snapshot.executableNodeIds, []);
  });
});

describe("in-scope blockers are precedence edges", () => {
  it("orders a dependent rather than excluding it", () => {
    // Without this a blocked_by-chained SPEC resolves to exactly one eligible
    // descendant per run, and waves cannot exist at all.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, blockedBy: [420] },
        { number: 420 },
      ],
    });

    assert.deepEqual(reasonsFor(snapshot, 419), []);
    assert.deepEqual(ordered(snapshot), [420, 419]);
  });

  it("excludes on a blocker outside the set", () => {
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, blockedBy: [999] },
        { number: 420, blockedBy: [421] },
        { number: 421, labels: [] },
      ],
    });

    // #999 is in no snapshot at all; #421 is a member this run will never run.
    assert.deepEqual(reasonsFor(snapshot, 419), ["blocked"]);
    assert.deepEqual(reasonsFor(snapshot, 420), ["blocked"]);
    assert.deepEqual(snapshot.executableNodeIds, []);
  });

  it("propagates that exclusion down the chain", () => {
    // #421 is ineligible, so #420 will not run, so #419 has no foundation
    // either — one pass over the candidates is not enough.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, blockedBy: [420] },
        { number: 420, blockedBy: [421] },
        { number: 421, labels: [] },
        { number: 422 },
      ],
    });

    assert.deepEqual(reasonsFor(snapshot, 419), ["blocked"]);
    assert.deepEqual(reasonsFor(snapshot, 420), ["blocked"]);
    // An independent item is untouched by its neighbour's chain.
    assert.deepEqual(numbersOf(snapshot, snapshot.executableNodeIds), [422]);
  });
});

describe("run order", () => {
  it("keys the topological sort on authored order", () => {
    // Authored order is the one signal carrying maintainer intent — GitHub's
    // reprioritise endpoint edits it, while an issue number is creation time.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 433 },
        { number: 430 },
        { number: 419, blockedBy: [430] },
        { number: 425 },
      ],
    });

    assert.deepEqual(ordered(snapshot), [433, 430, 419, 425]);
  });

  it("tie-breaks the repository-wide queue on ascending number", () => {
    // No parent means no authored order, so the only stable signal left is the
    // number.
    const snapshot = queueSnapshot([{ number: 42 }, { number: 7 }, { number: 19 }]);
    assert.deepEqual(ordered(snapshot), [7, 19, 42]);
  });

  it("reports a dependency cycle instead of an order", () => {
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, blockedBy: [420] },
        { number: 420, blockedBy: [419] },
        { number: 421 },
      ],
    });

    const order = runOrder(snapshot);
    assert.equal(order.ok, false);
    assert.ok(!order.ok);
    assert.deepEqual([...order.cycle].sort((a, b) => a - b), [419, 420]);
  });
});

describe("truncation", () => {
  it("takes a prefix of the sorted order, so no blocker is ever cut", () => {
    // Applied after the sort, never before: a prefix of a topological order
    // always contains its own blockers, and a filter applied first would not.
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419, blockedBy: [420] },
        { number: 420 },
        { number: 421 },
      ],
    });

    const items = itemsOf(snapshot);
    assert.deepEqual(
      truncate(items, 2).map((item) => item.number),
      [420, 419],
    );
    assert.deepEqual(truncate(items, 0), []);
    assert.deepEqual(truncate(items, 99).length, 3);
  });
});

describe("levels", () => {
  const tail = () =>
    specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 428 },
        { number: 429 },
        { number: 430 },
        { number: 431 },
        { number: 432, blockedBy: [428] },
      ],
    });

  function shape(snapshot: WorkScopeSnapshot, skipped: ReadonlySet<string> = new Set()) {
    return levels(snapshot, itemsOf(snapshot), skipped).map((level) =>
      level.map((item) => item.number),
    );
  }

  it("puts every unblocked item on the first level", () => {
    assert.deepEqual(shape(tail()), [[428, 429, 430, 431], [432]]);
  });

  it("shrinks when a transitive skip lands", () => {
    // Levels are a pure function of (list, accumulated skip set), recomputed at
    // each wave boundary — freezing them would dispatch #432 onto a foundation
    // #428 never laid.
    const snapshot = tail();
    const skipped = transitiveSkip(snapshot, [nodeIdFor(428)]);
    assert.deepEqual([...skipped].sort(), [nodeIdFor(428), nodeIdFor(432)].sort());
    assert.deepEqual(shape(snapshot, skipped), [[429, 430, 431]]);
  });

  it("treats a blocker that already left the pending set as satisfied", () => {
    // Wave two is cut after wave one merged: #428 is gone from the pending list
    // and #432 must be ready, not blocked by an absent id.
    const snapshot = tail();
    const pending = itemsOf(snapshot).filter((item) => item.number !== 428);
    assert.deepEqual(
      levels(snapshot, pending).map((level) => level.map((item) => item.number)),
      [[429, 430, 431, 432]],
    );
  });
});

describe("the transitive skip set", () => {
  const chain = () =>
    specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [
        { number: 419 },
        { number: 420, blockedBy: [419] },
        { number: 421, blockedBy: [420] },
        { number: 422 },
      ],
    });

  it("drops everything blocked by the failure, through a chain", () => {
    const skipped = transitiveSkip(chain(), [nodeIdFor(419)]);
    assert.deepEqual([...skipped].sort(), [419, 420, 421].map(nodeIdFor).sort());
  });

  it("leaves an independent item alone", () => {
    assert.ok(!transitiveSkip(chain(), [nodeIdFor(419)]).has(nodeIdFor(422)));
  });

  it("accumulates across waves", () => {
    const snapshot = chain();
    const first = transitiveSkip(snapshot, [nodeIdFor(422)]);
    const second = transitiveSkip(snapshot, [nodeIdFor(420)], first);
    assert.deepEqual([...second].sort(), [420, 421, 422].map(nodeIdFor).sort());
  });
});

describe("comment normalization", () => {
  it("drops the run's own report and keeps a bounce", () => {
    // Otherwise run five reads runs one through four as evidence about the
    // work. An item-level bounce comment carries no marker and is real review
    // context, so it survives.
    const snapshot = queueSnapshot([
      {
        number: 419,
        comments: [
          { id: 30, body: "Reviewer: acceptance criterion 3 is unmet." },
          { id: 10, body: `${RUN_REPORT_MARKER}\n\n## Sandcastle run\n\n#419 approved` },
          { id: 20, body: "A maintainer clarification." },
        ],
      },
    ]);

    const issue = issueByNodeId(snapshot, nodeIdFor(419));
    assert.deepEqual(
      issue?.comments.map((comment) => comment.databaseId),
      [20, 30],
    );
  });

  it("only matches the marker on the first line", () => {
    const snapshot = queueSnapshot([
      { number: 419, comments: [{ id: 10, body: `Quoting the runner:\n${RUN_REPORT_MARKER}` }] },
    ]);
    assert.equal(issueByNodeId(snapshot, nodeIdFor(419))?.comments.length, 1);
  });

  it("sorts labels lexically and leaves authored child order alone", () => {
    const snapshot = specSnapshot({
      number: 418,
      labels: ["spec", "ready-for-agent"],
      kids: [{ number: 430 }, { number: 419 }],
    });

    const anchor = issueByNodeId(snapshot, nodeIdFor(418));
    assert.deepEqual(anchor?.labels, ["ready-for-agent", "spec"]);
    assert.deepEqual(anchor?.childNodeIds, [nodeIdFor(430), nodeIdFor(419)]);
  });
});

describe("the canonical digest", () => {
  const nodes: readonly Node[] = [
    { number: 419, comments: [{ id: 10, body: "context" }] },
    { number: 420 },
  ];

  it("is a sha256 over the snapshot's own payload", () => {
    assert.match(queueSnapshot(nodes).snapshotId, /^sha256:[0-9a-f]{64}$/);
  });

  it("does not depend on the order keys were written in", () => {
    // The digest is what a pre-dispatch revalidation compares, so it has to be
    // a function of the state and not of how the fetch layer happened to build
    // its objects.
    const forward = queueSnapshot(nodes);
    const reversed = buildSnapshot({
      scopeKind: "all-ready-for-agent",
      repository: REPOSITORY,
      anchorNodeId: null,
      issues: nodes.map((node) => reverseKeys(record(node)) as IssueRecord),
    });
    assert.equal(reversed.snapshotId, forward.snapshotId);
  });

  it("changes when any observed byte changes", () => {
    const baseline = queueSnapshot(nodes).snapshotId;
    assert.notEqual(
      queueSnapshot([
        { number: 419, comments: [{ id: 10, body: "context, amended" }] },
        { number: 420 },
      ]).snapshotId,
      baseline,
    );
    assert.notEqual(queueSnapshot([{ number: 419 }, { number: 420 }]).snapshotId, baseline);
  });

  it("serializes every object with its keys sorted", () => {
    assert.equal(canonicalJson({ b: 1, a: [{ d: 2, c: 3 }] }), '{"a":[{"c":3,"d":2}],"b":1}');
  });
});

/** The same value with every object's keys inserted in the opposite order. */
function reverseKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(reverseKeys);
  if (value === null || typeof value !== "object") return value;
  const entries = Object.entries(value as Record<string, unknown>).reverse();
  return Object.fromEntries(entries.map(([key, entry]) => [key, reverseKeys(entry)]));
}

// ---------------------------------------------------------------------------
// What a prompt is told
// ---------------------------------------------------------------------------

const SPEC_TREE: TreeNode = {
  number: 418,
  title: "Universal Work scope",
  body: "## Acceptance criteria\n\n- [ ] every slice closed",
  labels: ["ready-for-agent", "spec"],
  kids: [
    {
      number: 422,
      title: "Flip the contract",
      body: "Fenced prose:\n\n```ts\nconst x = 1;\n```",
      comments: [
        { id: 10, body: "Review bounce: criterion 3 is unmet" },
        { id: 11, body: `${RUN_REPORT_MARKER}\nRun report: 4 of 15 settled` },
      ],
    },
  ],
};

describe("the record a work item's prompt is handed", () => {
  const snapshot = specSnapshot(SPEC_TREE);
  const item = workRecord(snapshot, nodeIdFor(422));

  it("carries the issue exactly as the eligibility decision saw it", () => {
    assert.equal(item.number, 422);
    assert.equal(item.title, "Flip the contract");
    assert.equal(item.body, "Fenced prose:\n\n```ts\nconst x = 1;\n```");
    assert.deepEqual(item.labels, ["ready-for-agent"]);
  });

  it("carries comment bodies, so a bounce reaches the next attempt", () => {
    assert.deepEqual(item.comments, ["Review bounce: criterion 3 is unmet"]);
  });

  it("drops the run's own reports, so a fifth run does not read four of them", () => {
    assert.equal(
      item.comments.some((comment) => comment.includes(RUN_REPORT_MARKER)),
      false,
    );
  });

  it("nests the ancestor SPEC, which is the contract the item sits inside", () => {
    assert.deepEqual(item.spec, {
      number: 418,
      title: "Universal Work scope",
      body: "## Acceptance criteria\n\n- [ ] every slice closed",
      labels: ["ready-for-agent", "spec"],
    });
  });

  it("names no edge at all, in the item or in its SPEC", () => {
    // An implementer told what depends on it has a motive to widen its own work,
    // and a reviewer told the same has a motive to judge work it was not shown.
    for (const record of [item, item.spec]) {
      assert.deepEqual(Object.keys(record ?? {}).filter((key) => key.includes("Node")), []);
      assert.equal("openBlockers" in (record ?? {}), false);
    }
  });

  it("survives a splice into a fenced block, because it is JSON", () => {
    // The item's own body carries a fence; encoded, every string value is one
    // line with escaped newlines, so no ``` can start a line of the arg.
    const encoded = JSON.stringify(item);
    assert.equal(
      encoded.split("\n").some((line) => line.startsWith("```")),
      false,
    );
  });

  it("finds the SPEC through an intermediate parent that is not one", () => {
    const nested = specSnapshot({
      ...SPEC_TREE,
      kids: [{ number: 430, labels: ["ready-for-agent"], kids: [{ number: 431 }] }],
    });
    assert.equal(workRecord(nested, nodeIdFor(431)).spec?.number, 418);
  });

  it("says `null` rather than guessing at a SPEC nobody read", () => {
    // The repository-wide queue has no tree, so an ancestor that was never
    // fetched is not one this module may invent.
    assert.equal(workRecord(queueSnapshot([{ number: 419 }]), nodeIdFor(419)).spec, null);
    assert.equal(ancestorSpec(snapshot, nodeIdFor(418)), undefined);
  });

  it("refuses an item outside the frozen snapshot", () => {
    assert.throws(() => workRecord(snapshot, nodeIdFor(999)), /outside the snapshot/);
  });
});

describe("the record a whole-branch prompt is handed", () => {
  it("is the anchor's brief when the scope named a target", () => {
    assert.deepEqual(anchorRecord(specSnapshot(SPEC_TREE)), {
      number: 418,
      title: "Universal Work scope",
      body: "## Acceptance criteria\n\n- [ ] every slice closed",
      labels: ["ready-for-agent", "spec"],
    });
  });

  it("is `null` under a repository-wide scope, which has no anchor", () => {
    assert.equal(anchorRecord(queueSnapshot([{ number: 419 }])), null);
    // Substituted as a literal, never as an absent key: Sandcastle fails loudly
    // on a `{{KEY}}` it has no value for.
    assert.equal(JSON.stringify(anchorRecord(queueSnapshot([{ number: 419 }]))), "null");
  });
});
