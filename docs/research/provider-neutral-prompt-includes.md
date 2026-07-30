# Provider-neutral prompt includes in Sandcastle

Research for [issue #360](https://github.com/hadrysm/foldwise-voice/issues/360),
current as of 2026-07-29. The source of truth is the **installed**
`@ai-hero/sandcastle@0.12.0` under `.sandcastle/node_modules/` — its shipped
`dist/index.js` was read directly, and every conclusion below was then confirmed
empirically by capturing the fully-expanded prompt from a real `sandcastle.run()`
(see [Empirical verification](#empirical-verification)).

## Conclusions

1. **`` !`shell` `` is the answer, and it is provider-neutral by construction.**
   The Sandcastle runner expands shell blocks *itself* — `preprocessPrompt`
   (`dist/index.js:65`) executes each block via `sandbox.exec()` and splices the
   stdout into the prompt string *before* the string reaches any agent. Both
   `claudeCode` (`dist/index.js:3415`) and `codex` (`dist/index.js:3215`) receive
   that already-expanded text on **stdin** (`claude … -p -` / `codex exec …`), so
   neither provider can tell an inlined document from text typed into the file.
   `` !`cat docs/CODING_STANDARDS.md` `` is the whole answer to the ticket.
2. **`@docs/CODING_STANDARDS.md` is passed through verbatim — the runner does
   nothing with it.** There is **no `@`-include handling anywhere** in the
   shipped `dist/`. The expansion we currently rely on is done by the Claude Code
   CLI on the prompt it receives, which is why the standards reach the reviewer
   today. A Codex-driven review receives the literal 26-character string
   `@docs/CODING_STANDARDS.md` and reviews without the standards. The ticket's
   premise is **confirmed**, not merely suspected.
3. **`{{VAR}}` promptArgs are also runner-side, and therefore also
   provider-neutral.** `substitutePromptArgs` (`dist/index.js:701`) does a plain
   string replace on `/\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}/g` before the
   prompt is dispatched. `SOURCE_BRANCH` and `TARGET_BRANCH` are built in and
   cannot be overridden; every other referenced key must be supplied or the run
   fails. Unreferenced keys produce a warning, not an error.
4. **Substitution runs *before* shell expansion, so args compose into
   commands.** This is what makes the existing
   `` !`git diff {{REVIEW_BASE}}...HEAD` `` work. Order is: read file →
   substitute `{{}}` → expand `` !`` ``.
5. **Relative paths inside a shell block resolve against the repo root, not the
   prompt file's folder.** `preprocessPrompt` is handed `ctx.sandboxRepoDir` as
   its `cwd`; under this repo's `branchStrategy: { type: "head" }` +
   `noSandbox()` configuration that is the host repo dir, which is
   `resolveCwd(options.cwd)` and — since `main.mts` passes no `cwd` — is
   `process.cwd()`. **Moving prompts into `workflows/<id>/` therefore changes
   nothing about how their shell blocks resolve paths.** `` !`cat
   docs/CODING_STANDARDS.md` `` keeps working from any prompt location, and a
   prompt-folder-relative path such as `` !`cat ./sibling.md` `` does *not*
   resolve.
6. **`promptFile` accepts an absolute path, and that is the right choice for
   self-contained workflow folders.** `resolvePrompt` (`dist/index.js:562`) does
   a host-side `fs.readFileString(promptFile)` on the raw string — a relative
   value is resolved against `process.cwd()`, *not* against the calling module.
   A workflow module that hard-codes `"./.sandcastle/workflows/<id>/review-prompt.md"`
   is only correct when the runner is launched from the repo root, which
   undercuts "self-contained". `join(import.meta.dirname, "review-prompt.md")`
   was verified to work and makes the folder genuinely relocatable.
7. **Inlining fails loudly where `@` fails silently.** A shell block whose
   command exits non-zero aborts the whole run with a `PromptError` *before the
   agent starts* — verified: a missing file killed the run and no prompt was ever
   dispatched. A missing `@`-target degrades silently instead. For the standards
   specifically this is an **improvement**: it is no longer possible to run a
   review that quietly lacks the standards.
8. **Shell blocks cannot be injected through arg values or through inlined
   content.** `substitutePromptArgs` marks the file's own shell blocks with a
   `\x01` sentinel and strips that sentinel from every arg value; `preprocessPrompt`
   only expands *marked* blocks and strips the sentinel from its output. So a
   `` !`…` `` arriving via a `{{VAR}}` value, or inside text pulled in by an
   earlier `cat`, is inert. Inlining a document that itself contains shell-block
   syntax is safe, and the sentinel never leaks into the dispatched prompt
   (verified: zero `\x01` bytes in the capture).
9. **Shell expansion only happens for `promptFile`, never for inline
   `prompt: "…"`.** Marking is done by `substitutePromptArgs`, which is skipped
   for inline prompts, so an inline prompt reaches `preprocessPrompt` with no
   marked blocks and passes through unchanged (`dist/index.js:1478`, `:2315`).
   Passing `promptArgs` alongside an inline prompt is a hard error. Workflows
   must keep using `promptFile` for anything that needs an include.

## Recommendation

Replace `@docs/CODING_STANDARDS.md` in both prompts with an explicit inline:

```markdown
Apply the coding standards below.

<coding-standards>
!`cat docs/CODING_STANDARDS.md`
</coding-standards>
```

Do the same for `@docs/agents/issue-tracker.md`. Keep the paths **repo-root
relative** (conclusion 5) even after the prompts move into `workflows/<id>/`, and
build `promptFile` from `import.meta.dirname` (conclusion 6).

### Costs this buys

- `docs/CODING_STANDARDS.md` is 9,882 bytes ≈ **2.5k tokens**, paid by every
  agent whose prompt includes it, on every iteration — where `@` let Claude read
  it lazily (or skip it). `docs/agents/issue-tracker.md` adds its own share. This
  is the real trade, and it is the price of Codex seeing the standards at all.
  Sandcastle prints a per-block `<command> → ~N tokens` line during expansion, so
  the cost is observable at run time.
- Each block gets a **30s timeout** (`PROMPT_EXPANSION_TIMEOUT_MS`); blocks in
  one prompt run with unbounded concurrency. Not a concern for `cat`.

### Syntax constraints worth knowing

- The pattern is ``/!`([^`]+)`/g`` — **no backticks inside the command**. Use
  `$(…)`, never backtick substitution.
- The negated class matches newlines, so multi-line commands are allowed.
- Non-zero exit aborts the run (conclusion 7). Where a soft include is genuinely
  wanted, `|| echo "(not present)"` makes it optional — but do not do this for
  the standards.

## Empirical verification

A throwaway probe ran a real `sandcastle.run()` with a stub agent provider whose
`buildPrintCommand` returned `{ command: "cat > /tmp/…", stdin: prompt }`, which
captures the exact text an agent would receive at zero token cost. `promptFile`
was an absolute path built from `import.meta.dirname`, pointing at a prompt two
directories below the repo root. Captured output:

| Probe | Prompt source | Captured | Conclusion |
| --- | --- | --- | --- |
| A | `@docs/CODING_STANDARDS.md` | `@docs/CODING_STANDARDS.md` | 2 — verbatim, runner ignores `@` |
| B | `{{PROBE_ARG}}` | `ARG-VALUE` | 3 — runner-side substitution |
| C | arg value `INJECT-START !\`echo PWNED\` INJECT-END` | unchanged, `PWNED` absent | 8 — args cannot inject |
| D | `` !`pwd` `` | `/Users/…/perth` (repo root) | 5 — cwd is the repo root |
| E | `` !`head -1 docs/CODING_STANDARDS.md` `` | `# Coding Standards` | 1, 5 — root-relative works |
| F | `` !`cat ./sibling.md \|\| echo NOT-RESOLVED…` `` | `NOT-RESOLVED-FROM-PROMPT-DIR` | 5 — prompt-dir-relative does not |
| G | `` !`echo base={{PROBE_ARG}}` `` | `base=ARG-VALUE` | 4 — substitution precedes expansion |
| H | `cat` of a file containing `` !`echo PWNED` `` | unchanged, `PWNED` absent | 8 — output not re-expanded |

A second run replaced the prompt with `` !`cat docs/DOES_NOT_EXIST.md` `` and
died with
`PromptError: Command \`cat docs/DOES_NOT_EXIST.md\` exited with code 1`,
producing **no capture file** — proving the abort happens before dispatch
(conclusion 7). The probe files were removed; they are not part of the repo.

## Consequences for the restructure

- **No new include mechanism is needed.** The map's candidate was right; nothing
  has to be built, designed, or abstracted. The seam work inherits a working
  provider-neutral include for free.
- **Prompt authoring gains one rule** worth stating in the ADR (#365) and
  enforcing in the prompts written for Review Only (#364): *shared repo docs
  enter a prompt through `` !`cat <repo-root-relative-path>` ``, never through
  `@`.* `@` is a Claude-Code-only affordance and using it silently degrades every
  non-Claude provider in the catalog.
- **Workflow modules should resolve `promptFile` from `import.meta.dirname`**, so
  a `workflows/<id>/` folder stays copy-to-fork-able as the map intends.
- The `{{VAR}}` mechanism needs no replacement either, and its
  ask-for-missing-keys behaviour (`clack.text` per unresolved key,
  `dist/index.js:1337`) is a **pre-existing interactive prompt** the picker work
  (#361, #362) should be aware of: a workflow that forgets to pass a promptArg
  will interrogate the user mid-run rather than fail.
