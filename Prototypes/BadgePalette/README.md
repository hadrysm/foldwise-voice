# FoldWise Badge palette prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Prototype the orange-led Badge palette across states,” not production code.

Question: Which orange-led neutral, active, working, done, and error treatment
should replace the Badge’s violet/cyan palette across Light and Dark while
preserving its capsule silhouette, exact geometry, state content, controls,
motion roles, and semantic error identity?

Run the isolated native SwiftUI gallery from the repository root:

```sh
./Prototypes/BadgePalette/run.sh
```

The bottom review bar switches among three treatments:

- **A — Ember Trace**: the direct Ember Edge translation. The neutral Badge is
  quiet graphite/ivory; orange traces recording and working; green confirms
  Done; red owns every Error.
- **B — Copper Key**: a warmer, quieter standing identity. Muted copper marks
  Idle and secondary controls while brighter orange is reserved for the primary
  action and live work.
- **C — Signal Notch**: the strongest permanent Cues+ treatment. A short
  internal leading notch pairs state color with position and shape, without
  changing the capsule silhouette or dimensions.

Every preview is drawn at the production Badge’s real 38-point height and exact
88, 132, 176, or 208-point width. The gallery covers Idle, Hover, quiet and
normal Recording, spinner and status Working, Done, clipboard and pipeline
Error, and Mode-cycle confirmation.

Command–Left Arrow and Command–Right Arrow cycle treatments. The review bar
also forces Light or Dark, Standard or Contrast+, and Motion or Reduced Motion.
Contrast+ increases the border from one to two points. Reduced Motion freezes
the preview ribbons and spinner while keeping the same state cues.

Render the six Light/Dark treatment snapshots into
`.context/badge-palette-shots` with:

```sh
./Prototypes/BadgePalette/run.sh --render
```

## Verdict

Pending live review.
