// Source as data — the reading half of tier 3.
//
// A static sweep is the only tier that covers code nobody has written yet, and
// it can do that only if it reads source the way a compiler does rather than
// the way `grep` does. Three things go wrong with `grep` here, each of them
// silently: a rule about executed commands matches the same word in the comment
// explaining the rule, a rule about flags matches prose, and a rule about one
// call's arguments cannot see past a helper that forwards them.
//
// So every sweep reads a real syntax tree, from the `typescript` this package
// already type-checks with. What it deliberately does *not* build is a
// `Program`: a checker would need the whole dependency graph resolved and a
// second copy of the compiler options, and every question a sweep asks — which
// command is this, which flag is that, does this prompt exist — is answerable
// from syntax alone.
//
// **Unreadable is a finding, never a pass.** Every extractor below hands back
// what it could not resolve rather than dropping it, so the rules can report
// it. A sweep that quietly ignores the one call it cannot parse is a sweep that
// stops covering whatever somebody writes next — which is the failure this
// whole tier exists to prevent.

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import * as ts from "typescript";

/** `.sandcastle/`, which every name a sweep prints is relative to. */
export const SANDCASTLE_DIR = resolve(import.meta.dirname, "../..");

/** One module, parsed. */
export interface Module {
  /** `drivers/git.mts` — how a failing sweep names it. */
  readonly name: string;
  /** Absolute, or `null` for a module a test composed in memory. */
  readonly path: string | null;
  readonly text: string;
  readonly ast: ts.SourceFile;
}

/**
 * Parse text as a module.
 *
 * The seam the planted-violation suite runs through: a rule that only ever sees
 * the real tree has never been shown to fail, and a rule nobody has seen fail
 * is a rule nobody knows works.
 */
export function moduleFrom(name: string, text: string): Module {
  return {
    name,
    path: null,
    text,
    // `setParentNodes`, because several extractors below walk upward to decide
    // what a node is being used *as*.
    ast: ts.createSourceFile(name, text, ts.ScriptTarget.ES2023, true, ts.ScriptKind.TS),
  };
}

export function moduleAt(path: string): Module {
  const absolute = resolve(SANDCASTLE_DIR, path);
  const module = moduleFrom(relative(SANDCASTLE_DIR, absolute), readFileSync(absolute, "utf8"));
  return { ...module, path: absolute };
}

/** Every `.mts` directly in one folder, in a stable order. */
export function modulesIn(directory: string): readonly Module[] {
  return readdirSync(resolve(SANDCASTLE_DIR, directory))
    .filter((entry) => entry.endsWith(".mts"))
    .sort()
    .map((entry) => moduleAt(join(directory, entry)));
}

/**
 * Depth-first from one node, the root included — the primitive every
 * enumeration below is built on. Inclusive because a rule that asks what is
 * inside one argument is usually asking about an argument that *is* the string.
 */
export function walkFrom(root: ts.Node, visit: (node: ts.Node) => void): void {
  const descend = (node: ts.Node): void => {
    visit(node);
    ts.forEachChild(node, descend);
  };
  descend(root);
}

/** Depth-first over every node, which is what "enumerate from the source" means. */
export function walk(module: Module, visit: (node: ts.Node) => void): void {
  walkFrom(module.ast, visit);
}

/**
 * The name of the function one node is written inside, or `null` at top level.
 *
 * How a rule follows an argument through a helper: `git.mts` spawns git in one
 * arrow function and every flag in the file is an argument to *that*, so the
 * question "does this string reach git" is answered by walking up.
 */
export function enclosingName(node: ts.Node): string | null {
  for (let current = node.parent; current; current = current.parent) {
    if (ts.isVariableDeclaration(current) && ts.isIdentifier(current.name)) return current.name.text;
    if (ts.isFunctionDeclaration(current) && current.name) return current.name.text;
    if (ts.isMethodDeclaration(current) && ts.isIdentifier(current.name)) return current.name.text;
  }
  return null;
}

/** `drivers/git.mts:151`, so a finding is one click from the code. */
export function at(module: Module, node: ts.Node): string {
  const { line } = module.ast.getLineAndCharacterOfPosition(node.getStart(module.ast));
  return `${module.name}:${line + 1}`;
}

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------

/** One piece of literal text, wherever in the module it was written. */
export interface Literal {
  readonly node: ts.Node;
  readonly value: string;
}

/**
 * Every literal string in the module, template chunks included and comments
 * excluded — which is the whole reason this is not a regular expression over
 * the file. `drivers/git.mts` spends its header explaining that it uses no
 * force flag; a text scan for `-f` finds that explanation.
 */
export function literalsIn(root: ts.Node): readonly Literal[] {
  const found: Literal[] = [];
  walkFrom(root, (node) => {
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
      found.push({ node, value: node.text });
    } else if (ts.isTemplateHead(node) || ts.isTemplateMiddle(node) || ts.isTemplateTail(node)) {
      found.push({ node, value: node.text });
    }
  });
  return found;
}

export function literals(module: Module): readonly Literal[] {
  return literalsIn(module.ast);
}

/** The whole of a string expression, or `null` when a substitution hides part of it. */
export function wholeString(node: ts.Node | null | undefined): string | null {
  if (!node) return null;
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
  return null;
}

/**
 * What a string expression is known to *start* with.
 *
 * Enough for a command: `` `git ${command}` `` names git whatever `command`
 * holds, and that is exactly the question the framework-neutrality rule asks.
 * `null` when even the opening is a substitution, which the caller reports
 * rather than skips.
 */
