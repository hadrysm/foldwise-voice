// Include hygiene for every prompt every workflow ships.
//
// The failure this guards is silent on both sides. Claude Code's `@path`
// mention reaches Codex verbatim — Sandcastle has no `@` handling at all — so a
// `gpt-5.x` agent is asked to apply a document it never received, and nothing
// reports it. A shell block is provider-neutral by construction, but only if it
// is well formed and its path resolves: a wrong path aborts the run at startup,
// and a stray backtick silently truncates the command.

import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, it } from "node:test";
import { WORKFLOWS } from "../../workflows/registry.mts";

// Shell blocks are executed with the runner's cwd, which is the repo root —
// three levels above this file, whatever folder a workflow itself lives in.
const REPO_ROOT = resolve(import.meta.dirname, "../../..");

/** The shipped expander's own pattern: a command may not contain a backtick. */
const SHELL_BLOCK = /!`([^`]+)`/g;

/** Claude Code's include syntax, the thing that must not come back. */
const AT_MENTION = /(^|\s)@\S+\.md/;

/**
 * A slash command, the other thing only one provider understands. Skills are
 * Claude Code's, so `/code-review` reaches a `gpt-5.x` agent as inert text and
 * the work it names silently does not happen. Whatever a prompt needs, it has to
 * say itself.
 */
const SKILL_CALL = /(^|\s)\/[a-z][a-z-]{2,}(\s|$|[.,)`])/;

interface Prompt {
  name: string;
  text: string;
}

function everyPrompt(): readonly Prompt[] {
  return WORKFLOWS.flatMap((workflow) =>
    readdirSync(workflow.dir)
      .filter((entry) => entry.endsWith(".md"))
      .map((entry) => ({
        name: `${workflow.id}/${entry}`,
        text: readFileSync(join(workflow.dir, entry), "utf8"),
      })),
  );
}

function shellBlocks(prompt: Prompt): readonly string[] {
  return [...prompt.text.matchAll(SHELL_BLOCK)].map((match) => match[1] ?? "");
}

/** The document a `cat` include splices in; other blocks (`git`, `gh`) have none. */
function includedDocument(command: string): string | undefined {
  return /^cat (\S+)$/.exec(command)?.[1];
}

describe("every workflow prompt", () => {
  it("inlines shared documents with a shell block, never an @ mention", () => {
    for (const prompt of everyPrompt()) {
      const mention = AT_MENTION.exec(prompt.text)?.[0].trim();
      assert.equal(mention, undefined, `${prompt.name} names a document by @ mention`);
    }
  });

  it("asks for the work itself rather than delegating to a skill", () => {
    for (const prompt of everyPrompt()) {
      const call = SKILL_CALL.exec(prompt.text)?.[0].trim();
      assert.equal(call, undefined, `${prompt.name} delegates to a skill`);
    }
  });

  it("names every included document by a path that resolves from the repo root", () => {
    for (const prompt of everyPrompt()) {
      for (const command of shellBlocks(prompt)) {
        const document = includedDocument(command);
        if (!document) continue;
        assert.ok(
          existsSync(resolve(REPO_ROOT, document)),
          `${prompt.name} includes ${document}, which does not resolve from the repo root`,
        );
      }
    }
  });

  it("inlines each document exactly once", () => {
    for (const prompt of everyPrompt()) {
      const documents = shellBlocks(prompt)
        .map(includedDocument)
        .filter((document) => document !== undefined);
      assert.deepEqual([...new Set(documents)], documents, `${prompt.name} pays for a document twice`);
    }
  });

  it("closes every shell block without a backtick inside it", () => {
    for (const prompt of everyPrompt()) {
      // An opener the expander's pattern cannot match is a block whose command
      // reaches the agent as prose instead of as output.
      assert.equal(
        prompt.text.split("!`").length - 1,
        shellBlocks(prompt).length,
        `malformed shell block in ${prompt.name}`,
      );
    }
  });

  it("puts every shell block on its own line", () => {
    for (const prompt of everyPrompt()) {
      for (const match of prompt.text.matchAll(SHELL_BLOCK)) {
        const lineStart = prompt.text.lastIndexOf("\n", match.index) + 1;
        assert.equal(
          match.index,
          lineStart,
          `${prompt.name} contains an inline shell block: ${match[0]}`,
        );
      }
    }
  });
});
