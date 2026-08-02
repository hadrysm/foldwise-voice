// What the sweeps are pointed at, and the only place that decides it.
//
// The admission rule this module exists to satisfy: **a sweep enumerates from a
// registry or the filesystem, never from a literal list of today's cases.**
// Written as three hardcoded assertions about `runner.mts`, `sequential` and
// `wave-parallel`, *"no toolchain command reaches a driver"* silently stops
// covering the fourth driver somebody adds later — which is exactly how a
// framework-agnostic boundary rots while the suite stays green.
//
// So nothing below names a driver, a workflow or a prompt. The three sources
// are `DRIVERS`, `WORKFLOWS` and `readdir`, and `driversAreCovered` closes the
// loop between the first two: a driver whose module this corpus cannot find is
// reported, so an id that stops matching its filename fails loudly rather than
// dropping out of every sweep at once.

import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import * as ts from "typescript";
import { DRIVERS } from "../../drivers/registry.mts";
import { WORKFLOWS } from "../../workflows/registry.mts";
import {
  moduleAt,
  modulesIn,
  objectLiterals,
  propertyNames,
  propertyValue,
  SANDCASTLE_DIR,
  type Module,
} from "./source.mts";
import type { NamedUse, Prompt, PromptArgUse, Violation, WorkflowPrompts } from "./sweeps.mts";

/**
 * Everything that stands between a workflow and a process: the runner, and
 * every module in the drivers folder.
 *
 * The whole folder rather than the three modules `DRIVERS` points at, because
 * a driver's helpers are on the same side of the boundary as the driver —
 * `drivers/git.mts` is where the force flags would be, and `drivers/tracker.mts`
 * is where the `gh` vectors are, and neither is named by an id.
 */
export function sweptModules(): readonly Module[] {
  return [moduleAt("runner.mts"), ...modulesIn("drivers")];
}

/**
 * Every driver in the registry has a module in the swept set.
 *
 * The join between the registry and the filesystem, and the reason the sweeps
 * can enumerate the folder without quietly missing a driver: a shape added to
 * `DriverId` whose module is named something else is reported here rather than
 * silently escaping every rule.
 */
export function driversAreCovered(modules: readonly Module[]): readonly Violation[] {
  const names = new Set(modules.map((module) => module.name));
  return Object.keys(DRIVERS).flatMap((id) =>
    names.has(join("drivers", `${id}.mts`))
      ? []
      : [
          {
            where: `drivers/registry.mts · ${id}`,
            detail: `names a driver with no drivers/${id}.mts, so every sweep over the drivers folder now misses it`,
          },
        ],
  );
}

// ---------------------------------------------------------------------------
// Workflows and their prompts
// ---------------------------------------------------------------------------

/** Each workflow's own module, reached through the registry's `dir`. */
export function workflowModules(): readonly Module[] {
  return WORKFLOWS.map((workflow) =>
    moduleAt(relative(SANDCASTLE_DIR, join(workflow.dir, "workflow.mts"))),
  );
}

/**
 * Every workflow with its body and its prompt folder read off disk.
 *
 * `String(workflow.run)` rather than the module's source text: the body is what
 * two workflows either share or do not, and reading it from the value is what
 * makes the comparison independent of everything around it in the file.
 */
export function workflowPrompts(): readonly WorkflowPrompts[] {
  return WORKFLOWS.map((workflow) => ({
    id: workflow.id,
    body: String(workflow.run),
    prompts: new Map(
      readdirSync(workflow.dir)
        .filter((entry) => entry.endsWith(".md"))
        .sort()
        .map((entry) => [entry, readFileSync(join(workflow.dir, entry), "utf8")] as const),
    ),
  }));
}

/** Every prompt every workflow ships, flattened. */
export function everyPrompt(): readonly Prompt[] {
  return workflowPrompts().flatMap((workflow) =>
    [...workflow.prompts].map(([file, text]) => ({ name: `${workflow.id}/${file}`, text })),
  );
}

// ---------------------------------------------------------------------------
// Prompt arguments
// ---------------------------------------------------------------------------

/** A prompt-arg name, which the expander matches case-sensitively. */
const ARG_NAME = /^[A-Z][A-Z0-9_]*$/;

const PLACEHOLDER = /\{\{([A-Z][A-Z0-9_]*)\}\}/g;

/**
 * Who writes which prompt argument, from three enumerations that never meet in
 * production: the object literals that actually set a name, the placeholders
 * the shipped prompts expand, and `reserved` — which the caller passes in, so
 * this module stays clear of `runner.mts` and the Sandcastle import behind it.
 *
 * The keys a *body* may set are read from the workflow modules' `promptArgs`
 * options rather than from the contract, because the contract types the option
 * and says nothing about which names go in it.
 *
 * `written` is every upper-case key on *any* object literal in those modules
 * rather than only the ones that become prompt args, and the looseness is
 * deliberate: the runner writes `{ WORK }` and `{ ANCHOR }` as plain returned
 * literals that never sit under a `promptArgs` key, so a narrower read would
 * find neither. It only ever makes the staleness check — *does anything still
 * write this reserved name* — more forgiving, never the collision check.
 */
export function promptArgUse(reserved: readonly string[]): PromptArgUse {
  const written: string[] = [];
  for (const module of sweptModules()) {
    for (const object of objectLiterals(module)) {
      written.push(...propertyNames(object).filter((name) => ARG_NAME.test(name)));
    }
  }

  const fromBodies: NamedUse[] = [];
  for (const module of workflowModules()) {
    for (const object of objectLiterals(module)) {
      const args = propertyValue(object, "promptArgs");
      if (!args || !ts.isObjectLiteralExpression(args)) continue;
      for (const name of propertyNames(args)) fromBodies.push({ where: module.name, name });
    }
  }

  const placeholders: NamedUse[] = [];
  for (const prompt of everyPrompt()) {
    for (const [, name = ""] of prompt.text.matchAll(PLACEHOLDER)) {
      placeholders.push({ where: prompt.name, name });
    }
  }

  return { reserved, written, fromBodies, placeholders };
}
