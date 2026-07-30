# ADR-0010: Sandcastle workflows are self-contained folders driven by an injected dispatch

## Status

Accepted (2026-07-29).

This decision **does not amend
[ADR-0001](0001-sandcastle-in-place-not-sandboxed.md)**: both shipped workflows
remain no-sandbox on the `head` branch strategy, and no Dockerfile is added.
What changes is *where* that constraint is expressed — see "The runner owns
ADR-0001's constraint" below.

## Context

`.sandcastle/` currently holds exactly one workflow, and holds it by
construction rather than by choice. `main.mts` is a single ~560-line module
containing the provider registry, a hand-rolled `selectOption` TUI widget, the
picker flow, the CLI version and auth checks, and the implement→review loop
inline in `main()`. `MAX_ITERATIONS` is a `const` at line 53. `run-config.mts`
holds two unrelated things — the model catalog and the run store. The two
prompt files sit loose at the `.sandcastle/` root.

The forcing function is a **second workflow**: *Review Only* — one agent, no
loop, diffing `origin/main...HEAD`. Its reason to exist is **cross-provider
review**, pointing a different provider's model at a branch the session's own
model wrote, which a same-session review skill structurally cannot do. It is
also the cheapest possible stress test of the seam, differing from the existing
loop on two axes: a different agent count, and no `promptArgs` at all.

Adding it to the flat file forces four questions the current shape cannot
answer:

- The picker asks per **phase** with the labels `Implementer`/`Reviewer`
  hardcoded, and `RunPlan` has exactly those two fields. A workflow with one
  agent has nowhere to fit.
- `MAX_ITERATIONS` is meaningful for the loop and meaningless for Review Only,
  so it cannot stay a module constant and cannot become a question every
  workflow is asked.
- Both workflows drive the same *reviewer* agent with two **different** prompts,
  so a prompt cannot be a property of an agent.
- Every `sandcastle.run()` call site repeats `sandbox: noSandbox()`,
  `branchStrategy: { type: "head" }`, `maxIterations: 1` and the
  `swift package resolve` hook. None of those four is a per-workflow choice —
  the first two are ADR-0001's hard constraint — yet a second workflow would
  copy all four, and could then contradict them.

## Decision

Restructure `.sandcastle/` around a **workflow**: a self-contained folder
exporting metadata plus a `run()`, selected in the picker alongside the
existing per-agent model and effort picks.

### The runner owns ADR-0001's constraint; the workflow receives `dispatch`

The seam is a **function handed to the workflow**, not a set of options handed
to `sandcastle.run()`. A workflow **never imports Sandcastle**. It receives
`dispatch(agent, { promptFile, promptArgs? })`, and `runner.mts` — the only
module that calls `sandcastle.run()` — supplies `noSandbox()`, `head`,
`maxIterations: 1`, the resolve hook, and the provider it built from the plan.

ADR-0001's constraint therefore lives in exactly **one enforceable place**
instead of once per call site, and a workflow is unit-testable against a fake
`dispatch` with no CLI, no auth, and no agent process.

`dispatch` returns Sandcastle's `RunResult` **unchanged**, so
`result.commits.length` — the signal that the backlog is empty — keeps working
without a wrapper type. Unrecognised `RunOptions` keys pass through, so the
narrow API needn't chase Sandcastle's. Two keys are deliberately **not**
reachable: `hooks`, which is sandbox policy, and `maxIterations`, which is
Sandcastle's own loop. A workflow that could raise `maxIterations` would be
running two competing loops — the mistake today's `maxIterations: 1` comment
already warns about. **The loop is the workflow's `for`; Sandcastle's stays
pinned at 1.**

`run({ dispatch, knobs }) => Promise<void>`. The context deliberately omits the
resolved agents: a workflow that can read the winning model id will eventually
branch on it, and *who* runs a step is the axis the picker owns — *what* runs is
the workflow's. Narration is plain `console.log`, which keeps every ANSI escape
inside `cli/`.

### A workflow is a folder; discovery is a static registry

`workflows/<id>/workflow.mts` plus that workflow's own prompts. Forking a
workflow means copying a folder. The module is **side-effect-free at import**,
and exports `id`, `label`, `description`, `dir`, `agents`, `knobs`,
`runShape(knobs)` and `run`.

