# Guided setup logic prototype

> **PROTOTYPE — throw this away after issue #328 is resolved.**

## Question

Does this five-step state model make the promises of Guided setup honest?

1. Accessibility
2. Speech model
3. Microphone
4. Push-to-Talk shortcut
5. Polish

The accepted order puts the optional insertion permission first, starts the
speech-model download second so it can continue behind every later choice, and
then reaches Microphone as the only hard gate. It treats shortcut selection as
a real Setup step, but as confirmation of the valid `alt_r` default rather than
required reconfiguration. It also keeps **Setup completed** independent from
**Dictation ready**: starting the speech-model download is enough to leave that
Setup step, but only an observable ready model makes Dictation ready.

Run it from the repository root:

```sh
swift run --package-path Prototypes/GuidedSetupLogicPrototype
```

Drive both the happy path and the refusal paths. The useful reactions are:

- Does any step come too early or too late?
- Does “Download and continue” over-promise?
- Is Accessibility one choice with an Input Monitoring fallback, or two steps?
- Does confirming the shipped shortcut earn a whole Setup step?
- Can setup honestly be completed while the speech model is still downloading?

## Deliberate boundaries

This prototype does not settle work owned by neighboring tickets:

- The exact speech-model download, failure, cancellation, and progress
  affordances belong to “Decide the speech-model step's contract.”
- The no-LLM contracts on Home, History, Modes, and Models belong to “Decide
  the honest no-Polish end state.”
- Window entry, holding, release, and Badge behavior belong to “Decide the
  main-window takeover mechanics.”
- Copy and visual design remain fog on the Wayfinder map.

The reducer is pure and lives in `GuidedSetupModel.swift`. `main.swift` is only
the throwaway terminal shell.
