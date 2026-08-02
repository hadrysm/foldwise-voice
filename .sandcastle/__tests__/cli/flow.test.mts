import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import { IMPLEMENTER, REVIEWER } from "../../agents/catalog.mts";
import type { RunModel } from "../../agents/models.mts";
import {
  applyAnswer,
  initialState,
  maxParallelQuestion,
  nextStep,
  rememberedFor,
  resolvePlan,
  runGuardQuestion,
  runToRemember,
  scopeSummary,
  storeIsReplayable,
  toWorkScope,
  type Answer,
  type EffortsFor,
  type FlowState,
  type ResolvedPlan,
  type ScopeResolution,
  type Step,
} from "../../cli/flow.mts";
import { mergeStoredRun, serializeStoredRun, type StoredRun } from "../../cli/store.mts";
import type { Agent, Dispatch, Workflow } from "../../contract.mts";
import { driveSequential } from "../../drivers/sequential.mts";
import { repo } from "../../repo.mts";
import { workList } from "../../runner.mts";
import type { ScopeOutcome } from "../../scope/github.mts";
import type { WorkScopeSnapshot } from "../../scope/snapshot.mts";
import { WORKFLOWS } from "../../workflows/registry.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";
import { issueSnapshot, queueSnapshot, specSnapshot } from "../support/scope.mts";

/**
 * The catalog's own efforts, which is what a CLI advertising everything would
 * report. The real lookup spawns `claude --help`; injecting it is what lets the
 * screen sequence be asserted at all.
 */
const everyEffort: EffortsFor = (model: RunModel) => model.efforts;

/** The worktree that wrote the store, and one that did not. */
const HOME_ORIGIN = "/clone/.git/worktrees/perth";
const OTHER_ORIGIN = "/clone/.git/worktrees/albany";

/**
 * A SPEC with three eligible slices — 420 chained behind 419 — and one closed.
 * Three is deliberate: it is more than one, so the run guard is asked.
 */
const SPEC_SNAPSHOT = specSnapshot({ number: 418, title: "Universal Work scope" }, [
  { number: 419, title: "The pure snapshot" },
  { number: 420, title: "Resolve against GitHub", blockedBy: [419] },
  { number: 421, title: "Scope-first picker" },
  { number: 422, title: "Already done", state: "closed" },
]);

function ok(snapshot: WorkScopeSnapshot): ScopeOutcome {
  return { ok: true, snapshot };
}

const UNREACHABLE: ScopeOutcome = {
  ok: false,
  reason: "unavailable",
  message: "Reading `repos/x/issues/418` from GitHub failed: could not connect",
  anchor: undefined,
};

const REJECTED: ScopeOutcome = {
  ok: false,
  reason: "target-rejected",
  message: "#417 Fix the baseline cannot be a run target: it is closed.",
  anchor: undefined,
};

/** A remembered run of the registered workflow, with two different models. */
function populatedStore(overrides: Partial<StoredRun> = {}): StoredRun {
  return {
    lastWorkflowId: "sequential-reviewer",
    lastScope: { kind: "specific-spec", target: "418", origin: HOME_ORIGIN },
    maxWorkItems: 5,
    maxParallel: 3,
    agents: {
      implementer: { model: "claude-opus-5", effort: "xhigh" },
      reviewer: { model: "gpt-5.6-sol", effort: "high" },
    },
    passthrough: {},
    ...overrides,
  };
}

/**
 * The one shape no shipped workflow declares yet: the driver that runs waves.
 * Registered in `DRIVERS` as draining *and* concurrent from this slice on, which
 * is what lets the picker ask `MAX_PARALLEL` before slices 8-10 build it.
 */
const waveParallel: Workflow = {
  id: "wave-parallel",
  label: "Waves",
  description: "Plan a wave, work it, merge it",
  dir: sequentialReviewer.dir,
  agents: [IMPLEMENTER, REVIEWER],
  driver: "wave-parallel",
  runShape: (workItems) => `plan → implement → review, up to ${workItems} issues`,
  run: async () => undefined,
};

interface WalkOptions {
  store?: StoredRun;
  origin?: string;
  /** One per resolve step, in order. The last one is reused if the walk asks again. */
  outcomes?: readonly ScopeOutcome[];
  workflows?: readonly Workflow[];
  /** What is typed when a resolve step asks for a target. */
  target?: string;
  /** Stop *before* answering this step, to inspect the state that produced it. */
  stopAt?: string;
}

