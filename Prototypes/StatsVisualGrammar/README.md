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

Approved: **C — Dictation Pulse**.

Dictation Pulse won because it makes the Monthly activity calendar the clear
primary surface while keeping all four lifetime metrics visible in one compact
row. Its five fixed waveform bars give spoken-word intensity a FoldWise-specific
non-color cue: levels one through five fill the corresponding number of bars,
while neutral elapsed days retain the em dash. Exact spoken-word values remain
available in day detail and accessibility output, so the waveform does not
replace or redefine the activity measure.

The approved treatment retains the Ember Edge palette and component grammar:

- Metrics use their existing order, values, symbols, and accessibility grouping
  in a compressed, typography-led strip.
- The calendar uses one opaque surface with a restrained orange ingress edge;
  orange signals activity and focus without becoming a general surface wash.
- Hover uses the raised surface, keyboard focus uses the separated orange ring,
  today keeps its dot and outline, and future days remain visually quiet and
  excluded from focus and accessibility.
- Empty and saving-off notices retain their precedence, copy, icon/shape cues,
  and Open History behavior.
- The 880×640 compact view keeps one metric row and seven calendar columns.
- Contrast+ strengthens essential borders to two points. Reduced Motion makes
  detail and state changes immediate.
