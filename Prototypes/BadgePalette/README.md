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

Approved: **A — Ember Trace**, with **Standard** contrast as the baseline and
the existing Contrast+ and Reduced Motion adaptations retained.

Ember Trace won because it extends the approved Ember Edge grammar most
directly without making the small floating surface ornamental. The opaque
graphite/ivory pill and neutral resting border keep Idle quiet; orange identifies
the static glyph, primary Hover action, Mode-cycle identity, Recording ribbons,
active border, Working spinner, and progress treatment. Done remains semantic
green through its border, filled checkmark, and text. Every Error remains
semantic red through its border, warning icon, and recovery/failure text.

The approved treatment preserves the 38-point capsule silhouette, exact
88/132/176/208-point widths, state content, control order, ribbon and spinner
roles, dwell timing, and Mode-cycle motion. It adds no standing notch or warm
surface wash. Standard uses a one-point border; Contrast+ uses a two-point
border. Reduced Motion freezes decorative timelines while leaving every
persistent shape, icon, text, and border cue intact.

Foreground text, orange, success green, and error red all exceed 5:1 against
their Light and Dark pill surfaces in the prototype palette.