interface Walk {
  ids: readonly string[];
  steps: readonly Step[];
  state: FlowState;
  plan: ResolvedPlan | undefined;
}

/** Pressing enter: whatever the step opens on. */
function defaultAnswer(step: Step): Answer {
  if (step.kind === "number") return step.defaultValue;
  if (step.kind === "select") return step.initialValue ?? step.options[0].value;
  throw new Error("a resolve step is answered by the walk, not by pressing enter");
}

/**
 * Walk the whole flow, answering each step from `answers` or by pressing enter.
 * This is the driver `cli/prompts.mts` runs, minus the terminal and minus
 * GitHub — the resolve step is answered from `outcomes` rather than resolved.
 */
function walk(answers: Record<string, Answer> = {}, options: WalkOptions = {}): Walk {
  const workflows = options.workflows ?? WORKFLOWS;
  const outcomes = [...(options.outcomes ?? [ok(SPEC_SNAPSHOT)])];
  let state = initialState(options.store, options.origin ?? HOME_ORIGIN);
  const steps: Step[] = [];

  while (steps.length <= 24) {
    const step = nextStep(state, everyEffort, workflows);
    if (!step || step.id === options.stopAt) {
      return {
        steps,
        ids: steps.map((asked) => asked.id),
        state,
        plan: resolvePlan(state, workflows),
      };
    }
    steps.push(step);

    let answer: Answer;
    if (step.kind === "resolve") {
      const outcome = outcomes.length > 1 ? outcomes.shift() : outcomes[0];
      assert.ok(outcome, "the walk ran out of scope outcomes");
      const resolution: ScopeResolution = {
        target: step.needsTarget ? (options.target ?? step.initialValue ?? "418") : undefined,
        outcome,
      };
      answer = resolution;
    } else {
      answer = step.id in answers ? answers[step.id] : defaultAnswer(step);
    }

    const folded = applyAnswer(state, step, answer);
    assert.notEqual(folded, state, "applyAnswer must return a new state, not mutate its input");
    state = folded;
  }

  throw new Error(`The walk never settled: ${steps.map((asked) => asked.id).join(", ")}`);
}

function stepById(walked: Walk, id: string): Step {
  const step = walked.steps.find((asked) => asked.id === id);
  assert.ok(step, `expected the walk to ask ${id}, got ${walked.ids.join(", ")}`);
  return step;
}

function initialValueOf(walked: Walk, id: string): string | undefined {
  const step = stepById(walked, id);
  return step.kind === "select" || step.kind === "resolve" ? step.initialValue : undefined;
}

function optionsOf(walked: Walk, id: string): readonly string[] {
  const step = stepById(walked, id);
  assert.equal(step.kind, "select");
  return step.kind === "select" ? step.options.map((option) => option.value) : [];
}

describe("the step sequence", () => {
  it("asks Work scope first, resolves it, and only then asks about the run", () => {
    assert.deepEqual(walk().ids, [
      "scope",
      "resolve",
      "workflow",
      "run-guard",
      "same-model",
      "model:*",
      "effort:*",
      "confirm",
    ]);
  });

  it("offers the three Work scopes in picker order", () => {
    assert.deepEqual(optionsOf(walk(), "scope"), [
      "specific-spec",
      "specific-issue",
      "all-ready-for-agent",
    ]);
  });

  it("asks a model and an effort per agent when they are configured separately", () => {
    assert.deepEqual(walk({ "same-model": "separate" }).ids, [
      "scope",
      "resolve",
      "workflow",
      "run-guard",
      "same-model",
      "model:implementer",
      "effort:implementer",
      "model:reviewer",
      "effort:reviewer",
      "confirm",
    ]);
  });

  it("asks a single-agent, non-draining workflow neither number", () => {
    // Review Only walks no work items, so the run guard has nothing to bound and
    // a wave width has nothing to widen.
    assert.deepEqual(walk({ workflow: "review-only" }).ids, [
      "scope",
      "resolve",
      "workflow",
      "model:reviewer",
      "effort:reviewer",
      "confirm",
    ]);
  });

  it("asks the wave width only of a workflow that runs items side by side", () => {
    const walked = walk({}, { workflows: [waveParallel] });
    assert.deepEqual(walked.ids, [
      "scope",
      "resolve",
      "workflow",
      "run-guard",
      "max-parallel",
      "same-model",
      "model:*",
      "effort:*",
      "confirm",
    ]);
  });

  it("never asks the run guard when exactly one work item is eligible", () => {
    // A Specific issue resolves to one item, so the guard has one meaningful
    // value and asking for it would be a screen with no decision on it.
    const walked = walk({}, { outcomes: [ok(issueSnapshot({ number: 421 }))] });
    assert.equal(walked.ids.includes("run-guard"), false);
    assert.equal(walked.plan?.maxWorkItems, 1);
  });

  it("does not mutate the state it folds an answer into", () => {
    const before = initialState();
    const step = nextStep(before, everyEffort);
    assert.ok(step);
    applyAnswer(before, step, "specific-spec");
    assert.deepEqual(before, initialState());
  });
});

