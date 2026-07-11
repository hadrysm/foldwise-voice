# Testing FoldWise Voice

This guide separates deterministic automated checks from validation that must
cross real macOS boundaries. XCTest protects decisions and a few stable rendered
invariants. The manual smoke procedure protects permissions, global input, audio
hardware, other applications, and real ASR engines without adding XCUITest.

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
