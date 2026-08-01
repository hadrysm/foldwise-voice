# ADR-0010: Sandcastle workflows are self-contained folders driven by an injected dispatch

## Status

Accepted (2026-07-29). Amended (2026-08-01): the runner gained **Work scope** —
universal work selection, asked before the workflow — and the seam grew a
**driver** layer so a third, wave-parallel workflow can run one loop per work
item concurrently. `Knob` retires, `DispatchOptions` becomes an allow-list,
`.sandcastle/repo.mts` appears, and "Rejected alternative: parallel or
containerised workflows" is superseded on its first half. Every amended
passage is marked *Amendment, 2026-08-01*.

This decision **does not amend
[ADR-0001](0001-sandcastle-in-place-not-sandboxed.md)** on host execution: no
workflow is sandboxed and no Dockerfile is added. What changes is *where* that
constraint is expressed — see "The runner owns ADR-0001's constraint" below.
The 2026-08-01 amendment does trigger an amendment *to* ADR-0001 — per-item
host worktrees under the parallel driver — which is recorded there, not here.

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
`dispatch(agent, { promptFile, promptArgs? })`, and the runner — the only layer
that calls `sandcastle.run()` — supplies `noSandbox()`, the branch strategy,
`maxIterations: 1`, the hooks, and the provider it built from the plan.

ADR-0001's constraint therefore lives in exactly **one enforceable place**
instead of once per call site, and a workflow is unit-testable against a fake
`dispatch` with no CLI, no auth, and no agent process.

`run(context) => Promise<void>`. The context deliberately omits the resolved
agents: a workflow that can read the winning model id will eventually branch on
it, and *who* runs a step is the axis the picker owns — *what* runs is the
workflow's. Narration is plain `console.log`, which keeps every ANSI escape
inside `cli/`.

#### `DispatchOptions` and `DispatchResult` are the contract's own types

*Amendment, 2026-08-01. This replaces the original pass-through design, and the
reason is a hole in it.*

The original seam omitted keys from Sandcastle's `RunOptions` — `sandbox`,
`branchStrategy`, `maxIterations`, `hooks` and six more — and returned
Sandcastle's `RunResult` unchanged so `commits.length` needed no wrapper. The
claim was that a workflow *cannot* contradict ADR-0001. **The return type
defeated it.** `RunResult` carries `resume?` and `fork?`, whose own options
type omits neither `branchStrategy` nor `hooks`, so this compiled in shipped
code:

```ts
const implement = await dispatch(IMPLEMENTER, { promptFile: "implement-prompt.md" });
await implement.resume?.("keep going", { branchStrategy: { type: "merge-to-head" }, hooks: {} });
```

A second agent iteration, on a branch strategy ADR-0001 forbids, with hooks the
runner never chose. Nobody wrote it — but "cannot be written" was the claim.

So **`contract.mts` owns both types and Sandcastle stops crossing the seam**:

```ts
export interface DispatchOptions {
  readonly promptFile: string;
  readonly promptArgs?: Readonly<Record<string, string>>;
}

export interface DispatchResult {
  readonly commits: readonly { readonly sha: string }[];
  readonly baseSha: string;
}
```

Decided by arithmetic rather than taste: across both shipped workflows the
entire use of `RunOptions` is `promptFile` and `promptArgs`, and the entire use
of `RunResult` is `commits.length` and `baseSha`. Three things follow.

- **Enforcement flips from a denylist to an allow-list.** An allow-list cannot
  be defeated by a return type, and cannot silently widen when Sandcastle adds
  an option — which the denylist would, on every upgrade.
- **It is the only shape both `run()` and `Worktree.run()` can satisfy.**
  `WorktreeRunOptions` is a separate, narrower interface with no `output`, no
  `cwd`, no `copyToWorktree` and no `timeouts`; anything wider is a union or a
  lie about one path. `signal` in particular must not be reachable — it is the
  per-item wall-clock timeout, and passthrough would let a workflow defeat it.
- **`stdout` stops crossing the seam.** A workflow that can read agent stdout
  can branch on model output — the same category of leak as reading the winning
  model id, which this ADR already refused.