describe("the resolve step", () => {
  it("asks for a target for an explicit scope and for nothing for the queue", () => {
    const spec = stepById(walk(), "resolve");
    assert.equal(spec.kind === "resolve" && spec.needsTarget, true);

    const queue = stepById(
      walk({ scope: "all-ready-for-agent" }, { outcomes: [ok(queueSnapshot([{ number: 7 }]))] }),
      "resolve",
    );
    assert.equal(queue.kind === "resolve" && queue.needsTarget, false);
  });

  it("carries the scope it will resolve, so the shell forges none of it", () => {
    const step = stepById(walk({ scope: "specific-issue" }, { outcomes: [ok(issueSnapshot({ number: 421 }))] }), "resolve");
    assert.equal(step.kind === "resolve" && step.scope, "specific-issue");
  });

  it("builds a target-free scope for the repository-wide queue", () => {
    assert.deepEqual(toWorkScope("all-ready-for-agent", "418"), { kind: "all-ready-for-agent" });
    assert.deepEqual(toWorkScope("specific-spec", "418"), { kind: "specific-spec", target: "418" });
  });
});

describe("recovery from a scope that produced no work", () => {
  function recoveryFor(outcome: ScopeOutcome, scope = "specific-spec"): Walk {
    return walk({ scope, recovery: "cancel" }, { outcomes: [outcome, ok(SPEC_SNAPSHOT)] });
  }

  it("offers a retry for a failure a maintainer can fix and try again into", () => {
    assert.deepEqual(optionsOf(recoveryFor(UNREACHABLE), "recovery"), [
      "retry",
      "target",
      "scope",
      "cancel",
    ]);
  });

  it("offers no retry for a target that will be refused the same way every time", () => {
    assert.deepEqual(optionsOf(recoveryFor(REJECTED), "recovery"), ["target", "scope", "cancel"]);
  });

  it("offers no target entry for the repository-wide queue, which has none", () => {
    const walked = walk(
      { scope: "all-ready-for-agent", recovery: "cancel" },
      { outcomes: [ok(queueSnapshot([]))] },
    );
    assert.deepEqual(optionsOf(walked, "recovery"), ["retry", "scope", "cancel"]);
  });

  it("treats a resolved but empty scope as a recovery, not as a run", () => {
    const drained = specSnapshot({ number: 418 }, [{ number: 419, state: "closed" }]);
    const walked = walk({ recovery: "cancel" }, { outcomes: [ok(drained)] });
    assert.equal(stepById(walked, "recovery").noteTitle, "No work is eligible right now");
    assert.equal(walked.plan, undefined);
  });

  it("refuses a dependency cycle before confirmation rather than at a wave boundary", () => {
    const cyclic = specSnapshot({ number: 418 }, [
      { number: 419, blockedBy: [420] },
      { number: 420, blockedBy: [419] },
    ]);
    const walked = walk({ recovery: "cancel" }, { outcomes: [ok(cyclic)] });
    const step = stepById(walked, "recovery");
    assert.equal(step.noteTitle, "These work items block each other in a cycle");
    // Not retryable: nothing about asking GitHub again breaks the cycle.
    assert.deepEqual(optionsOf(walked, "recovery"), ["target", "scope", "cancel"]);
    assert.equal(walked.plan, undefined);
  });

  it("shows the resolved target's number, title and labels when there is one", () => {
    const walked = walk(
      { recovery: "cancel" },
      { outcomes: [ok(specSnapshot({ number: 418, title: "Universal Work scope" }, []))] },
    );
    assert.deepEqual(stepById(walked, "recovery").note, [
      "Nothing in this scope is open, released to an agent and unblocked from outside it.",
      "Resolved     #418 · Universal Work scope",
      "Labels       ready-for-agent, spec",
    ]);
  });

  it("resolves the same target again on a retry, without asking for it twice", () => {
    const walked = walk({ recovery: "retry" }, { outcomes: [UNREACHABLE, ok(SPEC_SNAPSHOT)] });
    assert.deepEqual(walked.ids.slice(0, 4), ["scope", "resolve", "recovery", "resolve"]);
    const second = walked.steps.filter((step) => step.id === "resolve")[1];
    assert.equal(second?.kind === "resolve" && second.needsTarget, false);
    assert.equal(second?.kind === "resolve" && second.initialValue, "418");
    assert.ok(walked.plan, "a successful retry must reach a plan");
  });

  it("asks for another target pre-filled with the one that failed", () => {
    const walked = walk(
      { recovery: "target" },
      { outcomes: [REJECTED, ok(SPEC_SNAPSHOT)], target: "418" },
    );
    const second = walked.steps.filter((step) => step.id === "resolve")[1];
    assert.equal(second?.kind === "resolve" && second.needsTarget, true);
    assert.equal(second?.kind === "resolve" && second.initialValue, "418");
  });

  it("goes back to the Work scope question, forgetting the target", () => {
    const walked = walk({ recovery: "scope" }, { outcomes: [REJECTED, ok(SPEC_SNAPSHOT)] });
    assert.deepEqual(walked.ids.slice(0, 4), ["scope", "resolve", "recovery", "scope"]);
    // The second resolve asks from scratch rather than pre-filling the target
    // that was just refused: a different Work scope is different work.
    const second = walked.steps.filter((step) => step.id === "resolve")[1];
    assert.equal(second?.kind === "resolve" && second.needsTarget, true);
    assert.equal(second?.kind === "resolve" && second.initialValue, undefined);
  });

  it("cancels with no plan, from a prompt where nothing has been dispatched", () => {
    assert.equal(recoveryFor(UNREACHABLE).plan, undefined);
  });
});

