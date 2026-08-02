// The fetch layer, against a fake transport.
//
// The transport is the only seam this module has, and faking it is what makes
// the abort paths testable at all: "the third comment page returned 403" is not
// a state anyone can arrange on real GitHub, and it is exactly the state that
// must never become an empty comment list. The recorded canary beside this file
// covers the other half — whether GitHub's real bytes still look like this.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  flattenPages,
  ghArgs,
  httpFailure,
  parseTarget,
  resolveScope,
  revalidate,
  ScopeError,
  type GitHubRequest,
  type GitHubTransport,
  type ScopeOutcome,
} from "../../scope/github.mts";
import { runOrder, type WorkScope, type WorkScopeSnapshot } from "../../scope/snapshot.mts";

const REPOSITORY = "hadrysm/foldwise-voice";

// ---------------------------------------------------------------------------
// A fake GitHub
// ---------------------------------------------------------------------------

interface Relationship {
  readonly number: number;
  /** `/dependencies/blocked_by` returns closed relationships too. */
  readonly state?: "open" | "closed";
  readonly repository?: string;
}

/** One issue on the fake tracker. Everything unstated takes an open, released default. */
interface Fixture {
  readonly number: number;
  readonly state?: "open" | "closed";
  readonly labels?: readonly string[];
  readonly title?: string;
  readonly repository?: string;
  readonly children?: readonly number[];
  readonly blockedBy?: readonly Relationship[];
  readonly comments?: readonly { readonly id: number; readonly body: string }[];
  readonly parent?: number;
  readonly pullRequest?: boolean;
}

function issueJson(fixture: Fixture): Record<string, unknown> {
  const repository = fixture.repository ?? REPOSITORY;
  return {
    id: fixture.number * 1000,
    node_id: `I_${fixture.number}`,
    number: fixture.number,
    repository_url: `https://api.github.com/repos/${repository}`,
    html_url: `https://github.com/${repository}/issues/${fixture.number}`,
    title: fixture.title ?? `Issue ${fixture.number}`,
    body: null,
    state: fixture.state ?? "open",
    state_reason: null,
    labels: (fixture.labels ?? ["ready-for-agent"]).map((name) => ({ name })),
    updated_at: "2026-08-02T00:00:00Z",
    ...(fixture.pullRequest === true ? { pull_request: { url: "https://example.invalid" } } : {}),
  };
}

function commentJson(comment: { readonly id: number; readonly body: string }): unknown {
  return {
    id: comment.id,
    node_id: `IC_${comment.id}`,
    user: { login: "hadrysm" },
    body: comment.body,
    created_at: "2026-08-02T00:00:00Z",
    updated_at: "2026-08-02T00:00:00Z",
  };
}

const ISSUE = /^repos\/(?<repo>[^?]+)\/issues\/(?<number>\d+)$/;
const SUB_ISSUES = /^repos\/[^?]+\/issues\/(?<number>\d+)\/sub_issues\?/;
const COMMENTS = /^repos\/[^?]+\/issues\/(?<number>\d+)\/comments\?/;
const BLOCKERS = /^repos\/[^?]+\/issues\/(?<number>\d+)\/dependencies\/blocked_by\?/;
const PARENT = /^repos\/[^?]+\/issues\/(?<number>\d+)\/parent$/;
const QUEUE = /^repos\/[^?]+\/issues\?/;

function notFound(path: string): ScopeError {
  return new ScopeError("not-found", `GitHub returned 404 for \`${path}\` — not found or inaccessible.`);
}

interface World {
  readonly transport: GitHubTransport;
  readonly requests: readonly GitHubRequest[];
}

/**
 * A GitHub whose whole contents are the fixtures given. `failures` fails one
 * exact path, which is how a single mid-tree page is made to fail.
 */
