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

Pending live review. Record the approved composition and any borrowed elements
here before this prototype is retired or absorbed into the complete gallery.
