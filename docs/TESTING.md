# Testing FoldWise Voice

This guide separates deterministic automated checks from validation that must
cross real macOS boundaries. XCTest protects decisions and a few stable rendered
invariants. The manual smoke procedure protects permissions, global input, audio
hardware, other applications, and real ASR engines without adding XCUITest.

## Test layers and local commands

The automated suite has three practical layers:

1. Pure behavior tests cover reducers, projections, parsing, catalogs,
   persistence, and workflow decisions through non-private interfaces.
2. Boundary-fake tests cover the dictation Pipeline and external-service
   fallbacks with injected recorders, ASR session handles, engine-family
   adapters, transports, pasteboards, clocks, and system-effect closures. They
   never use live internet services, microphones, permissions, models, or the
   user's general pasteboard.
3. A small platform-component layer renders stable SwiftUI/AppKit invariants in
   process. Real system integration belongs to the manual smoke procedure.

Use these commands from the repository root:

```sh
swift test
./scripts/coverage.sh
COVERAGE_BASE_REF=<target-ref> ./scripts/coverage.sh
./scripts/coverage.sh <target-ref>
python3 scripts/run_pane_performance.py
```

`swift test` is the fast full-suite command. `./scripts/coverage.sh` is the
required local gate: it runs that XCTest suite exactly once with SwiftPM code
coverage, exports LLVM's report, calculates the target-branch diff, and invokes
`scripts/check_coverage.py`. CI calls the same script without a retry wrapper.
The default target is `origin/main`, then local `main`, then `HEAD`; use either
override form above when the review target differs.

`scripts/run_pane_performance.py` is the separate fixed-Mac Release harness for
real packaged-app pane navigation. It deliberately does not run under coverage
or on floating CI timing. See
[Pane navigation performance harness](pane-performance-harness.md) for its
measurement contract, isolated fixtures, and evidence layout.

## Coverage calculation and gates

Only LLVM executable lines in `Sources/FoldWiseVoiceKit` count as production
coverage. Dependency, executable-wrapper, test, generated-runner, and test-support
lines neither help nor hurt the result. A production file is included unless its
exact path appears in the exemption register below; glob and line-level
exemptions are rejected.

LLVM omits `Log.swift` from its JSON because that file contains only static
Logger declarations and has no instrumentable lines. Its reviewed exemption is
the sole policy entry allowed to have missing coverage data. Every other
production file, including every other exempt boundary, must appear in the
report so the overall denominator cannot silently shrink.

The command enforces all four gates in one pass:

- **Per-file core:** each included file must be at least 80% covered.
- **Aggregate core:** included files together must be at least 90% covered.
- **Changed lines:** at least 85% of added executable lines in included files,
  relative to the target merge base, must be covered. Exempt and non-executable
  added lines do not enter the denominator.
- **Overall production:** all reported production files, including exemptions,
  must remain at or above the accepted `47.817098382585435%` floor.

The exact accepted values live in `coverage-policy.json`. The checker rejects a
core policy below 90%, a changed-line policy below 85%, or a per-file policy
below 80%. Policy version 2 is the reviewed one-time reset from the original
90% policy. An unversioned policy is version 1 and retains the original 90/90/90
minimums. Within a version, the checker rejects decreases from the target branch's
accepted floors. A later reset requires corresponding checker support; changing
the policy-version value alone is rejected. The overall production floor remains
ratcheted across resets. New production files are included by default. No source
or coverage artifact is uploaded to a hosted coverage service.

On success, output includes the overall, aggregate, and changed-line fractions,
the number of included and exempt files, and the ten lowest-covered included
files. A failure exits nonzero and names every failed threshold. Changed-line
failures also print actionable `path:line` locations, for example:

```text
Coverage policy FAILED
- Sources/FoldWiseVoiceKit/Example.swift coverage 77.50% is below 80.00%
- changed included coverage 50.00% is below 85.00%
- uncovered changed lines: Sources/FoldWiseVoiceKit/Example.swift:42
```

A policy/configuration error exits separately and explains the malformed policy,
missing production report, invalid exemption, or unavailable merge base.

## Final exemption register

These are the only production files excluded from the per-file, aggregate-core,
and changed-line gates. They remain part of overall production coverage. Adding
or broadening an exemption is a reviewed policy change; mixed modules first move
their meaningful decisions into covered collaborators.