function world(
  fixtures: readonly Fixture[],
  failures: Readonly<Record<string, ScopeError>> = {},
): World {
  const byNumber = new Map(fixtures.map((fixture) => [fixture.number, fixture]));
  const requests: GitHubRequest[] = [];

  const find = (raw: string | undefined, path: string): Fixture => {
    const fixture = byNumber.get(Number(raw));
    if (!fixture) throw notFound(path);
    return fixture;
  };

  const transport: GitHubTransport = async (request) => {
    requests.push(request);
    const failure = failures[request.path];
    if (failure) throw failure;
    const { path } = request;

    const parent = PARENT.exec(path);
    if (parent) {
      const fixture = find(parent.groups?.["number"], path);
      if (fixture.parent === undefined) throw notFound(path);
      return issueJson(find(String(fixture.parent), path));
    }

    const subIssues = SUB_ISSUES.exec(path);
    if (subIssues) {
      const fixture = find(subIssues.groups?.["number"], path);
      return (fixture.children ?? []).map((child) => issueJson(find(String(child), path)));
    }

    const comments = COMMENTS.exec(path);
    if (comments) {
      return (find(comments.groups?.["number"], path).comments ?? []).map(commentJson);
    }

    const blockers = BLOCKERS.exec(path);
    if (blockers) {
      return (find(blockers.groups?.["number"], path).blockedBy ?? []).map((relationship) =>
        issueJson({
          number: relationship.number,
          state: relationship.state ?? "open",
          repository: relationship.repository,
        }),
      );
    }

    const issue = ISSUE.exec(path);
    if (issue) return issueJson(find(issue.groups?.["number"], path));

    if (QUEUE.test(path)) {
      return fixtures
        .filter((fixture) => (fixture.labels ?? ["ready-for-agent"]).includes("ready-for-agent"))
        .filter((fixture) => (fixture.state ?? "open") === "open")
        .map(issueJson);
    }

    throw notFound(path);
  };

  return { transport, requests };
}

function expectResolved(outcome: ScopeOutcome): WorkScopeSnapshot {
  assert.equal(outcome.ok, true, outcome.ok ? "" : `resolution failed: ${outcome.message}`);
  if (!outcome.ok) throw new Error("unreachable");
  return outcome.snapshot;
}

function expectFailure(outcome: ScopeOutcome): Extract<ScopeOutcome, { ok: false }> {
  assert.equal(outcome.ok, false, "expected the scope to be refused");
  if (outcome.ok) throw new Error("unreachable");
  // The property the whole module exists to hold: a failure is never a scope
  // with nothing in it.
  assert.equal("snapshot" in outcome, false);
  return outcome;
}

const SPEC_SCOPE: WorkScope = { kind: "specific-spec", target: "418" };

/** The shape most tests vary: a SPEC with three released slices. */
const SIMPLE_SPEC: readonly Fixture[] = [
  { number: 418, labels: ["ready-for-agent", "spec"], children: [419, 420, 421] },
  { number: 419, parent: 418 },
  { number: 420, parent: 418, blockedBy: [{ number: 419 }] },
  { number: 421, parent: 418 },
];

// ---------------------------------------------------------------------------

describe("parseTarget", () => {
  it("accepts a bare positive number", () => {
    assert.equal(parseTarget("418"), 418);
    assert.equal(parseTarget("  418  "), 418);
  });

  it("accepts an exact same-repository issue URL", () => {
    assert.equal(parseTarget(`https://github.com/${REPOSITORY}/issues/418`), 418);
    assert.equal(parseTarget(`https://github.com/${REPOSITORY}/issues/418/`), 418);
    // Owner and repository are case-insensitive path parameters on GitHub.
    assert.equal(parseTarget("https://github.com/Hadrysm/FoldWise-Voice/issues/418"), 418);
  });

  it("rejects a number that is not a positive issue number", () => {
    for (const raw of ["0", "-3", "", "   ", "12.5", "#418"]) {
      assert.throws(() => parseTarget(raw), (error: unknown) => {
        assert.ok(error instanceof ScopeError);
        assert.equal(error.reason, "invalid-target");
        return true;
      });
    }
  });

  it("rejects a foreign-repository URL", () => {
    assert.throws(
      () => parseTarget("https://github.com/cli/cli/issues/1"),
      /names cli\/cli rather than/,
    );
  });

  it("rejects a pull-request URL", () => {
    assert.throws(
      () => parseTarget(`https://github.com/${REPOSITORY}/pull/434`),
      /not an issue URL/,
    );
  });

  it("rejects a URL that is not plainly a github.com issue", () => {
    const cases = [
      `http://github.com/${REPOSITORY}/issues/418`,
      `https://github.example.com/${REPOSITORY}/issues/418`,
      `https://user:token@github.com/${REPOSITORY}/issues/418`,
      `https://github.com:8443/${REPOSITORY}/issues/418`,
      `https://github.com/${REPOSITORY}/issues/418?x=1`,
      `https://github.com/${REPOSITORY}/issues/418#comment`,
      `https://github.com/${REPOSITORY}/issues/0`,
      `https://github.com/${REPOSITORY}/issues`,
    ];
    for (const raw of cases) {
      assert.throws(() => parseTarget(raw), new RegExp("is not a target"), raw);
    }
  });
});

