// Every sweep, shown failing against a deliberately-planted violation.
//
// **A sweep nobody has seen fail is a sweep nobody knows works.** The two
// suites beside this one assert that the shipped source is clean, and a rule
// that silently matched nothing — a regular expression that never fires, an
// enumeration that returns an empty list, a predicate inverted — would pass
// them exactly as convincingly as a rule that works.
//
// So each rule is exercised twice here: once against source written to break it
// and once against the same source with the break removed. That is only
// possible because the rules are pure functions over source they are handed;
// pointing a rule at the repository and hoping is the shape this deliberately
// is not.
//
// Every planted module is written as text rather than as a fixture on disk, so
// a violation this suite plants can never be found by a sweep that is looking
// at the real tree.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { driversAreCovered } from "../support/corpus.mts";
import { moduleFrom, type Closure } from "../support/source.mts";
import {
  cleanupIsUnforced,
  commandsAreFrameworkNeutral,
  commentComposers,
  composedBodiesCarryTheMarker,
  consultations,
  consultTagsAppearInPrompts,
  knownDefects,
  nothingReachesSandcastle,
  promptArgNamesAreDisjoint,
  reconcileKnownDefects,
  sharedPromptsMatch,
  shellBlocksLeaveGitAlone,
  trackerOnlyCorrects,
  type Prompt,
  type Violation,
  type WorkflowPrompts,
} from "../support/sweeps.mts";

/** A planted module, written the way the rules read one. */
function planted(...lines: readonly string[]) {
  return moduleFrom("planted/driver.mts", lines.join("\n"));
}

function assertCaught(found: readonly Violation[], mentioning: string): void {
  assert.equal(found.length, 1, `expected exactly one finding, got ${found.length}`);
  assert.ok(
    (found[0]?.detail ?? "").includes(mentioning),
    `finding does not mention ${mentioning}: ${found[0]?.detail}`,
  );
}

function assertClean(found: readonly Violation[]): void {
  assert.deepEqual(found, []);
}

const MARKER = "<!-- sandcastle-run-report -->";

// ---------------------------------------------------------------------------

describe("the framework-neutral command sweep", () => {
  const importsExec = 'import { execFileSync } from "node:child_process";';

  it("catches a toolchain command", () => {
    const found = commandsAreFrameworkNeutral([
      planted(importsExec, 'execFileSync("swift", ["build", "--build-tests"]);'),
    ]);
    assertCaught(found, "swift");
  });

  it("passes once the command is git", () => {
    assertClean(
      commandsAreFrameworkNeutral([
        planted(importsExec, 'execFileSync("git", ["status", "--porcelain"]);'),
      ]),
    );
  });

  it("follows an alias, which is the quietest way out of the rule", () => {
    const found = commandsAreFrameworkNeutral([
      planted('import { execSync as shell } from "node:child_process";', 'shell("pnpm test");'),
    ]);
    assertCaught(found, "pnpm");
  });

  it("reports a command it cannot read rather than passing it", () => {
    const found = commandsAreFrameworkNeutral([
      planted(importsExec, "execFileSync(program, [subcommand]);"),
    ]);
    assertCaught(found, "cannot read");
  });

  it("reports an empty corpus as covering nothing", () => {
    assertCaught(commandsAreFrameworkNeutral([]), "enumerated nothing");
  });
});

