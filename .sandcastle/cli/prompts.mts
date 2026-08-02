// The shell around `cli/flow.mts`: it walks the flow's questions, draws each one
// and hands the answer back. Every ANSI escape the picker emits lives behind this
// module, and the drawing itself is `@clack/prompts` — the only widget logic here
// is the typed number field, which clack has no primitive for.
//
// Why a library rather than the widget this replaces: that widget wrapped no
// labels and counted array entries rather than terminal rows when erasing, so at
// 48 columns a single arrow press stranded a copy of its own prompt on screen.
// Clack hard-wraps the whole frame before diffing it, which makes counting
// newlines the same thing as counting rows
// (see docs/research/picker-widget-lift-or-replace.md).
//
// `.sandcastle/package.json` declares `@clack/prompts` directly even though
// Sandcastle already pulls it in as its one and only runtime dependency. That
// declaration is the pin: there is no width regression test here, so the
// dependency entry is what stops a transitive hoist from moving underneath us.

import { intro, isCancel, log, note, select, spinner, text } from "@clack/prompts";
import { availableEfforts } from "../providers/registry.mts";
import { parseTarget, resolveScope } from "../scope/github.mts";
import {
  applyAnswer,
  initialState,
  nextStep,
  resolvePlan,
  scopeSummary,
  summaryByAgent,
  toWorkScope,
  type Answer,
  type NumberQuestion,
  type ResolvedPlan,
  type ResolveScope,
  type ResolveStep,
  type ScopeResolution,
  type SelectQuestion,
  type Step,
} from "./flow.mts";
import { readStoredRun, worktreeOrigin } from "./store.mts";

/** True when a question was cancelled rather than answered. Narrows the answer. */
function wasCancelled<Value>(answer: Value | symbol): answer is symbol {
  return isCancel(answer);
}

/**
 * Refuse a typed knob value rather than clamp it: a number outside the bounds is
 * a mistake to correct, and a silent clamp would run a count nobody chose. An
 * empty field is valid — clack substitutes the default *after* validation runs,
 * so "" means "accept what the hint says enter accepts".
 */
export function validateInteger(
  raw: string | undefined,
  bounds: { min: number; max: number },
): string | undefined {
  const typed = raw?.trim() ?? "";
  if (!typed) return undefined;
  if (!/^-?\d+$/.test(typed)) return "Enter a whole number.";
  const value = Number(typed);
  if (value < bounds.min || value > bounds.max) {
    return `Enter a number between ${bounds.min} and ${bounds.max}.`;
  }
  return undefined;
}

/**
 * Refuse a target the resolver could not build a request path from, before a
 * spinner starts. `parseTarget` is the same parser the fetch layer runs, so what
 * this field accepts and what GitHub is asked for cannot drift apart.
 */
export function validateTarget(raw: string | undefined): string | undefined {
  const typed = raw?.trim() ?? "";
  if (!typed) return "Enter an issue number or a GitHub issue URL.";
  try {
    parseTarget(typed);
    return undefined;
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

async function askNumber(question: NumberQuestion): Promise<number | symbol> {
  const answer = await text({
    message: question.prompt,
    placeholder: question.hint,
    defaultValue: String(question.defaultValue),
    validate: (value) => validateInteger(value, question),
  });
  if (wasCancelled(answer)) return answer;
  return Number(answer);
}

function askSelect(question: SelectQuestion): Promise<string | symbol> {
  return select<string>({
    message: question.prompt,
    options: [...question.options],
    initialValue: question.initialValue,
  });
}

/**
 * The one step that is not a question: ask for a target if this walk still needs
 * one, then go to GitHub. The outcome — success or failure — folds back in as an
 * answer, because the recovery it leads to is `cli/flow.mts`'s decision, not
 * this module's.
 */
async function askResolve(
  step: ResolveStep,
  resolve: ResolveScope,
): Promise<ScopeResolution | symbol> {
  let target = step.initialValue ?? "";
  if (step.needsTarget) {
    const typed = await text({
      message: step.prompt,
      // Deliberately not a URL literal: `scope/github.mts` is the only module
      // allowed to spell an endpoint, and a sweep enforces it.
      placeholder: "an issue number, or the issue URL from your browser",
      initialValue: step.initialValue,
      validate: validateTarget,
    });
    if (wasCancelled(typed)) return typed;
    target = typed.trim();
  }

  const progress = spinner();
  progress.start("Resolving this Work scope with GitHub");
  const outcome = await resolve(toWorkScope(step.scope, target));
  progress.stop(outcome.ok ? "Work scope resolved" : "Work scope not resolved");
  return { target: step.needsTarget ? target : undefined, outcome };
}

/**
 * Draw one step. `initialValue` only moves the cursor: the question is always
 * shown, so the walk never silently answers for you.
 */
function ask(step: Step, resolve: ResolveScope): Promise<Answer | symbol> {
  switch (step.kind) {
    case "number":
      return askNumber(step);
    case "resolve":
      return askResolve(step, resolve);
    case "select":
      return askSelect(step);
  }
}

/**
 * Walk the picker and return what to run, or `undefined` if it was cancelled.
 * Nothing here decides what comes next — that is `nextStep`, which is why this
 * loop is the same screens for a workflow it has never seen, and why the point
 * at which GitHub is asked is not a decision made in this file.
 *
 * Cancellation is safe at every prompt: nothing has been dispatched, and the
 * store is only written after `prepare()` succeeds.
 */
export async function choosePlan(
  resolve: ResolveScope = resolveScope,
): Promise<ResolvedPlan | undefined> {
  // Clack drives the terminal in raw mode, so it needs a real TTY just as the
  // widget it replaced did. It calls `setRawMode` optionally, so without this
  // guard a stdin that lacks it would render a picker whose arrow keys do
  // nothing rather than say why.
  if (!process.stdin.isTTY || !process.stdout.isTTY || !process.stdin.setRawMode) {
    throw new Error("Sandcastle must be started from an interactive terminal.");
  }

  const store = readStoredRun();

  intro("Sandcastle");
  log.message([
    "Choose what this run works on, then the workflow and the model behind each agent.",
    ...(store ? ["Defaults are your last run in this repo."] : []),
  ]);

  let state = initialState(store, worktreeOrigin());
  let announced: string | undefined;
  for (;;) {
    const step = nextStep(state, availableEfforts);
    if (!step) break;
    if (step.note) note(step.note.join("\n"), step.noteTitle ?? "Sandcastle");

    const answer = await ask(step, resolve);
    if (wasCancelled(answer)) return undefined;
    state = applyAnswer(state, step, answer);

    // Said once per resolution, and only for a scope that survived judgment —
    // the failed ones speak for themselves, on the recovery screen.
    const resolved = state.resolved;
    if (resolved && resolved.snapshot.snapshotId !== announced) {
      announced = resolved.snapshot.snapshotId;
      note(scopeSummary(resolved).join("\n"), "Work scope");
    }
  }

  return resolvePlan(state);
}

/** The last thing printed before the first agent starts. */
export function printRunHeader(plan: ResolvedPlan): void {
  for (const line of summaryByAgent(plan)) log.step(line);
}
