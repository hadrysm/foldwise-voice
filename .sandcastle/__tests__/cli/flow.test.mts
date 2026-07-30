import type { RunResult } from "@ai-hero/sandcastle";
import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import type { RunModel } from "../../agents/models.mts";
import {
  applyAnswer,
  initialState,
  knobQuestion,
  nextQuestion,
  rememberedFor,
  resolvePlan,
  storeIsReplayable,
  type Answer,
  type EffortsFor,
  type FlowState,
  type Question,
  type ResolvedPlan,
} from "../../cli/flow.mts";
import { mergeStoredRun, serializeStoredRun, type StoredRun } from "../../cli/store.mts";
import type { Agent, Dispatch } from "../../contract.mts";
import { sequentialReviewer } from "../../workflows/sequential-reviewer/workflow.mts";

/**
 * The catalog's own efforts, which is what a CLI advertising everything would
 * report. The real lookup spawns `claude --help`; injecting it is what lets the
 * screen sequence be asserted at all.
 */
const everyEffort: EffortsFor = (model: RunModel) => model.efforts;

/** A remembered run of the registered workflow, with two different models. */
function populatedStore(overrides: Partial<StoredRun> = {}): StoredRun {
  return {
    lastWorkflowId: "sequential-reviewer",
    agents: {
      implementer: { model: "claude-opus-5", effort: "xhigh" },
      reviewer: { model: "gpt-5.6-sol", effort: "high" },
    },
    knobs: { "sequential-reviewer": { maxIterations: 5 } },
    ...overrides,
  };
}

/** Pressing enter: whatever the question opens on. */
function defaultAnswer(question: Question): Answer {
  if (question.kind === "number") return question.defaultValue;
  return question.initialValue ?? question.options[0].value;
}

interface Walk {
  ids: readonly string[];
  questions: readonly Question[];
  state: FlowState;
  plan: ResolvedPlan | undefined;
}

/**
 * Walk the whole flow, answering each question from `answers` or by pressing
 * enter. This is the driver `cli/prompts.mts` runs, minus the terminal.
 */
function walk(answers: Record<string, Answer> = {}, store?: StoredRun): Walk {
  let state = initialState(store);
  const questions: Question[] = [];

  while (questions.length <= 20) {
    const question = nextQuestion(state, everyEffort);
    if (!question) {
      return { questions, ids: questions.map((asked) => asked.id), state, plan: resolvePlan(state) };
    }
    questions.push(question);
    const answer = question.id in answers ? answers[question.id] : defaultAnswer(question);
    const folded = applyAnswer(state, question, answer);
    assert.notEqual(folded, state, "applyAnswer must return a new state, not mutate its input");
    state = folded;
  }

  throw new Error(`The walk never settled: ${questions.map((asked) => asked.id).join(", ")}`);
}

function questionById(walked: Walk, id: string): Question {
  const question = walked.questions.find((asked) => asked.id === id);
  assert.ok(question, `expected the walk to ask ${id}, got ${walked.ids.join(", ")}`);
  return question;
}

describe("the question sequence", () => {
  it("asks workflow → knob → same-model → one model pass → confirm", () => {
    assert.deepEqual(walk().ids, [
      "workflow",
      "knob:maxIterations",
      "same-model",
      "model:*",
      "effort:*",
      "confirm",
    ]);
  });

  it("asks a model and an effort per agent when they are configured separately", () => {
    assert.deepEqual(walk({ "same-model": "separate" }).ids, [
      "workflow",
      "knob:maxIterations",
      "same-model",
      "model:implementer",
      "effort:implementer",
      "model:reviewer",
      "effort:reviewer",
      "confirm",
    ]);
  });

  it("asks four questions for a single-agent, zero-knob workflow", () => {
    // No knob screen because Review Only declares none, and no same-model screen
    // because one agent has nobody to share a model with.
    assert.deepEqual(walk({ workflow: "review-only" }).ids, [
      "workflow",
      "model:reviewer",
      "effort:reviewer",
      "confirm",
    ]);
  });

  it("opens the workflow question on nothing, so a fresh clone lands on registry index 0", () => {
    const question = questionById(walk(), "workflow");
    assert.equal(question.kind, "select");
    if (question.kind !== "select") return;
    assert.equal(question.initialValue, undefined);
    assert.equal(question.options[0].value, "sequential-reviewer");
    assert.equal(walk().plan?.workflow.id, "sequential-reviewer");
  });

  it("does not mutate the state it folds an answer into", () => {
    const before = initialState();
    const question = nextQuestion(before, everyEffort);
    assert.ok(question);
    applyAnswer(before, question, "sequential-reviewer");
    assert.deepEqual(before, initialState());
  });
});

