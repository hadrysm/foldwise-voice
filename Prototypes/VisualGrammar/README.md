# FoldWise visual grammar calibration

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Calibrate the orange-led cross-appearance visual grammar,” not production
> code.

Question: Which exact palette, typography, spacing, material, border, radius,
icon, focus, hover, motion, and component rules best translate the approved
orange-led screenshot into one FoldWise system across Dark, Light, and the
Badge?

Run the native SwiftUI gallery from the repository root:

```sh
./Prototypes/VisualGrammar/run.sh
```

The bottom review bar switches among three deliberately different calibrations:

- **A — Ember Edge**: closest to the approved screenshot. Near-black layered
  surfaces, eight-point corners, restrained orange ingress marks, and a calm
  SF Pro hierarchy.
- **B — Signal Ledger**: denser and more technical. Flatter surfaces,
  four-point corners, tabular labels, and orange rules instead of glow.
- **C — Warm Relay**: softer and more native. Warm graphite/ivory materials,
  twelve-point corners, roomier rhythm, and filled orange controls.

Command–Left Arrow and Command–Right Arrow cycle calibrations. The review bar
also forces Light or Dark and previews increased contrast, emphasized non-color
cues, and Reduce Motion.

Render the six Light/Dark calibration snapshots to
`.context/visual-grammar-shots` with:

```sh
./Prototypes/VisualGrammar/run.sh --render
```

The gallery intentionally stops at the shared grammar. Later Wayfinder tickets
apply the approved calibration to the complete shell, destinations, sheets, and
every Badge state.

## Verdict

Approved: **A — Ember Edge**, with **Standard** contrast as the baseline and
**Cues+** as the permanent non-color state language.

Ember Edge won because it translates the approved screenshot most directly:
near-black layered Dark surfaces, warm off-white Light surfaces, restrained
orange ingress marks, and typography-led hierarchy. Standard keeps the baseline
fine and quiet; the separate Contrast+ adaptation remains available when macOS
Increase Contrast is enabled. Cues+ is not optional decoration: selections,
success, warning, and error states pair color with persistent shape, icon, text,
weight, or underline cues.

The approved grammar uses:

- SF Pro for interface language and SF Mono only for time, shortcuts, and model
  data, on a four-point spacing grid.
- Eight-point surface radii, six-point control radii, one-point baseline borders,
  and two-point increased-contrast borders.
- A two-point orange focus ring separated from the control by a two-point canvas
  gap.
- A 160 ms ease-out for hover and state changes; immediate transitions under
  Reduce Motion.
- Orange for selection ingress, active icons, focus, and primary actions—not as
  a general surface wash or substitute for semantic status colors.
- The same orange family on the Badge without glow or geometry changes; Badge
  errors retain their dedicated icon, text, and border treatment.