describe("the force-flag sweep", () => {
  // The shape `drivers/git.mts` has: one arrow function holds the spawn, and
  // everything else in the module reaches git through it — `attempt` through a
  // second hop. The rule has to follow both, or it reads the whole file.
  const gitHelpers = [
    'import { execFileSync } from "node:child_process";',
    'const git = (...args) => execFileSync("git", [...args], { cwd: repoRoot });',
    "const attempt = (...args) => { try { git(...args); } catch { return false; } };",
  ];

  it("catches a forced branch delete", () => {
    assertCaught(cleanupIsUnforced([planted(...gitHelpers, 'git("branch", "-D", branch);')]), "-D");
  });

  it("catches a forced worktree removal one helper further away", () => {
    assertCaught(
      cleanupIsUnforced([planted(...gitHelpers, 'attempt("worktree", "remove", "--force", path);')]),
      "--force",
    );
  });

  it("passes the unforced pair, and does not read --no-ff as a force flag", () => {
    assertClean(
      cleanupIsUnforced([
        planted(
          ...gitHelpers,
          'git("merge", "--no-ff", "--no-edit", branch);',
          'attempt("branch", "-d", branch);',
          'attempt("worktree", "remove", path);',
        ),
      ]),
    );
  });

  it("leaves a flag that never reaches git alone", () => {
    // `tail -f <log>` is a line the ledger prints, not a command anybody runs,
    // and a rule that read every string in the file would report it.
    assertClean(
      cleanupIsUnforced([planted(...gitHelpers, 'const hint = `tail -f ${logPath}`;')]),
    );
  });

  it("reads string literals rather than the file, so a comment cannot trip it", () => {
    assertClean(
      cleanupIsUnforced([planted(...gitHelpers, "// No --force and no -D appears below.")]),
    );
  });
});

describe("the shared-prompt sweep", () => {
  const copy = (id: string, implement: string): WorkflowPrompts => ({
    id,
    body: "async ({ dispatch }) => { await dispatch(); }",
    prompts: new Map([["implement-prompt.md", implement]]),
  });

  it("catches a copy whose prompt has drifted", () => {
    const found = sharedPromptsMatch([copy("first", "do the work"), copy("second", "do it twice")]);
    assert.equal(found.length, 1);
    assert.equal(found[0]?.where, "second/implement-prompt.md");
  });

  it("passes once the copies match again", () => {
    assertClean(sharedPromptsMatch([copy("first", "do the work"), copy("second", "do the work")]));
  });

  it("reports a corpus in which nothing is a copy any more", () => {
    const found = sharedPromptsMatch([
      copy("first", "do the work"),
      { id: "second", body: "async () => {}", prompts: new Map() },
    ]);
    assertCaught(found, "no two workflows supply the same body");
  });
});

describe("the prompt-argument sweep", () => {
  const reserved = ["WORK", "ANCHOR"];
  const written = ["WORK", "ANCHOR"];

  it("catches a body setting a reserved name", () => {
    const found = promptArgNamesAreDisjoint({
      reserved,
      written,
      fromBodies: [{ where: "planted/workflow.mts", name: "WORK" }],
      placeholders: [{ where: "planted/prompt.md", name: "WORK" }],
    });
    assertCaught(found, "the runner reserves");
  });

  it("catches a placeholder nothing writes", () => {
    const found = promptArgNamesAreDisjoint({
      reserved,
      written,
      fromBodies: [],
      placeholders: [{ where: "planted/prompt.md", name: "REVIEW_BASE" }],
    });
    assertCaught(found, "which nothing writes");
  });

  it("catches a reserved name the runner has stopped writing", () => {
    const found = promptArgNamesAreDisjoint({
      reserved: [...reserved, "RETIRED"],
      written,
      fromBodies: [],
      placeholders: [{ where: "planted/prompt.md", name: "WORK" }],
    });
    assertCaught(found, "which no runner or driver writes");
  });

  it("passes a body key that is its own, expanded where it is written", () => {
    assertClean(
      promptArgNamesAreDisjoint({
        reserved,
        written,
        fromBodies: [{ where: "planted/workflow.mts", name: "REVIEW_BASE" }],
        placeholders: [
          { where: "planted/prompt.md", name: "WORK" },
          { where: "planted/prompt.md", name: "REVIEW_BASE" },
        ],
      }),
    );
  });
});

