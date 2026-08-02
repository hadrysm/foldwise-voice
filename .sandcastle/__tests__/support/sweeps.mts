// The rules half of tier 3: what a sweep is looking for, as pure functions.
//
// Every rule here takes the source it judges as an argument and hands back what
// it found. Two things follow, and both are why the rules are not simply
// written inline in the suites that run them:
//
//   1. **A rule can be shown to fail.** `__tests__/sweeps/planted.test.mts`
//      feeds each one a deliberately-planted violation and asserts it is
//      caught. A sweep nobody has seen fail is a sweep nobody knows works, and
//      a green suite looks exactly the same either way.
//   2. **A rule cannot quietly cover nothing.** Each one reports an empty
//      corpus as a violation of itself. The failure this tier exists to prevent
//      is a boundary rotting while the suite stays green, and "the enumeration
//      returned nothing" is the quietest way that happens.
//
// The admission rule the whole tier turns on: **a sweep enumerates from a
// registry or the filesystem, never from a literal list of today's cases.** The
// lists that do appear below are *vocabularies* — which commands are
// framework-neutral, which git subcommands only read, which tracker acts a run
// may perform — and every one is an allow-list, so the case they do not name is
// the case that gets reported.

import * as ts from "typescript";
import {
  arrayLiterals,
  at,
  calleeName,
  calls,
  callsIn,
  declaredValue,
  enclosingName,
  imports,
  interfaceMembers,
  literals,
  literalsIn,
  openingText,
  propertyValue,
  walk,
  wholeString,
  type Closure,
  type Module,
} from "./source.mts";

/** One thing a sweep found, named where a reader can go and look at it. */
export interface Violation {
  /** `drivers/git.mts:151`, or a prompt's `wave-parallel/plan-prompt.md`. */
  readonly where: string;
  /** What is wrong, and — where the rule has one — what to write instead. */
  readonly detail: string;
}

/**
 * Findings as an assertion message.
 *
 * One line each, and never a count: a sweep that says *3 violations* has told
 * the reader to go and run it themselves.
 */
export function describeViolations(found: readonly Violation[]): string {
  return found.map((violation) => `\n  ${violation.where} — ${violation.detail}`).join("");
}

/** A corpus that enumerated to nothing is a rule that stopped covering anything. */
function coversNothing(rule: string): Violation {
  return {
    where: rule,
    detail: "this sweep enumerated nothing, so it is no longer covering what it names",
  };
}

// ---------------------------------------------------------------------------
// No toolchain command reaches the runner or a driver
// ---------------------------------------------------------------------------

/**
 * The rule, in one line: *the runner may run a command whose output it
 * discards; it may never run a command whose exit code it branches on — except
 * git's.*
 *
 * `gh` joins git for the reason git is excepted: neither says anything about
 * what language the workspace is written in, so both would be identical in a
 * web or a mobile repository. `swift package resolve` was hardcoded in
 * `runner.mts` before slice 1, and this is what stops it coming back — in the
 * fourth driver as much as in the three that exist.
 */
const FRAMEWORK_NEUTRAL_COMMANDS: ReadonlySet<string> = new Set(["git", "gh"]);

/** Everything `node:child_process` offers that starts a process. */
const SPAWNERS: ReadonlySet<string> = new Set([
  "exec",
  "execFile",
  "execFileSync",
  "execSync",
  "fork",
  "spawn",
  "spawnSync",
]);

const CHILD_PROCESS = "node:child_process";

/** One process a module starts, and the program it was told to run. */
interface Spawn {
  readonly call: ts.CallExpression;
  /** The callee as this file writes it, so an alias still reads as itself. */
  readonly callee: string;
  /** `null` when the program name is hidden behind a substitution. */
  readonly program: string | null;
}

/**
 * Every process one module starts.
 *
 * Callees are matched under the name the *file* uses, so `{ execSync as run }`
 * is still recognised: an alias would otherwise take a module out of every rule
 * built on this, which is the quietest possible way out of one.
 */
