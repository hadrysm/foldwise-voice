# FoldWise Home, History, and Dictation row prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Prototype Home, History, and shared Dictation rows,” not production code.

Question: How should Home, History, and the shared Dictation row translate into
the approved Ember Edge grammar and Continuous Frame while preserving their
existing information, actions, states, and responsive behavior?

Run the isolated native SwiftUI gallery from the repository root:

```sh
./Prototypes/HomeHistory/run.sh
```

The bottom review bar switches among three structurally different compositions:

- **A — Instrument Panel**: the approved-reference direction. Metrics form a
  calm rail, readiness attaches below it, and recent Dictation rows read as a
  dense ledger.
- **B — Command Deck**: readiness and Push to Talk lead the surface. Metrics
  become a side instrument cluster beside the current work.
- **C — Activity Spine**: dates and timestamps form a strong vertical spine;
  controls occupy a persistent utility lane and metrics become an editorial
  summary.

The same bar previews Home and History, four representative states, wide and
compact composition, resting/hover/focus/copied/overflow-menu row states, Light
and Dark, and standard or increased contrast. Command–Left Arrow and
Command–Right Arrow cycle variants.

Render review snapshots to `.context/home-history-shots` with:

```sh
./Prototypes/HomeHistory/run.sh --render
```

## Preserved behavior represented by the gallery

- Home keeps its live Push to Talk hint, four lifetime metrics, full system
  summary, newest ten grouped Dictation rows, Stats link, All history link,
  empty state, Accessibility action, and four-wide/two-by-two breakpoint.
- History keeps saving and retention as separate controls, all retention
  choices, live search, Flagged-only filtering, grouped rows, Clear all,
  first-run and no-result states, and the saving-off-with-retained-data state.
- A Dictation row remains 44 points high with a 24-hour timestamp, one-line
  text, Mode identity, deleted-Mode and flag cues, and the exact Home versus
  History action order. Copy confirmation and keyboard focus remain visible
  non-color states.
- Wide represents `windowWidth >= 940`; Compact represents the existing
  below-940 two-by-two Home metrics and automatic 52-point navigation rail.
- All colors, radii, borders, type roles, focus treatment, and semantic status
  colors come from the approved Ember Edge grammar. Contrast+ uses two-point
  borders.

## Verdict

Pending human review. Record the chosen structure and any borrowed elements
here before deleting or absorbing the prototype.
