# Guided setup takeover prototype

> **PROTOTYPE — throw this away after issue #333 is resolved.**

## Question

How should Guided setup enter, hold, and release FoldWise's main window?

This native SwiftUI wireframe compares three structural variants:

- **A — Shell takeover:** Guided setup is state above the six-pane system. It
  keeps the production titlebar but replaces the sidebar + destination area.
- **B — Setup rail:** Guided setup replaces the app sidebar with a setup-only
  progress rail. App destinations remain unreachable until release.
- **C — Separate root:** the window swaps to a dedicated setup root and
  restores `SettingsView` only on release.

The variants deliberately stay visually rough. They answer an ownership and
window-lifecycle question, not the map's still-open visual-design question.

Run from the repository root:

```sh
swift run --package-path Prototypes/GuidedSetupTakeoverPrototype
```

Use the bottom switcher or the Left/Right arrow keys to compare variants. Drive
these transitions in each:

1. **Trigger permission-recovery request** while setup is active.
2. **Close main window**, then reopen it.
3. **Finish setup** and inspect the release destination.
4. **Run setup again** from the simulated Home destination.

The useful reactions are:

- Which representation has the right ownership boundary?
- Should the Badge remain visible during the takeover?
- Is closing the window an explicit Setup skipped outcome, or should the
  takeover first ask for confirmation?
- Is Home the right release destination, with no summary screen?

## Fixed constraints

- The app promotes from `.accessory` to `.regular` whenever the main window is
  shown, including automatic first-run entry.
- The app's six-destination sidebar and its toggle are unreachable during the
  takeover.
- A permission-recovery presentation request never opens a competing sheet
  during Guided setup; the active Setup step owns the same live permission
  state.
- Finish and skip/dismiss are terminal outcomes. Only quitting the app preserves
  a mid-step cursor. Whether skipped and completed need distinct persisted
  values remains owned by “Decide whether Setup skipped is persisted distinctly
  from Setup completed.”
- Release returns to Home; the five decided Setup steps contain no separate
  summary step.

## Deliberate boundaries

- This prototype does not settle step copy or final visual design.
- It does not implement production state, persistence, permission polling, or
  window-controller behavior.
- It does not make the Permission recovery guide part of first-run setup; that
  guide remains a returning-user repair surface.
