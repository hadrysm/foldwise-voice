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

Approved: **A — Instrument Panel**.

Home keeps its direct operating sequence: page title and live Push to Talk
instruction, four lifetime metrics, the attached system-readiness band, then
the newest grouped Dictation rows. Metrics remain one four-tile strip at or
above 940 points and become a two-by-two composition below it. Readiness uses
the Ember Edge ingress mark and semantic icon/text cues; it does not turn the
whole surface orange. “Stats” and “All history” remain in-place destination
links.

History leads with its title and local/text-only assurance, followed by two
equal setting cells that keep saving and retention visibly independent. Search
and Flagged-only share one control strip above date-grouped ledgers. “Clear all
history” remains a distinct destructive action rather than a row-level command.
Empty, no-result, saving-off, and confirmation states keep their existing
meanings and copy.

The shared Dictation row uses the approved dense ledger treatment: a 44-point
line with monospaced 24-hour time, a restrained orange ingress rule, single-line
text, then Mode/deleted/flag identity. Hover or keyboard focus swaps that
identity for Copy and Flag on Home, plus More on History. Focus, copied,
flagged, deleted-Mode, Raw/Polished, and destructive states retain permanent
non-color cues and accessible descriptions.

This is a visual composition decision only. It does not change metrics,
sorting, grouping, persistence, filtering, retention, row commands, breakpoint
policy, or accessibility behavior. Variants B and C remain in this throwaway
artifact only as review context; the complete gallery and implementation
specification should carry forward Variant A.
