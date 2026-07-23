# FoldWise Stats visual-grammar prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Prototype Stats within the new visual grammar,” not production code.

Question: How should the approved metric strip and Monthly activity calendar be
restyled in the Ember Edge grammar across populated, empty, saving-off,
future-day, hover, keyboard-focus, compact, and accessibility states without
changing metric or calendar behavior?

Run the isolated native SwiftUI gallery from the repository root:

```sh
./Prototypes/StatsVisualGrammar/run.sh
```

The bottom review bar switches among three structurally different treatments:

- **A — Ember Tiles**: four distinct instrument tiles and one contained
  calendar. This is the closest translation of the approved reference.
- **B — Signal Rail**: one continuous metric rail and a flatter, ruled calendar
  with intensity carried by a persistent bottom edge.
- **C — Dictation Pulse**: a calendar-first treatment with a compressed metric
  strip and tiny waveform bars as the permanent non-color intensity cue.

The review controls also switch among populated, empty, saving-off, and quiet
current-month data; Light and Dark; 880×640 compact and 1180×760 wide windows;
neutral, hover, and keyboard-focus detail; Standard and Contrast+; and Motion
and Reduced Motion. Command–Left Arrow and Command–Right Arrow cycle
treatments. Tab enters the calendar and unmodified arrow keys move the roving
day focus. Future days remain excluded from focus and accessibility.

Render the review matrix to `.context/stats-visual-grammar-shots` with:

```sh
./Prototypes/StatsVisualGrammar/run.sh --render
```

## Verdict

Pending live review.