`dir` is always `import.meta.dirname`, and `promptFile` is folder-relative.
Sandcastle resolves `promptFile` against `process.cwd()`, so anchoring on `dir`
is what makes the folder relocatable — a structural guarantee rather than a
convention each author must remember, stated once per workflow instead of once
per dispatch.

`runShape(knobs)` interpolates the one line the confirmation screen leads with
(`"implement → review, up to 5 issues"`). Only the workflow knows its knob
means a repeat count rather than a timeout, and that line is what you
sanity-check before handing an agent an hour.

Discovery is `workflows/registry.mts` exporting `WORKFLOWS` in picker order,
**not** a glob — see the rejected alternatives.

### An agent is identity only

`{ id, label }`. **No prompt path, and no default model or effort.** This
corrects the framing this decision was originally chartered under ("agents as
identity plus model default"): a per-agent default model is visible exactly once
per clone — the store overwrites it after the first run — and buys a permanent
three-level precedence rule in the picker. Defaults stay where they already
are: the store, then `DEFAULT_EFFORT`, then catalog order. The catalog needs
exactly two entries, *Implementer* and *Reviewer*.

The **workflow** binds an agent to a prompt and supplies its `promptArgs`, which
are optional rather than an empty object. That binding is why both workflows can
drive the same reviewer agent differently.

### Prompts are owned by the workflow

Each prompt markdown file lives in its workflow's folder. There is **no
top-level `prompts/`**. Prompt files are named for the **agent** they drive;
folders for the **workflow** — a convention for readers, never a lookup key.

Sharing between prompts uses `` !`cat <repo-root-relative-path>` `` shell
includes, which both Claude Code and Codex honour because the runner expands
them before dispatch — provider-neutral by construction, and failing loudly
where Claude Code's `@path` syntax reaches Codex verbatim and degrades
silently. Shell blocks resolve against the **repo root**, so moving prompts into
workflow folders changes nothing about them.

### A knob is a workflow-declared run parameter

A typed integer with `min`/`max`/`defaultValue` and its own wording, which the
picker renders generically. `maxIterations` is the first and, today, the only
one. A workflow with no loop declares none and is never asked. Out-of-range
answers are rejected rather than silently clamped; range is re-checked at point
of use, dropping to the default rather than clamping.

### Layout

```
.sandcastle/
  main.mts                      entry point only: pick → execute → print error
  runner.mts                    validate distinct models → memoise providers → dispatch → run()
  contract.mts                  Agent, Knob, Workflow, WorkflowContext, Dispatch, DispatchOptions
  agents/catalog.mts            IMPLEMENTER, REVIEWER
  agents/models.mts             ModelID, RunEffort, RunModel, RUN_MODELS, DEFAULT_EFFORT, findModel
  cli/flow.mts                  the picker flow; ResolvedAgent, ResolvedPlan
  cli/prompts.mts               clack adapter
  cli/store.mts                 the run store
  providers/                    claude-code/codex registry, version + auth checks
  workflows/registry.mts        WORKFLOWS, in picker order
  workflows/sequential-reviewer/{workflow.mts, implement-prompt.md, review-prompt.md}
  workflows/review-only/{workflow.mts, review-prompt.md}
```

`contract.mts` is a runtime **leaf** — its Sandcastle imports are type-only.
`sequential-reviewer` keeps its id for lineage to the upstream template ADR-0001
cites, and takes the label "Implement & Review".

## Rejected alternative: a declarative phase list

Describing a workflow as data — an ordered list of `{ agent, promptFile,
promptArgs }` — is the smaller contract, and it cannot express what the existing
loop already does:

- **The early exit.** The loop stops when an implement phase produces no
  commits. That is a conditional on a phase's *result*, and a list has no place
  to put it short of inventing a predicate language.
- **`promptArgs` computed at runtime.** `REVIEW_BASE` is `git rev-parse HEAD`
  captured *between* two phases of the same iteration. A declarative entry can
  only hold values known before the run starts.

The control flow is the only thing that genuinely varies between workflows, so
it is the thing the contract should carry as code.

## Rejected alternative: standalone per-workflow entry points

One `tsx` entry point per workflow, selected by which command you type, was
rejected because it splits the picker across a **process boundary**:

- The provider version and auth checks and the run store would be duplicated or
  hoisted into a shared module every entry point must remember to call.
- The typed link between the plan the picker built and the workflow consuming it
  is lost — the plan would have to be re-derived, or serialised across the
  boundary and re-validated.
- Choosing a workflow stops being a question the picker asks and becomes
  something you must already know before you start.

`providers/dispatch.mts` was the runner-up placement for the glue, but it would
put the workflow contract inside the provider folder and blur the boundary this
ADR draws. The glue is `runner.mts`.

## Rejected alternative: a flat shared `prompts/` folder

Keeping every prompt in one top-level folder reads fine for two workflows and
fails on the third: a workflow needing a *variant* of an existing prompt has
nowhere to put it without stepping on the shared one. The pressure resolves as
either a name suffix convention or an edit that quietly changes another
workflow's behaviour.

Ownership is the honest model — a prompt is part of a workflow, which is why
copying the folder is a complete fork. Genuinely shared text is a `` !`cat` ``
include, which is an explicit dependency rather than an implicit one.

## Rejected alternative: a glob over `workflows/*/workflow.mts`

Less code to touch when adding a workflow, at three costs a two-line registry
edit does not repay:

- **The type gate.** `tsc --noEmit` cannot check that a dynamically imported
  module conforms to `Workflow`, so a broken workflow becomes a runtime
  surprise.
- **Synchronous startup.** The catalog becomes async, so the picker's first
  screen awaits I/O.
- **The option order.** `readdir` is alphabetical, which would sort
  `review-only` above `sequential-reviewer` and invert the intended default —
  the picker falls back to index 0 when nothing is remembered.

## Rejected alternative: parallel or containerised workflows

Upstream Sandcastle's `parallel-planner` and `parallel-planner-with-review`
templates, and container mode generally, remain out of the question on
ADR-0001's **hard constraint**: the macOS-only Swift package cannot compile in a
Linux container, so agents could never run the verify loop they are required to
run before committing. Host worktrees on named `sandcastle/*` branches were the
non-Docker route to parallelism and were tried and reverted (ADR-0001's second
amendment).

This ADR therefore ships two **sequential** workflows, and the `dispatch` seam
is deliberately not designed for concurrent dispatch.

## Consequences

- **The workflow becomes a test surface.** `run()` against a fake `dispatch`
  asserts the loop's early exit, the `REVIEW_BASE` hand-off, and that Review
  Only dispatches once with no `promptArgs` — none of which requires a provider.
- **ADR-0001 becomes enforceable rather than remembered.** `noSandbox` and
  `head` appear once, in `runner.mts`, and no workflow can override them because
  `DispatchOptions` omits the keys.
- **Validation stays eager and providers are memoised by model *and* effort.**
  A Codex auth failure must not surface at iteration 7, and today's "same for
  both" behaviour — one `AgentProvider` object reused — is how the memo
  generalises to N agents. Both are testable in `runner.mts` and were untestable
  as top-level statements in `main.mts`.
- **`main.mts` shrinks to an entry point**, and the picker widget is replaced by
  `@clack/prompts` — already Sandcastle's only runtime dependency, so no package
  is added. `RunPlan`, `RunConfiguration` and `PHASE_LABEL_WIDTH` retire.
- **The run store moves to v2**, keyed by agent id globally plus knob values per
  workflow, so "reviewer = Opus 5 / high" applies to every workflow using that
  agent. It stays in the git common dir, shared across worktrees on different
  branches, so writes are key-level upserts and never replacements.
- **"Phase" is demoted.** *Agent* is the term for who runs a step; *phase* now
  means only a step in a workflow's sequence, and phases are not 1:1 with
  agents. Prompt-file names, log prefixes and picker labels all key off the
  agent id.
- **`tsconfig.json`'s `include` must widen from `*.mts` to `**/*.mts`**, or the
  type gate silently stops covering everything the registry does not reach.
- **Non-interactive invocation stays unavailable.** Selecting a workflow with a
  flag is only meaningful once this seam exists, and is a separate effort.