function spawns(module: Module): readonly Spawn[] {
  const spawners = new Set(SPAWNERS);
  for (const imported of imports(module)) {
    if (imported.specifier !== CHILD_PROCESS) continue;
    for (const binding of imported.bindings) {
      if (SPAWNERS.has(binding.imported)) spawners.add(binding.local);
    }
  }

  return calls(module).flatMap((call) => {
    const callee = calleeName(call);
    if (callee === null || !spawners.has(callee)) return [];
    const opening = openingText(call.arguments[0]);
    return [
      { call, callee, program: opening === null ? null : (opening.trim().split(/\s+/)[0] ?? "") },
    ];
  });
}

/** Nothing in these modules runs a command that is not git or `gh`. */
export function commandsAreFrameworkNeutral(modules: readonly Module[]): readonly Violation[] {
  if (modules.length === 0) return [coversNothing("commandsAreFrameworkNeutral")];

  return modules.flatMap((module) =>
    spawns(module).flatMap((spawn) => {
      if (spawn.program === null) {
        return [
          {
            where: at(module, spawn.call),
            detail: `${spawn.callee} is given a command this sweep cannot read; write the program name as literal text`,
          },
        ];
      }
      if (FRAMEWORK_NEUTRAL_COMMANDS.has(spawn.program)) return [];
      return [
        {
          where: at(module, spawn.call),
          detail: `runs \`${spawn.program}\`, which is a toolchain command — it belongs in repo.mts, passed through and never branched on`,
        },
      ];
    }),
  );
}

// ---------------------------------------------------------------------------
// No force flag anywhere in a driver
// ---------------------------------------------------------------------------

/**
 * `--force`, `-f` and `-D`, including inside a short-flag cluster.
 *
 * The whole safety argument is that git refuses: `git worktree remove` refuses
 * a worktree holding modified or untracked files, and `git branch -d` refuses
 * an unmerged branch. A flag takes that refusal away, so a run could destroy
 * work no human has seen. `-d` and `--no-ff` are deliberately not matched —
 * the pattern is a short cluster or a `--force…` long form, never a substring.
 */
function destroysWork(token: string): boolean {
  if (token.startsWith("--force")) return true;
  if (!/^-[A-Za-z]+$/.test(token)) return false;
  return token.includes("f") || token.includes("D");
}

/**
 * Every local name that reaches git, however many helpers deep.
 *
 * A driver never calls `execFileSync` beside its flags: `drivers/git.mts` binds
 * one arrow function to the spawn and everything else in the file goes through
 * it — and `attempt` goes through *that*. So the seed is the function a git
 * spawn is written inside, and the fixpoint is every function that calls one
 * already in the set. Without it the rule either reads the whole file, which
 * catches `tail -f` in a log hint, or reads only the spawn, which catches
 * nothing at all.
 */
function reachesGit(module: Module): ReadonlySet<string> {
  const reaching = new Set<string>();
  for (const spawn of spawns(module)) {
    if (spawn.program !== "git") continue;
    const name = enclosingName(spawn.call);
    if (name !== null) reaching.add(name);
  }

  // Functions only. `const before = headSha()` forwards to git in the sense
  // that it calls something that does, but it is a SHA rather than a way to
  // reach git, and admitting it would put every value in the module in the set.
  const bodies = new Map<string, ts.Node>();
  walk(module, (node) => {
    if (ts.isFunctionDeclaration(node) && node.name) bodies.set(node.name.text, node);
    if (!ts.isVariableDeclaration(node) || !ts.isIdentifier(node.name)) return;
    const initializer = node.initializer;
    if (!initializer) return;
    if (ts.isArrowFunction(initializer) || ts.isFunctionExpression(initializer)) {
      bodies.set(node.name.text, initializer);
    }
  });

  for (let grew = true; grew; ) {
    grew = false;
    for (const [name, body] of bodies) {
      if (reaching.has(name)) continue;
      const forwards = callsIn(body).some((call) => {
        const callee = calleeName(call);
        return callee !== null && callee !== name && reaching.has(callee);
      });
      if (!forwards) continue;
      reaching.add(name);
      grew = true;
    }
  }
  return reaching;
}

