// The schema canary: one recorded read of a real GitHub tree, replayed through
// the real resolver.
//
// ## Why this exists
//
// Every other test in `__tests__/scope/` is a hand-authored literal, and they
// share one fatal blind spot. `issue_dependencies_summary.blocked_by` and the
// `/dependencies/blocked_by` endpoint are a newer GitHub surface, and if GitHub
// renames or nests either one, **every hand-authored test still passes while
// production sees zero blockers and dispatches a whole SPEC dependency-blind,
// in the wrong order.** The type system cannot catch it either: our own type is
// the thing that would be wrong.
//
// A recording is the only thing that fails when reality moves — and only when
// it is refreshed, which is why refreshing it is the deliberate act below and
// never something the suite or CI does for you.
//
// ## How and when to refresh it
//
//   pnpm --dir .sandcastle exec tsx __tests__/scope/canary/refresh.mts
//
// Needs the network and a `gh` login. Refresh it **when you want to know**:
// before trusting a run after a long gap, when GitHub announces a change to
// issue dependencies or sub-issues, or when this test is the only thing between
// you and a wrong-order overnight run. Then *read the diff* — the point is the
// failure it produces, so a refresh that goes straight to a commit has thrown
// away the only signal the fixture carries.
//
// ## How to skip it
//
//   SANDCASTLE_SKIP_SCHEMA_CANARY=1 pnpm --dir .sandcastle run test
//
// Skippable because it is the one test whose subject is outside this repository.
// A missing fixture skips too, so a clone that has not captured one is not a
// red suite.

import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import { resolveScope, type GitHubTransport } from "../../../scope/github.mts";
import { runOrder, type WorkScopeSnapshot } from "../../../scope/snapshot.mts";
import { CANARY_SCOPE } from "./canary.mts";

const FIXTURE = fileURLToPath(new URL("./spec-418-tree.json", import.meta.url));

const skip =
  process.env["SANDCASTLE_SKIP_SCHEMA_CANARY"] === "1"
    ? "SANDCASTLE_SKIP_SCHEMA_CANARY=1"
    : !existsSync(FIXTURE)
      ? "no recorded fixture; run __tests__/scope/canary/refresh.mts"
      : false;

interface Recording {
  readonly capturedAt: string;
  readonly apiVersion: string;
  readonly outcome: string;
  readonly responses: Readonly<Record<string, unknown>>;
}

function recording(): Recording {
  return JSON.parse(readFileSync(FIXTURE, "utf8")) as Recording;
}

/**
 * Replays the recording. A path the resolver asks for that was never recorded
 * is a hard failure, not an empty answer: the whole value of the canary is that
 * the reads it covers are the reads production makes.
 */
function replay(responses: Readonly<Record<string, unknown>>): GitHubTransport {
  return async ({ path }) => {
    if (!(path in responses)) throw new Error(`The canary recording has no \`${path}\`.`);
    return responses[path];
  };
}

function resolved(): Promise<WorkScopeSnapshot> {
  return resolveScope(CANARY_SCOPE, replay(recording().responses)).then((outcome) => {
    assert.equal(outcome.ok, true, outcome.ok ? "" : `the recording no longer resolves: ${outcome.message}`);
    if (!outcome.ok) throw new Error("unreachable");
    return outcome.snapshot;
  });
}

/** Every raw issue payload the recording holds, by issue number. */
function rawIssues(responses: Readonly<Record<string, unknown>>): Map<number, Record<string, unknown>> {
  const found = new Map<number, Record<string, unknown>>();
  for (const value of Object.values(responses)) {
    for (const candidate of Array.isArray(value) ? value : [value]) {
      const raw = candidate as Record<string, unknown>;
      if (typeof raw?.["number"] === "number" && typeof raw["node_id"] === "string") {
        found.set(raw["number"] as number, raw);
      }
    }
  }
  return found;
}

describe("the schema canary", { skip }, () => {
  it("still resolves a real tree end to end", async () => {
    const snapshot = await resolved();
    const anchor = snapshot.issues.find((issue) => issue.role === "anchor");

    assert.equal(snapshot.repository, "hadrysm/foldwise-voice");
    assert.equal(anchor?.number, 418);
    assert.ok(snapshot.memberNodeIds.length > 1, "the recorded SPEC has descendants");
    assert.equal(snapshot.memberNodeIds.length, snapshot.issues.length);
  });

  it("was recorded against the API version this module pins", () => {
    assert.equal(recording().apiVersion, "2026-03-10");
    assert.equal(recording().outcome, "ok");
  });

  it("derives every open blocker from the recorded relationship list", async () => {
    const { responses } = recording();
    const snapshot = await resolved();

    for (const issue of snapshot.issues) {
      const path = `repos/hadrysm/foldwise-voice/issues/${issue.number}/dependencies/blocked_by?per_page=100`;
      const recorded = responses[path];
      assert.ok(Array.isArray(recorded), `no recorded blockers for #${issue.number}`);
      const open = recorded
        .map((blocker) => blocker as Record<string, unknown>)
        .filter((blocker) => blocker["state"] === "open")
        .map((blocker) => blocker["number"]);
      assert.deepEqual(
        issue.openBlockers.map((blocker) => blocker.number),
        open,
        `#${issue.number}`,
      );
    }
  });

  it("agrees with GitHub's own open-blocker count", async () => {
    // The named blind spot, checked directly. If GitHub renames or nests
    // `issue_dependencies_summary.blocked_by`, this is the assertion that fails
    // on the next refresh — before a run orders a SPEC as if nothing blocked
    // anything.
    const { responses } = recording();
    const raws = rawIssues(responses);
    const snapshot = await resolved();

    for (const issue of snapshot.issues) {
      const summary = raws.get(issue.number)?.["issue_dependencies_summary"] as
        | Record<string, unknown>
        | undefined;
      assert.ok(summary, `#${issue.number} has no issue_dependencies_summary`);
      assert.equal(summary["blocked_by"], issue.openBlockers.length, `#${issue.number}`);
    }
  });

  it("still covers a relationship that exists but is closed", async () => {
    // Not a property of GitHub — a property of *this recording*. A refresh that
    // loses the case has blinded the canary to the difference between
    // "relationship exists" and "blocker is open", so it should say so loudly
    // rather than quietly stop covering it.
    const { responses } = recording();
    const snapshot = await resolved();

    const closedOnly = snapshot.issues.filter((issue) => {
      const path = `repos/hadrysm/foldwise-voice/issues/${issue.number}/dependencies/blocked_by?per_page=100`;
      const recorded = responses[path];
      return Array.isArray(recorded) && recorded.length > 0 && issue.openBlockers.length === 0;
    });

    assert.ok(
      closedOnly.length > 0,
      "no recorded issue has a closed-only blocker relationship; re-record against a tree that does",
    );
  });

  it("orders the real chain by its real dependency edges", async () => {
    const snapshot = await resolved();
    const order = runOrder(snapshot);

    assert.equal(order.ok, true, "the recorded tree has a dependency cycle");
    if (!order.ok) return;

    const position = new Map(order.items.map((item, index) => [item.nodeId, index]));
    let edges = 0;
    for (const issue of snapshot.issues) {
      const at = position.get(issue.nodeId);
      if (at === undefined) continue;
      for (const blocker of issue.openBlockers) {
        const before = position.get(blocker.nodeId);
        if (before === undefined) continue;
        edges += 1;
        assert.ok(before < at, `#${blocker.number} must run before #${issue.number}`);
      }
    }
    assert.ok(edges > 0, "no in-scope dependency edge survived; re-record against a chained SPEC");
  });
});