describe("the gh transport's request shape", () => {
  it("pins the media type and the API version on every read", () => {
    const args = ghArgs({ path: "repos/o/r/issues/1", paginate: false });
    assert.deepEqual(args, [
      "api",
      "-H",
      "Accept: application/vnd.github+json",
      "-H",
      "X-GitHub-Api-Version: 2026-03-10",
      "repos/o/r/issues/1",
    ]);
  });

  it("follows every page of a list read", () => {
    const args = ghArgs({ path: "repos/o/r/issues/1/comments?per_page=100", paginate: true });
    assert.ok(args.includes("--paginate"));
    assert.ok(args.includes("--slurp"));
  });

  it("flattens slurped pages into one list, and refuses anything else", () => {
    assert.deepEqual(flattenPages([[1, 2], [3]], "p"), [1, 2, 3]);
    assert.deepEqual(flattenPages([], "p"), []);
    assert.throws(() => flattenPages({ message: "Not Found" }, "p"), /is not a list/);
    assert.throws(() => flattenPages([[1], 2], "p"), /A page of/);
  });

  it("keeps 404 ambiguous, and separates denial from unavailability", () => {
    const missing = httpFailure("p", "gh: Not Found (HTTP 404)", "");
    assert.equal(missing.reason, "not-found");
    assert.match(missing.message, /not found or inaccessible/);

    assert.equal(httpFailure("p", "gh: Bad credentials (HTTP 401)", "").reason, "denied");
    assert.equal(httpFailure("p", "gh: Forbidden (HTTP 403)", "").reason, "denied");
    assert.equal(httpFailure("p", "gh: rate limit (HTTP 429)", "").reason, "denied");
    assert.equal(httpFailure("p", "gh: Bad gateway (HTTP 502)", "").reason, "unavailable");
    assert.equal(httpFailure("p", "", "spawn ENOENT").reason, "unavailable");
  });
});

