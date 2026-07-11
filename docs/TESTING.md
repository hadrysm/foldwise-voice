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
   fallbacks with injected recorders, transcribers, transports, pasteboards,
   clocks, and system-effect closures. They never use live internet services,
   microphones, permissions, models, or the user's general pasteboard.
3. A small platform-component layer renders stable SwiftUI/AppKit invariants in
   process. Real system integration belongs to the manual smoke procedure.

Use these commands from the repository root:

```sh
swift test
./scripts/coverage.sh
COVERAGE_BASE_REF=<target-ref> ./scripts/coverage.sh
./scripts/coverage.sh <target-ref>
```

`swift test` is the fast full-suite command. `./scripts/coverage.sh` is the
required local gate: it runs that XCTest suite exactly once with SwiftPM code
coverage, exports LLVM's report, calculates the target-branch diff, and invokes
`scripts/check_coverage.py`. CI calls the same script without a retry wrapper.
The default target is `origin/main`, then local `main`, then `HEAD`; use either
override form above when the review target differs.

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

- **Per-file core:** each included file must be at least 90% covered.
- **Aggregate core:** included files together must be at least 90% covered. The
  current accepted floor is the higher `95.51515151515152%`, so it cannot
  regress merely because the permanent minimum is 90%.
- **Changed lines:** at least 90% of added executable lines in included files,
  relative to the target merge base, must be covered. Exempt and non-executable
  added lines do not enter the denominator.
- **Overall production:** all reported production files, including exemptions,
  must remain at or above the accepted `47.817098382585435%` floor.

The exact accepted values live in `coverage-policy.json`. The checker rejects a
core, changed-line, or per-file policy below 90%, rejects a decrease from the
target branch's accepted floors, and includes new production files by default.
No source or coverage artifact is uploaded to a hosted coverage service.

On success, output includes the overall, aggregate, and changed-line fractions,
the number of included and exempt files, and the ten lowest-covered included
files. A failure exits nonzero and names every failed threshold. Changed-line
failures also print actionable `path:line` locations, for example:

```text
Coverage policy FAILED
- Sources/FoldWiseVoiceKit/Example.swift coverage 87.50% is below 90.00%
- changed included coverage 50.00% is below 90.00%
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
| `AudioRecorder.swift` | AVFoundation microphone capture adapter |
| `AudioDucker.swift` | Thin AppleScript system-command adapter; coordination lives in `AudioDuckCoordinator` |
| `BadgeController.swift` | AppKit window and event-composition shell |
| `BadgeView.swift` | Declarative SwiftUI Badge composition |
| `HistoryView.swift` | Declarative SwiftUI history composition |
| `HomeView.swift` | Declarative SwiftUI home composition |
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
| `UpdateCheckEnvironment.swift` | Thin application-bundle, URLSession, and recurring-timer configuration adapter |
| `WhisperTranscriber.swift` | Real WhisperKit model-loading and inference adapter |

There are no line suppression annotations, temporary sub-90 core floors, Swift
Testing targets, XCUITest targets, automatic retries, or dynamic exclusions.

## Automated platform-component checks

Run the focused rendered checks with:

```sh
swift test --filter 'BadgeHaloTests|BadgeIdleSilhouetteTests|TitlebarAlignmentTests'
```

These tests intentionally protect only three visible invariants:

- the idle Badge has no glow or shadow bleeding onto a light background;
- the idle Badge glyph keeps its intentional dot/bar silhouette; and
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
| Microphone capture | 1, 2, and 3 |
| Permission onboarding or prompts | 1 and 6; section 1 must use a clean macOS user account |
| Global hotkey installation or handling | 2 and 3, while another app has focus |
| Parakeet, Whisper, model storage, or ASR dispatch | 2 and 4; always exercise both ASR engines |
| Ollama transport or Polish integration | 5 |
| Clipboard or Accessibility insertion | 2 and 6 |
| Badge, menu bar, or AppKit window behavior | 7 |
| Audio ducking or restoration | 8 |

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
4. For Polish checks, run Ollama and install the model selected by the Clean
   Mode. Note how to stop and restart Ollama on this Mac.
5. In **Settings → Modes**, identify the raw **Voice to Text** Mode and the
   polished **Clean** Mode. In **Settings → Settings**, identify the configured
   push-to-talk and toggle hotkeys and enable **Pause other audio**.
6. Close any document containing unsaved work. The procedure deliberately
   changes permission grants, focus, audio playback, and the clipboard.

## Complete smoke checklist

### 1. First-run permissions on a clean account

This section is mandatory whenever permission onboarding changes and once for
every release candidate. Use a newly created macOS user account that has never
run FoldWise Voice; resetting privacy data in an existing account is not an
equivalent first-run check.

1. Sign in to the clean account, install the candidate, and launch it.
2. Follow the Microphone, Accessibility, and Input Monitoring onboarding. Check
   that every explanation names the capability being requested and opens the
   matching **System Settings → Privacy & Security** pane when offered.
3. Grant all three capabilities. Keep another app frontmost and confirm the
   global hotkey begins working after the grant (relaunch if macOS explicitly
   requires it).
4. Complete one raw dictation into TextEdit.

Pass when the app appears under the correct privacy categories, captures audible
speech, responds to the hotkey outside its own windows, and inserts the spoken
text. Fail if prompts overlap, point to the wrong pane, silently leave the user
stuck, or only work because the account held an earlier grant.

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

1. Start Ollama, select an installed Polish model, and activate **Clean**.
2. Dictate a sentence with obvious filler or missing punctuation. Confirm the
   inserted result is polished and still expresses what was spoken.
3. Stop Ollama while leaving Clean active. Dictate a new distinctive sentence.
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
   active Mode checkmark also updates in the menu-bar menu and Settings.
2. Use the Badge microphone button for a dictation, then use its open-app button.
3. Drag the Badge, relaunch the app, and confirm its position is retained and
   remains on-screen.
4. Observe idle, recording, working, inserted, clipboard-only, and error states
   while running the other sections.

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

## Finish and record evidence

Re-enable any permission changed during the procedure, restore the desired ASR
engine and Mode, and confirm Ollama and audio playback are in their original
state. Record failures with the numbered section, exact candidate, macOS version,
selected models, and observed versus expected result. A failed required section
blocks the release; do not retry it until it happens to pass without diagnosing
the failure.