The cost, accepted openly: the passthrough convenience is gone, and a
Sandcastle upgrade that changes `RunResult` becomes a runner-side edit.
`contract.mts` is now the adapter boundary, with Sandcastle an implementation
detail *below* it.

#### There is exactly one loop, and it belongs to the driver

*Amendment, 2026-08-01. This replaces "the loop is the workflow's `for`."*

The original claim was that a workflow that could raise `maxIterations` would
be running two competing loops, so **the loop is the workflow's `for` and
Sandcastle's stays pinned at 1**. It becomes:

> **There is exactly one loop over work items per run, and it belongs to the
> driver. A workflow supplies that loop's body; it can neither create a loop
> nor bound one. Sandcastle's own iteration stays pinned at 1 on every path —
> `run()` and `Worktree.run()` both default to it, and neither exposes it to a
> workflow.**

Strictly stronger. Under the original a workflow *has* a `for` and is merely
prevented from nesting a second inside it; under this it has no loop at all, so
"two competing loops" has no syntax rather than being forbidden by an omission.

Who now supplies what the omissions used to name:

| Was omitted | Supplied by |
| --- | --- |
| `branchStrategy` | the driver — `head` for the sequential drivers, a named `sandcastle/<number>-<slug>` branch passed to `createWorktree` for the parallel one |
| `sandbox: noSandbox()` | the driver, explicitly on both paths, because `WorktreeRunOptions.sandbox` is required and does not default |
| `hooks` | repo config → driver → `createWorktree`, which executes only `host.onWorktreeReady` and passes the rest through |
| `maxIterations` | nobody; the default of 1 stands everywhere |

### Work selection is the runner's, and it is universal

*Amendment, 2026-08-01.*

**Work scope** — which GitHub issues a run may touch — is asked **before** the
workflow, and is handed to every current and future workflow. It is not a
workflow-declared capability and there is no `appliesWhen` predicate: a
workflow does not opt in to being scoped, and cannot opt out.

The three choices — a specific SPEC and its eligible descendants, a specific
issue, or the whole `ready-for-agent` queue — are a discriminated union in the
picker and the runner, and they are **flattened before any workflow sees
them**. A workflow cannot read `scopeKind`, so it cannot branch on it, and the
resulting list *is* the bound, so there is no count to honour and none to
widen. This is the same argument the original decision used to keep the
resolved agents out of `WorkflowContext`, applied to a second axis: *a workflow
that can read it will eventually branch on it.*

The runner therefore owns, and a workflow never sees:

- **membership** — a version-pinned REST snapshot of the issue tree, frozen at
  the picker and revalidated immediately before each dispatch;
- **order** — a stable topological sort keyed on authored sub-issue order, with
  ascending issue number for the repository-wide queue, truncated as a prefix;
- **dependency edges** — the third thing a workflow may not see, after the
  resolved agents and `scopeKind`, on the same argument each time. An in-scope
  open blocker is a *precedence edge*, not an exclusion, and the runner alone
  knows that;
- **the transitive skip set** — an item that produced no commits, crashed,
  timed out or whose merge was rewound drops its in-set dependents too;
- **branch names**, worktrees, fan-in and cleanup;
- **the run guard** — 1–50, default 10. It is a brake on an unattended run's
  token budget, not a work-selection number, which is what makes it universal
  across scopes rather than a per-workflow knob;
- **the handoff** — the end-of-run report, and the anchor's `code-review` label
  evaluated against live GitHub state.

Two consequences worth naming, because they are new obligations rather than
restatements:

- **The run now writes to the tracker.** Previously the only tracker write was
  the implementer closing its own issue from inside its prompt. The runner now
  posts one marker-prefixed comment on the anchor and may apply `code-review`
  to it — and its own comment normalization drops marker-bearing comments, so
  run N does not read runs 1…N-1's bookkeeping as evidence. The runner never
  *closes* an anchor; that judgment stays human.
- **`scope/` is a new pair of modules, not part of `runner.mts`.** GitHub
  resolution is a third side effect and it must run *during the picker walk*,
  before `prepare()` exists, so it cannot live behind the runner's
  `prepare → dispatch` closure. `scope/snapshot.mts` is pure; `scope/github.mts`
  is the only module that talks to GitHub.

### A workflow declares a driver and supplies a body