describe("resolving a Specific SPEC", () => {
  it("freezes the tree in authored order, with the anchor never executable", async () => {
    const { transport } = world(SIMPLE_SPEC);
    const snapshot = expectResolved(await resolveScope(SPEC_SCOPE, transport));

    assert.equal(snapshot.repository, REPOSITORY);
    assert.equal(snapshot.anchorNodeId, "I_418");
    assert.deepEqual(snapshot.memberNodeIds, ["I_418", "I_419", "I_420", "I_421"]);
    assert.deepEqual(snapshot.executableNodeIds, ["I_419", "I_420", "I_421"]);
    assert.match(snapshot.snapshotId, /^sha256:[0-9a-f]{64}$/);
  });

  it("paginates every list read, at GitHub's maximum page size", async () => {
    const { transport, requests } = world(SIMPLE_SPEC);
    await resolveScope(SPEC_SCOPE, transport);

    const lists = requests.filter((request) => request.path.includes("?"));
    assert.ok(lists.length > 0);
    for (const request of lists) {
      assert.equal(request.paginate, true, request.path);
      assert.ok(request.path.includes("per_page=100"), request.path);
    }
    // Every issue's comments and blockers, not only the candidates.
    for (const number of [418, 419, 420, 421]) {
      assert.ok(requests.some((r) => r.path === `repos/${REPOSITORY}/issues/${number}/comments?per_page=100`));
      assert.ok(
        requests.some(
          (r) => r.path === `repos/${REPOSITORY}/issues/${number}/dependencies/blocked_by?per_page=100`,
        ),
      );
    }
  });

  it("walks through ineligible intermediates to reach an eligible descendant", async () => {
    const { transport } = world([
      { number: 418, labels: ["ready-for-agent", "spec"], children: [419] },
      // Closed, unreleased and human-owned, all at once — and still walked.
      { number: 419, parent: 418, state: "closed", labels: ["ready-for-human"], children: [420] },
      { number: 420, parent: 419, children: [421] },
      { number: 421, parent: 420, labels: [] },
      { number: 422, parent: 420 },
    ]);
    const snapshot = expectResolved(await resolveScope(SPEC_SCOPE, transport));

    assert.deepEqual(snapshot.memberNodeIds, ["I_418", "I_419", "I_420", "I_421"]);
    assert.deepEqual(snapshot.executableNodeIds, ["I_420"]);
  });

  it("treats a closed blocker relationship as no blocker at all", async () => {
    const { transport } = world([
      { number: 418, labels: ["ready-for-agent", "spec"], children: [419, 420] },
      { number: 419, parent: 418, blockedBy: [{ number: 999, state: "closed" }] },
      { number: 420, parent: 418, blockedBy: [{ number: 998, state: "open" }] },
    ]);
    const snapshot = expectResolved(await resolveScope(SPEC_SCOPE, transport));

    const [, released, gated] = snapshot.issues;
    assert.deepEqual(released?.openBlockers, []);
    assert.deepEqual(released?.eligibility, { status: "eligible" });
    assert.deepEqual(gated?.openBlockers.map((blocker) => blocker.number), [998]);
    // #998 is outside the scope, so it excludes rather than orders.
    assert.deepEqual(gated?.eligibility, { status: "excluded", reasons: ["blocked"] });
  });

  it("orders an in-scope blocker chain rather than excluding it", async () => {
    const { transport } = world(SIMPLE_SPEC);
    const snapshot = expectResolved(await resolveScope(SPEC_SCOPE, transport));
    const order = runOrder(snapshot);

    assert.equal(order.ok, true);
    if (!order.ok) return;
    assert.deepEqual(order.items.map((item) => item.number), [419, 420, 421]);
  });

  it("carries an open cross-repository blocker as a gate", async () => {
    const { transport } = world([
      { number: 418, labels: ["ready-for-agent", "spec"], children: [419] },
      { number: 419, parent: 418, blockedBy: [{ number: 7, repository: "cli/cli" }] },
    ]);
    const snapshot = expectResolved(await resolveScope(SPEC_SCOPE, transport));

    assert.deepEqual(snapshot.executableNodeIds, []);
    assert.equal(snapshot.issues[1]?.openBlockers[0]?.repository, "cli/cli");
  });
});