describe("what resolving a scope reports", () => {
  it("states a SPEC's eligible descendants against what it is not running", () => {
    const walked = walk({ recovery: "cancel" }, { outcomes: [ok(SPEC_SNAPSHOT)] });
    assert.ok(walked.state.resolved);
    assert.deepEqual(scopeSummary(walked.state.resolved), [
      "Work scope   Specific SPEC",
      "Target       #418 · Universal Work scope",
      "Labels       ready-for-agent, spec",
      "Eligible     3 open, unblocked issues",
      "Not run      1 closed",
    ]);
  });

  it("states that a Specific issue runs exactly one thing", () => {
    const walked = walk({}, { outcomes: [ok(issueSnapshot({ number: 421, title: "Scope-first picker" }))] });
    assert.ok(walked.state.resolved);
    assert.deepEqual(scopeSummary(walked.state.resolved), [
      "Work scope   Specific issue",
      "Target       #421 · Scope-first picker",
      "Labels       ready-for-agent",
      "Eligible     exactly 1 issue",
    ]);
  });

  it("states the repository-wide queue's own size, with no target", () => {
    const queue = queueSnapshot([{ number: 7 }, { number: 9 }, { number: 11, labels: ["bug"] }]);
    const walked = walk({ scope: "all-ready-for-agent" }, { outcomes: [ok(queue)] });
    assert.ok(walked.state.resolved);
    assert.deepEqual(scopeSummary(walked.state.resolved), [
      "Work scope   All ready-for-agent issues",
      "Eligible     2 open, unblocked issues",
      "Not run      1 unreleased",
    ]);
  });
});