export function openingText(node: ts.Node | null | undefined): string | null {
  if (!node) return null;
  const whole = wholeString(node);
  if (whole !== null) return whole;
  if (ts.isTemplateExpression(node)) return node.head.text === "" ? null : node.head.text;
  return null;
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------

/** `execFileSync` for both `execFileSync(…)` and `childProcess.execFileSync(…)`. */
export function calleeName(call: ts.CallExpression): string | null {
  const callee = call.expression;
  if (ts.isIdentifier(callee)) return callee.text;
  if (ts.isPropertyAccessExpression(callee)) return callee.name.text;
  return null;
}

export function callsIn(root: ts.Node): readonly ts.CallExpression[] {
  const found: ts.CallExpression[] = [];
  walkFrom(root, (node) => {
    if (ts.isCallExpression(node)) found.push(node);
  });
  return found;
}

export function calls(module: Module): readonly ts.CallExpression[] {
  return callsIn(module.ast);
}

// ---------------------------------------------------------------------------
// Object literals, arrays and declarations
// ---------------------------------------------------------------------------

export function objectLiterals(module: Module): readonly ts.ObjectLiteralExpression[] {
  const found: ts.ObjectLiteralExpression[] = [];
  walk(module, (node) => {
    if (ts.isObjectLiteralExpression(node)) found.push(node);
  });
  return found;
}

export function arrayLiterals(module: Module): readonly ts.ArrayLiteralExpression[] {
  const found: ts.ArrayLiteralExpression[] = [];
  walk(module, (node) => {
    if (ts.isArrayLiteralExpression(node)) found.push(node);
  });
  return found;
}

/** The written-out property names of one object literal; a spread contributes none. */
export function propertyNames(object: ts.ObjectLiteralExpression): readonly string[] {
  return object.properties.flatMap((property) => {
    const name = property.name;
    if (!name) return [];
    if (ts.isIdentifier(name) || ts.isStringLiteral(name)) return [name.text];
    return [];
  });
}

export function propertyValue(
  object: ts.ObjectLiteralExpression,
  name: string,
): ts.Expression | null {
  for (const property of object.properties) {
    if (!ts.isPropertyAssignment(property)) continue;
    const key = property.name;
    if ((ts.isIdentifier(key) || ts.isStringLiteral(key)) && key.text === name) {
      return property.initializer;
    }
  }
  return null;
}

/** What `const NAME = …` was initialised to, anywhere in the module. */
export function declaredValue(module: Module, name: string): ts.Expression | null {
  let found: ts.Expression | null = null;
  walk(module, (node) => {
    if (found) return;
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === name) {
      found = node.initializer ?? null;
    }
  });
  return found;
}

/** The member names of one interface, or `null` when the module declares no such interface. */
export function interfaceMembers(module: Module, name: string): readonly string[] | null {
  let found: readonly string[] | null = null;
  walk(module, (node) => {
    if (!ts.isInterfaceDeclaration(node) || node.name.text !== name) return;
    found = node.members.flatMap((member) =>
      member.name && (ts.isIdentifier(member.name) || ts.isStringLiteral(member.name))
        ? [member.name.text]
        : [],
    );
  });
  return found;
}

// ---------------------------------------------------------------------------
// Imports
// ---------------------------------------------------------------------------

/** One name an import brings in, under both of the names it has. */
export interface Binding {
  /** What the module being imported calls it; `default` or `*` for the whole module. */
  readonly imported: string;
  /** What this file calls it — which is the name its call sites use. */
  readonly local: string;
}

/** One import, whether or not it is type-only — a type-only leak is still a leak. */
export interface Import {
  readonly node: ts.Node;
  readonly specifier: string;
  /**
   * Both names of everything it binds. A rule that knew only the imported name
   * would miss `{ execSync as run }`, and one that knew only the local name
   * could not tell which API it was.
   */
  readonly bindings: readonly Binding[];
}

export function imports(module: Module): readonly Import[] {
  return module.ast.statements.flatMap((statement) => {
    if (!ts.isImportDeclaration(statement)) return [];
    const specifier = wholeString(statement.moduleSpecifier);
    if (specifier === null) return [];

    const clause = statement.importClause;
    const named = clause?.namedBindings;
    const bindings: Binding[] = [];
    if (clause?.name) bindings.push({ imported: "default", local: clause.name.text });
    if (named && ts.isNamespaceImport(named)) {
      bindings.push({ imported: "*", local: named.name.text });
    }
    if (named && ts.isNamedImports(named)) {
      for (const element of named.elements) {
        bindings.push({
          imported: (element.propertyName ?? element.name).text,
          local: element.name.text,
        });
      }
    }
    return [{ node: statement, specifier, bindings }];
  });
}

/** Every module reachable from one entry by following its relative imports. */
export interface Closure {
  readonly modules: readonly Module[];
  /** A relative import that names no file on disk — reported, never skipped. */
  readonly unresolved: readonly { readonly where: string; readonly specifier: string }[];
}

export function importClosure(entry: string): Closure {
  const modules = new Map<string, Module>();
  const unresolved: { where: string; specifier: string }[] = [];

  const visit = (path: string): void => {
    const absolute = resolve(SANDCASTLE_DIR, path);
    if (modules.has(absolute)) return;
    const module = moduleAt(relative(SANDCASTLE_DIR, absolute));
    modules.set(absolute, module);

    for (const imported of imports(module)) {
      if (!imported.specifier.startsWith(".")) continue;
      const target = resolve(dirname(absolute), imported.specifier);
      try {
        readFileSync(target, "utf8");
      } catch {
        unresolved.push({ where: at(module, imported.node), specifier: imported.specifier });
        continue;
      }
      visit(relative(SANDCASTLE_DIR, target));
    }
  };

  visit(entry);
  return { modules: [...modules.values()], unresolved };
}