| File | Reviewed reason |
|---|---|
| `AppMain.swift` | Application lifecycle and composition root |
| `CoreAudioHardware.swift` | Thin Core Audio and AVFoundation hardware boundary; routing policy lives in `AudioRecorder` |
| `AudioDucker.swift` | Thin AppleScript system-command adapter; coordination lives in `AudioDuckCoordinator` |
| `BadgeController.swift` | AppKit window and event-composition shell |
| `BadgeView.swift` | Declarative SwiftUI Badge composition |
| `HistoryView.swift` | Declarative SwiftUI history composition |
| `HomeView.swift` | Declarative SwiftUI home composition |
| `DictationRowView.swift` | Declarative SwiftUI shared Dictation-row composition; presentation, action composition, and interaction rules live in covered collaborators |
| `HotkeyListener.swift` | Thin CGEventTap and NSEvent monitor adapter; matching and dispatch live in `HotkeyDispatcher` |
| `Log.swift` | Static Logger declarations produce no LLVM-instrumentable lines; the policy explicitly permits its absent LLVM entry |
| `OllamaTransport.swift` | Thin URLSession data and streaming transport adapter |
| `MenuBarController.swift` | AppKit status-menu composition shell |
| `Permissions.swift` | macOS permission prompt adapter |
| `SettingsComponents.swift` | Declarative SwiftUI settings components |
| `SettingsController.swift` | AppKit settings window, pasteboard, and keyboard-event adapter; decisions live in `SettingsWorkflow` |
| `SettingsView.swift` | Declarative SwiftUI settings composition |
| `StatsView.swift` | Declarative SwiftUI statistics composition |
| `Theme.swift` | Declarative SwiftUI styling primitives |
| `TextInsertionSystem.swift` | Thin macOS Accessibility, CGEvent, and main-queue scheduling adapter |
| `Transcriber.swift` | Real FluidAudio model-loading and inference adapter |
| `ASRModelLibraryStorage.swift` | Thin FluidAudio and WhisperKit network-storage boundary; mapping, progress, and availability policy live in covered adapters |
| `UpdateCheckEnvironment.swift` | Thin application-bundle, URLSession, and recurring-timer configuration adapter |
| `WhisperTranscriber.swift` | Real WhisperKit model-loading and inference adapter |

There are no line suppression annotations, temporary threshold waivers, Swift
Testing targets, XCUITest targets, automatic retries, or dynamic exclusions.

## Automated platform-component checks

Run the focused rendered checks with:

```sh
swift test --filter 'BadgeHaloTests|BadgeIdleSilhouetteTests|BadgeViewHostedTests|TitlebarAlignmentTests'
```

These tests intentionally protect only these visible invariants:

- the idle Badge has no glow or shadow bleeding onto a light background;
- the idle Badge glyph keeps its intentional dot/bar silhouette;
- neutral Badge surfaces resolve to the canonical opaque Light and Dark tokens;
- primary Badge presentations render their canonical active, success, and error
  semantic tokens;
- Reduce Motion freezes the Badge's decorative recording waveform at its
  representative amplitude;
- Increase Contrast strengthens the Badge's essential capsule boundary; and
- the sidebar toggle stays aligned and proportionate to the traffic lights in a
  real AppKit window.

They render local SwiftUI/AppKit components in-process. They do not request a
permission, use a microphone, install a global event tap, contact a service,
load an ASR model, or control another application. They compare geometry or
bounded pixel properties rather than maintaining reference screenshots. Do not
grow this into a broad snapshot suite: presentation decisions belong in pure
reducers and projections, and only important stable platform invariants belong
here.

## Manual macOS smoke policy

Run the complete checklist below against every release candidate before the
release is published. Record the date, candidate version or commit, macOS and
hardware version, tester, and pass/fail result for each numbered section in the
release notes or release evidence.

Run the relevant sections earlier when a boundary changes:

| Changed boundary | Required sections |
|---|---|
| Microphone capture or input-device routing | 1, 2, 3, and 9 |
| Permission onboarding or prompts | 1 and 6; section 1 must use a clean macOS user account |
| Global hotkey installation or handling | 2, 3, and 11, while another app has focus |
| Mode configuration, lifecycle, or History attribution | 5, 7, 10, 11, and 12 |
| Configuration loading, persistence, or recovery | 2, 11, and 13 |
| Parakeet, Whisper, model storage, or ASR lifecycle | 2 and 4; always exercise both ASR engines |
| Ollama transport or Polish integration | 5 |
| Clipboard or Accessibility insertion | 2 and 6 |
| Badge, menu bar, or AppKit window behavior | 7 and 11 |
| Audio ducking or restoration | 8 |
| Home or History Dictation-row presentation and interaction | 10 |

Passing a focused change-triggered run does not replace the complete
pre-release run.

## Preparation

1. Install the candidate `.app` that will be released. Permission grants bind
   to the built application and its signing identity, so `swift run` is not a
   substitute for permission validation.
2. Have TextEdit available as the insertion target and Spotify or Music
   available as the audio source.
3. In **Settings → Models → Speech recognition**, make sure Parakeet TDT v3 and
   at least one Whisper model are downloaded. A first-time download is allowed
   in this manual procedure.
4. For Polish checks, run Ollama and install the model selected by the Casual
   Mode. Note how to stop and restart Ollama on this Mac.
5. In **Settings → Modes**, identify the protected **Voice to Text** selection
   and the polished **Casual** Mode. In **Settings → Settings**, identify the configured
   push-to-talk, toggle, and optional Cycle Modes shortcuts and enable
   **Pause other audio**.
6. Close any document containing unsaved work. The procedure deliberately
   changes permission grants, focus, audio playback, and the clipboard.

## Complete smoke checklist

### 1. First-run permissions on a clean account

This section is mandatory whenever permission onboarding changes and once for
every release candidate. Use a newly created macOS user account that has never
run FoldWise Voice; resetting privacy data in an existing account is not an
equivalent first-run check.

1. Sign in to the clean account, install the candidate, and launch it.
2. Follow the Permission recovery guide for Microphone and Accessibility. Check
   that each explanation names the capability being requested and opens the
   matching **System Settings → Privacy & Security** pane when offered.
3. Grant Microphone and Accessibility. Keep another app frontmost and confirm
   the global hotkey begins working without also granting Input Monitoring
   (relaunch only if macOS explicitly requires it).
4. Complete one raw dictation into TextEdit.

Pass when the app appears under the correct privacy categories, captures audible
speech, responds to the hotkey outside its own windows, and inserts the spoken
text. The guide must update live and close after both grants. Fail if prompts
overlap, point to the wrong pane, require Input Monitoring for full capability,
silently leave the user stuck, or only work because the account held an earlier
grant.

### 2. Parakeet push-to-talk and insertion

1. Select **Parakeet TDT v3** and the raw **Voice to Text** Mode.
2. Put the insertion point in TextEdit, then return focus to TextEdit after any
   settings change.
3. Hold the configured push-to-talk hotkey, say a distinctive sentence, and
   release it.

Pass when recording starts only while the key is held, the Badge progresses
from recording through working to completion, and the recognizable sentence is
inserted once at the TextEdit cursor. The menu-bar icon must show listening and
working states without taking focus from TextEdit.

### 3. Toggle hotkey

1. Configure a toggle hotkey if none is set and keep TextEdit frontmost.
2. Press it once, speak a different sentence without holding the key, then
   press it again.
3. Press unrelated keys before and after the session.

Pass when the first press starts one session, the second press stops it, the
sentence is inserted once, and unrelated or repeated key events do not start an
extra session.

### 4. Both real ASR engines

1. Complete section 2 with **Parakeet TDT v3** selected.
2. Select a downloaded **Whisper** model, such as Whisper small, and repeat the
   same distinctive raw dictation.
3. Switch back to Parakeet and complete one final short raw dictation.

Pass when both engines transcribe recognizable speech, model preparation or
download progress remains visible rather than appearing hung, and switching in
both directions leaves the next session usable. Any ASR integration change
requires both engines; validating only the changed engine is insufficient.

### 5. Ollama Polish and fallback

1. Start Ollama, select an installed Polish model, and activate **Casual**.
2. Dictate a sentence with obvious filler or missing punctuation. Confirm the
   inserted result is polished and still expresses what was spoken.