*Amendment, 2026-08-01.*

Concurrency is not something a workflow can be trusted to assemble for itself
without handing it back the raw git, worktree handles and `sandcastle.run`
options this ADR spent its whole length taking away. The extension point is a
**driver**: the runner-side module that owns how work becomes dispatches. A
workflow declares which driver it wants and receives the context *that driver*
grants.

| Layer | Owns | Changes when |
| --- | --- | --- |
| runner core | providers, model validation, the frozen allow-list, prompt-arg injection, git primitives | rarely |
| **driver** | worktrees, concurrency, fan-in, skips, cleanup, the Planner and Merger dispatches | a genuinely new execution shape |
| workflow folder | agents, prompts, a driver choice, one per-item body | every new idea |
| repo config | pre-warm, `copyToWorktree`, the `MAX_PARALLEL` default, the item timeout | per repo |

Three drivers exist:

| | `sequential` | `wave-parallel` | `whole-branch` |
| --- | --- | --- | --- |
| work items | one at a time | a wave at a time | none |
| location | host checkout | per-item host worktree | host checkout |
| extra dispatches | — | Planner, Merger | — |
| workflow | Implement & Review | the wave-parallel workflow | Review Only |

**Capability is strictly non-increasing.** Adding a workflow that reuses a
driver is a new folder and zero contract change; adding a new execution shape
is a new runner-side driver and zero change to existing workflows. Extending
never means reaching further.

This is a strengthening of this ADR, not a break with it: *workflows are
folders driven by an injected dispatch* becomes *…driven by an injected
**driver***, of which the original bare `dispatch` is the degenerate
one-agent case. A work-item driver invokes a per-item body with a `dispatch`
already scoped to that item:

```ts
await core.runWaves(async (item, dispatch) => {
  const implement = await dispatch(IMPLEMENTER, { promptFile: "implement-prompt.md" });
  if (!implement.commits.length) return;
  await dispatch(REVIEWER, {
    promptFile: "review-prompt.md",
    promptArgs: { REVIEW_BASE: implement.baseSha },
  });
});
```

The item is passed to the body to *read* — number, title, url — and never to
`dispatch`, because the dispatch already **is** that item. No `Worktree` handle
crosses the seam: Sandcastle's carries `.close()`, `.createSandbox()` and
`.interactive()`, so handing one over would let a workflow tear down its own
worktree or spawn a second sandbox.

**Outcomes never reach the contract.** The body returns `void`, and the driver
learns every outcome from git, the process or GitHub rather than the workflow's
testimony — `git rev-list` against the wave base for commits, a rejected
promise for a crash, its own `AbortSignal` for a timeout, `git merge --no-ff`'s
exit code for the fan-in, and a re-read of the live issue for a bounce. A body
that reported its own fate could claim success for an item that crashed, which
would hand a workflow influence over the transitive skip set.

#### The Planner does not weaken "a workflow holds control flow and nothing else"

The parallel workflow uses two agents no sequential workflow has: a **Planner**
that proposes which of the ready items may run concurrently, and a **Merger**
that verifies the merged tree after a wave's fan-in. An agent that proposes a
wave looks, at a distance, like work selection escaping to a workflow. It is
not, on two independent grounds:

- **The Planner cannot select work.** The runner has already frozen membership,
  computed the order and computed the levels; the Planner is handed the current
  ready level and may only *subset* it. It cannot discover an item, add one,
  widen a wave, cross a level or name a branch, and omitting an item defers it
  to the next wave rather than dropping it. Its one real power is the judgment
  the dependency edges do not encode — which two ready items rewrite the same
  module. It sees no dependency edges either.
- **The Planner and Merger are not `Dispatch` calls.** They are
  **driver-internal**, made through the runner core on the host. That is what
  lets them use `output` — structured output exists only on a host dispatch,
  never on `WorktreeRunOptions` and never on the contract's `DispatchOptions` —
  and it is why the two layers need different dispatch types at all.

What the workflow folder contributes is `plan-prompt.md` and `merge-prompt.md`,
resolved against `Workflow.dir` like every other prompt. The folder seam stays
absolute: a workflow still holds control flow and prompts, and now one line of
control flow fewer than before.

### A workflow is a folder; discovery is a static registry

