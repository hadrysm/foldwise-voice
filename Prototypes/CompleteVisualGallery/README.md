# FoldWise complete visual prototype gallery

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Assemble and approve the complete visual prototype gallery,” not production
> code.

Question: When the approved shell and destination treatments are assembled into
one native SwiftUI gallery, do they form one coherent FoldWise identity across
the curated appearance, width, interaction, lifecycle, and accessibility
states—and what final corrections are required?

Run the gallery from the repository root:

```sh
./Prototypes/CompleteVisualGallery/run.sh
```

The review bar keeps only the approved compositions:

- **Continuous Frame** shell and **Ember Edge** visual grammar
- **Instrument Panel** Home and History with shared Dictation rows
- **Command Ledger** Modes
- **Trace Ledger** Models
- **Dictation Pulse** Stats
- **Signal Ledger** Settings
- **Ember Trace** Badge

Use the controls to move through all six destinations and the Badge; Light and
Dark; wide and compact layouts; baseline, hover, focus, empty, progress, and
error states; Standard and Contrast+; and Motion and Reduced Motion.
Command–Left Arrow and Command–Right Arrow cycle surfaces.

Render the curated integration matrix to
`.context/complete-visual-gallery-shots` with:

```sh
./Prototypes/CompleteVisualGallery/run.sh --render
```

## Design plan

- **Color:** Ember orange (`#FF6A1A` Dark / `#BF4008` Light), graphite canvas
  (`#07090B`), warm paper canvas (`#F7F3EC`), semantic green, amber, and red.
- **Type:** SF Pro for interface hierarchy; SF Mono only for time, shortcuts,
  model facts, and review metadata.
- **Layout:** one continuous titlebar over a persistent navigation column and
  destination canvas; compact mode becomes the approved 52-point rail.
- **Signature:** one restrained orange signal trace joins selected navigation,
  inspected content, focus, Monthly activity calendar intensity, and active
  Badge work without washing any surface orange.

Review-only treatment names remain in the review bar rather than inside the app
surface. This removes prototype narration from the assembled product view and
lets the shared system—not labels—carry the identity.

## Verdict

Pending live review.
