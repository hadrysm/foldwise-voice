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

The Recording Badge preserves the production mic-reactive ribbon contract:
amplitude sweeps the smoothed `0.10…0.45` range at 30 Hz in Motion previews,
while Working keeps calm ribbons at a fixed `0.18`. Reduced Motion freezes the
decorative timeline without removing the persistent state cues.

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

Approved: the assembled FoldWise visual system is coherent across every curated
main-window and Badge review state.

Continuous Frame, Ember Edge, Instrument Panel, Command Ledger, Trace Ledger,
Dictation Pulse, Signal Ledger, and Ember Trace read as one identity in Light
and Dark, wide and compact layouts, hover and keyboard focus, empty, progress,
error, Contrast+, and Reduced Motion states.

Live review exposed one integration correction: the first assembled Badge
preview reduced Recording to a static dot. The approved gallery restores the
existing dynamic-amplitude contract—mic-reactive ribbons sweep the smoothed
`0.10…0.45` range at 30 Hz while Recording, and Working keeps calm ribbons at
the fixed `0.18` amplitude. Recording, Working, Done, and Error retain their
production 208-point width.

No exceptional component or token migration remains unresolved. Production
implementation can proceed from the resulting visual specification and slice
plan without reopening these visual decisions.