`workflows/<id>/workflow.mts` plus that workflow's own prompts. Forking a
workflow means copying a folder. The module is **side-effect-free at import**,
and exports `id`, `label`, `description`, `dir`, `agents`, `driver`,
`runShape(workItems)` and `run`. *(Amendment, 2026-08-01: `knobs` is gone and
`driver` is new; `runShape` takes the resolved work-item count.)*

`dir` is always `import.meta.dirname`, and `promptFile` is folder-relative.
Sandcastle resolves `promptFile` against `process.cwd()`, so anchoring on `dir`
is what makes the folder relocatable — a structural guarantee rather than a
convention each author must remember, stated once per workflow instead of once
per dispatch.

`runShape(workItems)` interpolates the one line the confirmation screen leads
with (`"implement → review, up to 10 issues"`) — the line you sanity-check
before handing an agent an hour. The Work scope and Eligible rows beside it are
`cli/flow.mts`'s, not `runShape`'s, which is what keeps `runShape` down to a
single number and keeps the anchor out of the workflow.

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

### ~~A knob is a workflow-declared run parameter~~ — retired

The original design gave a workflow a `Knob`: a typed integer with
`min`/`max`/`defaultValue` and its own wording, which the picker rendered
generically. `maxIterations` was the first and only one; out-of-range answers
were rejected rather than clamped, and the range was re-checked at point of
use.

*Amendment, 2026-08-01.* **`Knob` is deleted**, along with
`WorkflowContext.knobs`, `knobQuestion`, `resolveKnob`, `knobsFor` and the
store's per-workflow knob bucket. Its only instance moved out from under it:
`maxIterations` became the **run guard**, a run-level property owned by the
picker and applied by the runner, universal across scopes because it is a
token-budget brake rather than a work-selection number. What remained was
speculative generality, and removing it is a net deletion across eleven files.

The two run parameters that exist today are runner-authored questions gated on
a **driver** property, not workflow-declared knobs: the picker asks for the run
guard because the driver drains work items, and for `MAX_PARALLEL` because the
driver is concurrent. So a workflow never declares its own concurrency shape,
and "drains but is asked nothing" has no syntax. Reintroducing a generic knob
later is a two-line contract addition, and this section documents the design.

### Repo-shaped configuration lives in `.sandcastle/repo.mts`

*Amendment, 2026-08-01.*

The original runner hardcoded `swift package resolve` as a sandbox hook.
Sandcastle is meant to drive web and mobile repos too, so the line this seam
actually needs is not *runner vs workflow* but **portable vs per-repo**. One
module holds everything per-repo — `onHostReady`, `onWorktreeReady`,
`copyToWorktree`, the `MAX_PARALLEL` default, the per-item timeout — and
everything else in `.sandcastle/` becomes portable. Dropping Sandcastle into
another repo is one file to edit, plus whatever prompts differ. It is a typed
module rather than JSON or TOML, which keeps the defaults typed and adds no
parser; it is per-repo rather than per-workflow because `swift package resolve`
is a fact about this repo, not about Implement & Review.

A repo-declared setup hook and a workflow-declared verify command look
identical from a distance, so the boundary is stated as a rule:

> **The runner may run a command whose output it discards. It may never run a
> command whose exit code it branches on — except git's, which is
> framework-neutral.**

A pre-warm is fire-and-forget: idempotent, result ignored, opaque to the
runner. A verify's exit code must be interpreted and *repaired*, which needs
judgment — so the fan-in verify lives in `merge-prompt.md` and belongs to the
Merger, not to any driver. This is the same boundary `host.onWorktreeReady`
draws, and it is statically assertable.

### Layout

*Amendment, 2026-08-01: `scope/`, `drivers/`, `repo.mts` and the wave-parallel
workflow folder are new; `Knob` leaves `contract.mts` and `prepare()` returns a
runner core rather than a bare `Dispatch`.*