describe("the contract's Sandcastle sweep", () => {
  const closure = (...modules: readonly string[]): Closure => ({
    modules: modules.map((text, index) => moduleFrom(`planted/${index}.mts`, text)),
    unresolved: [],
  });

  it("catches a type-only import, which is the same leak by a quieter route", () => {
    const found = nothingReachesSandcastle(
      closure('import type { RunResult } from "@ai-hero/sandcastle";'),
    );
    assertCaught(found, "@ai-hero/sandcastle");
  });

  it("catches it one module along the closure, not just at the entry", () => {
    const found = nothingReachesSandcastle(
      closure(
        'import type { WorkItem } from "./snapshot.mts";',
        'import { noSandbox } from "@ai-hero/sandcastle/sandboxes/no-sandbox";',
      ),
    );
    assertCaught(found, "@ai-hero/sandcastle");
  });

  it("reports an import it could not follow rather than assuming it is clean", () => {
    const found = nothingReachesSandcastle({
      modules: [moduleFrom("planted/0.mts", "export const x = 1;")],
      unresolved: [{ where: "planted/0.mts:1", specifier: "./gone.mts" }],
    });
    assertCaught(found, "resolves to no file");
  });

  it("passes a closure that names only its own modules", () => {
    assertClean(nothingReachesSandcastle(closure('import type { WorkItem } from "./snapshot.mts";')));
  });
});

describe("the tracker sweep", () => {
  const reopens = 'gh(["issue", "reopen", String(number), "--comment", body]);';

  it("catches a fourth act composed onto the issue noun", () => {
    const found = trackerOnlyCorrects([planted('gh(["issue", "transfer", String(number)]);')]);
    assertCaught(found, "gh issue transfer");
  });

  it("catches the word close wherever a driver writes it", () => {
    const found = trackerOnlyCorrects([planted(reopens, 'const act = "close";')]);
    assertCaught(found, "never closes an issue");
  });

  it("catches a Tracker that offers closing at all", () => {
    const found = trackerOnlyCorrects([
      planted(
        reopens,
        "export interface Tracker {",
        "  closeIssue: (number: number) => void;",
        "}",
      ),
    ]);
    assertCaught(found, "close an issue");
  });

  it("passes the three acts a run may make", () => {
    assertClean(
      trackerOnlyCorrects([
        planted(
          reopens,
          'gh(["issue", "comment", String(number), "--body", body]);',
          'gh(["issue", "edit", String(number), "--add-label", label]);',
        ),
      ]),
    );
  });

  it("reports a corpus with no gh vector in it at all", () => {
    assertCaught(trackerOnlyCorrects([planted("export const x = 1;")]), "enumerated nothing");
  });
});

describe("the run-report marker sweep", () => {
  const writes = planted(
    "function correct(tracker) {",
    "  const body = correctionComment(input);",
    "  tracker.comment(1, body);",
    "}",
  );

  it("finds the function that composed the body", () => {
    assert.deepEqual(
      commentComposers([writes]).map((composer) => composer.name),
      ["correctionComment"],
    );
  });

  it("catches a body that does not open with the marker", () => {
    const found = composedBodiesCarryTheMarker(
      commentComposers([writes]),
      new Map([["correctionComment", "Reopened by Sandcastle."]]),
      MARKER,
    );
    assertCaught(found, "does not open with");
  });

  it("catches a composer nobody has a sample of, rather than skipping it", () => {
    const found = composedBodiesCarryTheMarker(commentComposers([writes]), new Map(), MARKER);
    assertCaught(found, "no sample of");
  });

  it("catches a body it cannot trace back to a composer", () => {
    const opaque = planted("function correct(tracker, body) {", "  tracker.reopen(1, body);", "}");
    assertCaught(
      composedBodiesCarryTheMarker(commentComposers([opaque]), new Map(), MARKER),
      "cannot trace",
    );
  });

  it("passes once the marker leads the body", () => {
    assertClean(
      composedBodiesCarryTheMarker(
        commentComposers([writes]),
        new Map([["correctionComment", `${MARKER}\nReopened by Sandcastle.`]]),
        MARKER,
      ),
    );
  });
});

describe("the git-mutation sweep", () => {
  const prompt = (text: string): readonly Prompt[] => [{ name: "planted/prompt.md", text }];

  it("catches a standalone fetch, which is #417 exactly", () => {
    assertCaught(shellBlocksLeaveGitAlone(prompt("!`git fetch origin main`")), "git fetch");
  });

  it("catches a subcommand it has never seen, rather than assuming it reads", () => {
    assertCaught(shellBlocksLeaveGitAlone(prompt("!`git switch main`")), "git switch");
  });

  it("passes the fix, which chains the read onto the mutation", () => {
    assertClean(
      shellBlocksLeaveGitAlone(prompt("!`git fetch origin main && git diff origin/main...HEAD`")),
    );
  });

  it("passes a read, and anything that is not git at all", () => {
    assertClean(
      shellBlocksLeaveGitAlone(
        prompt("!`git log --oneline -10`\n!`git diff HEAD`\n!`cat docs/CODING_STANDARDS.md`"),
      ),
    );
  });

  it("reports an empty corpus as covering nothing", () => {
    assertCaught(shellBlocksLeaveGitAlone([]), "enumerated nothing");
  });
});

