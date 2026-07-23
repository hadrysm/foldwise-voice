# Complete surface and state matrix

Inventory for [Inventory the complete surface and state matrix](https://github.com/hadrysm/foldwise-voice/issues/249), based on commit `8f02369` (`feat: redesign Stats with a monthly activity calendar (#247)`).

This is a preservation inventory for the visual-system Wayfinder map. It records what the redesign must continue to express; it does not prescribe the new styling. “Representative gallery state” means a curated prototype state worth rendering, not a requirement to encode every combinatorial variant.

## Cross-surface contracts

- The main window has six destinations in this order: Home, Modes, Models, History, Stats, Settings. Models contains both Speech recognition and Polish; Settings contains shortcuts, input, sound, appearance, and updates.
- The application remains a menu-bar accessory until the main window opens. Opening the window promotes it to a regular app; closing it returns to accessory mode.
- Preferences commit immediately and transactionally. A failed validation or write restores the last committed presentation. Mode drafts are the exception: they commit only through the editor’s explicit Save action.
- Configuration recovery is read-only. Voice to Text remains available, the original invalid file remains untouched, and the user can Reset Configuration or Quit. Modes, Models, History, and Settings are disabled; Home and Stats remain readable.
- The Appearance preference is global: System follows live macOS appearance, while Light and Dark override the main window and Badge together.
- Main-window content uses the same information and actions in both appearances. The redesign may change layout, spacing, typography, component shape, and visual hierarchy, but not what a control means or when it is available.
- Keyboard focus, accessible names/values/hints, non-color state cues, Reduce Motion, and localized number/date semantics are product behavior, not decoration.
- A Dictation row is one shared component across Home and History. History adds capabilities; it does not define a different row identity.
- Saved ASR model selection, Effective ASR model, and ASR model availability are separate facts. The UI must not visually collapse them into one state.
- Voice to Text is a permanent system Dictation selection outside the editable Mode library.
- History is text-only and on-device. No audio is saved.
- The Badge remains a non-activating, always-on-top, draggable pill. It never becomes key or main and never steals focus from the dictated-into app.

## Resize and layout boundaries

| Boundary | Current contract | Existing seam |
| --- | --- | --- |
| Initial main-window content size | `980 × 720` points | `SettingsController.makeMainWindow` and `TitlebarAlignmentTests` |
| Main-window minimum | `880 × 640` points, enforced by both SwiftUI and `NSWindow` | `SettingsView.frame`, `SettingsController.makeMainWindow` |
| Window restoration | AppKit frame autosave name `FoldWiseMainWindow` | `SettingsController.build` |
| Full-size titlebar | Custom bar occupies the actual top safe-area inset; falls back to 32 points in fullscreen | `SettingsView.titlebar`, `TitlebarAlignmentTests` |
| Sidebar expanded / rail | 190 / 52 points | Theme tokens and `SidebarPresentationTests` |
| Sidebar automatic collapse | Below 940-point window width; resize does not persist this transient collapse | `SidebarPresentation` |
| Explicit sidebar expansion while narrow | Beats automatic collapse until the window is widened again; explicit toggles persist | `SidebarPresentationTests` |
| Home metric composition | Four columns at `windowWidth >= 940`; two-by-two below 940 | `HomeOverviewLayoutTests` |
| Settings appearance tiles | Horizontal when computed content width is at least 650; vertical below it | `SettingsView.appearanceChoices`; no hosted boundary test currently |
| Models split | Ledger minimum 340, inspector minimum 270, initial divider near 55/45 | `ModelsSplitGeometry`, projection and hosted split tests |
| Stats metric strip | Always one four-tile row at required window sizes | `StatsPaneHostedTests` |
| Stats calendar | Always seven weekday columns at required window sizes | `StatsPaneHostedTests` |
| Mode editor | Fixed `820 × 570` sheet; title and footer remain visible when errors appear | `ModeEditorHostedTests` |
| Mode icon palette | Fixed `360 × 280` popover with a three-column grid | `ModeEditorSheet` |
| Badge height | 38 points in every state | `Theme.badgeHeight` |
| Badge widths | Idle 88, hover 132, Mode-cycle confirmation 176, recording/working/done/error 208 | `BadgeReducerTests`, `BadgeModeCyclePresentationTests` |
| Badge screen clamping | Four-point margin inside the current screen’s visible frame, preserving the user anchor | `BadgeFramePolicy`, `BadgeModeCyclePresentationTests` |

## Shared main-window shell

### Composition

- Transparent full-size titlebar with traffic lights, sidebar toggle, “FoldWise Voice” label, and draggable window background.
- Expanded sidebar: labeled navigation rows and version/update footer.
- Collapsed rail: icons only, with a window-level hover tooltip so it is not clipped by content.
- One content destination at a time.
- Optional configuration-recovery banner above the destination.
- Optional global status strip below the destination. Success and error status are semantically distinct.
- Sidebar toggle is available through the titlebar button and `⌘\`.

### States and interactions

| State | Required presentation / behavior |
| --- | --- |
| Expanded navigation | 190-point labeled list; active row has icon, text, background, and weight cues |
| Rail navigation | 52-point icon rail; active tile remains distinguishable; hovering reveals the destination name |
| Narrow automatic rail | Does not overwrite the saved sidebar preference |
| Narrow explicit expansion | User choice wins until the window crosses back into the wide range |
| Reduce Motion | Sidebar toggles without animation; active rail-tooltip/sidebar transition subtrees are reset if Reduce Motion becomes enabled mid-transition |
| Update idle/failed/unavailable | Footer shows version only |
| Update checking | Footer shows “checking…” |
| Update current | Footer shows “up to date” |
| Update available | Footer exposes an accent “Get v…” action and version summary |
| Configuration recovery | Warning banner with cause, Voice to Text assurance, Reset Configuration, and Quit; configuration-owning destinations disabled |
| Save/status success | Bottom status strip shows success and clears after two seconds |
| Validation/persistence error | Bottom status strip remains visible until superseded |

### Existing verification

- `SidebarPresentationTests` pins automatic collapse, persistence, and narrow explicit override behavior.
- `TitlebarAlignmentTests` pins the titlebar/traffic-light geometry.
- `AppearanceReactorTests` pins live global appearance propagation.
- `ThemeAppearanceTests` samples approved light/dark window and Badge colors.
- There is no hosted shell test covering all six destination switches or the configuration-recovery disabled matrix.

## Home

### Composition and data

- “Ready when you are.” title.
- Live Push to Talk keycap instruction.
- Four lifetime metrics: total words, speaking speed, current streak, time saved.
- System status card: Effective ASR model, selected Polish model or “no polish model,” Accessibility permission, app version, and Stats link.
- Empty explanation or the ten newest Dictation rows grouped by Today, Yesterday, and localized absolute day.
- “All history” navigation action when recent rows exist.

### State matrix

| Axis | States to preserve |
| --- | --- |
| History | Empty; one or more recent rows; more than ten saved rows (show newest ten only) |
| Metrics | Concrete value; unavailable speaking speed/streak/time saved rendered as an em dash; singular/plural streak unit |
| Layout | Four-wide metric strip; compact two-by-two strip |
| System readiness | “All systems go”; “Needs attention” with Open Accessibility action |
| Polish summary | Selected Polish model; no Polish model |
| Relative dates | Today; Yesterday; localized absolute date; refresh at calendar-day boundary |
| Dictation row attribution | Current Mode identity; deleted Mode fallback identity; Voice to Text/legacy name-only identity |
| Dictation row interaction | Resting identity; hover/focus actions; flagged/unflagged; copied confirmation |

### Behavior contracts

- Metrics derive from saved History. Total words use raw spoken words, not expanded Polish output.
- Recent rows always sort newest first and retain their exact source entry for actions.
- Home rows expose Copy displayed text and Flag only. They do not expose History’s overflow actions.
- Stats and All history links change the selected destination without opening another window.
- The hotkey hint always reflects the committed Push to Talk binding.

### Representative gallery states

1. Populated, wide, all systems ready.
2. Populated, compact, with unavailable derived metrics.
3. Empty first-run Home.
4. Accessibility attention state.
5. Recent rows showing current, deleted, flagged, and raw/polished identities.

### Existing verification

- `HomeOverviewLayoutTests`, `HomeProjectionTests`, and `HomeViewHostedTests`.
- `UsageStatsAggregatorTests` and `StreakRulesTests` pin metric semantics.
- `DictationRowHostedTests`, `DictationRowInteractionTests`, and `DictationRowPresentationTests` pin shared row geometry, actions, focus, and attribution.
- The wide/compact Home composition is selected by a pure tested policy, but its resulting hosted geometry is not currently snapshot- or pixel-tested.

## Modes

### Composition and data

- Introductory explanation and Add Mode action.
- System section containing permanent Voice to Text.
- Editable ordered Mode library.
- Selected Mode detail with icon, transformation type, AI model, Polish instructions, preserved vocabulary, edit/duplicate/reorder/delete actions.
- Empty-library onboarding card.
- Empty-detail prompt when no editable Mode is selected.

### State matrix

| Axis | States to preserve |
| --- | --- |
| Library | Empty; one Mode; multiple ordered Modes |
| Dictation selection | Voice to Text selected; editable Mode selected |
| Detail | Selected editable Mode; no editable selection |
| Model availability | Assigned model installed; assigned model unavailable with raw-transcript fallback and Open Models action |
| Reordering | First item cannot move up; last item cannot move down; middle items can move both ways |
| Deletion | Confirmation pending; successful deletion; persistence failure retains confirmation for retry |
| Configuration | Normal editable; recovery read-only |

### Behavior contracts

- Selecting Voice to Text or a Mode changes the next Dictation session only.
- Mode ordering is both display order and Mode-cycle order.
- Add creates a new selected Mode; duplicate inserts immediately after the source and selects the copy.
- Duplicate names follow `Copy`, `Copy 2`, and so on after normalization.
- Editing preserves stable Mode identity. Rename, reorder, and edit do not rewrite saved History attribution.
- Deleting the selected Mode changes selection to Voice to Text. History remains and the referenced Ollama model is not uninstalled.
- Mode mutations are candidate transactions: persist first, then publish live state.

### Mode editor sheet

| Axis | States to preserve |
| --- | --- |
| Purpose | Add Mode; Duplicate Mode; Edit Mode |
| Installed-model inventory | Checking; no installed models; assigned model available; draft references unavailable model |
| Validation | Empty/duplicate name; no installed model selected; installed inventory still loading; unavailable model; empty prompt |
| Save | Valid Save; persistence error changes action to Retry while preserving the complete draft |
| Transformation | Keep wording (`inPlace`); Reshape (`expanding`) with explanatory copy |
| Icon | Stored/current symbol; palette open; unknown stored symbol falls back visually without discarding stored identity |
| Dismissal | Close button, Cancel, and Escape discard; interactive swipe/window dismissal is disabled; Return activates Save |

The sheet edits name, icon, installed AI model, transformation, system prompt, and ordered vocabulary. Vocabulary is one term per line; Save removes empty and repeated terms while preserving order.

### Representative gallery states

1. Multiple Modes with a selected middle item.
2. Empty library.
3. Voice to Text selected with editable Modes still present.
4. Selected Mode whose model is unavailable.
5. Add editor, populated Edit editor, validation errors, and persistence Retry.
6. Delete confirmation and icon palette.

### Existing verification

- `ModeSelectionProjectionTests`, `ModeEditorPolicyTests`, and `ModeEditorHostedTests`.
- `ConfigBehaviorTests`, `ConfigSchema1Tests`, and `ConfigChangePropagationTests` pin transaction and recovery behavior.

## Models

### Composition

- Header and two-pane native split.
- Left comparison ledger, ordered Speech recognition then Polish.
- Per-family heading, semantic label, column headers, optional recovery notice, rows/placeholders.
- Right inspector for the currently inspected row, with explanation, status/error/progress, primary action, optional destructive menu, and install-by-name form where applicable.
- One destructive confirmation alert shared by ASR deletion and Ollama uninstall.

### Speech recognition state matrix

| State | Required distinction / action |
| --- | --- |
| Snapshot unavailable | Family-local “Checking speech models…” placeholder |
| Selected and available | “Selected”; no select action |
| Available but not selected | “Ready”; Select action |
| Unavailable and not selected | “Download”; Download action |
| Saved selection unavailable | “Saved · unavailable”; Download again; Effective model named separately |
| Effective fallback | “Effective fallback”; saved intent remains unchanged |
| Unknown saved identifier | Recovery notice only; no synthetic model row |
| Downloading | Determinate or indeterminate progress; cancellation allowed |
| Default bootstrap | Preparing progress; not cancelable |
| Switching | Indeterminate progress; cancellation allowed |
| Restoring | Indeterminate progress; not cancelable |
| Deleting | Indeterminate progress; not cancelable |
| Download/load/select/bootstrap failure | Error retained with the affected row; Retry only when lifecycle says bootstrap retry is valid |
| Selection canceled | Returns to prior actionable state; not presented as an error |
| Deletion failure | Error targets the destructive retry seam if data remains deletable |
| Selected optional-model deletion | Confirmation states that Parakeet becomes selected before data removal |

Only one ASR management operation runs at a time. Competing controls explain why they are disabled. Optional download never silently selects. The default Parakeet model cannot be deleted.

### Polish state matrix

| State | Required distinction / action |
| --- | --- |
| Inventory checking | “Checking Ollama…” placeholder and neutral inspector |
| Ollama unavailable | Directed unavailable placeholder with Retry; Speech recognition remains usable |
| Curated model available | Fit/size/rating row with Install |
| Curated model installed | Installed state with uninstall action |
| External Ollama model installed | External-model row; unrated values remain explicit |
| Install another model | Final utility row with model:tag text input and Install |
| Installing | Determinate/indeterminate progress on the target; competing mutations disabled |
| Uninstalling | Indeterminate, non-cancelable progress |
| Install/uninstall failure | Error remains attached to the target row and inspector |
| Uninstall model used by Modes | Confirmation lists affected Modes and raw-text fallback |
| All recommendations installed | Utility inspector explains that arbitrary additional models remain installable |

### Interaction and focus contracts

- Clicking or arrowing through the ledger changes inspection without changing ASR selection.
- Up/Down navigation follows one ordered ledger stop across both families.
- Operation start, cancellation, completion, failure, and inventory replacement deliberately restore focus to the relevant cancel/action/row.
- Progress percentage changes update accessibility value without repeatedly announcing operation start.
- Start/completion/failure boundaries produce accessibility announcements.
- Removing the inspected Polish row selects the next surviving row, then previous, then placeholder.

### Representative gallery states

1. Baseline with selected Speech recognition model and mixed installed/available Polish models.
2. Saved-unavailable ASR selection with Effective fallback.
3. ASR download/switch/restore/delete progress.
4. Targeted ASR failure and recovery.
5. Ollama checking and unavailable placeholders.
6. Polish install/uninstall progress and failure.
7. External model plus install-by-name utility.
8. Destructive confirmations, including affected Modes.

### Existing verification

- `ModelsWorkspaceProjectionTests` is the principal state/focus/announcement contract.
- `ModelsWorkspaceHostedTests` pins compact split minimums, row identity, inspector action placement, and highlighted-row contrast.
- `ModelsRatingMeterHostedTests` pins rating presentation.
- Lifecycle behavior is independently pinned by `ASRModelLifecycleTests`.

## History

### Composition

- Save dictation history switch.
- Retention picker only while saving is enabled.
- Empty state, or search + Flagged-only controls, grouped Dictation rows, and Clear all history.
- Separate confirmation alerts for Clear All and for optionally deleting existing entries when saving is turned off.

### State matrix

| Axis | States to preserve |
| --- | --- |
| Saving | On; off with no retained entries; off with retained entries and delete/keep confirmation |
| Retention | 7 days; 30 days; 90 days; Forever |
| Collection | No saved entries; populated; search has no matches; Flagged-only has no matches |
| Filtering | Blank search; live case-insensitive search across displayed and raw text; Flagged-only; combined filters |
| Grouping | Today; Yesterday; localized absolute date; day-boundary refresh |
| Row text | Raw; polished; whitespace-collapsed one-line preview |
| Mode attribution | Current Mode; deleted Mode with recorded name; Voice to Text/legacy name |
| Row actions | Copy; Copy raw only when polished; Flag/unflag; Re-run Polish submenu only when eligible Modes exist; Delete |
| Destruction | Delete one without confirmation; Clear all with confirmation; turning saving off offers Delete or Keep |

### Behavior contracts

- Retention and saving are independent. Forever means keep everything, not stop saving.
- Changing retention sweeps immediately and reloads the visible collection.
- Clear All also resets the persisted streak. Deleting a single row does not retroactively recompute the lifetime streak.
- Re-run Polish always starts from stored raw text, updates the same entry, and safely falls back to raw if Polish fails or goes Off-task.
- Search and Flagged-only never mutate the store.
- A live append prepends the new entry without polling.

### Representative gallery states

1. Populated grouped History with mixed raw/polished, flagged, and deleted-Mode rows.
2. Empty first-run state.
3. Search and Flagged-only no-result states.
4. Saving off with retained data.
5. Clear-All and turn-off/delete confirmations.
6. Row hover/focus, copy confirmation, and full overflow menu.

### Existing verification

- `HistoryProjectionTests`, `HistoryPanePerfTests`, `HistoryReprocessorTests`, and store round-trip tests.
- Shared row tests cover geometry, conditional action composition, keyboard traversal, copy announcement, and attribution.

## Stats

### Composition and data

- Introductory explanation.
- Optional notice.
- Four lifetime metric tiles in fixed order: Words dictated, Speaking speed, Current streak, Time saved.
- Current Monthly activity calendar with localized month/weekday/day labels, month word/day summaries, day cells, hover/focus detail, and six-level intensity legend.

### State matrix

| Axis | States to preserve |
| --- | --- |
| Notice | No notice; no History; saving off with Open History action |
| Notice precedence | Saving-off notice replaces no-History notice when both are true |
| Data | Empty; retained activity; retained activity while saving is off; quiet current month with lifetime activity outside the month |
| Metrics | Concrete values; unavailable speaking speed/streak/time saved rendered as em dashes |
| Day | Elapsed active; elapsed empty; today active/empty; future |
| Intensity | Neutral 0; low 1–249; moderate 250–599; medium 600–999; high 1000–1599; very high 1600+ spoken words |
| Detail | Neutral instruction; hovered past/today detail; keyboard-focused detail |
| Timing | Complete timing and estimated saving; partial timing; unavailable timing; no positive saving |
| Localization | Locale-specific first weekday, dates, digits, plural forms, grouping, compact numbers, durations; explicit English, Polish, and Arabic seams |
| Motion | 140 ms intensity crossfade; immediate update under Reduce Motion |

### Behavior contracts

- Lifetime metrics use all retained saved History, while the calendar uses only the current local calendar month through today.
- Future entries and future days do not contribute and future cells are excluded from the accessibility tree.
- A zero-word saved Dictation session counts as an active day but remains neutral intensity.
- Hover or keyboard focus changes detail; it performs no activation action.
- Today is the initial and sole tab stop. Arrow keys move among elapsed/today dates and stop at the boundaries; Return and Space remain inert.
- Calendar focus repairs after month/day/time-zone changes.
- Hidden duplicate visual headers/details are excluded from accessibility.
- Open History changes destination in place.

### Representative gallery states

1. Active month with several intensity levels and complete timing.
2. Empty History.
3. Saving off with retained activity.
4. Quiet current month with lifetime totals.
5. Hovered day and keyboard-focused day.
6. A non-English locale and right-to-left locale check.

### Existing verification

- `StatsProjectionTests`, `StatsPaneHostedTests`, `StatsActivityStyleTests`, `CalendarFocusNavigatorTests`, aggregation/streak/store tests.
- Hosted tests pin the four-tile row, seven-column calendar, accessible tree, focus movement, and every data-state layout at required widths.

## Settings

### Keyboard shortcuts

| Axis | States to preserve |
| --- | --- |
| Push to Talk | Assigned; capturing; reset to right Option |
| Toggle Recording | Unassigned; assigned; capturing; remove assignment |
| Cycle Modes | Unassigned; assigned; capturing; remove assignment |
| Capture | Clicking the active capture cancels; captured key is swallowed and does not run a command |
| Validation | Unsupported key; shortcut collision including aliases/case/whitespace; persistence/rebind failure restores committed values |
| Listener health | Global; focused-app-only warning with Open System Settings action |

The capture gate suspends global shortcut handling while any shortcut field is recording.

### Input

| State | Required presentation / behavior |
| --- | --- |
| System Default | Always listed; names current macOS default when known |
| Connected preferred device | Selected and “in use” |
| Connected non-preferred device | Available but not selected |
| Preferred device disconnected | Retained disabled row, “Not connected — Preferred” |
| Fallback | Names missing preferred and current Effective input device |
| Restored | Announces restored device |
| Deferred during Dictation | Names device used by current Dictation session and device for next session |
| Unavailable | Error message; no usable input |

### Sound, appearance, and updates

| Area | States to preserve |
| --- | --- |
| Pause other audio | On/off immediate preference |
| Appearance | System, Light, Dark; selected/not-selected cue plus descriptive text |
| Appearance layout | Horizontal cards at content width ≥650; vertical below |
| Updates | Idle, checking, current, available, failed, unavailable dev build |
| Update action | Check again, download available release, or no action for unavailable dev build |

### Representative gallery states

1. Baseline with assigned/unassigned shortcuts and connected input devices.
2. Active shortcut capture and collision error.
3. Focused-app-only shortcut permission warning.
4. Missing preferred input with fallback, restored, deferred, and unavailable messages.
5. All three appearance preferences in horizontal and vertical compositions.
6. Checking, available, failed, and unavailable update states.
7. Global configuration-recovery banner with this pane disabled.

### Existing verification

- `SettingsWorkflowTests`, `SettingsControllerWiringTests`, `SettingsModelTests`, `ShortcutPolicyTests`, and hotkey binding tests.
- `SettingsViewPresentationTests` pins appearance option content, but not the hosted responsive layout.
- Audio input selection behavior is tested below the view layer in `AudioRecorderDevicePolicyTests`.

## Shared Dictation row

### Fixed identity

- 44-point row height.
- 24-hour `HH:mm` timestamp.
- Single-line, whitespace-collapsed, tail-truncated displayed text.
- Compact Mode name up to 16 lowercased characters plus Mode icon.
- Deleted Mode annotation when stable Mode ID no longer resolves.
- Raw/Polished and Flagged/Not flagged are included in the accessible description even when not all are visually prominent.

### Interaction states

| State | Required presentation / behavior |
| --- | --- |
| Resting | Trailing region shows Mode identity and optional flag |
| Pointer hover | Trailing region swaps to actions |
| Keyboard focus | Actions remain revealed and a visible focus outline appears |
| Home action order | Row → Copy → Flag |
| History action order | Row → Copy → Flag → More |
| Copy confirmed | Copy icon becomes checkmark for 1.4 seconds and announces “Copied” |
| Flagged | Non-color flag shape remains visible; action becomes Remove flag |
| More menu | Copy, conditional Copy raw, Flag/Remove flag, conditional Re-run Polish submenu, separator, destructive Delete |

The row itself owns hover, focus, and transient copy feedback. The containing surface owns semantic commands and persistence.

## Badge

### Panel and geometry contracts

- Borderless non-activating `NSPanel`, status-bar level, transparent background, no shadow, mouse-enabled.
- Joins all Spaces and remains available beside full-screen apps.
- Bottom-center default position with 96-point bottom margin.
- Native dragging persists the user anchor. Programmatic resizing must not drift that anchor.
- Capsule silhouette and 38-point height stay fixed; state changes resize around the anchor.

### Primary state matrix

| State | Width / content | Entry and exit behavior |
| --- | --- | --- |
| Idle | 88; static dot/bar glyph | Launch/ready state; hover enters Hover |
| Hover | 132; Change selection, Dictate, Open FoldWise round actions | Pointer exit returns Idle; button actions do not make the panel key |
| Recording | 208; live mic-reactive ribbons and `m:ss` timer | Pipeline listening enters; hover is ignored; click requests stop but remains Recording until pipeline advances |
| Working, spinner | 208; calm ribbons plus spinner | Transcribing or Polishing; click is inert |
| Working, status | 208; calm ribbons plus status text | Default model preparation/download, ASR switch, or recognition unavailable |
| Done | 208; checkmark and “inserted” | Successful insertion; dwells 0.6 s; click dismisses early |
| Error, clipboard | 208; “copied — press ⌘V” with error border | Clipboard fallback; dwells 3 s; click dismisses early |
| Error, pipeline | 208; “something went wrong” | Pipeline error; dwells 3 s |
| Error, Mode selection | 208; “couldn’t select Mode” / “couldn’t switch Mode” | Immediate when available; deferred while pipeline-owned feedback is visible |

Working status variants are:

- `downloading N%`
- `preparing…`
- `switching speech model…`
- `speech model unavailable`
- `nil`, which selects the spinner

### Mode-cycle confirmation overlay

| Axis | States to preserve |
| --- | --- |
| Phases | Prepared, swapping, settled |
| Geometry | 176-point confirmation width; 300 ms resize |
| Standard motion | Opposed vertical reel travel; 260 ms swap |
| Reduce Motion | Opacity-only swap with no vertical travel; 180 ms |
| Dwell | Settled destination remains for 900 ms |
| Queue | Rapid committed cycles play FIFO |
| Pipeline ownership | Successes defer/coalesce while Badge is busy; pipeline feedback wins |
| Failure | Cancels current success or defers until pipeline feedback clears |
| Live Mode changes | Rename/icon updates refresh visible and queued items; deletion/direct selection cancels stale confirmation |
| Accessibility | Full, untruncated destination name and “Selected Mode” value |
| Hover | Suppressed for the whole confirmation presentation |

### Behavior contracts

- Optional ASR downloads that do not block Dictation do not change the Badge.
- ASR lifecycle presentation overrides the latest pipeline state only while Dictation is blocked, then restores the latest pipeline state.
- Ribbons follow microphone amplitude only in Recording; Working uses calm fixed amplitude.
- The idle glyph is motionless.
- Error meaning is not color-only: text and border both change.
- The three hover actions have specific accessible labels naming current Dictation selection and configured shortcut.

### Representative gallery states

1. Idle and Hover.
2. Recording at quiet and normal mic amplitudes.
3. Working spinner plus every status-text variant.
4. Done, clipboard error, pipeline error, and Mode-selection error.
5. Mode-cycle prepared/swapping/settled in standard and Reduce Motion modes.
6. Light, Dark, and high-contrast manual checks for every state.

### Existing verification

- `BadgeReducerTests` pins state transitions, widths, dwell, pipeline mapping, click rules, and ribbon ownership.
- `BadgeModeCyclePresentationTests` and `BadgeModeCycleWiringTests` pin queueing, interruption, Reduce Motion, accessibility, geometry, non-activation, and live Mode changes.
- `BadgeIdleSilhouetteTests`, `BadgeHaloTests`, and `RibbonReactionTests` pin idle geometry, no halo, and amplitude response.
- The base Badge crossfade and ribbon timelines do not currently branch on Reduce Motion; only Mode-cycle motion has a directly tested reduced path.

## Shared sheets, popovers, and destructive alerts

| Presentation | Trigger | Persistence/dismissal contract |
| --- | --- | --- |
| Mode editor sheet | Add, Edit, Duplicate Mode | Explicit Save or Retry; Cancel/Close discards; interactive dismissal disabled |
| Mode icon popover | Icon control in editor | Selection updates draft and closes popover |
| Mode deletion alert | Delete selected Mode | Failed deletion leaves alert state available for retry |
| Model destructive alert | Delete ASR download or uninstall Polish model | Action copy reflects selection and affected Modes before mutation |
| Clear History alert | Clear all history | Explicit destructive confirmation |
| Turn-saving-off alert | Disabling saving while entries exist | Delete existing or Keep; saving remains off either way |

## Verification seam index

| Concern | Pure/value seam | Hosted/integration seam |
| --- | --- | --- |
| Global appearance | `AppearanceReactor`, Theme dynamic colors | `AppearanceReactorTests`, `ThemeAppearanceTests` |
| Shell/sidebar | `SidebarPresentation` | `SidebarPresentationTests`, `TitlebarAlignmentTests` |
| Home | `HomeProjection`, `HomeOverviewLayout`, `UsageStatsAggregator` | `HomeViewHostedTests`, shared row hosted tests |
| Modes/editor | `ModeSelectionProjection`, `ModeEditorPolicy`, `ModeEditorPresentation` | `ModeEditorHostedTests`, Config behavior/schema tests |
| Models | `ModelsWorkspaceProjection`, split/focus/announcement policies | `ModelsWorkspaceHostedTests`, lifecycle tests |
| History | `HistoryProjection`, `DictationRowPresentation`, `HistoryReprocessor` | Projection/performance/store/hosted row tests |
| Stats | `StatsProjection`, `CalendarFocusNavigator`, `StatsActivityStyle`, streak/usage policies | `StatsPaneHostedTests` |
| Settings workflows | `SettingsWorkflow`, shortcut and input-device policies | Workflow/controller/hotkey/audio tests |
| Badge | `BadgeReducer`, `BadgeModeCycleReducer`, `BadgeFramePolicy` | Badge wiring, hosted rendering, halo/silhouette/ribbon tests |

## Known verification gaps the redesign must close

These are not permission to change behavior. They are places where the current implementation relies on platform behavior or code inspection more than a direct UI verification seam.

1. **Increase Contrast and Differentiate Without Color have no explicit environment branch or dedicated hosted test.** Many states already use text, symbols, shapes, labels, and outlines in addition to color, but the complete high-contrast result is unpinned.
2. **Base Badge motion is only partially Reduce-Motion-aware.** Mode-cycle travel has a tested reduced path; the primary state crossfade, round-button hover scale, spinner, and ribbons continue to use animation timelines.
3. **Responsive coverage is uneven.** Sidebar, Models split, Home breakpoint policy, and Stats composition are tested; the hosted Home 2×2 metric result and Settings appearance tile breakpoint are not.
4. **Theme sampling is narrow.** Tests sample representative light/dark colors, not every token/component/state combination.
5. **The configuration-recovery matrix is behavior-tested below the view but not hosted across all six destinations.**

The prototype gallery should therefore include explicit Increase Contrast, Reduce Motion, keyboard-only, narrow-window, and light/dark review passes. Those checks belong inside the already-charted surface prototype tickets rather than reopening product logic.