```
.sandcastle/
  main.mts                      entry point only: pick → execute → print error
  runner.mts                    preflight → memoise providers → runner core; hands off to a driver
  contract.mts                  Agent, Workflow, WorkflowContext, Dispatch, DispatchOptions, DispatchResult
  repo.mts                      the only per-repo module: hooks, copyToWorktree, MAX_PARALLEL default, item timeout
  scope/snapshot.mts            pure: WorkScope, WorkScopeSnapshot, eligibility, ordering, digest
  scope/github.mts              the only module that talks to GitHub
  drivers/                      sequential, wave-parallel, whole-branch; outcomes, fan-in, skips, cleanup, the ledger
  agents/catalog.mts            IMPLEMENTER, REVIEWER, PLANNER, MERGER
  agents/models.mts             ModelID, RunEffort, RunModel, RUN_MODELS, DEFAULT_EFFORT, findModel
  cli/flow.mts                  the picker flow; ResolvedAgent, ResolvedPlan
  cli/prompts.mts               clack adapter; performs scope resolution
  cli/store.mts                 the run store
  providers/                    claude-code/codex registry, version + auth checks
  workflows/registry.mts        WORKFLOWS, in picker order
  workflows/sequential-reviewer/{workflow.mts, implement-prompt.md, review-prompt.md}
  workflows/wave-parallel/{workflow.mts, implement-prompt.md, review-prompt.md, plan-prompt.md, merge-prompt.md}
  workflows/review-only/{workflow.mts, review-prompt.md}
```

`contract.mts` is a runtime **leaf**, and after the 2026-08-01 amendment it
exports no Sandcastle type at all. `sequential-reviewer` keeps its id for
lineage to the upstream template ADR-0001 cites, and takes the label
"Implement & Review".

`prepare(plan)` returns the runner core a driver needs — providers, the frozen
work list, repo config, git helpers — and the driver cannot be invoked without
a value only a passing preflight produces. The preflight covers everything
knowable before the first dispatch: every distinct model's CLI version and
login, `gh auth status`, a clean workspace tree, no leftover `sandcastle/*`
branch or worktree, and the frozen ordered list itself. What must **not**
become eager is the partition into levels: the *list* is frozen, but the
*levels* are a pure function of the list and the accumulated skip set,
recomputed at each wave boundary, because a transitive skip shrinks what is
ready.

The wave-parallel workflow's implement and review prompts are **byte-identical
copies** of the sequential pair rather than a shared file or a cross-folder
path. Sandcastle already does everything a variant would have needed — shell
blocks expand at the worktree, `SOURCE_BRANCH`/`TARGET_BRANCH` are injected and
cannot be overridden, and the agent's cwd is the worktree — so the folder seam
stays absolute at the cost of a fix applied twice, which a plain file
comparison detects.

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

**Superseded on parallelism, 2026-08-01. Still standing on containers.** The
original text is kept because its two claims came apart, and which one was load-
bearing turned out to matter:

> Upstream Sandcastle's `parallel-planner` and `parallel-planner-with-review`
> templates, and container mode generally, remain out of the question on
> ADR-0001's **hard constraint**: the macOS-only Swift package cannot compile in
> a Linux container, so agents could never run the verify loop they are required
> to run before committing. Host worktrees on named `sandcastle/*` branches were
> the non-Docker route to parallelism and were tried and reverted (ADR-0001's
> second amendment).
>
> This ADR therefore ships two **sequential** workflows, and the `dispatch` seam
> is deliberately not designed for concurrent dispatch.

**Containers stay rejected, on unchanged reasoning.** The Swift package still
cannot compile on Linux, so a containerised agent still could not run its verify
loop. Nothing in the 2026-08-01 amendment touches that.

**Parallelism was never actually blocked by it, and the passage above conflates
the two.** Verified against the installed `@ai-hero/sandcastle@0.12.0`,
`noSandbox()` supports every branch strategy and `createWorktree` plus
`Worktree.run({ sandbox: noSandbox() })` gives per-item worktrees on the host —
so ADR-0001's container rejection never reached host concurrency. The second
sentence is also a misreading of ADR-0001's second amendment: what was reverted
was a per-*cycle* worktree in a *sequential* run, which bought nothing, not a
per-*item* worktree in a concurrent one, where the checkout is the contended
resource.

The forcing function was speed, not capability: a sequential implement→review
loop is too slow on a large SPEC. So a **third** workflow ships on the
`wave-parallel` driver, and the seam is redesigned for concurrent dispatch —
but concurrency belongs to the driver, not to the workflow, and the dispatch a
body receives is narrower than the one this ADR originally shipped, not wider.