describe("the fast path", () => {
  it("comes after resolution, so accepting it always starts a run", () => {
    const walked = walk({}, { store: populatedStore() });
    assert.deepEqual(walked.ids, ["scope", "resolve", "fast-path"]);
    assert.equal(walked.plan?.workflow.id, "sequential-reviewer");
  });

  it("is never offered for a scope that produced no work", () => {
    const walked = walk(
      { recovery: "cancel" },
      { store: populatedStore(), outcomes: [ok(queueSnapshot([]))] },
    );
    assert.equal(walked.ids.includes("fast-path"), false);
  });

  it("states eligibility in its own hint, which is what moving it here buys", () => {
    const step = stepById(walk({}, { store: populatedStore() }), "fast-path");
    const hint = step.kind === "select" ? step.options[0].hint : undefined;
    assert.equal(
      hint,
      "Implement & Review · Claude Opus 5 · Extra High / GPT-5.6 Sol · High · 3 eligible issues",
    );
  });

  it("replays exactly what was remembered", () => {
    const walked = walk({}, { store: populatedStore() });
    assert.deepEqual(
      walked.plan?.agents.map((agent) => [agent.agentId, agent.model.id, agent.effort]),
      [
        ["implementer", "claude-opus-5", "xhigh"],
        ["reviewer", "gpt-5.6-sol", "high"],
      ],
    );
    assert.equal(walked.plan?.maxWorkItems, 5);
    assert.equal(walked.plan?.maxParallel, 1);
  });

  it("is not offered when there is nothing replayable to offer", () => {
    const walked = walk({}, { store: { agents: {}, passthrough: {} } });
    assert.equal(walked.ids.includes("fast-path"), false);
  });

  it("walks every question when Change something is chosen", () => {
    assert.deepEqual(walk({ "fast-path": "change" }, { store: populatedStore() }).ids, [
      "scope",
      "resolve",
      "fast-path",
      "workflow",
      "run-guard",
      "same-model",
      "model:implementer",
      "effort:implementer",
      "model:reviewer",
      "effort:reviewer",
      "confirm",
    ]);
  });

  it("opens every walked question on the remembered value", () => {
    // Pressing enter at every screen of the long walk has to land on the same
    // run the one-keystroke replay would have started.
    const changed = walk({ "fast-path": "change" }, { store: populatedStore() });
    const replayed = walk({}, { store: populatedStore() });
    assert.deepEqual(changed.plan?.agents, replayed.plan?.agents);
    assert.equal(changed.plan?.maxWorkItems, replayed.plan?.maxWorkItems);
  });
});

describe("storeIsReplayable", () => {
  it("is false with no store at all", () => {
    assert.equal(storeIsReplayable(undefined), false);
  });

  it("is false when no workflow was remembered", () => {
    assert.equal(storeIsReplayable(populatedStore({ lastWorkflowId: undefined })), false);
  });

  it("is false when the remembered workflow is not in the registry", () => {
    // What another branch's workflow looks like from here: the store is shared
    // across every worktree of the clone, so an id this branch never declared is
    // routine rather than corrupt.
    const store = populatedStore({ lastWorkflowId: "another-branches-workflow" });
    assert.equal(storeIsReplayable(store), false);
  });

  it("is false when an agent the workflow drives has no pick", () => {
    const store = populatedStore();
    delete store.agents.reviewer;
    assert.equal(storeIsReplayable(store), false);
  });

  it("is false when a needed pick has a model but no effort", () => {
    // A dropped effort tier means the run is no longer reproducible in one
    // keystroke, so the fast path vanishes for that one run.
    const store = populatedStore();
    store.agents.reviewer = { model: "gpt-5.6-sol" };
    assert.equal(storeIsReplayable(store), false);
  });

  it("is false for a draining workflow with no remembered run guard", () => {
    // The one run after an upgrade: the walk's own write fills the key in.
    assert.equal(storeIsReplayable(populatedStore({ maxWorkItems: undefined })), false);
  });

  it("is false for a concurrent workflow with no remembered wave width", () => {
    const store = populatedStore({ lastWorkflowId: "wave-parallel", maxParallel: undefined });
    assert.equal(storeIsReplayable(store, [waveParallel]), false);
    assert.equal(storeIsReplayable(populatedStore({ lastWorkflowId: "wave-parallel" }), [waveParallel]), true);
  });

  it("needs no remembered Work scope, because scope is pre-fill and not replay", () => {
    assert.equal(storeIsReplayable(populatedStore({ lastScope: undefined })), true);
  });

  it("is true for a complete remembered run", () => {
    assert.equal(storeIsReplayable(populatedStore()), true);
  });
});