3. Stop Ollama while leaving Casual active. Dictate a new distinctive sentence.
4. Restart Ollama after the check.

Pass when the healthy path inserts a sensible polished result and the unavailable
path inserts the raw transcript without losing the dictation session or sending
it to an external service.

### 6. Clipboard restoration and Accessibility denial

1. With Accessibility granted, put the unique text `clipboard-before-smoke` on
   the clipboard. Dictate into TextEdit and wait for insertion to complete.
2. Paste into a scratch location and confirm the clipboard again contains
   `clipboard-before-smoke`, not the transcript.
3. Turn off FoldWise Voice under **Privacy & Security → Accessibility** while
   leaving Input Monitoring enabled. Relaunch if required, focus TextEdit, and
   dictate a different distinctive sentence.
4. Confirm no synthetic paste occurs, the Badge says the text was copied and
   prompts for ⌘V, and a manual ⌘V inserts the complete transcript.
5. Re-enable Accessibility and verify one normal insertion before continuing.

Pass when successful insertion preserves the earlier clipboard and denied
Accessibility leaves the new transcript safely on the clipboard. Fail if the
text disappears, a paste is reported when none occurred, or the user's earlier
clipboard is overwritten after a successful synthetic paste.

### 7. Badge and menu behavior

1. With TextEdit frontmost, hover the Badge and use its Mode picker. Confirm the
   active Mode checkmark also updates in the menu-bar menu and Settings, with no
   Mode-cycle reel for this direct selection.
2. Use the Badge microphone button for a dictation, then use its open-app button.
3. Drag the Badge, relaunch the app, and confirm its position is retained and
   remains on-screen.
4. Observe idle, recording, working, inserted, clipboard-only, and error states
   while running the other sections.
5. Enable VoiceOver and traverse the System, Light, and Dark Appearance tiles.
   Confirm each tile announces whether it is selected and changing the choice
   updates those values immediately.

Pass when the Badge remains a single crisp pill, idle is motionless, state text
is readable, menus and checkmarks stay synchronized, and hovering or choosing a
Mode does not steal focus from the dictation target. The menu-bar icon and menu
must remain usable throughout a session.

### 8. Audio duck and restore

1. Enable **Pause other audio** and start audible playback in Spotify or Music.
   Note the current system mute state.
2. Start a push-to-talk session and keep it recording long enough to observe the
   player pause and other output become muted.
3. Release the hotkey and let the session finish.
4. Repeat with the toggle hotkey, stopping the session with its second press.
5. Disable **Pause other audio** and begin one more session.

Pass when playback and the prior mute state are restored after both completed
sessions, no stale restoration changes audio later, and disabling the setting
leaves playback untouched. Fail if the player remains paused, output remains
muted, or audio resumes when it was not playing before the session.

### 9. Input-device routing

Use a Mac with its built-in microphone, one USB input, and one Bluetooth input.
Record the exact devices and macOS default route in the release evidence.

1. Select **System Default** in FoldWise, choose the built-in microphone as the
   macOS default, and complete a distinctive dictation. Confirm Settings names
   the built-in microphone under System Default.
2. While FoldWise remains open, change the macOS default to USB and then
   Bluetooth. After each change, confirm the roster and System Default detail
   update in platform order, then complete a dictation through that input.
3. Select the USB input explicitly, change the macOS default to Bluetooth, and
   confirm FoldWise keeps USB selected and in use.
4. Start dictating through USB, select Bluetooth before stopping, and confirm
   the deferred message names USB as current and Bluetooth as next. Stop the
   session, then confirm the following session uses Bluetooth without combining
   audio from both inputs.
5. Select USB again and disconnect it while idle. Confirm the saved preference
   remains as a dimmed **Not connected — Preferred** row, the fallback message
   names USB and the live default, and changing the macOS default also changes
   the fallback. Reconnect USB and confirm it is restored automatically with the
   temporary restoration message. With VoiceOver, confirm the disconnected row
   is announced as unavailable and cannot be activated.
6. Start a new USB session with **Pause other audio** enabled, then physically
   disconnect USB while speaking. Confirm the session ends in an error, partial
   audio is not transcribed, inserted, or saved to History, ducked audio is
   restored, and the next session uses the resolved fallback.