Two costs are recorded rather than discovered later. Concurrency on one host has
no isolation, which is ADR-0001's problem and is written down there. And a
concurrent run cannot use Sandcastle's `stdout` logging: it resolves to a Clack
display that owns the cursor, so N dispatches would fight over it. `file` mode
is forced, per-item log files are the only permitted shape, and the driver
renders an **append-only ledger** — the right shape anyway for an AFK run, where
the maintainer wants a scrollback rather than a view of *now*.

## Consequences

- **The workflow becomes a test surface.** `run()` against a fake `dispatch`
  asserts the body's early exit and the `REVIEW_BASE` hand-off — neither of
  which requires a provider. *(Amendment, 2026-08-01: the driver becomes a
  second, larger test surface, and a better one — merge order, skip
  propagation, the Merger skip and timeout classification are pure functions
  over a list of outcomes, unit-testable with no workflow, no network and no
  git. Under an async-iterable design they would only have been observable by
  driving a workflow. Two shipped assertions about `promptArgs` become wrong
  once the runner writes `{{WORK}}` into every dispatch.)*
- **ADR-0001 becomes enforceable rather than remembered.** `noSandbox` and the
  branch strategy are the runner's, and no workflow can override them because
  `DispatchOptions` is an allow-list of exactly `promptFile` and `promptArgs`.
  *(Amendment, 2026-08-01: it was an omission list until the `resume`/`fork`
  hole showed that a denylist can be defeated by the return type.)*
- **Validation stays eager and providers are memoised by model *and* effort.**
  A Codex auth failure must not surface at iteration 7, and today's "same for
  both" behaviour — one `AgentProvider` object reused — is how the memo
  generalises to N agents. Both are testable in `runner.mts` and were untestable
  as top-level statements in `main.mts`.
- **`main.mts` shrinks to an entry point**, and the picker widget is replaced by
  `@clack/prompts` — already Sandcastle's only runtime dependency, so no package
  is added. `RunPlan`, `RunConfiguration` and `PHASE_LABEL_WIDTH` retire.
- **The run store moves to v2**, keyed by agent id globally, so "reviewer =
  Opus 5 / high" applies to every workflow using that agent. It stays in the git
  common dir, shared across worktrees on different branches, so writes are
  key-level upserts and never replacements. *(Amendment, 2026-08-01: the
  per-workflow knob bucket loses its only user and the store gains **top-level
  passthrough**, which absorbs the orphaned `knobs` key with no special case.
  The schema deliberately stays at v2 — a bump is strictly worse than none
  across worktrees, because an old parser would treat an unrecognised version
  as an empty store and destroy the agent picks on its next write. The store
  remembers the maintainer's **answers, never a run's outcomes**.)*
- **"Phase" is demoted.** *Agent* is the term for who runs a step; *phase* now
  means only a step in a workflow's sequence, and phases are not 1:1 with
  agents. Prompt-file names, log prefixes and picker labels all key off the
  agent id.
- **`tsconfig.json`'s `include` must widen from `*.mts` to `**/*.mts`**, or the
  type gate silently stops covering everything the registry does not reach.
- **Non-interactive invocation stays unavailable.** Selecting a workflow with a
  flag is only meaningful once this seam exists, and is a separate effort.
- **The picker's first question is no longer the workflow.** *Amendment,
  2026-08-01.* Work scope is asked first, because the eligible count is what
  the run guard and the confirmation screen are stated against. The remembered
  fast path therefore moves to *after* scope resolution: its hint can then read
  `up to 10 of 23 eligible`, at the cost of no longer being one keystroke or
  network-free.
- **The seam now spans three layers of prompt ownership, and the reserved
  names are shared state.** *Amendment, 2026-08-01.* The runner writes
  `WORK`/`ANCHOR`, the driver writes `READY`/`MAX_PARALLEL`/`WAVE`, and a
  workflow body writes only `REVIEW_BASE`. They are disjoint by construction,
  which is worth an assertion rather than a convention — a collision is a
  runtime throw, and a *missing* key makes `run()` and `Worktree.run()` fail
  loudly rather than silently.