describe("the run guard", () => {
  /** A resolved scope with the guard still unanswered — where the question lives. */
  function stateWith(store?: StoredRun): FlowState {
    return walk({ "fast-path": "change" }, { store, stopAt: "run-guard" }).state;
  }

  it("uses the declared default when nothing is remembered", () => {
    assert.equal(runGuardQuestion(stateWith(), sequentialReviewer)?.defaultValue, 10);
  });

  it("uses a remembered value that is still in range, and says what it accepts", () => {
    const question = runGuardQuestion(stateWith(populatedStore({ maxWorkItems: 3 })), sequentialReviewer);
    assert.equal(question?.defaultValue, 3);
    assert.equal(question?.hint, "1–50  ·  enter accepts 3");
  });

  it("drops an out-of-range value to the default rather than clamping it", () => {
    // 50 is the maximum, so a clamp would silently drain 50 issues.
    for (const stored of [0, 51, 9999]) {
      const state = stateWith(populatedStore({ maxWorkItems: stored }));
      assert.equal(runGuardQuestion(state, sequentialReviewer)?.defaultValue, 10, String(stored));
    }
  });

  it("is never asked of a workflow that walks no work items", () => {
    const reviewOnly = WORKFLOWS.find((workflow) => workflow.id === "review-only");
    assert.ok(reviewOnly);
    assert.equal(runGuardQuestion(stateWith(), reviewOnly), undefined);
  });

  it("truncates nothing it was not asked to, and says so on the confirmation", () => {
    const big = specSnapshot(
      { number: 418 },
      Array.from({ length: 12 }, (_unused, index) => ({ number: 500 + index })),
    );
    const walked = walk({}, { outcomes: [ok(big)] });
    assert.equal(walked.plan?.maxWorkItems, 10);
    assert.deepEqual(stepById(walked, "confirm").note?.[1], "Eligible     up to 10 of 12 eligible");
  });
});

describe("the wave width", () => {
  function stateWith(store?: StoredRun): FlowState {
    return walk(
      { "fast-path": "change" },
      { store, workflows: [waveParallel], stopAt: "max-parallel" },
    ).state;
  }

  it("opens on this repository's measured default", () => {
    const question = maxParallelQuestion(stateWith(), waveParallel);
    assert.equal(question?.defaultValue, 3);
    assert.equal(question?.hint, "1–10  ·  enter accepts 3");
  });

  it("uses a remembered width that is still in range", () => {
    assert.equal(maxParallelQuestion(stateWith(populatedStore({ maxParallel: 2 })), waveParallel)?.defaultValue, 2);
  });

  it("drops an out-of-range width to the default rather than clamping it", () => {
    assert.equal(maxParallelQuestion(stateWith(populatedStore({ maxParallel: 40 })), waveParallel)?.defaultValue, 3);
  });

  it("is never asked of a workflow that runs one item at a time", () => {
    assert.equal(maxParallelQuestion(stateWith(), sequentialReviewer), undefined);
    assert.equal(walk({}).plan?.maxParallel, 1);
  });

  it("reaches the plan when it is asked", () => {
    assert.equal(walk({ "max-parallel": 2 }, { workflows: [waveParallel] }).plan?.maxParallel, 2);
  });
});

describe("the remembered Work scope", () => {
  it("pre-fills the kind, wherever the run that chose it happened", () => {
    const store = populatedStore({
      lastScope: { kind: "all-ready-for-agent", origin: OTHER_ORIGIN },
    });
    assert.equal(initialValueOf(walk({}, { store, outcomes: [ok(queueSnapshot([{ number: 7 }]))] }), "scope"), "all-ready-for-agent");
  });

  it("pre-fills the target only in the worktree that wrote it", () => {
    const store = populatedStore();
    assert.equal(initialValueOf(walk({}, { store }), "resolve"), "418");
    assert.equal(initialValueOf(walk({}, { store, origin: OTHER_ORIGIN }), "resolve"), undefined);
  });

  it("does not pre-fill a target remembered for a different scope kind", () => {
    const store = populatedStore();
    const walked = walk({ scope: "specific-issue" }, { store, outcomes: [ok(issueSnapshot({ number: 9 }))] });
    assert.equal(initialValueOf(walked, "resolve"), undefined);
  });

  it("does not pre-fill a target a pre-origin store never stamped", () => {
    const store = populatedStore({ lastScope: { kind: "specific-spec", target: "418" } });
    assert.equal(initialValueOf(walk({}, { store }), "resolve"), undefined);
  });

  it("remembers the answer that resolved, never the snapshot it produced", () => {
    const plan = walk().plan;
    assert.ok(plan);
    assert.deepEqual(runToRemember(plan).scope, { kind: "specific-spec", target: "418" });
  });

  it("remembers no target for a scope that has none", () => {
    const plan = walk({ scope: "all-ready-for-agent" }, { outcomes: [ok(queueSnapshot([{ number: 7 }]))] }).plan;
    assert.ok(plan);
    assert.deepEqual(runToRemember(plan).scope, { kind: "all-ready-for-agent" });
  });
});