describe("failing closed", () => {
  it("aborts on a cross-repository descendant rather than dropping the subtree", async () => {
    const { transport } = world([
      { number: 418, labels: ["ready-for-agent", "spec"], children: [419] },
      { number: 419, parent: 418, repository: "cli/cli" },
    ]);
    const failure = expectFailure(await resolveScope(SPEC_SCOPE, transport));

    assert.equal(failure.reason, "cross-repository");
    assert.match(failure.message, /cli\/cli/);
  });

  it("aborts on a child reached twice", async () => {
    const { transport } = world([
      { number: 418, labels: ["ready-for-agent", "spec"], children: [419, 420] },
      { number: 419, parent: 418, children: [420] },
      { number: 420, parent: 418 },
    ]);
    const failure = expectFailure(await resolveScope(SPEC_SCOPE, transport));

    assert.equal(failure.reason, "malformed-tree");
  });

  it("aborts when the target is a pull request", async () => {
    const { transport } = world([{ number: 434, pullRequest: true }]);
    const failure = expectFailure(
      await resolveScope({ kind: "specific-issue", target: "434" }, transport),
    );

    assert.equal(failure.reason, "not-an-issue");
    assert.match(failure.message, /pull request/);
  });

  it("aborts when the canonical read landed on a different issue", async () => {
    const transport: GitHubTransport = async () =>
      issueJson({ number: 999, title: "Transferred elsewhere" });
    const failure = expectFailure(
      await resolveScope({ kind: "specific-issue", target: "418" }, transport),
    );

    assert.equal(failure.reason, "not-an-issue");
    assert.match(failure.message, /redirected/);
  });

  it("aborts on a failure at any read, and never returns an empty scope", async () => {
    const paths = [
      `repos/${REPOSITORY}/issues/418`,
      `repos/${REPOSITORY}/issues/418/comments?per_page=100`,
      `repos/${REPOSITORY}/issues/418/dependencies/blocked_by?per_page=100`,
      `repos/${REPOSITORY}/issues/418/sub_issues?per_page=100`,
      `repos/${REPOSITORY}/issues/420/sub_issues?per_page=100`,
      // The mid-tree comment page: the read whose silent emptiness would be a
      // slice implemented without the acceptance context a maintainer added.
      `repos/${REPOSITORY}/issues/420/comments?per_page=100`,
      `repos/${REPOSITORY}/issues/420/dependencies/blocked_by?per_page=100`,
    ];

    for (const path of paths) {
      const { transport } = world(SIMPLE_SPEC, {
        [path]: new ScopeError("denied", `GitHub returned 403 for \`${path}\``),
      });
      const failure = expectFailure(await resolveScope(SPEC_SCOPE, transport));
      assert.equal(failure.reason, "denied", path);
    }
  });

  it("aborts when GitHub answers in a shape this runner does not read", async () => {
    for (const answer of [{ number: 418 }, [], "418", null]) {
      const transport: GitHubTransport = async () => answer;
      const failure = expectFailure(
        await resolveScope({ kind: "specific-issue", target: "418" }, transport),
      );
      assert.equal(failure.reason, "malformed-response");
    }
  });

  it("reports a missing target without claiming it knows why", async () => {
    const { transport } = world([]);
    const failure = expectFailure(await resolveScope(SPEC_SCOPE, transport));

    assert.equal(failure.reason, "not-found");
    assert.match(failure.message, /not found or inaccessible/);
  });

  it("refuses an unparseable target before any request", async () => {
    const { transport, requests } = world(SIMPLE_SPEC);
    const failure = expectFailure(
      await resolveScope({ kind: "specific-spec", target: "not-a-number" }, transport),
    );

    assert.equal(failure.reason, "invalid-target");
    assert.deepEqual(requests, []);
  });
});

