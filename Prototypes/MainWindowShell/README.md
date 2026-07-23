# FoldWise main-window shell prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Prototype the redesigned main-window shell,” not production code.

Question: How should the titlebar, brand lockup, expanded sidebar, collapsed
rail, content canvas, footer, configuration-recovery banner, and global status
area compose in the approved Ember Edge grammar without changing navigation,
collapse, resizing, or recovery behavior?

Run the isolated native SwiftUI gallery from the repository root:

```sh
./Prototypes/MainWindowShell/run.sh
```

The bottom review bar switches among three structurally different shell
compositions:

- **A — Continuous Frame**: one titlebar spans the window; the sidebar and
  destination canvas divide the body below it.
- **B — Sidebar Mast**: brand and navigation form a full-height mast below a
  quiet traffic-light strip; the destination owns its compact toolbar.
- **C — Inset Workbench**: titlebar spans the frame while navigation and
  destination canvas become separate inset working surfaces.

The same bar previews the expanded 190-point sidebar and 52-point rail, Light
and Dark appearances, normal/recovery/success/error feedback, and standard or
increased contrast. Command–Left Arrow and Command–Right Arrow cycle variants.

The interior Home-like blocks are deliberately low-fidelity context. They show
content density and scroll boundaries without deciding the later Home surface
prototype.

Render review snapshots to `.context/main-window-shell-shots` with:

```sh
./Prototypes/MainWindowShell/run.sh --render
```

## Preserved behavior represented by the gallery

- Six destinations remain in their existing order.
- The labeled sidebar remains 190 points and the icon rail remains 52 points.
- Existing resizing rules remain authoritative: 880×640 minimum and automatic
  rail below 940 points, with explicit expansion continuing to win while
  narrow.
- Recovery keeps Home and Stats available, disables configuration-owning
  destinations, keeps Voice to Text available, and offers Reset Configuration
  and Quit.
- Success status is transient in production; error status remains until
  superseded. The prototype keeps either visible for comparison.
- The footer retains version/update information in the expanded sidebar; the
  rail exposes the same information through its version control help.
- Orange remains an ingress/signaling color. Warning, success, and error retain
  their semantic colors plus persistent icon and text cues.

## Verdict

Approved: **A — Continuous Frame**.

The main window uses one titlebar spanning the complete frame. Traffic lights,
the existing sidebar toggle, and the FoldWise Voice brand lockup share that
strip. Below it, the 190-point expanded sidebar or 52-point rail divides cleanly
from one destination canvas.

The sidebar footer stays anchored to the navigation column. Configuration
recovery and global status belong to the content edge instead: recovery sits
above the destination and status below it, so neither shifts or competes with
navigation. Their orange, warning, success, and error ingress marks follow the
approved Ember Edge and Cues+ grammar.

This is a composition decision only. Existing navigation order, persisted and
automatic collapse rules, explicit narrow expansion, 880×640 minimum, recovery
permissions, status lifetimes, keyboard command, and accessibility behavior
remain unchanged.

Variants B and C remain in this throwaway artifact only as review context. The
complete prototype gallery and production specification should carry forward
Variant A.