describe("the fast path", () => {
  it("offers a replay first, and starts the run with no confirm screen", () => {
    const walked = walk({}, populatedStore());
    assert.deepEqual(walked.ids, ["fast-path"]);
    assert.equal(walked.plan?.workflow.id, "sequential-reviewer");
  });

  it("names the workflow, every agent's model and effort, and the knob values", () => {
    const question = questionById(walk({}, populatedStore()), "fast-path");
    assert.equal(question.kind, "select");
    const hint = question.kind === "select" ? question.options[0].hint : undefined;
    assert.equal(
      hint,
      "Implement & Review · Claude Opus 5 · Extra High / GPT-5.6 Sol · High · iterations 5",
    );
  });

  it("replays exactly what was remembered", () => {
    const walked = walk({}, populatedStore());
    assert.deepEqual(
      walked.plan?.agents.map((agent) => [agent.agentId, agent.model.id, agent.effort]),
      [
        ["implementer", "claude-opus-5", "xhigh"],
        ["reviewer", "gpt-5.6-sol", "high"],
      ],
    );
    assert.deepEqual(walked.plan?.knobs, { maxIterations: 5 });
  });

  it("is not offered when there is nothing replayable to offer", () => {
    assert.equal(walk({}, { agents: {}, knobs: {} }).ids.includes("fast-path"), false);
  });

  it("walks every question when Change something is chosen", () => {
    assert.deepEqual(walk({ "fast-path": "change" }, populatedStore()).ids, [
      "fast-path",
      "workflow",
      "knob:maxIterations",
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
    const changed = walk({ "fast-path": "change" }, populatedStore());
    const replayed = walk({}, populatedStore());
    assert.deepEqual(changed.plan?.agents, replayed.plan?.agents);
    assert.deepEqual(changed.plan?.knobs, replayed.plan?.knobs);
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

  it("is true for a complete remembered run", () => {
    assert.equal(storeIsReplayable(populatedStore()), true);
  });
});

describe("knob resolution", () => {
  const bucketed = (maxIterations: number): StoredRun =>
    populatedStore({ knobs: { "sequential-reviewer": { maxIterations } } });

  it("uses the declared default when nothing is remembered", () => {
    const question = knobQuestion(initialState(), sequentialReviewer);
    assert.equal(question?.defaultValue, 10);
  });

  it("uses a remembered value that is still in range", () => {
    assert.equal(knobQuestion(initialState(bucketed(3)), sequentialReviewer)?.defaultValue, 3);
  });

  it("drops an out-of-range value to the default rather than clamping it", () => {
    // 50 is the maximum, so a clamp would silently run 50 iterations.
    assert.equal(knobQuestion(initialState(bucketed(9999)), sequentialReviewer)?.defaultValue, 10);
    assert.equal(knobQuestion(initialState(bucketed(0)), sequentialReviewer)?.defaultValue, 10);
  });

  it("drops an out-of-range value on the fast path too", () => {
    assert.deepEqual(walk({}, bucketed(9999)).plan?.knobs, { maxIterations: 10 });
  });

  it("says what it will accept", () => {
    assert.equal(knobQuestion(initialState(bucketed(3)), sequentialReviewer)?.hint, "1–50  ·  enter accepts 3");
  });

  it("asks no knob question once every knob is answered", () => {
    const answered: FlowState = { ...initialState(), knobs: { maxIterations: 4 } };
    assert.equal(knobQuestion(answered, sequentialReviewer), undefined);
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
    assert.equal(rememberedFor({ agents: {}, knobs: {} }, sequentialReviewer, "*"), undefined);
  });

  it("reaches the widget as a primitive model id, never a model object", () => {
    const walked = walk({ "fast-path": "change" }, populatedStore());
    const question = questionById(walked, "model:reviewer");
    assert.equal(question.kind, "select");
    if (question.kind !== "select") return;
    assert.equal(question.initialValue, "gpt-5.6-sol");
    for (const option of question.options) assert.equal(typeof option.value, "string");
  });
});

describe("one model for every agent", () => {
  it("opens on Same for every agent when nothing is remembered", () => {
    const question = questionById(walk(), "same-model");
    assert.equal(question.kind === "select" ? question.initialValue : undefined, "shared");
  });

  it("opens on Configure separately when the remembered picks differ", () => {
    const walked = walk({ "fast-path": "change" }, populatedStore());
    const question = questionById(walked, "same-model");
    assert.equal(question.kind === "select" ? question.initialValue : undefined, "separate");
  });

  it("opens on Same for every agent when the remembered picks match", () => {
    const store = populatedStore({
      agents: {
        implementer: { model: "claude-opus-5", effort: "high" },
        reviewer: { model: "claude-opus-5", effort: "high" },
      },
    });
    const walked = walk({ "fast-path": "change" }, store);
    const question = questionById(walked, "same-model");
    assert.equal(question.kind === "select" ? question.initialValue : undefined, "shared");
  });

  it("opens on Configure separately when only one agent is remembered", () => {
    // Copying the surviving pick onto the other agent would be a choice nobody
    // made; landing on the long walk shows both prompts instead.
    const store = populatedStore();
    delete store.agents.reviewer;
    const walked = walk({}, store);
    const question = questionById(walked, "same-model");
    assert.equal(question.kind === "select" ? question.initialValue : undefined, "separate");
  });

  it("fans a shared pick out to one entry per agent, and never writes the shared key", () => {
    const plan = walk().plan;
    assert.ok(plan);
    const raw = serializeStoredRun(mergeStoredRun(undefined, plan));
    assert.deepEqual(JSON.parse(raw).agents, {
      implementer: { model: "claude-opus-5", effort: "high" },
      reviewer: { model: "claude-opus-5", effort: "high" },
    });
    assert.equal(raw.includes("*"), false);
    assert.deepEqual(Object.keys(JSON.parse(raw)), ["version", "lastWorkflowId", "agents", "knobs"]);
  });
});

describe("the confirmation", () => {
  it("lists one row per agent and one Runs row from runShape", () => {
    const question = questionById(walk(), "confirm");
    assert.deepEqual(question.note, [
      "Implementer  Claude Opus 5 · High",
      "Reviewer     Claude Opus 5 · High",
      "Runs         implement → review, up to 10 issues",
    ]);
  });

  it("shows the summary only on the confirm screen", () => {
    for (const question of walk().questions) {
      if (question.id !== "confirm") assert.equal(question.note, undefined, question.id);
    }
  });

  it("yields no plan when the run is declined", () => {
    assert.equal(walk({ confirm: "cancel" }).plan, undefined);
  });
});

describe("a chosen knob value", () => {
  /** A dispatch that runs no CLI and touches no git; it only counts its calls. */
  function countingDispatch(t: TestContext): { calls: Agent[]; dispatch: Dispatch } {
    t.mock.method(console, "log", () => undefined);
    const calls: Agent[] = [];
    const dispatch: Dispatch = (agent) => {
      calls.push(agent);
      const result: RunResult & { baseSha: string } = {
        iterations: [],
        stdout: "",
        commits: [{ sha: "commit-1" }],
        branch: "feature",
        baseSha: `sha-${calls.length}`,
      };
      return Promise.resolve(result);
    };
    return { calls, dispatch };
  }

  it("drives that many iterations and is remembered under its own workflow", async (t) => {
    const plan = walk({ "knob:maxIterations": 3 }).plan;
    assert.ok(plan);
    assert.deepEqual(plan.knobs, { maxIterations: 3 });

    const { calls, dispatch } = countingDispatch(t);
    await plan.workflow.run({ dispatch, knobs: plan.knobs });
    assert.equal(calls.filter((agent) => agent.id === "implementer").length, 3);

    assert.deepEqual(mergeStoredRun(undefined, plan).knobs, {
      "sequential-reviewer": { maxIterations: 3 },
    });
  });
});

describe("Review Only, chosen with an Implement & Review run remembered", () => {
  function walkReviewOnly(): Walk {
    return walk({ "fast-path": "change", workflow: "review-only" }, populatedStore());
  }

  it("opens on the reviewer's remembered pick, because the agent is the same one", () => {
    const walked = walkReviewOnly();
    const model = questionById(walked, "model:reviewer");
    assert.equal(model.kind === "select" ? model.initialValue : undefined, "gpt-5.6-sol");
    const effort = questionById(walked, "effort:reviewer");
    assert.equal(effort.kind === "select" ? effort.initialValue : undefined, "high");
  });

  it("confirms with one agent row and Review Only's own run shape", () => {
    assert.deepEqual(questionById(walkReviewOnly(), "confirm").note, [
      "Reviewer  GPT-5.6 Sol · High",
      "Runs      review once, origin/main...HEAD",
    ]);
  });

  it("leaves the implementer's pick and the other workflow's knob bucket untouched", () => {
    const plan = walkReviewOnly().plan;
    assert.ok(plan);
    assert.deepEqual(mergeStoredRun(populatedStore(), plan), {
      lastWorkflowId: "review-only",
      agents: {
        implementer: { model: "claude-opus-5", effort: "xhigh" },
        reviewer: { model: "gpt-5.6-sol", effort: "high" },
      },
      knobs: { "sequential-reviewer": { maxIterations: 5 } },
    });
  });
});
