# Production visual system specification

Implementation specification and slice plan for
[Modernize FoldWise's complete visual system](https://github.com/hadrysm/foldwise-voice/issues/248).

## Status and authority

This document is the production handoff from the approved native SwiftUI gallery
in [`Prototypes/CompleteVisualGallery`](../../Prototypes/CompleteVisualGallery/README.md).
It turns the gallery's visual decisions into production contracts; it does not
make the throwaway prototype a runtime dependency.

When sources disagree, use this order:

1. Product behavior and state ownership in the production code, accepted ADRs,
   and the
   [complete surface and state matrix](complete-surface-and-state-matrix.md).
2. Tokens, compositions, and visual state language in this specification.
3. The approved complete gallery at commit `db81ee0` as the visual oracle.
4. Individual prototype galleries as supporting review history only.
5. The original attached image as visual direction, not a pixel template.

The implementation is complete only when the production app matches the intent
of the approved gallery while retaining every behavior in the preservation
matrix.

## Scope boundary

### In scope

- One production Ember Edge token system for Light, Dark, the main window, and
  the Badge.
- Continuous Frame across the titlebar, navigation column, destination canvas,
  Configuration recovery state, and global status area.
- The approved Instrument Panel, Command Ledger, Trace Ledger, Dictation Pulse,
  Signal Ledger, and Ember Trace treatments.
- Explicit Increase Contrast, Differentiate Without Color, Reduce Motion,
  keyboard-focus, VoiceOver, compact-width, and localization adaptations.
- Production tests and manual evidence proving visual and behavioral parity.

### Out of scope

- New destinations, data, metrics, controls, commands, workflows, persistence,
  or state transitions.
- Changes to Dictation processing, model lifecycle semantics, History storage,
  statistics definitions, configuration schema, or the menu-bar item.
- Badge geometry, panel behavior, interaction order, state-machine behavior,
  dwell timing, or Mode-cycle choreography changes other than the approved
  Reduce Motion treatment.
- Shipping prototype review controls, mock data, treatment names, screenshot
  renderers, or prototype-only layout abstractions in production.
- A broad production screenshot test suite. Screenshots are a human review
  oracle; deterministic behavior and stable rendered invariants belong in
  XCTest.

## Non-negotiable system contracts

The visual migration must not change these facts:

- The destination order is Home, Modes, Models, History, Stats, Settings.
- The main window minimum is `880 × 640`. The expanded navigation column is
  `190` points and the compact rail is `52` points. Automatic rail presentation
  begins below `940` points; an explicit narrow expansion still wins.
- Configuration recovery remains read-only. Home and Stats remain readable;
  Voice to Text remains usable; Modes, Models, History, and Settings remain
  disabled; Reset Configuration and Quit remain available.
- Preferences commit immediately and transactionally through `Config`. A failed
  write restores the last committed presentation. Mode drafts still commit only
  through Save.
- Appearance preference remains System, Light, or Dark and propagates live to
  both the main window and Badge.
- A Dictation row remains one shared `44`-point component. Home and History
  supply different command capabilities without defining different row types.
- ASR model selection, Effective ASR model, and ASR model availability remain
  separate facts. Inspection remains separate from selection.
- The Badge remains a non-activating, always-on-top `NSPanel`, `38` points high,
  with exact `88`, `132`, `176`, and `208` point state widths and a stable
  persisted anchor.
- Accessibility names, values, hints, focus order, non-color cues, localized
  dates and numbers, Reduce Motion, and Increase Contrast are behavior, not
  optional polish.

## Canonical design tokens

`Theme` remains the sole production owner of visual tokens. Call sites consume
semantic names; no production view owns a duplicate hex literal, opacity-based
essential contrast, or private substitute palette.

### Color

All base colors are opaque sRGB. `Theme` resolves Light and Dark dynamically so
System appearance continues to update live.

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `canvas` | `#07090B` | `#F7F3EC` | Destination background |
| `navigation` | `#090B0E` | `#EEE8DE` | Titlebar and navigation column |
| `surface` | `#0D1013` | `#FFFCF7` | Cards, ledgers, Badge neutral fill |
| `raised` | `#13171B` | `#F4EFE7` | Selected, attached, or emphasized regions |
| `hover` | `#1A2026` | `#EAE2D7` | Pointer hover only |
| `border` | `#262C32` | `#D8CFC1` | Standard essential border |
| `borderStrong` | `#5B6570` | `#978B7C` | Increase Contrast essential border |
| `textPrimary` | `#F4F5F6` | `#1A1714` | Primary labels and values |
| `textSecondary` | `#A4AAB0` | `#625C55` | Supporting copy |
| `textTertiary` | `#747C85` | `#766E65` | Inactive, metadata, and future-day copy |
| `accent` | `#FF6A1A` | `#BF4008` | Ingress, active icons, focus, primary actions |
| `accentHover` | `#FF8A4A` | `#9E3305` | Hovered primary action |
| `accentForeground` | `#160900` | `#FFFFFF` | Content on a filled accent control |
| `success` | `#43D17A` | `#147A42` | Successful outcome only |
| `warning` | `#F0B44B` | `#865B00` | Warning or deferred state only |
| `error` | `#FF6464` | `#B4232C` | Failure or destructive state only |

Rules:

- Orange is an ingress and signaling color. It marks selection edges,
  inspection, active icons, focus, progress, and primary actions. It is not a
  surface wash and never replaces success, warning, or error.
- Color is never the only state cue. Selection, inspection, progress, success,
  warning, error, raw/polished, flagged, and deleted-Mode states also use a
  persistent icon, text, shape, weight, checkmark, underline, waveform fill
  count, or border.
- Essential contrast never depends on blur, translucency, glow, gradient, or
  shadow. The main-window design uses no decorative shadow.
- The Badge neutral fill is `surface`. Its active border and ribbons use
  `accent`; Done uses `success`; Error uses `error`.
- Primary, secondary, small text, action foregrounds, semantic colors, and focus
  accents must remain at least `4.5:1` against their actual surface. Essential
  non-text boundaries in Increase Contrast must remain at least `3:1`.

### Typography

Use the system SF family through the existing `Theme.ui` and `Theme.mono`
factory seam. Do not bundle fonts.

| Role | Specification | Use |
| --- | --- | --- |
| Display | SF Pro, `30`, semibold, `-0.5` tracking | Destination title |
| Section | SF Pro, `11`, bold, `+0.7` tracking, uppercase | Structural group label |
| Body | SF Pro, `13.5`, regular | Main interface copy |
| Body emphasis | SF Pro, `13.5`, semibold | Selected labels and row titles |
| Data | SF Mono, `11`, medium | Time, shortcuts, model facts, durations |
| Compact metadata | SF Mono, `9–10.5`, medium/bold | Status tags and dense facts |

SF Mono is reserved for time, shortcuts, model data, numeric metadata, and
compact status tags. It does not replace prose or navigation labels.

### Spacing and geometry

- Base spacing unit: `4` points.
- Named rhythm: `4`, `8`, `12`, `16`, `20`, `24`, `28`, `32`, `36`.
- Surface radius: `8`.
- Control radius: `6`.
- Standard border: `1`.
- Increase Contrast border: `2`.
- Selection/inspection ingress rule: `2`.
- Recovery and global-status ingress rule: `3`.
- Focus ring: `2` points of `accent`, separated from the control by a
  `2`-point `canvas` gap.
- Main destination horizontal padding: `28` wide and `20` compact unless a
  fixed production geometry below is more specific.

One-off fixed sizes required by preserved behavior do not need to land on the
spacing grid: window, navigation, Models split, Mode editor, Dictation row, and
Badge geometries remain exact.

### Motion

- Ordinary hover and visual state transitions use `160 ms` ease-out.
- Under Reduce Motion, ordinary transitions are immediate.
- The Badge keeps its accepted state-machine timing. Reduce Motion freezes
  decorative ribbon, spinner, crossfade, and hover-scale timelines while
  leaving state changes and persistent cues visible.
- Mode cycle keeps its existing reduced `180 ms` opacity-only swap and
  `900 ms` settled dwell. Standard mode keeps its existing `260 ms` opposed
  reel travel and `300 ms` resize.
- Recording samples the existing smoothed microphone amplitude at `30 Hz`
  across `0.10 ... 0.45`. Working uses fixed `0.18` ribbons. Reduced Motion
  freezes the visual timeline at a legible representative amplitude; it does
  not hide the waveform.

### Environment adaptations

- Light and Dark select the corresponding opaque token set. System follows the
  live effective macOS appearance through the existing appearance reactor.
- Increase Contrast changes every essential boundary from the standard
  `1`-point `border` to the `2`-point `borderStrong` treatment. It does not
  introduce heavier decoration or change layout.
- Cues+ is the baseline in every environment, not a conditional mode.
  Differentiate Without Color therefore never needs to reveal a cue that was
  absent before the setting changed; it verifies that the permanent icon, text,
  shape, weight, underline, checkmark, or waveform cue remains sufficient.
- Reduce Motion selects the immediate ordinary transition policy and the
  explicit Badge adaptations above. It does not remove content, progress, focus,
  or outcome feedback.

## Shared component contracts

These are visual components, not new state owners. They accept values and
actions from existing projections, workflows, reducers, and controllers.

### Surface

The standard surface is an opaque `surface` fill, `8`-point radius, and an
essential border. It uses `border` at `1` point or `borderStrong` at `2` points
under Increase Contrast. A raised surface substitutes the `raised` fill but
keeps the same border contract.

The component owns only chrome. It does not own loading, validation, selection,
or persistence state.

### Ingress

An ingress rule attaches to the leading edge of the region it identifies:

- `accent`, `2` points: selected navigation, selected Mode, inspected model,
  active Monthly activity calendar, Dictation row identity.
- Semantic color, `2` points: inline success, warning, or error.
- Semantic color, `3` points: Configuration recovery or global status edge.

Ingress never stands alone. The identified region also exposes text, an icon,
weight, selection value, or another permanent cue.

### Section label

An uppercase Section token with the approved section typography. A section
symbol may precede it only when the symbol identifies the subsystem; numeric or
decorative prefixes are not allowed.

### Focus treatment

Every custom clickable or keyboard-focusable region uses the separated focus
ring. It must remain visible over selected, hovered, success, warning, and error
states. Native text fields and controls may retain the native focus effect when
it is equally visible and does not conflict with the custom ring.

Focus styling observes `isFocused`; it does not become a second keyboard
navigation model. Existing focus policies remain authoritative.

### Status notice

Status notices take a semantic kind (`success`, `warning`, or `error`), icon,
title, optional detail, and optional action. They render a semantic ingress rule
plus the matching icon and explicit text.

The caller owns lifetime and recovery. A notice component never starts a timer,
clears an error, retries work, or decides whether an action is available.

### Buttons and controls

- Primary action: filled `accent`, `accentForeground`, `6`-point radius, visible
  focus ring, `accentHover` on pointer hover.
- Quiet action: `surface` or transparent fill with essential border; hover uses
  `hover`.
- Destructive action: text/icon and confirmation use `error`; do not fill a
  whole card red.
- Selection control: ingress/checkmark/weight plus text. Selected state may use
  `raised`; it must not depend on a tinted wash.
- Disabled controls retain legible text and explain why through adjacent or
  accessible text when the existing behavior provides a reason.

### Empty state

An empty state uses one identifying symbol, a direct title, and a next-step
detail. It occupies the surface's normal content region and does not introduce
new actions. Search-no-result and first-run empty states keep distinct copy.

### Dictation row

The production `DictationRow` remains the single component:

- Fixed height `44`.
- Monospaced `HH:mm` time.
- A `2`-point orange identity rule.
- One-line, whitespace-collapsed, tail-truncated displayed text.
- Trailing Mode identity, deleted annotation, and optional flag at rest.
- Hover or keyboard focus swaps identity for semantic actions.
- Home order: row, Copy, Flag.
- History order: row, Copy, Flag, More.
- Copy confirmation remains `1.4` seconds and announces “Copied”.

`DictationRowInteractionState` and `DictationRowCopyFeedback` continue to own
hover/focus/transient presentation. Home and History continue to own commands
and persistence.

## Surface specifications

### Continuous Frame

- One titlebar spans the entire window and centers its content on the real
  traffic-light row.
- Traffic lights, existing sidebar toggle, waveform mark, and FoldWise Voice
  lockup share the titlebar.
- Below it, the `190`-point expanded navigation column or `52`-point rail
  divides from one destination canvas with an essential hairline.
- Selected navigation uses a leading accent ingress, active icon, semibold
  label, and checkmark in expanded mode. The rail retains an accessible selected
  value.
- The version/update footer remains anchored to the navigation column. In rail
  mode its control exposes the same information through help/accessibility.
- Configuration recovery attaches above the destination. Global success/error
  attaches below it. Neither shifts navigation.
- `⌘\`, persisted collapse preference, automatic collapse, explicit narrow
  expansion, and activation-policy behavior remain unchanged.

Production owners:

- `SettingsView`: titlebar, navigation, destination canvas, recovery/status
  placement.
- `SidebarPresentation`: collapse decision only.
- `SettingsController`: AppKit window construction, minimum size, activation,
  titlebar integration, and status lifetime.

### Home — Instrument Panel

- Preserve the direct order: title and live Push to Talk instruction, four
  lifetime metrics, attached system-readiness band, newest grouped Dictation
  rows, All history action.
- Metrics remain four across at or above `940` points and `2 × 2` below.
- The readiness band uses an ingress plus semantic icon/text. Its Stats action
  remains secondary to the readiness information.
- The newest ten rows remain date grouped and use the shared Dictation row.
- Empty, unavailable, hover, focus, copied, flagged, raw/polished, current Mode,
  deleted Mode, and Voice to Text states remain explicit.

Production owners:

- `HomeProjection` and `HomeOverviewLayout`: data, grouping, and breakpoint
  decisions.
- `HomeView`: composition only.
- `DictationRow`: shared row chrome and interaction presentation.

### History — Instrument Panel

- Preserve title and local/text-only assurance.
- Saving and retention are equal visual cells but remain independent controls.
- Search and Flagged-only share one utility strip.
- Date-grouped ledgers use the shared Dictation row.
- Clear all remains visually separate and destructive.
- First-run empty, search no-result, Flagged-only no-result, saving-off with
  retained data, destructive confirmations, and full row menus remain distinct.

Production owners:

- `HistoryProjection` and `HistoryReprocessor`: filtering, grouping, and
  semantic operations.
- `HistoryPane`: composition, alerts, and command routing.
- `DictationRow`: shared row chrome and interaction presentation.

### Modes — Command Ledger

- Voice to Text is a separate permanent system selection.
- The editable ordered Mode library remains persistently visible.
- A stable inspector shows the selected Mode's icon, name, transformation,
  model, Polish instructions, vocabulary, availability guidance, and actions.
- Selection uses accent ingress, active icon, semibold text, and checkmark.
- The fixed `820 × 570` editor remains a sheet with explicit Save/Retry and
  Cancel. It retains validation, keyboard behavior, icon popover, and disabled
  interactive dismissal.
- Empty library, unavailable model, delete confirmation, validation failure,
  persistence Retry, and icon palette states stay attached to their owner.

Production owners:

- `ModeSelectionProjection`, `ModeEditorPolicy`, and
  `ModeEditorPresentation`: selection, validation, and action presentation.
- `SettingsView`: Mode library and inspector composition.
- `ModeEditorSheet`: editor composition only.
- `SettingsWorkflow` and `Config`: candidate transaction and persistence.

### Models — Trace Ledger

- The comparison ledger and inspector remain side by side at every supported
  width.
- At exactly `617` points of Models content width, the ledger is `340` and the
  inspector `276`, separated by the existing split boundary.
- An accent ingress links the inspected row to the inspector. Inspection never
  changes ASR model selection.
- The saved ASR model selection remains a separate checkmark-and-text fact.
- Speech recognition remains Global selection; Polish remains Mode inventory.
- Rows stay compact and two-line. Model facts use SF Mono.
- Fallback simultaneously exposes saved intent and Effective ASR model.
- Progress, failure, repair, cancellation, destructive consequences, focus, and
  restoration stay attached to the affected family/model.
- Confirmation copy continues to name removed storage, affected Modes, raw-text
  fallback, and selected-model consequences.

Production owners:

- `ModelsWorkspaceProjection` and lifecycle types: state, focus, action,
  announcement, and fallback truth.
- `ModelsCombinedPane`: ledger/inspector composition and focus application.
- `ASRModelLifecycle`: all ASR operations.
- `SettingsWorkflow`: Polish model operations.

### Stats — Dictation Pulse

- All four lifetime metrics remain in their fixed order in one compressed,
  typography-led row.
- The Monthly activity calendar is the primary surface.
- Each elapsed activity cell has five fixed waveform bars. Intensity `1 ... 5`
  fills the same number of bars; neutral days use an em dash.
- Exact spoken-word values remain in detail and accessibility output.
- Today retains its dot and outline. Future days remain visually quiet and are
  excluded from focus and accessibility.
- Hover uses `hover`. Keyboard focus uses the separated focus ring.
- The calendar stays seven columns at all supported window widths.
- Notice precedence and Open History behavior remain unchanged.
- Under Reduce Motion, detail and intensity changes are immediate.

Production owners:

- `StatsProjection`, `CalendarFocusNavigator`, and `StatsActivityStyle`: data,
  intensity, notice, focus, and transition decisions.
- `StatsPane` and its private calendar components: composition only.

### Settings — Signal Ledger

- One dense vertical scroll path with icon-led Section labels and restrained row
  surfaces.
- Shortcut capture, assignment, removal, collision validation, and
  focused-app-only permission feedback stay attached to the shortcut ledger.
- Input-device selection, preferred-device fallback, restoration, deferral, and
  unavailability stay attached to the input roster.
- Pause other audio and update controls remain compact native rows.
- Appearance remains System, Light, Dark with persistent selected/not-selected
  cues. It is horizontal at content widths `>= 650` and vertical below `650`.
- Configuration recovery and global feedback use Continuous Frame, not an
  additional Settings-only banner.

Production owners:

- `SettingsWorkflow`, shortcut policies, and input-device policies: behavior.
- `SettingsModel`: observable presentation state.
- `SettingsView`: Settings composition.
- `SettingsController`: AppKit effects, window boundary, and status lifetime.

### Badge — Ember Trace

- Neutral fill is opaque graphite/ivory with a quiet neutral border.
- Idle uses a static accent glyph. Hover exposes Change selection, Dictate, and
  Open FoldWise in the existing order and accessible wording.
- Recording uses the `208`-point capsule, live amplitude ribbons, and timer.
- Working uses the `208`-point capsule, fixed `0.18` ribbons, and spinner or
  existing status text.
- Done uses success border/checkmark plus “inserted”.
- Error uses error border/warning icon plus the existing recovery/failure text.
- Mode cycle uses the `176`-point confirmation geometry and existing
  reducer-owned choreography.
- No glow, standing notch, warm surface wash, shadow, silhouette change, or new
  semantic state is allowed.

Production owners:

- `BadgeReducer`, `BadgeModeCycleReducer`, `BadgeFramePolicy`, and
  `ASRBadgePresentation`: all state, timing, width, queue, interruption, and
  accessibility decisions.
- `BadgeController`: panel, timers, anchoring, event routing, and rendering
  environment values.
- `BadgeView`: visual composition only.

## Production ownership seams

| Concern | Production owner | Visual consumer | Must not move into the visual layer |
| --- | --- | --- | --- |
| Tokens and environment adaptation | `Theme` | Every production view | Product state or persistence |
| Shared surface/ingress/focus/status chrome | Design-system SwiftUI components | Feature views | Timers, retries, validation, routing |
| Main-window shell | `SettingsView` + `SettingsController` | Six destinations | Collapse policy, config permissions |
| Navigation collapse | `SidebarPresentation` | Shell | Window rendering |
| Home | `HomeProjection`, `HomeOverviewLayout` | `HomeView` | Metrics/grouping decisions |
| Dictation row | Row presentation/interaction types | `DictationRow` | History persistence and semantic commands |
| History | `HistoryProjection`, `HistoryReprocessor` | `HistoryPane` | Store mutation rules |
| Modes | Mode policies/projections + `SettingsWorkflow` | `SettingsView`, `ModeEditorSheet` | Candidate transaction and Config writes |
| Models | `ModelsWorkspaceProjection`, lifecycle/workflow | `ModelsCombinedPane` | Model operation or fallback decisions |
| Stats | `StatsProjection`, focus/style policies | `StatsPane` | Aggregation and streak rules |
| Settings | `SettingsWorkflow`, `SettingsModel` | `SettingsView` | System effects and Config writes |
| Badge | Badge reducers/policies + controller | `BadgeView` | Widths, dwell, queue, anchor, panel behavior |

The migration may add value types for visual decisions that need deterministic
tests, such as a border-width or motion policy. It must not create “view model”
duplicates of existing projections or reducers.

## Migration strategy

### Rules

- Work one independently reviewable slice at a time.
- Start each behavior-affecting change test-first. Pure visual composition may
  begin with a hosted invariant that fails against the current chrome.
- Keep each slice buildable and usable. Do not land an all-token horizontal
  layer with no production consumer.
- Add canonical tokens and migrate Continuous Frame in the foundation slice.
  Existing token names may remain as temporary compatibility aliases for
  unmigrated destinations, but the final gate removes them.
- Reuse existing projections, workflows, actions, bindings, accessibility text,
  and controllers. A visual slice does not rewrite product logic.
- Do not copy a complete prototype view into production. Port the approved
  contract into the existing production owner.
- Keep prototype code marked throwaway and isolated. Do not “clean it up” into a
  second design system.
- Each slice runs its focused tests plus `swift test`; the final gate runs the
  coverage policy and full manual matrix.

### Dependency graph

```text
1. Ember Edge + Continuous Frame
├── 2. Home + shared Dictation row
│   └── 3. History
├── 4. Modes + Mode editor
├── 5. Models
├── 6. Stats
├── 7. Settings + global feedback
└── 8. Badge

2–8 ──> 9. Integrated accessibility and parity gate
```

After slice 1, slices 2, 4, 5, 6, 7, and 8 may proceed in parallel. Slice 3
follows slice 2 because it consumes the migrated shared Dictation row. Slice 9
is the only convergence slice.

## Independently implementable slices

### Slice 1 — Install Ember Edge and Continuous Frame

Scope:

- Replace the current production palette with the canonical tokens.
- Add the shared Surface, Ingress, Section label, Focus, Status notice, and
  button/control chrome used by the shell.
- Migrate titlebar, expanded navigation, rail, footer, destination canvas,
  Configuration recovery, and global status placement.
- Preserve old token aliases only where needed by unmigrated destinations.

Acceptance:

- Light/Dark values and contrast adaptations resolve exactly as specified.
- One titlebar spans the frame; navigation and destination divide below it.
- `880 × 640`, `190`, `52`, `940`, `⌘\`, explicit narrow expansion, recovery
  permissions, and status lifetimes are unchanged.
- Theme, sidebar, titlebar, and recovery hosted tests pass.
- All six existing destinations remain reachable and usable.

### Slice 2 — Migrate Home and the shared Dictation row

Scope:

- Apply Instrument Panel to Home.
- Migrate the production `DictationRow` once, including hover, keyboard focus,
  copy confirmation, flag state, Mode attribution, and action reveal.
- Add direct hosted coverage for the `4`-wide/`2 × 2` metric breakpoint.

Acceptance:

- Four metrics and readiness band retain their exact meaning and action.
- Newest-ten ordering, day grouping, row commands, `44`-point geometry, and
  accessible descriptions are unchanged.
- Home wide/compact and row hover/focus/copy/flag states match the gallery.
- Existing Home, row presentation/interaction, and hosted tests pass.

### Slice 3 — Migrate History

Scope:

- Apply Instrument Panel to saving, retention, filters, grouped ledgers, empty
  states, and destructive actions.
- Consume the shared migrated Dictation row without forking it.

Acceptance:

- Saving and retention remain independent and transactional.
- Search, Flagged-only, grouping, all More-menu capability rules, confirmations,
  and re-run Polish behavior are unchanged.
- Empty, no-result, saving-off, hover/focus, copied, and overflow states match
  the gallery.
- Existing History, store, performance, reprocessor, and shared-row tests pass.

### Slice 4 — Migrate Modes and the Mode editor

Scope:

- Apply Command Ledger to Voice to Text, the ordered Mode library, stable
  inspector, actions, warnings, and editor sheet.

Acceptance:

- Selection timing, cycle order, stable identity, duplicate naming, History
  attribution, raw fallback, validation, persistence Retry, and keyboard
  behavior are unchanged.
- The editor remains fixed at `820 × 570`.
- Empty, unavailable-model, deletion, validation, Retry, icon, Light/Dark, and
  Increase Contrast states match the gallery.
- Existing Mode projection/policy, Config, workflow, and hosted editor tests
  pass.

### Slice 5 — Migrate Models

Scope:

- Apply Trace Ledger to both model families, aligned rows, inspector, targeted
  lifecycle states, progress, recovery, and destructive confirmation.

Acceptance:

- Inspection and selection remain separate.
- The exact `617`-point split remains `340 + 1 + 276`.
- Saved-unavailable intent and Effective ASR model remain simultaneously
  visible.
- Focus restoration, announcements, operation serialization, cancellation, and
  failure semantics are unchanged.
- Existing Models projection/hosted/lifecycle/rating tests pass.

### Slice 6 — Migrate Stats

Scope:

- Apply Dictation Pulse to the metric row, Monthly activity calendar, day cells,
  detail, notice, and legend.
- Add the five-bar waveform cue without changing intensity thresholds.

Acceptance:

- Metric order/semantics, seven columns, notice precedence, localization,
  future-day exclusion, arrow focus, and Open History remain unchanged.
- Filled waveform-bar count equals intensity `1 ... 5`; neutral remains an em
  dash.
- Compact `880 × 640`, Light/Dark, focus, Increase Contrast, and Reduce Motion
  states match the gallery.
- Existing Stats projection, style, focus, hosted, aggregation, streak, and
  store tests pass.

### Slice 7 — Migrate Settings and global feedback

Scope:

- Apply Signal Ledger to shortcut, input, sound, appearance, and update groups.
- Complete the shell-owned Configuration recovery and global feedback
  presentations against real `SettingsModel` state.
- Add direct hosted coverage for the `650`-point Appearance layout boundary and
  the recovery permission matrix across destinations.

Acceptance:

- Immediate persistence, rollback, capture gating, input-device lifecycle,
  update actions, and status lifetimes are unchanged.
- Appearance choices are horizontal at `>= 650` content width and vertical
  below.
- Every success, warning, and error remains attached to its owning subsystem
  unless it is truly global.
- Existing Settings workflow/model/controller/hotkey/input tests pass.

### Slice 8 — Migrate the Badge to Ember Trace

Scope:

- Replace neutral, active, Done, and Error Badge chrome with canonical tokens.
- Apply Reduce Motion to base Badge transitions and decorative timelines while
  retaining the existing Mode-cycle reduced path.

Acceptance:

- Panel behavior, silhouette, `38`-point height, all exact widths, anchor,
  controls, content, transitions, queueing, and dwell timing are unchanged.
- Recording remains mic reactive at `30 Hz` across `0.10 ... 0.45`; Working
  remains fixed at `0.18`.
- Idle has no glow or motion. Done is green plus checkmark/text. Error is red
  plus warning/text.
- Base crossfade, hover scale, spinner, and ribbons freeze or update immediately
  under Reduce Motion as specified.
- Existing Badge reducer, Mode-cycle, wiring, halo, silhouette, frame, and
  ribbon tests pass, with new deterministic Reduce Motion coverage.

### Slice 9 — Integrated accessibility and visual parity gate

Scope:

- Remove temporary legacy token aliases and unused old chrome.
- Close cross-surface hosted gaps.
- Run the full automated and manual matrices.
- Record review evidence against the approved gallery.

Acceptance:

- No production view uses old hex values, violet Badge tokens, unapproved
  shadows/glow, or a private substitute palette.
- No review-only treatment name or mock state appears in the product.
- All automated gates pass.
- Every manual matrix row has recorded pass/fail evidence; failures are fixed or
  explicitly block release.
- A live end-to-end run confirms no product logic, state transition,
  persistence, responsive, or accessibility regression.

## Automated verification matrix

| Area | Existing seam to retain | Required addition |
| --- | --- | --- |
| Tokens | `ThemeAppearanceTests` | Resolve every canonical Light/Dark semantic token; assert contrast-mode border/motion policy |
| Appearance propagation | `AppearanceReactorTests` | Hosted main-window + Badge sampling after live System/Light/Dark changes |
| Shell | `SidebarPresentationTests`, `TitlebarAlignmentTests` | Hosted Continuous Frame recovery/status placement and six-destination permission matrix |
| Home | `HomeProjectionTests`, `HomeOverviewLayoutTests`, `HomeViewHostedTests` | Hosted four-across vs `2 × 2` metric composition |
| Dictation row | Presentation, interaction, and hosted row tests | Stable ingress/focus/non-color cue checks without screenshot baselines |
| History | Projection, reprocessor, store, and performance tests | Hosted first-run/no-result/saving-off structure where no seam exists |
| Modes | Mode policy/projection, Config, workflow, editor hosted tests | Hosted Command Ledger selection cues and fixed editor geometry |
| Models | Projection, hosted workspace/rating, lifecycle tests | Trace ingress continuity and Contrast+ boundary checks |
| Stats | Projection, focus, activity-style, hosted, aggregation/store tests | Waveform fill-count mapping and Reduced Motion/Contrast+ hosted checks |
| Settings | Workflow/model/controller and shortcut/input tests | Appearance `650` breakpoint and subsystem-attached feedback hosted checks |
| Badge | Reducer, Mode-cycle, wiring, halo, silhouette, ribbon tests | Base Reduce Motion policy and semantic palette/cue hosted checks |
| Repository | `swift test`, coverage policy | SwiftFormat, strict SwiftLint, `git diff --check`, `./scripts/coverage.sh origin/main` |

Testing rules:

- Keep product decisions in pure projections, reducers, and value policies.
- Add hosted tests only for stable geometry, focus, accessibility structure, and
  bounded pixel/color invariants that pure values cannot prove.
- Do not add a snapshot suite for every state or color. The approved gallery and
  manual matrix own holistic visual judgment.
- New production files are covered by default. Extract meaningful decisions
  from declarative views rather than adding coverage exemptions casually.

## Manual verification matrix

Record commit, app version, macOS version, hardware, tester, date, and result.
Use a built `.app` for panel, permission, focus, and appearance-boundary checks.

| Pass | Appearance / width | Interaction / environment | Surfaces and required observations |
| --- | --- | --- | --- |
| 1 | Dark, wide `1180 × 720` | Pointer, Standard, Motion | Six destinations baseline; opaque layers, fine borders, orange restraint, no clipped content |
| 2 | Light, wide `1180 × 720` | Pointer, Standard, Motion | Six destinations baseline; warm off-white identity, equivalent hierarchy and information |
| 3 | Dark, minimum `880 × 640` | Keyboard only, Standard, Motion | Rail, every destination scroll boundary, Home `2 × 2`, Models `617` split, no unreachable action |
| 4 | Light, minimum `880 × 640` | Keyboard only, Increase Contrast, Reduce Motion | Essential `2`-point boundaries, separated focus, immediate ordinary state changes |
| 5 | Both | Differentiate Without Color | Selected, inspected, raw/polished, flagged, unavailable, success, warning, error all retain non-color cues |
| 6 | Both | VoiceOver | Destination order, selected values, row descriptions/actions, Models announcements, Stats day detail, no hidden duplicates |
| 7 | Both | Configuration recovery | Home/Stats readable; Voice to Text usable; Modes/Models/History/Settings disabled; Reset/Quit reachable |
| 8 | System → Light → Dark | Live appearance change | Main window and Badge update together without relaunch or mixed old/new tokens |
| 9 | Both | English, Polish, Arabic/RTL | Dates, numbers, pluralization, long Mode/model names, row truncation, calendar ordering and focus |
| 10 | Both | Badge full state pass | Idle, Hover, Recording quiet/normal, all Working labels, Done, clipboard/pipeline/Mode errors, Mode cycle |
| 11 | Both | Real microphone and other app frontmost | Badge stays non-activating; ribbons react only while Recording; anchor does not drift during resize |
| 12 | Both | Destructive and failure states | Mode/model/history confirmations name consequences; failed writes restore committed UI; retries remain reachable |

Also run the existing manual smoke checklist sections:

- 7 — Badge and menu behavior
- 10 — Home and History Dictation rows
- 11 — Cycle Modes shortcut and permission recovery
- 12 — User-managed Mode lifecycle, accessibility, and concurrent Dictation
- 13 — Transaction failure and Configuration recovery

Run sections 2, 4, 5, and 9 as a regression sample because the visual migration
touches the UI that exposes Pipeline, both ASR engines, Polish fallback, and
input-device state even though their logic is unchanged.

## Definition of done

The production migration is ready for final human review when:

- Every slice acceptance list is satisfied.
- The canonical tokens have one owner and every production surface consumes
  them.
- All approved compositions are present without prototype-only controls or
  narration.
- Existing behavior contracts and ownership seams remain intact.
- Automated tests, formatting, lint, diff checks, and coverage pass.
- The manual matrix and required macOS smoke sections have recorded evidence.
- The approved complete gallery can be placed beside production Light/Dark,
  wide/compact, focus, error, Contrast+, Reduced Motion, and Badge captures
  without exposing a missing component, exceptional token, or reopened product
  decision.
