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

import { intro, isCancel, log, note, select, text } from "@clack/prompts";
import { availableEfforts } from "../providers/registry.mts";
import {
  applyAnswer,
  initialState,
  nextQuestion,
  resolvePlan,
  summaryByAgent,
  type Answer,
  type NumberQuestion,
  type Question,
  type ResolvedPlan,
} from "./flow.mts";
import { readStoredRun } from "./store.mts";

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

/**
 * Draw one question. `initialValue` only moves the cursor: the question is always
 * shown, so the walk never silently answers for you.
 */
function ask(question: Question): Promise<Answer | symbol> {
  if (question.kind === "number") return askNumber(question);
  return select<string>({
    message: question.prompt,
    options: [...question.options],
    initialValue: question.initialValue,
  });
}

/**
 * Walk the picker and return what to run, or `undefined` if it was cancelled.
 * Nothing here decides what comes next — that is `nextQuestion`, which is why
 * this loop is the same six screens for a workflow it has never seen.
 */
export async function choosePlan(): Promise<ResolvedPlan | undefined> {
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
    "Pick a workflow, then the model and effort for each of its agents.",
    ...(store ? ["Defaults are your last run in this repo."] : []),
  ]);

  let state = initialState(store);
  for (;;) {
    const question = nextQuestion(state, availableEfforts);
    if (!question) break;
    if (question.note) note(question.note.join("\n"), "Ready to run Sandcastle");

    const answer = await ask(question);
    if (wasCancelled(answer)) return undefined;
    state = applyAnswer(state, question, answer);
  }

  return resolvePlan(state);
}

/** The last thing printed before the first agent starts. */
export function printRunHeader(plan: ResolvedPlan): void {
  for (const line of summaryByAgent(plan)) log.step(line);
}