7. With an explicit input still selected, deny FoldWise microphone permission
   and try to dictate. Confirm FoldWise reports an error without claiming to be
   listening and does not clear the preference. Re-enable permission and confirm
   a later retry succeeds.
8. Disconnect the preferred USB input, quit FoldWise, and relaunch it. Confirm
   the unavailable preference and fallback survive relaunch; reconnect USB and
   confirm automatic restoration. Repeat one ordinary dictation with Bluetooth
   explicitly selected before finishing.

Pass when all three input types capture successfully, System Default follows
live macOS changes, explicit identity remains stable, healthy changes defer to
the next session, reconnect restores the preference, active loss fails without
partial output, permission denial is recoverable, and an unavailable preference
survives relaunch. Any failure blocks the release.

### 10. Home and History Dictation rows

Prepare saved raw and polished dictations with short and long text, short and
long Mode names, and both flagged states. Open Home and History wide enough to
compare the same saved entry on both surfaces.

1. Compare rows at rest and while hovering each action area. Confirm both
   surfaces keep the same 44-point row geometry, fixed-width time column, text
   position, spacing, and trailing width while identity swaps to actions.
2. Confirm long transcripts remain one collapsed, tail-truncated line and long
   Mode names remain lowercased and tail-truncated without shifting the row.
3. Confirm a flagged row shows an orange filled flag at rest on both surfaces;
   activate Flag and Remove Flag and verify the saved state updates everywhere.
4. Without using the pointer, focus a row and press Tab through Copy and Flag
   on Home, then Copy, Flag, and More on History. Shift-Tab back through the
   same order. Confirm actions remain visible and a focus ring surrounds the
   active row without changing its geometry.
5. Open History's More menu with the keyboard. Verify Copy; Copy Raw only for a
   polished entry; Flag or Remove Flag; every available Re-run Polish Mode; and
   Delete separated and marked destructive. Navigate and activate the submenu
   and actions without the pointer.
6. Enable VoiceOver and move through a raw and a polished row. Confirm it reads
   the 24-hour time, full single-line text, full untruncated Mode name,
   Raw or Polished status, and flagged state. Confirm Copy, Flag or Remove Flag,
   and More actions have specific labels and hints.
7. Activate both the direct Copy action and More → Copy with VoiceOver. Confirm
   each announces “Copied,” shows a temporary checkmark, and returns to the Copy
   icon. Repeat after scrolling the row off-screen and back to confirm feedback
   does not remain stuck.

Pass when Home and History preserve identical row geometry and identity while
their surface-specific actions, keyboard traversal, More-menu navigation,
VoiceOver descriptions, Copy announcement, long-content truncation, and flagged
state all behave as described.

### 11. Cycle Modes shortcut and permission recovery

Record the initial Mode order and selection. Keep TextEdit frontmost whenever a
step says global; return to Settings only to change a binding or the Mode order.

1. Confirm Cycle Modes starts unassigned. Assign a dedicated function key,
   cancel capture by clicking its active chip again, repeat and cancel by
   clicking elsewhere, then assign Escape. Confirm capture itself never starts
   or stops a dictation and never changes the selected Mode. Use the separate
   Remove shortcut action, quit and relaunch, and confirm the binding remains
   cleared and Escape no longer dispatches. Assign a dedicated key again for
   the remaining steps.
2. Try to assign the effective Push to Talk key using different case, outer
   whitespace, or a generic left-modifier alias. Confirm the inline error names
   Push to Talk and the committed shortcut and selection remain unchanged.
   Repeat against Toggle Recording, then assign a distinct Cycle Modes key.
3. With TextEdit frontmost, press and release the Cycle Modes key once. Confirm
   Settings and both Mode menus select the next editable Mode before the Badge
   reel begins. Confirm the Badge remains centered on its existing screen anchor,
   grows from 88 × 38 points to 176 × 38 points, and reels the old icon/name up
   while the complete new icon/name enters from below. Use rapid discrete presses
   through wraparound and confirm every committed intermediate Mode appears FIFO,
   the final Mode remains for about 900 ms, and the Badge then returns to its
   static 88 × 38 point idle glyph. Hold the key and confirm OS autorepeat does
   not advance again.