describe("what the store is allowed to remember about the two numbers", () => {
  it("remembers a run guard that was actually asked for", () => {
    const plan = walk({ "run-guard": 2 }).plan;
    assert.ok(plan);
    assert.equal(runToRemember(plan).maxWorkItems, 2);
  });

  it("remembers no guard for a workflow that walks no work items", () => {
    // Review Only's `maxWorkItems` is the eligible count, which is a fact about
    // what resolved. Remembered, it would pre-fill the next draining run's
    // guard with a number nobody chose.
    const plan = walk({ workflow: "review-only" }).plan;
    assert.ok(plan);
    assert.equal(plan.maxWorkItems, 3);
    assert.equal(runToRemember(plan).maxWorkItems, undefined);
  });

  it("remembers no guard when one work item made the question meaningless", () => {
    const plan = walk({}, { outcomes: [ok(issueSnapshot({ number: 421 }))] }).plan;
    assert.ok(plan);
    assert.equal(plan.maxWorkItems, 1);
    assert.equal(runToRemember(plan).maxWorkItems, undefined);
  });

  it("remembers no wave width for a workflow that runs one item at a time", () => {
    const plan = walk().plan;
    assert.ok(plan);
    assert.equal(plan.maxParallel, 1);
    assert.equal(runToRemember(plan).maxParallel, undefined);
  });

  it("leaves the last answered value standing when this run was not asked", () => {
    const plan = walk({ workflow: "review-only" }, { store: populatedStore() }).plan;
    assert.ok(plan);
    const merged = mergeStoredRun(populatedStore(), runToRemember(plan), HOME_ORIGIN);
    assert.equal(merged.maxWorkItems, 5);
    assert.equal(merged.maxParallel, 3);
  });
});

describe("rememberedFor", () => {
  it("gives an agent its own remembered pick", () => {
    const store = populatedStore();
    assert.deepEqual(rememberedFor(store, sequentialReviewer, "implementer"), {
      model: "claude-opus-5",
      effort: "xhigh",
    });
    assert.deepEqual(rememberedFor(store, sequentialReviewer, "reviewer"), {
      model: "gpt-5.6-sol",
      effort: "high",
    });
  });

  it("gives the shared target the first remembered agent of the workflow", () => {
    const store = populatedStore();
    delete store.agents.implementer;
    assert.deepEqual(rememberedFor(store, sequentialReviewer, "*"), {
      model: "gpt-5.6-sol",
      effort: "high",
    });
  });

  it("gives nothing when nothing was remembered", () => {
    assert.equal(rememberedFor(undefined, sequentialReviewer, "implementer"), undefined);
    assert.equal(
      rememberedFor({ agents: {}, passthrough: {} }, sequentialReviewer, "*"),
      undefined,
    );
  });

  it("reaches the widget as a primitive model id, never a model object", () => {
    const walked = walk({ "fast-path": "change" }, { store: populatedStore() });
    const step = stepById(walked, "model:reviewer");
    assert.equal(step.kind, "select");
    if (step.kind !== "select") return;
    assert.equal(step.initialValue, "gpt-5.6-sol");
    for (const option of step.options) assert.equal(typeof option.value, "string");
  });
});

describe("one model for every agent", () => {
  it("opens on Same for every agent when nothing is remembered", () => {
    assert.equal(initialValueOf(walk(), "same-model"), "shared");
  });

  it("opens on Configure separately when the remembered picks differ", () => {
    const walked = walk({ "fast-path": "change" }, { store: populatedStore() });
    assert.equal(initialValueOf(walked, "same-model"), "separate");
  });

  it("opens on Same for every agent when the remembered picks match", () => {
    const store = populatedStore({
      agents: {
        implementer: { model: "claude-opus-5", effort: "high" },
        reviewer: { model: "claude-opus-5", effort: "high" },
      },
    });
    assert.equal(initialValueOf(walk({ "fast-path": "change" }, { store }), "same-model"), "shared");
  });

  it("opens on Configure separately when only one agent is remembered", () => {
    // Copying the surviving pick onto the other agent would be a choice nobody
    // made; landing on the long walk shows both prompts instead.
    const store = populatedStore();
    delete store.agents.reviewer;
    assert.equal(initialValueOf(walk({}, { store }), "same-model"), "separate");
  });

  it("fans a shared pick out to one entry per agent, and never writes the shared key", () => {
    const plan = walk().plan;
    assert.ok(plan);
    const raw = serializeStoredRun(mergeStoredRun(undefined, runToRemember(plan)));
    assert.deepEqual(JSON.parse(raw).agents, {
      implementer: { model: "claude-opus-5", effort: "high" },
      reviewer: { model: "claude-opus-5", effort: "high" },
    });
    assert.equal(raw.includes('"*"'), false);
    // No `maxParallel`: Implement & Review runs one item at a time, so it was
    // never asked for a wave width and has none to remember.
    assert.deepEqual(Object.keys(JSON.parse(raw)), [
      "version",
      "lastWorkflowId",
      "lastScope",
      "maxWorkItems",
      "agents",
    ]);
  });
});

