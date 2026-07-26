# Guided setup takeover prototype

> **PROTOTYPE — throw this away after issue #333 is resolved.**

## Accepted direction

**A — Shell takeover** is accepted. Guided setup is state above
`SettingsModel.Pane`: the production titlebar remains while the sidebar and
destination content are replaced. It is not a seventh Pane and does not reuse
`isPaneAvailable`.

The losing setup-rail and separate-root variants have been removed.

## Question still being resolved

How should the accepted shell takeover hold and release the main window?

Run from the repository root:

```sh
swift run --package-path Prototypes/GuidedSetupTakeoverPrototype
```

The prototype now makes every Setup step concrete:

1. **Accessibility** — choose automatic paste, a narrower global-shortcut
   fallback, or Badge-only recording with clipboard delivery.
2. **Speech model** — review the approximately 600 MB Parakeet download and
   start it before continuing.
3. **Microphone** — grant the only required permission and observe the hard
   navigation gate.
4. **Push-to-Talk shortcut** — keep Right Option or choose another valid key.
5. **Polish** — keep complete Voice to Text or opt into Ollama and the
   approximately 1.9 GB `qwen2.5:3b` model.

No option is preselected. Back is absent from the first Setup step. Step changes
move horizontally and crossfade; Reduce Motion removes the movement and uses an
immediate state change.

Diagnostic actions now live in a visibly separate **Prototype controls** panel.
Use them to trigger the permission-recovery interruption, preview Badge
visibility, and compare direct close with close confirmation.

## Fixed constraints

- Showing the main window promotes the app from `.accessory` to `.regular`;
  closing returns it to `.accessory`.
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

- The prose is explanatory prototype copy, not final copy. The dedicated copy
  ticket owns its exact wording and localization.
- This prototype does not settle the map's final visual design.
- It does not implement production state, persistence, permission polling, or
  window-controller behavior.
- It does not make the Permission recovery guide part of first-run setup; that
  guide remains a returning-user repair surface.