describe("the known-defect reconciliation", () => {
  const declaring = (text: string): readonly Prompt[] => [{ name: "planted/prompt.md", text }];
  const declaration = "<!-- sandcastle-known-defect: 417 — slice 12 chains the read onto it -->";

  it("lets a declared defect through, and only that one", () => {
    const prompts = declaring(`${declaration}\n!\`git fetch origin main\``);
    assertClean(
      reconcileKnownDefects(shellBlocksLeaveGitAlone(prompts), knownDefects(prompts)),
    );
  });

  it("still reports an undeclared defect in a file that declares another", () => {
    const prompts = [
      { name: "planted/declared.md", text: `${declaration}\n!\`git fetch origin main\`` },
      { name: "planted/silent.md", text: "!`git pull --rebase`" },
    ];
    const found = reconcileKnownDefects(shellBlocksLeaveGitAlone(prompts), knownDefects(prompts));
    assert.deepEqual(
      found.map((violation) => violation.where),
      ["planted/silent.md"],
    );
  });

  it("reports a declaration that has outlived its defect", () => {
    const prompts = declaring(`${declaration}\n!\`git diff HEAD\``);
    assertCaught(
      reconcileKnownDefects(shellBlocksLeaveGitAlone(prompts), knownDefects(prompts)),
      "no longer holds one",
    );
  });
});

describe("the consult-tag sweep", () => {
  const consult = planted(
    'export const PLAN_PROMPT = "plan-prompt.md";',
    'export const PLAN_TAG = "plan";',
    "export function selectWave(core) {",
    "  return core.consult(PLANNER, {",
    "    promptFile: PLAN_PROMPT,",
    "    promptArgs: { READY: ready },",
    "    tag: PLAN_TAG,",
    "    schema: PLAN_SCHEMA,",
    "  });",
    "}",
  );

  it("follows both options one hop to their declarations", () => {
    assert.deepEqual(
      consultations([consult]).map(({ promptFile, tag }) => ({ promptFile, tag })),
      [{ promptFile: "plan-prompt.md", tag: "plan" }],
    );
  });

  it("catches a prompt that never shows the tag", () => {
    const found = consultTagsAppearInPrompts(consultations([consult]), [
      { name: "planted/plan-prompt.md", text: "Choose which ready items start now." },
    ]);
    assertCaught(found, "<plan></plan>");
  });

  it("catches a prompt file no workflow ships", () => {
    const found = consultTagsAppearInPrompts(consultations([consult]), [
      { name: "planted/review-prompt.md", text: "Review it." },
    ]);
    assertCaught(found, "no workflow folder ships");
  });

  it("catches a consult whose options it cannot read", () => {
    const opaque = planted("core.consult(PLANNER, options);");
    const found = consultTagsAppearInPrompts(consultations([opaque]), []);
    assertCaught(found, "cannot resolve to text");
  });

  it("passes once the prompt shows the block", () => {
    assertClean(
      consultTagsAppearInPrompts(consultations([consult]), [
        { name: "planted/plan-prompt.md", text: 'Answer with <plan>{ "wave": [1] }</plan>.' },
      ]),
    );
  });

  it("reports a corpus with no consult in it at all", () => {
    assertCaught(consultTagsAppearInPrompts([], []), "enumerated nothing");
  });
});

describe("the driver-coverage join", () => {
  it("catches a registered driver whose module the sweeps cannot find", () => {
    const found = driversAreCovered([]);
    assert.ok(found.length > 0, "every registered driver should be reported as uncovered");
    assert.ok(found.every((violation) => violation.detail.includes("misses it")));
  });
});