describe("refusing a target that is not this run's to drive", () => {
  const cases: readonly { readonly name: string; readonly fixture: Fixture; readonly detail: RegExp }[] = [
    {
      name: "a closed SPEC",
      fixture: { number: 418, state: "closed", labels: ["ready-for-agent", "spec"] },
      detail: /it is closed/,
    },
    {
      name: "an unreleased SPEC",
      fixture: { number: 418, labels: ["spec"] },
      detail: /does not carry `ready-for-agent`/,
    },
    {
      name: "a SPEC that is a human's",
      fixture: { number: 418, labels: ["ready-for-human", "spec"] },
      detail: /carries `ready-for-human`/,
    },
    {
      name: "a SPEC labelled for both",
      fixture: { number: 418, labels: ["ready-for-agent", "ready-for-human", "spec"] },
      detail: /carries both `ready-for-human` and `ready-for-agent`/,
    },
    {
      name: "an issue that is not a SPEC",
      fixture: { number: 418, labels: ["ready-for-agent"] },
      detail: /does not carry `spec`/,
    },
    {
      name: "a blocked SPEC",
      fixture: {
        number: 418,
        labels: ["ready-for-agent", "spec"],
        blockedBy: [{ number: 99, state: "open" }],
      },
      detail: /blocked by #99/,
    },
  ];

  for (const { name, fixture, detail } of cases) {
    it(`refuses ${name} in place, with the issue to show`, async () => {
      const { transport } = world([fixture]);
      const failure = expectFailure(await resolveScope(SPEC_SCOPE, transport));

      assert.equal(failure.reason, "target-rejected");
      assert.match(failure.message, detail);
      // The picker renders number, title and labels, so the record travels with
      // the refusal rather than being re-fetched to explain it.
      assert.equal(failure.anchor?.number, 418);
      assert.deepEqual(failure.anchor?.labels, [...(fixture.labels ?? [])].sort());
    });
  }

  it("reports every problem at once", async () => {
    const { transport } = world([
      { number: 418, state: "closed", labels: [], blockedBy: [{ number: 99 }] },
    ]);
    const failure = expectFailure(await resolveScope(SPEC_SCOPE, transport));

    assert.match(failure.message, /it is closed; .*ready-for-agent.*; .*spec.*; .*blocked by #99/);
  });

  it("accepts a plain released issue as a Specific issue target", async () => {
    const { transport } = world([{ number: 420, labels: ["ready-for-agent"] }]);
    const snapshot = expectResolved(
      await resolveScope({ kind: "specific-issue", target: "420" }, transport),
    );

    assert.deepEqual(snapshot.executableNodeIds, ["I_420"]);
  });
});

describe("a Specific issue", () => {
  it("is exactly one issue, and its children are never discovered", async () => {
    const { transport, requests } = world(SIMPLE_SPEC);
    const snapshot = expectResolved(
      await resolveScope({ kind: "specific-issue", target: "418" }, transport),
    );

    assert.deepEqual(snapshot.memberNodeIds, ["I_418"]);
    assert.deepEqual(snapshot.executableNodeIds, ["I_418"]);
    assert.equal(
      requests.some((request) => request.path.includes("sub_issues")),
      false,
    );
  });
});

describe("the repository-wide queue", () => {
  it("drops the pull requests the issues endpoint returns", async () => {
    const { transport } = world([
      { number: 419 },
      { number: 434, pullRequest: true },
      { number: 420, labels: ["ready-for-human", "ready-for-agent"] },
      { number: 421, state: "closed" },
    ]);
    const snapshot = expectResolved(
      await resolveScope({ kind: "all-ready-for-agent" }, transport),
    );

    assert.equal(snapshot.anchorNodeId, null);
    // No authored order without a parent, so ascending number is all there is.
    assert.deepEqual(snapshot.memberNodeIds, ["I_419", "I_420"]);
    assert.deepEqual(snapshot.executableNodeIds, ["I_419"]);
  });
});

// ---------------------------------------------------------------------------
// Revalidation
// ---------------------------------------------------------------------------

describe("revalidating immediately before a dispatch", () => {
  async function frozen(fixtures: readonly Fixture[] = SIMPLE_SPEC): Promise<WorkScopeSnapshot> {
    const { transport } = world(fixtures);
    return expectResolved(await resolveScope(SPEC_SCOPE, transport));
  }

  it("passes an unchanged item, carrying the freshly read acceptance context", async () => {
    const snapshot = await frozen();
    const { transport } = world([
      ...SIMPLE_SPEC.filter((fixture) => fixture.number !== 419),
      { number: 419, parent: 418, comments: [{ id: 1, body: "Also handle the empty case." }] },
    ]);

    const result = await revalidate(snapshot, "I_419", transport);
    assert.equal(result.status, "ok");
    if (result.status !== "ok") return;
    assert.deepEqual(result.issue.comments.map((comment) => comment.body), [
      "Also handle the empty case.",
    ]);
  });

  it("reports a closed item as done rather than as deregulated", async () => {
    const snapshot = await frozen();
    const { transport } = world([
      ...SIMPLE_SPEC.filter((fixture) => fixture.number !== 419),
      { number: 419, parent: 418, state: "closed" },
    ]);

    const result = await revalidate(snapshot, "I_419", transport);
    assert.equal(result.status, "item-closed");
  });

  it("reports a deregulated item, by every way of deregulating one", async () => {
    const snapshot = await frozen();
    const variants: readonly Fixture[] = [
      { number: 419, parent: 418, labels: [] },
      { number: 419, parent: 418, labels: ["ready-for-agent", "ready-for-human"] },
      // Newly blocked from *outside* the run: #900 is nobody's work here.
      { number: 419, parent: 418, blockedBy: [{ number: 900, state: "open" }] },
    ];

    for (const variant of variants) {
      const { transport } = world([
        ...SIMPLE_SPEC.filter((fixture) => fixture.number !== 419),
        variant,
      ]);
      const result = await revalidate(snapshot, "I_419", transport);
      assert.equal(result.status, "item-deregulated", JSON.stringify(variant));
    }
  });

  it("passes an item newly blocked by something this run is going to do", async () => {
    const snapshot = await frozen();
    const { transport } = world([
      ...SIMPLE_SPEC.filter((fixture) => fixture.number !== 421),
      { number: 421, parent: 418, blockedBy: [{ number: 419, state: "open" }] },
    ]);

    // An in-set blocker is a precedence edge the driver already honours, so it
    // is not a reason to refuse the dispatch.
    const result = await revalidate(snapshot, "I_421", transport);
    assert.equal(result.status, "ok");
  });

  it("aborts the run when the anchor stops being the contract", async () => {
    const snapshot = await frozen();
    const anchors: readonly Fixture[] = [
      { number: 418, state: "closed", labels: ["ready-for-agent", "spec"], children: [419, 420, 421] },
      { number: 418, labels: ["spec"], children: [419, 420, 421] },
      { number: 418, labels: ["ready-for-agent"], children: [419, 420, 421] },
      { number: 418, labels: ["ready-for-agent", "spec", "ready-for-human"], children: [419, 420, 421] },
    ];

    for (const anchor of anchors) {
      const { transport } = world([
        anchor,
        ...SIMPLE_SPEC.filter((fixture) => fixture.number !== 418),
      ]);
      const result = await revalidate(snapshot, "I_419", transport);
      assert.equal(result.status, "anchor-changed", JSON.stringify(anchor.labels));
    }
  });

  it("aborts the run when the item no longer descends from the anchor", async () => {
    const snapshot = await frozen();
    const { transport } = world([
      { number: 418, labels: ["ready-for-agent", "spec"], children: [420, 421] },
      // Detached: still open, still released, no longer under the SPEC.
      { number: 419 },
      { number: 420, parent: 418, blockedBy: [{ number: 419 }] },
      { number: 421, parent: 418 },
    ]);

    const result = await revalidate(snapshot, "I_419", transport);
    assert.equal(result.status, "anchor-changed");
    assert.match(result.status === "anchor-changed" ? result.detail : "", /no longer descends/);
  });

  it("checks the anchor before the item, so an abort is never reported as a skip", async () => {
    const snapshot = await frozen();
    const { transport } = world([
      { number: 418, state: "closed", labels: ["ready-for-agent", "spec"], children: [419, 420, 421] },
      { number: 419, parent: 418, state: "closed" },
      { number: 420, parent: 418, blockedBy: [{ number: 419 }] },
      { number: 421, parent: 418 },
    ]);

    const result = await revalidate(snapshot, "I_419", transport);
    assert.equal(result.status, "anchor-changed");
  });

  it("has no anchor to check under a Specific issue scope", async () => {
    const { transport: resolving } = world([{ number: 420 }]);
    const snapshot = expectResolved(
      await resolveScope({ kind: "specific-issue", target: "420" }, resolving),
    );
    const { transport, requests } = world([{ number: 420, state: "closed" }]);

    const result = await revalidate(snapshot, "I_420", transport);
    assert.equal(result.status, "item-closed");
    assert.equal(
      requests.some((request) => request.path.endsWith("/parent")),
      false,
    );
  });

  it("refuses to be asked about an issue outside the snapshot", async () => {
    const snapshot = await frozen();
    const { transport } = world(SIMPLE_SPEC);

    await assert.rejects(() => revalidate(snapshot, "I_900", transport), /outside the snapshot/);
  });

  it("propagates a read failure rather than passing the item", async () => {
    const snapshot = await frozen();
    const { transport } = world(SIMPLE_SPEC, {
      [`repos/${REPOSITORY}/issues/419`]: new ScopeError("denied", "403"),
    });

    await assert.rejects(() => revalidate(snapshot, "I_419", transport), ScopeError);
  });
});
