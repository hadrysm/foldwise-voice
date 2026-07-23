# FoldWise Settings and global feedback prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Prototype Settings and global feedback states,” not production code.

Question: How should Settings controls, cards, input-device lifecycle states,
Appearance choices, updates, shortcuts, sound controls, configuration recovery,
validation, and global status feedback translate into the approved Ember Edge
grammar while retaining native macOS usability and current behavior?

Run the isolated native SwiftUI gallery from the repository root:

```sh
./Prototypes/SettingsFeedback/run.sh
```

The bottom review bar switches among three structurally different compositions:

- **A — Signal Ledger**: one dense scan path with each lifecycle message attached
  to the control that owns it.
- **B — Control Matrix**: operational controls lead in a broad work area while
  personalization and maintenance form a compact secondary column.
- **C — Open Form**: border-light native form bands use typography and rules
  instead of nested cards.

The review bar also previews Light and Dark appearances, wide and minimum-width
compositions, standard and increased contrast, standard and reduced motion, and
representative shortcut, input-device, update, recovery, validation, success,
and error states. The minimum-width preview intentionally keeps the sidebar
expanded to exercise the existing explicit narrow-expansion rule and the
vertical Appearance layout below its 650-point content boundary. Command–Left
Arrow and Command–Right Arrow cycle variants.

Render review snapshots to `.context/settings-feedback-shots` with:

```sh
./Prototypes/SettingsFeedback/run.sh --render
```

## Preserved behavior represented by the gallery

- Push to Talk, Toggle Recording, and Mode cycle keep assigned, unassigned,
  capturing, reset/remove, collision, and focused-app-only permission states.
- The input roster keeps System Default, connected preferred/non-preferred,
  missing preferred with Effective input fallback, restored, deferred during a
  Dictation session, and unavailable states.
- Pause other audio remains an immediate preference.
- Appearance remains the global System, Light, or Dark preference for both the
  main window and Badge, using horizontal choices at content widths of at least
  650 points and vertical choices below that boundary.
- Updates retain idle/current, checking, available, failed, and unavailable
  development-build presentations and their existing actions.
- Configuration recovery remains content-attached above Settings, makes the
  pane read-only, keeps Voice to Text available, and offers Quit and Reset
  Configuration.
- Validation and persistence failures use the content-attached global status
  edge. Success is transient in production; errors persist until superseded.
- Orange marks selection, capture, focus, and primary actions. Success, warning,
  and error retain separate semantic colors plus icon, text, and shape cues.

## Verdict

Approved: **A — Signal Ledger**.

Settings remains one dense, vertically scrolling scan path. Each subsystem keeps
an uppercase icon-led section label and one restrained surface containing its
native controls, rows, and directly owned lifecycle feedback. Shortcut capture
and validation stay with the shortcut ledger; input fallback, restoration,
deferral, and unavailability stay with the input-device roster; sound and update
controls remain compact rows; and Appearance remains a three-choice card set
that changes from horizontal to vertical at the existing 650-point content
boundary.

Configuration recovery and global success/error feedback keep the approved
Continuous Frame placement above and below the destination. Recovery makes the
pane visibly read-only. Success is transient in production, while validation
and persistence errors remain until superseded. Every state keeps the approved
Cues+ icon, text, and shape language; orange remains limited to selection,
capture, focus, and primary actions.

Variants B and C remain in this throwaway artifact only as review context. The
complete prototype gallery and production specification should carry forward
Variant A.