describe("the confirmation", () => {
  it("leads with the scope and what it will reach, then the agents and the shape", () => {
    assert.deepEqual(stepById(walk(), "confirm").note, [
      "Work scope   Specific SPEC · #418 Universal Work scope",
      "Eligible     3 eligible issues",
      "Implementer  Claude Opus 5 · High",
      "Reviewer     Claude Opus 5 · High",
      "Runs         implement → review, up to 3 issues",
    ]);
  });

  it("names the anchor even for a workflow that walks no work items", () => {
    // `runShape` sees one number and nothing else, which is what keeps the
    // anchor and the scope kind out of every workflow.
    assert.deepEqual(stepById(walk({ workflow: "review-only" }), "confirm").note, [
      "Work scope   Specific SPEC · #418 Universal Work scope",
      "Eligible     3 eligible issues",
      "Reviewer     Claude Opus 5 · High",
      "Runs         review once, origin/main...HEAD",
    ]);
  });

  it("states a partially drained SPEC rather than implying it", () => {
    const walked = walk({ "run-guard": 2 });
    assert.deepEqual(stepById(walked, "confirm").note?.slice(0, 2), [
      "Work scope   Specific SPEC · #418 Universal Work scope",
      "Eligible     up to 2 of 3 eligible",
    ]);
  });

  it("shows the summary only on the confirm screen", () => {
    for (const step of walk().steps) {
      if (step.id !== "confirm") assert.equal(step.note, undefined, step.id);
    }
  });

  it("yields no plan when the run is declined", () => {
    assert.equal(walk({ confirm: "cancel" }).plan, undefined);
  });
});

describe("the run guard bounding the driver's loop", () => {
  /** A dispatch that runs no CLI and touches no git; it only counts its calls. */
  function countingDispatch(): { calls: Agent[]; dispatch: Dispatch } {
    const calls: Agent[] = [];
    const dispatch: Dispatch = (agent) => {
      calls.push(agent);
      return Promise.resolve({ commits: [{ sha: "commit-1" }], baseSha: `sha-${calls.length}` });
    };
    return { calls, dispatch };
  }

  it("cuts the list the driver walks, and is remembered as the run guard", async (t) => {
    // End to end from the answer to the loop: the number the picker collected is
    // what `workList` truncates to, and the driver runs the body once per item —
    // which is the whole of what replaced the workflow's own `for`.
    t.mock.method(console, "log", () => undefined);
    const plan = walk({ "run-guard": 2 }).plan;
    assert.ok(plan);
    assert.equal(plan.maxWorkItems, 2);

    const { calls, dispatch } = countingDispatch();
    const work = workList(plan.scope, plan.maxWorkItems);
    await driveSequential({ work, repo, forItem: () => dispatch, forBranch: () => dispatch }, plan.workflow);

    assert.equal(work.length, 2);
    assert.equal(calls.filter((agent) => agent.id === "implementer").length, 2);
    assert.equal(mergeStoredRun(undefined, runToRemember(plan)).maxWorkItems, 2);
  });
});

describe("Review Only, chosen with an Implement & Review run remembered", () => {
  function walkReviewOnly(): Walk {
    return walk({ "fast-path": "change", workflow: "review-only" }, { store: populatedStore() });
  }

  it("opens on the reviewer's remembered pick, because the agent is the same one", () => {
    const walked = walkReviewOnly();
    assert.equal(initialValueOf(walked, "model:reviewer"), "gpt-5.6-sol");
    assert.equal(initialValueOf(walked, "effort:reviewer"), "high");
  });

  it("leaves the implementer's pick untouched and re-stamps the scope", () => {
    const plan = walkReviewOnly().plan;
    assert.ok(plan);
    const merged = mergeStoredRun(
      populatedStore(),
      runToRemember(plan),
      HOME_ORIGIN,
    );
    assert.deepEqual(merged.agents, {
      implementer: { model: "claude-opus-5", effort: "xhigh" },
      reviewer: { model: "gpt-5.6-sol", effort: "high" },
    });
    assert.deepEqual(merged.lastScope, {
      kind: "specific-spec",
      target: "418",
      origin: HOME_ORIGIN,
    });
  });
});