4. Reorder the Modes in Settings, return focus to TextEdit, and press once.
   Confirm cycling immediately follows the new visible order. Select Voice to
   Text and confirm the next press enters at the first Mode. Reduce the library
   to one already-selected Mode, then zero Modes, and confirm presses are silent
   no-ops in both cases.
5. Start an idle Mode reel, then immediately begin a dictation. Confirm recording
   feedback cancels the reel without a visual overlap. Press Cycle Modes several
   times while recording and working, then finish the session. Confirm the current
   result and History attribution use the start-time Mode; after inserted/error
   feedback finishes, one reel starts at the last Mode fully shown before the
   interruption and ends at the final committed Mode. The next dictation must use
   that final Mode.
6. In **System Settings → Accessibility → Display**, enable **Reduce motion**.
   Repeat a single press and rapid wraparound presses. Confirm the whole icon/name
   row crossfades with no vertical travel, width changes without traveling, the
   900 ms final dwell remains, and TextEdit keeps focus. Disable Reduce motion and
   confirm the vertical reel returns.
7. Deny both Input Monitoring and Accessibility. Confirm Settings explains that
   shortcuts work only while FoldWise is focused and offers the correct System
   Settings route. Verify focused-app operation, then grant either effective
   permission while FoldWise stays running. Keep TextEdit frontmost and confirm
   global cycling recovers without relaunching or resaving the shortcut.
8. Quit and relaunch. Confirm the binding and selected stable Mode survive and
   one background press advances exactly once without activating FoldWise or
   moving focus from TextEdit.

Pass when capture, collision policy, edge dispatch, live order, start-time
freezing, persistence, FIFO/reduced-motion Badge feedback, focused fallback,
automatic global recovery, and focus retention all match the steps. Any failure
blocks the release.

### 12. User-managed Mode lifecycle, accessibility, and concurrent Dictation

Keep an installed Ollama model available for successful saves. Create a second
test model assignment that can be uninstalled during this section. Keep TextEdit
open as the focus target and save one legacy name-only History fixture from a
pre-Mode-ID build before starting.

1. With only the keyboard, select Voice to Text and each editable Mode from the
   Settings list and both Mode menus. Tab through Add, Edit, Duplicate, model,
   icon, transformation, prompt, vocabulary, Save, Cancel, move up/down, and
   Delete. Activate every action without clicking a row, dragging, or relying on
   pointer hover. Confirm Voice to Text is visibly separate and cannot be edited,
   reordered, duplicated, or deleted.
2. Add a Mode with a long unique name, choose an icon and installed model, use
   Reshape, and enter a prompt and vocabulary. Trigger empty-name, duplicate-name,
   unavailable-model, and empty-prompt validation in turn. Confirm Save exposes
   all current errors, preserves the draft, and that Cancel changes nothing.
   Save the valid draft, then duplicate it twice and verify the proposed names
   use `Copy` and the lowest free numbered suffix.
3. Rename the selected Mode, change its icon, prompt, transformation, vocabulary,
   and per-Mode model, then reorder it. Confirm its stable selection, Settings,
   both menus, Badge idle identity, and resolvable History rows update together.
   Confirm each Mode retains its own model assignment.
4. Turn on VoiceOver. Traverse the protected lane, every Mode row, the complete
   editor, model and icon choices, validation, reorder controls, delete prompt,
   shortcut capture, and both Mode menus. Confirm it announces full untruncated
   names plus selected, protected, transformation, unavailable-model, validation,
   destructive, capturing, collision, cleared, and permission-degraded states.
   No state may depend only on its icon, position, or color.
5. Quit FoldWise and, in a copied schema-1 acceptance fixture at an explicit
   configuration path, replace one saved Mode icon with a syntactically valid
   but unavailable SF Symbol name. Relaunch and confirm the file remains valid,
   the stored value survives an unrelated configuration save and relaunch, and
   every applicable surface renders `text.bubble` while VoiceOver announces the
   complete Mode name and state. Repair the icon through the editor before
   continuing; direct JSON editing is only an injected acceptance fixture, not
   a supported product workflow.
6. Uninstall the model assigned to one saved Mode from Models. Confirm the Mode
   keeps its model reference and all other instructions, shows an unavailable
   warning with a route to Models, and a Dictation falls back to the complete raw
   transcript. Reinstall it and confirm Polish resumes without repairing the Mode.
