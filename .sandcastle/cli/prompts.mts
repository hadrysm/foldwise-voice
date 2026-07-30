// The picker's terminal widgets. Every ANSI escape the picker emits lives behind
// this adapter, and the adapter is deliberately thin: `@clack/prompts` owns the
// drawing, the erasing and the echoed answer line.
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

import { isCancel, select, type Option } from "@clack/prompts";

/**
 * One row of a select. `value` is a primitive because clack matches
 * `initialValue` with strict `===` and silently falls back to the first row when
 * nothing matches — a remembered pick keyed by an object could never match.
 */
export interface Choice<Value extends string | boolean> {
  value: Value;
  label: string;
  hint?: string;
}

/**
 * Ask one single-choice question. `initialValue` only moves the cursor: the
 * question is always shown, so replaying the last run is enter-enter rather
 * than a silent skip. Cancelling (`esc` or `ctrl-c`) resolves with clack's
 * sentinel rather than throwing — test for it with `wasCancelled`.
 */
export async function chooseOne<Value extends string | boolean>(
  message: string,
  choices: readonly Choice<Value>[],
  initialValue?: Value,
): Promise<Value | symbol> {
  // Clack's `Option` is a conditional type, which tsc cannot check `Choice`
  // against while `Value` is still a type parameter. The two shapes are
  // identical once `Value` is a concrete primitive, and the constraint above is
  // what guarantees it always is. Declaring the parameter as `Option<Value>[]`
  // instead would be worse: inference through a conditional type fails, so
  // every call site would widen to `string | boolean`.
  const options = [...choices] as Option<Value>[];
  return select({ message, options, initialValue });
}

/** True when a question was cancelled rather than answered. Narrows the answer. */
export function wasCancelled<Value>(answer: Value | symbol): answer is symbol {
  return isCancel(answer);
}
