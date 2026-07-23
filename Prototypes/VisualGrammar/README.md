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

Pending human review. Record the chosen calibration and the reasons it won here
before the prototype is deleted or absorbed into the final visual specification.