7. While a Dictation is separately listening, transcribing, polishing, and
   inserting, exercise Cycle Modes, a full edit, rename, reorder, and selected
   deletion. For each run, record the selection snapshot at session start. The
   current output and History attribution must use that complete snapshot; the
   next session must use the latest committed selection and Mode definition.
   Re-run Polish from History, edit and then delete its chosen Mode while the job
   is running, and confirm each running job keeps its execution-start snapshot.
8. Delete a Mode with saved History. Confirm the prompt states that History
   remains and its model is not uninstalled. A selected deletion must fall back
   to Voice to Text; the saved row must retain its recorded full name, neutral
   icon, and Deleted Mode state. The legacy name-only row must remain readable
   with a neutral attribution that does not claim deletion. Delete every editable
   Mode and confirm the inviting empty state, Voice to Text Dictation, and silent
   Cycle Modes no-op all remain usable.
9. During direct selection, menu selection, queued cycle confirmation, deferred
   cycle error, and all concurrent operations above, keep typing in TextEdit.
   Confirm neither menu nor Badge activation moves the insertion point or makes
   FoldWise frontmost.

Pass when the complete library is keyboard- and VoiceOver-operable, long and
fallback content stays coherent, stable identity survives mutable presentation,
deleted and legacy attribution remain truthful, every active-session snapshot is
frozen, and zero Modes remains a valid Voice to Text configuration. Any failure
blocks the release.

### 13. Transaction failure and Configuration recovery

Record the resolved `config.json` path before this section. Keep an untouched
copy of the valid candidate configuration and restore normal directory
permissions after every injected failure.

1. With Settings, both Mode menus, the Badge, and a resolvable History row
   visible, open a complete Add/Edit/Duplicate draft, make the configuration
   directory read-only, and press Save. Confirm the entire draft and validation
   state remain open with Retry and Cancel while disk bytes, live selection,
   Settings, menu checks, Badge idle identity, and History resolution stay on
   the last commit. Trigger a Cycle Modes press and confirm the same committed
   state is also the next command's starting point. The Badge must show the
   non-activating “couldn't switch Mode” error for its normal dwell; if the
   pipeline owns the Badge, the error must appear once after idle. Restore write
   access, use Retry successfully, and confirm the next press commits normally.
2. Quit FoldWise, replace `config.json` with malformed bytes, and relaunch. Confirm
   the original bytes remain untouched, Settings opens to Configuration recovery,
   every configuration mutation is disabled, and Voice to Text still completes a
   real Dictation. Quit without resetting and relaunch once more to prove the
   recovery state and original bytes persist.
3. Reset from the recovery banner. Confirm a timestamped backup contains the
   exact rejected bytes before fresh schema-1 defaults appear. Relaunch and verify
   Casual then Email, Casual selected, and normal edits and Dictation work.
4. Repeat steps 2–3 with an otherwise valid file whose `schema_version` is an
   unsupported value. Confirm the banner names the unsupported version and the
   unsupported file is never silently rewritten before Reset.

Pass when failed transactions leave all projections and dispatch on one committed
state, recovery preserves rejected input across relaunch, Voice to Text remains
operational, Reset backs up before replacement, and fresh defaults relaunch as a
normal writable configuration. Any failure blocks the release.

## Finish and record evidence

Re-enable any permission changed during the procedure, restore configuration
directory permissions, the desired ASR engine and Mode, and confirm Ollama and
audio playback are in their original state.

The release evidence must record:

- candidate version and commit, build/signing identity, test date, tester, Mac
  model, and exact macOS version;
- selected ASR and per-Mode Ollama models, including the unavailable-model case;
- Microphone, Accessibility, and Input Monitoring grants before and after each
  permission-recovery step;
- the resolved configuration path and backup filenames created during recovery;
- one pass/fail row per numbered section and step, with observed versus expected
  behavior and links to screenshots, VoiceOver notes, or logs where useful.

Every required step is release-blocking. Record a failure immediately and stop
calling that candidate releasable; do not repeat it until it happens to pass
without first diagnosing the cause and producing a new candidate or documented
environment correction.
