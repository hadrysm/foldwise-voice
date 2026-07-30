# Lifting versus replacing the Sandcastle picker widget

Research for [issue #367](https://github.com/hadrysm/foldwise-voice/issues/367),
current as of 2026-07-29. Two sources of truth: the **installed**
`@ai-hero/sandcastle@0.12.0` and `.sandcastle/pnpm-lock.yaml` for what this repo
already ships, and a **differential probe** that drives both the shipped widget
and the candidate library through a small VT emulator at 30, 48 and 80 columns
(see [Empirical verification](#empirical-verification)). No claim below rests on
documentation alone.

## Conclusions

1. **Replace, don't lift.** Adopt [`@clack/prompts`](https://github.com/bombshell-dev/clack)
   for both widgets the picker needs. Do **not** carry the prototype's `paint`,
   `hardWrapStyled`, `wrapWithPrefix` and `visibleLength` into `cli/`.
2. **This adds no dependency.** `@clack/prompts` is already **the one and only
   runtime dependency of `@ai-hero/sandcastle`** — `dependencies:
   {"@clack/prompts": "^1.1.0"}`, nothing else — and it is already resolved in
   `.sandcastle/pnpm-lock.yaml` at `1.6.0`, with `@clack/core@1.4.2`,
   `fast-wrap-ansi`, `fast-string-width` and `sisteransi` beneath it. Declaring
   it directly adds an importer entry to the lockfile and **zero new packages**.
   We cannot drop it without dropping Sandcastle. So the choice was never
   "dependency versus no dependency" — it was "use the ANSI-wrapping engine we
   already ship, or hand-roll a second one beside it".
3. **The shipped widget's defect is corrupting; Clack's is cosmetic.** The probe
   reproduces #361's report exactly: at 48 columns the shipped widget strands a
   duplicate prompt on screen after a *single* arrow press. Clack renders
   correctly at every width tested, but wraps into `width - 13` columns where it
   should use `width - 3` — a flat **10-column loss**, at every width, caused by
   an upstream bug that measures a styled prefix with its ANSI escapes included.
4. **Clack covers four of #361's five requirements outright**; the fifth — the
   typed number knob — is **~15 lines** on top of `text()` + `validate`, and it
   is the only code `cli/` needs to own. Verified working, including that an
   out-of-range value is refused rather than clamped.
5. **Adopting Clack does not foreclose owning the render later.** `@clack/core`
   exports `SelectPrompt` and `limitOptions`, and `render` is a constructor
   option. If the 10-column loss becomes intolerable on narrow panes, a custom
   render is ~60–120 lines *on top of a correct erase engine* — which is a very
   different proposition from owning the erase engine too.

## What `cli/` therefore contains

This ticket exists to decide that, so, concretely:

| File | Contents | Origin |
|---|---|---|
| `cli/flow.mts` | `nextQuestion(state)`, `applyAnswer`, `resolvePlan` — the pure question sequence. Unit-testable under `node --test` with no TTY. | **Lifted** from `PROTOTYPE-picker-flow.mts` |
| `cli/prompts.mts` | A thin adapter — `chooseOne()`, `askNumber()`, `wasCancelled()` — over `@clack/prompts`. No ANSI, no wrapping, no row arithmetic. | **New, ~40 lines** |
| `cli/store.mts` | The run store, moved out of `run-config.mts`. | Moved |

And, explicitly, **no `cli/paint.mts`** — no `wrapText`, no `hardWrapStyled`, no
`wrapWithPrefix`, no `clearRenderedLines`, no `visibleLength`. The prototype
proved that code *works*; this ticket concludes we should not be the ones
maintaining it. Note the split in the #361 prototype: its **flow** file lifts
unchanged, its **TUI** file is what gets replaced.

## Requirements, verified one at a time

#361 fixed the requirement list. Every row below was executed, not read.

| # | Requirement from #361 | Clack | How |
|---|---|---|---|
| a | Select with a label | ✓ | `select({options: [{value, label, hint}]})` |
| a | Description shown **only** for the selected row | ✓ | `hint`; only the `active`/`disabled` row branches render it |
| a | Remembered initial cursor position | ✓ * | `initialValue` — see caveat below |
| b | Typed number with min/max | ✓ ~15 lines | `text()` + `validate` |
| b | `enter` accepts a default | ✓ | `defaultValue`, with the caveat below |
| b | Out-of-range error that does **not** silently clamp | ✓ | `validate` returning a string; probe fed `999` into a 1–50 field and got a refusal, not `50` |
| b | A hint line | ◐ | No dedicated slot; carried in `message`/`placeholder` |
| c | `esc` **and** `ctrl-c` cancel at any question | ✓ | Alias map lives in the `@clack/core` base class, so it applies to every prompt type; `isCancel()` detects it |
| c | Cancel unwinds the whole flow | ✓ | Resolves with a sentinel symbol — no throw, no `process.exit` |
| d | An echoed answer line left behind | ✓ | Built in and not suppressible; the `◇` transcript style `main.mts` imitates by hand today is Clack's |
| e | Correct redraw at any width, text of any length | ✓ | Clean at 30 / 48 / 80 across three redraws |

`*` **`initialValue` matches by value with strict `===`, and silently falls back
to index 0 when not found.** Keying remembered picks by a primitive (a model id
string) rather than by a `RunModel` object is therefore load-bearing — an object
would need to be referentially identical. This is a direct constraint on
[#363](https://github.com/hadrysm/foldwise-voice/issues/363).

**The `defaultValue` footgun, confirmed and avoidable.** Clack runs `validate`
*before* the hook that applies `defaultValue`, so a validator that rejects empty
input makes the default unreachable — `enter` would error instead of accepting
`10`. The validator must return `undefined` for empty input and let
`defaultValue` do its job. The probe verifies all three paths: empty→`10`,
`7`→`7`, `999`→refused→corrected→`8`.

## Empirical verification

`process.stdout.columns` cannot be faked by piping — both widgets read it
directly — so the probe pins it with `Object.defineProperty`, feeds each widget a
`PassThrough` input and a capturing `Writable` output (both `isTTY: true`), drives
real key bytes, then replays the captured stream through a ~90-line VT emulator.
The emulator models only what makes the bug possible: **deferred autowrap** (the
character in the last column does not move the cursor until the *next* character,
which is the off-by-one a full-width line trips over) plus `CSI nA` and `CSI 0J`,
the erase pair every one of these widgets uses.

**The shipped widget is the control.** A harness that cannot reproduce a known
defect proves nothing about a candidate — so the first requirement was that the
probe fail on `main.mts` in the way #361 described, and pass at 80 columns where
the bug has never been seen.

Content is #361's own scenario: a picker rendering GitHub issue titles.

### Control — the widget shipping in `main.mts` today

Live frame at **48 columns, after one arrow-down**:

```
+------------------------------------------------+
|Which PRD should this run work through?         |
|                                                |
|Which PRD should this run work through?         |   <-- stranded duplicate
|                                                |
|  Cut dictation latency so the first words appea|
|r while you are still speaking                  |   <-- label not wrapped
|❯ Make Sandcastle's workflow selectable and its |
|folders self-contained                          |
|│   Restructures .sandcastle/ around workflows, |
|│   agents, cli and providers                   |
|  Guided setup for a fresh install              |
|                                                |
|↑↓ move · enter select · esc cancel             |
+------------------------------------------------+
```

All three of #361's causes are visible in one frame: the label runs off the row
un-wrapped and un-indented, the erase under-counts the rows that soft-wrapping
consumed, and the frame has already drifted after a single keypress.

After two arrow-downs and submit — a flow that is supposed to erase itself
completely:

| Width | Rows left on screen after submit | Copies of the prompt stranded |
|---|---|---|
| 30 | **12** | **3** |
| 48 | **3** | **3** |
| 80 | 0 | 0 |

This is the "five copies of *Which PRD?*" report, reproduced deterministically.
It confirms the widget is correct only at wide terminals with short labels.

### Candidate — `@clack/prompts` 1.6.0

Same scenario, same widths, same driver. Live frame at **48 columns**:

```
+------------------------------------------------+
|│                                               |
|◆  Which PRD should this run work               |
|│  through?                                     |
|│  ○ Cut dictation latency so the               |
|│  first words appear while you are             |
|│  still speaking                               |
|│  ● Make Sandcastle's workflow                 |
|│  selectable and its folders                   |
|│  self-contained (Restructures                 |
|│  .sandcastle/ around workflows,               |
|│  agents, cli and providers)                   |
|│  ○ Guided setup for a fresh install           |
|│  ↑/↓ to navigate • Enter: confirm             |
|└                                               |
+------------------------------------------------+
```

| Check | 30 | 48 | 80 |
|---|---|---|---|
| Prompt survives on exactly one row (no duplication) | PASS | PASS | PASS |
| No row overflows the terminal width | PASS | PASS | PASS |
| `initialValue` honoured, then two downs land correctly | PASS | PASS | PASS |
| Transcript echoes the chosen label | PASS | PASS | PASS |
| `esc` resolves to the cancel sentinel (`isCancel` true) | — | PASS | — |

**1.7.0, the current latest, was run through the identical probe and behaves
identically** — no regression, no improvement, in this area.

Why it holds where the hand-roll does not: `Prompt.render` hard-wraps the
*entire frame* before diffing it, so counting newlines on the wrapped buffer
**is** counting terminal rows. That is the architecture the prototype arrived at
independently with `paint`. Clack's 1.0 rewrite (2026-01-28) was largely this
change; the maintainer's note on
[#441](https://github.com/bombshell-dev/clack/issues/441) — *"the core rendering
logic of 1.x has changed quite a lot. It shouldn't happen in 1.x"* — and the
reporter's confirmation six days later are the upstream record of it.

### The cost, measured

Clack wraps into a budget of **`width - 13`**, consistent at every width tested
(30→17, 48→34, 80→67), because `wrapTextWithPrefix` measures a styled prefix
with its ANSI escape bytes included — a 3-column `│  ` gutter counted as 13
characters. The correct budget is `width - 3`, so the loss is a flat **10
columns**: 21% of a 48-column pane, 33% of a 30-column one. Two smaller
cosmetic losses: wrapped label continuations are not indented past the bullet,
and the hint is appended in parentheses rather than given its own dim row.

This is real and worth reporting upstream. It is also strictly a *legibility*
cost against a *corruption* cost, and it fails safe — it never overflows and
never drifts.

## Residual risks, recorded

- **Upstream backlog.** 59 open issues / 27 open PRs. But the two areas still
  actively broken are `multiselect` row counting
  ([PR #577](https://github.com/bombshell-dev/clack/pull/577), unmerged) and
  `spinner` wrapping ([PR #584](https://github.com/bombshell-dev/clack/pull/584),
  unmerged) — **neither of which the picker uses**. `select` is the
  best-covered prompt in the library.
- **`block()` exits 0 on ctrl-c.** Reached transitively from `spinner()`, so
  ctrl-c during a spinner is indistinguishable from success
  ([#573](https://github.com/bombshell-dev/clack/issues/573)). Avoided by not
  adopting Clack's spinner — the runner has its own progress output.
- **Two hoisted copies of `@clack/core` silently break `isCancel()`** (it compares
  a module-private symbol). pnpm's strict layout plus a range matching
  Sandcastle's own `^1.1.0` keeps this to one copy; worth an assertion if the
  picker ever misreads a cancel.
- **No minimum-width clamp upstream**, and the budget goes negative below ~13
  columns. `main.mts` already floors terminal width at 24, which should be kept.
- **ESM-only, Node ≥ 20.12.** Already true of Sandcastle, so no new constraint.
- **Testability.** `cli/flow.mts` is pure and unit-testable; `cli/prompts.mts`
  needs a TTY and is not. That split is a *consequence* of this decision and
  input to the map's open question about test strategy, but it does not settle
  it — the workflow contract ([#362](https://github.com/hadrysm/foldwise-voice/issues/362))
  still has to land first.

## Alternatives considered

| Option | Why not |
|---|---|
| **Lift the prototype's widget** | ~200 lines of ANSI wrapping, row accounting and per-prefix budgets owned forever, duplicating an engine already in the dependency tree. #361 found three independent defects in the hand-roll one at a time; there is no reason to think that process finished. |
| **`@inquirer/prompts` 8.5.2** | Healthiest project of the set (11 open issues vs 961 closed) and its `description` is exactly requirement (a). But **it does not handle `esc` at all** — zero occurrences across the published `dist/`, and in `select` an ESC keypress falls through into type-to-search. Requirement (c) is not negotiable, and the fix is upstream ([#2179](https://github.com/SBoudrias/Inquirer.js/issues/2179), 0 comments). It would also be a genuinely new dependency, and it has no resize listener. |
| **`enquirer` 2.4.1** | Frozen: last commit 2023-07-28, 169 open issues. Renders `hint` on *every* row, not just the focused one, and wraps nothing at all. |
| **`prompts` (terkelg) 2.4.2** | No release in 4.8 years, ships no types. Its number prompt **silently clamps per keystroke** — the exact behaviour #361 ruled out. |
| **`@topcli/prompts` 4.0.0** | Modern and zero-dependency, but 43 stars, no wrapping anywhere, initial cursor cannot be set, and neither `esc` nor `ctrl-c` is handled. Fails (a), (b), (c) and (e). |
| **`ink` 7.1.1** | The only candidate with a real layout engine, but it means React + a reconciler + Yoga (25 deps) for five questions, it ships no prompt components, and its model is a rewritten frame rather than a scrolling transcript — requirement (d) would mean fighting `<Static>`. |

## Not verified

- **The probe is a VT emulator, not a terminal.** It models deferred autowrap
  and the `CSI nA` / `CSI 0J` erase pair faithfully, which is the mechanism at
  issue, but it is not iTerm2 or Ghostty. The control failing at 30/48 and
  passing at 80 — matching the field report — is the evidence that it models
  enough of one.
- **Only `select` and `text` were exercised.** Clack's `confirm`, `spinner`,
  `note` and `group` were not, and the picker should be assumed to use none of
  them without its own check.
- **No resize-mid-prompt test.** Clack registers a `resize` listener but
  recomputes the old frame's extent at the *new* width; artifacts are plausible.
  The shipped widget has no listener at all, so this is not a regression either way.
- **Terminals narrower than 30 columns** were not probed.

## Reproducing

The probe is kept as a primary source on branch `probe/picker-widget-367`, out of
`main`, under `.sandcastle/PROBE-picker-widget/`: `vt.mjs` (emulator),
`control-shipped.mjs` (the widget as it ships, with only its two stream
references parameterised), `run.mjs` (the checks above) and `live.mjs` (the frame
captures). `npm install && node run.mjs`.