/**
 * No driver hands git a flag that would override its refusal to destroy work.
 *
 * Scoped to arguments that actually reach git, rather than to every string in
 * the file. Both halves of that matter: a text scan over `drivers/git.mts`
 * finds the header explaining that the module uses no force flag, and a scan
 * over string literals alone finds `tail -f` in a log hint — neither of which
 * is a flag anybody passes to anything.
 *
 * **What it does not reach**, said out loud rather than left to be discovered:
 * the helper chain is followed *within* one module, so a flag handed across a
 * module boundary into something like `WaveGit.deleteBranch` would not be seen.
 * Nothing can be handed that way today — every `WaveGit` method takes a branch
 * or a path and no flags at all — and the day one takes a flag, that signature
 * is the change to argue with rather than this rule.
 */
export function cleanupIsUnforced(modules: readonly Module[]): readonly Violation[] {
  if (modules.length === 0) return [coversNothing("cleanupIsUnforced")];

  const found: Violation[] = [];
  for (const module of modules) {
    const reaching = reachesGit(module);
    const direct = new Set(
      spawns(module)
        .filter((spawn) => spawn.program === "git")
        .map((spawn) => spawn.call),
    );
    for (const call of calls(module)) {
      const callee = calleeName(call);
      if (!direct.has(call) && (callee === null || !reaching.has(callee))) continue;

      for (const argument of call.arguments) {
        for (const literal of literalsIn(argument)) {
          for (const token of literal.value.split(/\s+/).filter(destroysWork)) {
            found.push({
              where: at(module, literal.node),
              detail: `passes \`${token}\` to git, and a driver's cleanup is safe only while git is free to refuse it`,
            });
          }
        }
      }
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// A worktree variant ships the same prompts as the workflow it copies
// ---------------------------------------------------------------------------

export interface WorkflowPrompts {
  readonly id: string;
  /** The body's own source. Two workflows with the same body are the same workflow. */
  readonly body: string;
  /** Filename to contents, for every `.md` in the workflow's folder. */
  readonly prompts: ReadonlyMap<string, string>;
}

/**
 * Two workflows that supply the same loop body ship the same prompts.
 *
 * Keyed on the *body* rather than on a pair of names, which is what keeps it
 * enumerated: a third copy is covered the day it lands, and a copy that starts
 * to diverge is caught by the same assertion. The claim underneath is the
 * seam's strongest — the shape a run takes belongs entirely to the driver, so
 * the same six lines run one item at a time on the host checkout under one
 * declaration and three items in three worktrees under another. If the bodies
 * ever stop matching, something crossed the seam that should not have, which is
 * why *no two workflows share a body* is itself reported.
 */
export function sharedPromptsMatch(workflows: readonly WorkflowPrompts[]): readonly Violation[] {
  const byBody = new Map<string, WorkflowPrompts[]>();
  for (const workflow of workflows) {
    const group = byBody.get(workflow.body);
    if (group) group.push(workflow);
    else byBody.set(workflow.body, [workflow]);
  }

  const copies = [...byBody.values()].filter((group) => group.length > 1);
  if (copies.length === 0) {
    return [
      {
        where: "sharedPromptsMatch",
        detail:
          "no two workflows supply the same body any more, so nothing is a copy and this sweep covers nothing",
      },
    ];
  }

  const found: Violation[] = [];
  for (const [first, ...rest] of copies) {
    if (!first) continue;
    for (const other of rest) {
      for (const [file, text] of first.prompts) {
        const theirs = other.prompts.get(file);
        if (theirs === undefined || theirs === text) continue;
        found.push({
          where: `${other.id}/${file}`,
          detail: `differs from ${first.id}/${file}, and the two workflows supply the same body — a copy that drifts is a difference the driver seam cannot explain`,
        });
      }
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// Reserved prompt-arg names do not collide
// ---------------------------------------------------------------------------

/** One prompt-arg name, and the file that writes or expands it. */
export interface NamedUse {
  readonly where: string;
  readonly name: string;
}

export interface PromptArgUse {
  /** `RESERVED_PROMPT_ARGS` — the names the runner and its drivers write. */
  readonly reserved: readonly string[];
  /** Every upper-case key a runner- or driver-side object literal actually sets. */
  readonly written: readonly string[];
  /** Every key a workflow body sets through `promptArgs`. */
  readonly fromBodies: readonly NamedUse[];
  /** Every `{{NAME}}` any shipped prompt expands. */
  readonly placeholders: readonly NamedUse[];
}

/**
 * The five names the runner writes stay disjoint from the one a body writes,
 * and every `{{NAME}}` in a prompt has somebody writing it.
 *
 * At five against one this looks settled, which is exactly why it is asserted:
 * a collision is silent in both directions — the runner winning drops a
 * `REVIEW_BASE` a body depends on, and the body winning lets a workflow tell an
 * agent it is working on something else, which is work selection through the
 * one door left open. A `{{NAME}}` nobody writes is the quieter half:
 * `preprocessPrompt` leaves an unknown placeholder in the prompt verbatim, so
 * the agent reads it as prose.
 */
export function promptArgNamesAreDisjoint(use: PromptArgUse): readonly Violation[] {
  const found: Violation[] = [];
  if (use.placeholders.length === 0) found.push(coversNothing("promptArgNamesAreDisjoint"));

  const reserved = new Set(use.reserved);
  if (reserved.size !== use.reserved.length) {
    found.push({ where: "runner.mts", detail: "RESERVED_PROMPT_ARGS names something twice" });
  }
  for (const name of reserved) {
    if (use.written.includes(name)) continue;
    found.push({
      where: "runner.mts",
      detail: `reserves ${name}, which no runner or driver writes any more — a reserved name nobody writes only blocks a body`,
    });
  }

  const writable = new Set<string>(reserved);
  for (const body of use.fromBodies) {
    writable.add(body.name);
    if (!reserved.has(body.name)) continue;
    found.push({
      where: body.where,
      detail: `sets ${body.name}, which the runner reserves — the scope is not a workflow's to name`,
    });
  }

  for (const placeholder of use.placeholders) {
    if (writable.has(placeholder.name)) continue;
    found.push({
      where: placeholder.where,
      detail: `expands {{${placeholder.name}}}, which nothing writes — the agent reads it as prose`,
    });
  }
  return found;
}

// ---------------------------------------------------------------------------
// The contract knows nothing of Sandcastle
// ---------------------------------------------------------------------------

const SANDCASTLE_PACKAGE = "@ai-hero/sandcastle";

/**
 * Nothing the contract can reach imports Sandcastle, type-only included.
 *
 * Stated over the whole import closure rather than over `contract.mts` alone,
 * because a re-export one module along is the same leak by a longer route. And
 * *imports none* is what makes *exports none* structural: a module that never
 * names the package has no Sandcastle type to export, so the allow-list cannot
 * widen when an upgrade changes `RunResult` — which is precisely how the old
 * `Omit<RunOptions, …>` denylist was defeated by its own return type.
 */
export function nothingReachesSandcastle(closure: Closure): readonly Violation[] {
  if (closure.modules.length === 0) return [coversNothing("nothingReachesSandcastle")];

  const found: Violation[] = closure.unresolved.map((miss) => ({
    where: miss.where,
    detail: `imports ${miss.specifier}, which resolves to no file — this sweep cannot follow it`,
  }));

  for (const module of closure.modules) {
    for (const imported of imports(module)) {
      if (!imported.specifier.startsWith(SANDCASTLE_PACKAGE)) continue;
      found.push({
        where: at(module, imported.node),
        detail: `imports ${imported.specifier}; Sandcastle is an implementation detail below the contract, and a type-only import is the same leak`,
      });
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// The run corrects the tracker and never closes anything
// ---------------------------------------------------------------------------

/** Reopen, comment, label. There is no fourth, and there is deliberately no close. */
const TRACKER_ACTS: ReadonlySet<string> = new Set(["reopen", "comment", "edit"]);

/**
 * The three writes a run makes, and the one it must never make.
 *
 * A runner that could close an issue would be making the judgment
 * `docs/agents/triage-labels.md` reserves for a human — and a wrongly-closed
 * SPEC is far harder to notice than a wrongly-labelled open one. The reopen
 * path is where it would slip in, because reopening and closing are the same
 * `gh` noun with one verb changed.
 *
 * Enumerated from the `gh` argument vectors rather than from the three call
 * sites: `ghTracker` forwards its vector through a helper, so the vector is
 * where the subcommand is actually written down.
 */
export function trackerOnlyCorrects(modules: readonly Module[]): readonly Violation[] {
  if (modules.length === 0) return [coversNothing("trackerOnlyCorrects")];

  const found: Violation[] = [];
  let vectors = 0;

  for (const module of modules) {
    for (const array of arrayLiterals(module)) {
      if (wholeString(array.elements[0]) !== "issue") continue;
      vectors += 1;
      const act = wholeString(array.elements[1]);
      if (act !== null && TRACKER_ACTS.has(act)) continue;
      found.push({
        where: at(module, array),
        detail: `composes \`gh issue ${act ?? "?"}\`; a run may only reopen, comment and edit`,
      });
    }

    for (const literal of literals(module)) {
      if (literal.value !== "close") continue;
      found.push({
        where: at(module, literal.node),
        detail:
          "names `close`; the runner never closes an issue, and the implementer closes its own",
      });
    }

    for (const member of interfaceMembers(module, "Tracker") ?? []) {
      if (!/close/i.test(member)) continue;
      found.push({
        where: `${module.name} · Tracker.${member}`,
        detail: "gives a driver a way to close an issue, which no run may do",
      });
    }
  }

  if (vectors === 0) found.push(coversNothing("trackerOnlyCorrects"));
  return found;
}

// ---------------------------------------------------------------------------
// Every comment body the run composes leads with the run-report marker
// ---------------------------------------------------------------------------

/** One `Tracker` write, and the function whose return value became its body. */
export interface Composer {
  readonly where: string;
  /** `null` when the body is not traceable to a call in the same module. */
  readonly name: string | null;
}

/** The two `Tracker` methods that carry a body. `addLabel` carries a label. */
const BODY_WRITES: ReadonlySet<string> = new Set(["reopen", "comment"]);

/**
 * Which function composed each comment body the run writes to GitHub.
 *
 * Discovery rather than a rule, because the two halves of this question live in
 * different places: syntax settles *which* functions compose a body, and the
 * marker is one call away — the composers are pure, so the suite calls them.
 * Pairing the two is what makes a third composer added later fail loudly
 * instead of going unchecked.
 */
export function commentComposers(modules: readonly Module[]): readonly Composer[] {
  const found: Composer[] = [];
  for (const module of modules) {
    for (const call of calls(module)) {
      const callee = calleeName(call);
      if (callee === null || !BODY_WRITES.has(callee)) continue;
      // A tracker write is `(issueNumber, body)`. Anything else wearing these
      // names — a helper of a different shape — is not one of the three acts.
      if (call.arguments.length !== 2) continue;

      const argument = call.arguments[1];
      const source =
        argument && ts.isIdentifier(argument) ? declaredValue(module, argument.text) : argument;
      found.push({
        where: at(module, call),
        name: source && ts.isCallExpression(source) ? calleeName(source) : null,
      });
    }
  }
  return found;
}

/**
 * Every composed body opens with the run-report marker, on the one line the
 * snapshot's comment normalization looks at.
 *
 * The marker is what stops a run's own bookkeeping re-entering a later run's
 * prompt: normalization drops any comment carrying it, so the fifth run of one
 * SPEC does not read four previous reports as evidence about the work. A body
 * that forgets it becomes evidence — silently, and plausibly.
 *
 * `bodies` is keyed by composer name, so a composer the sweep discovered but
 * the suite has no sample of is reported rather than skipped.
 */
export function composedBodiesCarryTheMarker(
  composers: readonly Composer[],
  bodies: ReadonlyMap<string, string>,
  marker: string,
): readonly Violation[] {
  if (composers.length === 0) return [coversNothing("composedBodiesCarryTheMarker")];

  const found: Violation[] = [];
  for (const composer of composers) {
    if (composer.name === null) {
      found.push({
        where: composer.where,
        detail: "writes a comment body this sweep cannot trace back to a composer",
      });
      continue;
    }
    const body = bodies.get(composer.name);
    if (body === undefined) {
      found.push({
        where: composer.where,
        detail: `composes its body with ${composer.name}, which this suite has no sample of — add one`,
      });
      continue;
    }
    if (body.split("\n", 1)[0] === marker) continue;
    found.push({
      where: `${composer.where} · ${composer.name}`,
      detail: `does not open with ${marker}, so normalization will not drop it and a later run reads it as evidence`,
    });
  }
  return found;
}

// ---------------------------------------------------------------------------
// No prompt mutates git state in a block of its own
// ---------------------------------------------------------------------------

export interface Prompt {
  /** `review-only/review-prompt.md`. */
  readonly name: string;
  readonly text: string;
}

/** The shipped expander's own pattern: a command may not contain a backtick. */
const SHELL_BLOCK = /!`([^`]+)`/g;

/**
 * Git subcommands that only read.
 *
 * An allow-list, so a subcommand nobody has written yet is reported rather than
 * assumed safe — including a read-only one, which is the direction that costs a
 * deliberate line here instead of a silent race in production.
 */
const GIT_READS: ReadonlySet<string> = new Set([
  "blame",
  "cat-file",
  "describe",
  "diff",
  "grep",
  "log",
  "ls-files",
  "ls-remote",
  "ls-tree",
  "merge-base",
  "name-rev",
  "rev-list",
  "rev-parse",
  "shortlog",
  "show",
  "status",
  "symbolic-ref",
]);

/** What the shell is left running once the chain finishes. */
function lastSegment(command: string): string {
  const segments = command
    .split(/&&|\|\||;|\|/)
    .map((segment) => segment.trim())
    .filter(Boolean);
  return segments[segments.length - 1] ?? "";
}

/**
 * No shell block leaves a git mutation as its last act.
 *
 * `preprocessPrompt` expands every block with `{ concurrency: "unbounded" }`,
 * so document order decides only where output is spliced back in — never what
 * runs first. A block that mutates git state and stops there is therefore a
 * block some *other* block is racing: #417 is `git fetch origin main` on one
 * line and `git diff origin/main...HEAD` ten lines below, and the reviewer
 * reviews a stale base while completing normally and naming its axes.
 *
 * The check is the chain's **last** segment, which is what makes the fix
 * expressible: `git fetch origin main && git diff origin/main...HEAD` mutates
 * and then consumes its own mutation, so the ordering is the shell's rather
 * than the scheduler's. The existing include-hygiene sweep cannot see any of
 * this — it asks whether a block is well formed, and has no notion of one block
 * depending on another block's *effect*.
 */
export function shellBlocksLeaveGitAlone(prompts: readonly Prompt[]): readonly Violation[] {
  if (prompts.length === 0) return [coversNothing("shellBlocksLeaveGitAlone")];

  const found: Violation[] = [];
  for (const prompt of prompts) {
    for (const match of prompt.text.matchAll(SHELL_BLOCK)) {
      const tail = lastSegment(match[1] ?? "");
      const tokens = tail.split(/\s+/).filter(Boolean);
      if (tokens[0] !== "git") continue;
      const subcommand = tokens.slice(1).find((token) => !token.startsWith("-"));
      if (subcommand !== undefined && GIT_READS.has(subcommand)) continue;
      found.push({
        where: prompt.name,
        detail: `ends a shell block on \`git ${subcommand ?? ""}\`, which does not only read — every block expands concurrently, so whatever depends on it is racing it; chain the read onto it with && instead`,
      });
    }
  }
  return found;
}

// ---------------------------------------------------------------------------
// What a sweep already knows about
// ---------------------------------------------------------------------------

/**
 * A prompt's own declaration that it holds a defect somebody has already filed.
 *
 * `<!-- sandcastle-known-defect: 417 — why -->`, written in the prompt rather
 * than in a list inside the suite. Two reasons, and the second is the one that
 * matters: a list in the suite would be a literal array of today's cases, which
 * is the one thing the admission rule forbids — and a reader who opens the
 * prompt would find nothing saying it is knowingly broken.
 */
const KNOWN_DEFECT = /<!--\s*sandcastle-known-defect:\s*(\d+)/g;

export function knownDefects(prompts: readonly Prompt[]): ReadonlyMap<string, number> {
  const declared = new Map<string, number>();
  for (const prompt of prompts) {
    for (const match of prompt.text.matchAll(KNOWN_DEFECT)) {
      declared.set(prompt.name, Number(match[1]));
    }
  }
  return declared;
}

/**
 * What a sweep found, against what the source says it already knows.
 *
 * A register, not an exemption, and the difference is that it is reconciled in
 * **both** directions: a file that violates without declaring one is reported,
 * and a file that declares one and has stopped violating is reported too. So a
 * declaration cannot outlive the defect it records — the slice that fixes the
 * file has to delete the line, and a *second* defect can never hide behind the
 * first, because the moment the first is fixed the declaration fails.
 *
 * This exists because a rule and the instance it catches can belong to
 * different slices. Shipping the rule silent until its instance is fixed would
 * be the silent cap this whole tier is against; shipping it red would be a
 * suite nobody can read.
 */
export function reconcileKnownDefects(
  found: readonly Violation[],
  declared: ReadonlyMap<string, number>,
): readonly Violation[] {
  const violating = new Set(found.map((violation) => violation.where));

  const undeclared = found.filter((violation) => !declared.has(violation.where));
  const stale = [...declared]
    .filter(([where]) => !violating.has(where))
    .map(([where, issue]) => ({
      where,
      detail: `declares #${issue} as a known defect and no longer holds one — delete the sandcastle-known-defect line`,
    }));

  return [...undeclared, ...stale];
}

// ---------------------------------------------------------------------------
// A consult's prompt emits the tag the runner reads
// ---------------------------------------------------------------------------

/** One `core.consult` call, resolved to the prompt it runs and the tag it reads. */
export interface Consultation {
  readonly where: string;
  /** `null` when the option is not written as text this sweep can resolve. */
  readonly promptFile: string | null;
  readonly tag: string | null;
}

/**
 * Every driver-internal consult, with its prompt file and tag resolved.
 *
 * Both options are written as module constants rather than inline, so each is
 * followed one hop to its declaration — across all the modules handed in,
 * because the constant and the call need not live in the same file.
 */
export function consultations(modules: readonly Module[]): readonly Consultation[] {
  const resolveText = (node: ts.Expression | null): string | null => {
    if (node === null) return null;
    const direct = wholeString(node);
    if (direct !== null) return direct;
    if (!ts.isIdentifier(node)) return null;
    for (const module of modules) {
      const text = wholeString(declaredValue(module, node.text));
      if (text !== null) return text;
    }
    return null;
  };

  const found: Consultation[] = [];
  for (const module of modules) {
    for (const call of calls(module)) {
      if (calleeName(call) !== "consult") continue;
      const options = call.arguments[1];
      if (!options || !ts.isObjectLiteralExpression(options)) {
        found.push({ where: at(module, call), promptFile: null, tag: null });
        continue;
      }
      found.push({
        where: at(module, call),
        promptFile: resolveText(propertyValue(options, "promptFile")),
        tag: resolveText(propertyValue(options, "tag")),
      });
    }
  }
  return found;
}

/**
 * A prompt whose dispatch asks for structured output says the tag out loud.
 *
 * `Output.object({ tag })` reads one XML block out of whatever the agent wrote,
 * so a prompt that never shows the tag buys one shape retry and then a failure
 * — which, for the Planner, is a silent fall back to the computed wave on every
 * wave of every run.
 */
export function consultTagsAppearInPrompts(
  found: readonly Consultation[],
  prompts: readonly Prompt[],
): readonly Violation[] {
  if (found.length === 0) return [coversNothing("consultTagsAppearInPrompts")];

  const violations: Violation[] = [];
  for (const consultation of found) {
    const { promptFile, tag } = consultation;
    if (promptFile === null || tag === null) {
      violations.push({
        where: consultation.where,
        detail: "names its prompt file or its tag with something this sweep cannot resolve to text",
      });
      continue;
    }
    const shipped = prompts.filter((prompt) => prompt.name.endsWith(`/${promptFile}`));
    if (shipped.length === 0) {
      violations.push({
        where: consultation.where,
        detail: `runs ${promptFile}, which no workflow folder ships`,
      });
      continue;
    }
    for (const prompt of shipped) {
      if (prompt.text.includes(`<${tag}>`) && prompt.text.includes(`</${tag}>`)) continue;
      violations.push({
        where: prompt.name,
        detail: `never shows <${tag}></${tag}>, which is the block its dispatch reads its answer out of`,
      });
    }
  }
  return violations;
}
