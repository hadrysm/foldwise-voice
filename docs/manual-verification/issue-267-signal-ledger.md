# Issue 267 Signal Ledger manual verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#267` — Migrate Settings and global feedback to Signal Ledger |
| Visual candidate | `26c56dd5610c9942f09d37e125ce1b3cde3fc34b` |
| App | FoldWise Voice `0.15.0`, ad-hoc signed release bundle |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | Pass |

The candidate was built with `python3 scripts/build_swift_app.py --dmg` and
launched from `dist/dmg/FoldWise Voice.app`. Configurations, an isolated
Application Support directory, a separately identified permission candidate,
and captures lived under the gitignored `.context/issue-267-manual` directory.
No installed-app configuration or TCC grant was changed.

The approved references were rendered by the existing
`Prototypes/SettingsFeedback` gallery and compared with its `a-ledger-*`
images. A separately identified manual-matrix bundle exercised controlled
restored, deferred, and unavailable `AudioInputState` values through the
production app and `SettingsView`; its launch-only state injector was removed
before commit. The final source changes after the visual build add only
an accessibility identifier and direct hosted coverage for the input-roster
attachment invariant; they do not change pixels, hierarchy, or behavior.

## Evidence

| State | Result | Observation |
| --- | --- | --- |
| Dark, wide | Pass | The real `1180 × 720` window presented one dense vertical scan path with icon-led uppercase Keyboard Shortcuts, Input, Sound, Appearance, and Updates labels. Restrained opaque row surfaces, hairlines, compact controls, monospaced shortcut facts, and orange selection ingress matched the approved Signal Ledger reference. |
| Light, wide | Pass | Switching Appearance updated the complete real window immediately. The warm Light palette retained legible primary/secondary text, row boundaries, semantic colors, checkmarks, and selection ingress. The owner-attached `Saved ✓` notice appeared only inside Appearance and cleared after its production lifetime. |
| Light, compact rail | Pass | At the real minimum `880 × 672` frame (`880 × 640` content plus titlebar), automatic navigation used the rail and Settings remained a single vertical scroll path. At this width the content remained at least 650 points and the three Appearance choices stayed horizontal without clipping. |
| Appearance boundary | Pass | Explicitly expanding navigation at the same minimum frame reduced destination content below 650 points and changed Appearance to the vertical composition. The hosted boundary test separately rendered exactly 650 and immediately below 650 points, protecting both sides of the contract. |
| Permanent Appearance cues | Pass | System, Light, and Dark always exposed icon, label, descriptive text, bordered shape, selection ingress, checkmark, and accessibility selected/not-selected value. Light and Dark remained distinguishable with color removed and in increased contrast. |
| Shortcut capture gate | Pass | Cycle Modes entered a visible `Capturing` state whose accessibility hint stated that the captured key would not run a command. Capturing the already assigned `F19` did not start Dictation, ended capture, restored Cycle Modes to unassigned, and retained Toggle Recording as `F19`. |
| Collision, assignment, removal | Pass | The collision rendered as a persistent error inside Keyboard Shortcuts, not at the Continuous Frame edge. A later `F18` assignment superseded it with owner-attached success, persisted, and exposed an explicit remove action; removal restored the unassigned presentation and persisted. |
| Focused-app permission | Pass | A separately identified copy launched through LaunchServices without inherited Accessibility/Input Monitoring grants. Settings showed `Global shortcuts need permission` inside Keyboard Shortcuts with the focused-app-only explanation and Open System Settings action. No system permission was changed. |
| Input roster and fallback | Pass | The real roster exposed System Default, the built-in input, a connected Continuity input, and a connected virtual input with separate preferred and effective cues. An isolated stale preferred UID rendered a disabled `Not connected — Preferred` row plus the owner-attached fallback naming the effective built-in input; the saved preferred intent remained selected. |
| Input restoration, deferral, unavailable | Pass | A separately identified real app bundle rendered controlled restored, deferred-during-Dictation, and unavailable `AudioInputState` values through the production `SettingsView`. Each presentation was visually compared with the approved gallery and inspected in the live accessibility tree: semantic icon/copy stayed inside Input, preferred/effective cues stayed distinct, and no global toast appeared. Direct hosted coverage protects the shared input-roster geometry invariant, while existing recorder/workflow tests cover topology and transactional behavior. Real hardware was not forcibly detached because doing so would require privileged Core Audio mutation; the real-device pass covered selection and fallback. |
| Sound | Pass | Pause other audio remained one compact native switch row with its existing explanatory copy and immediate owner-attached persistence route. No duplicate card or global notice appeared. |
| Updates | Pass | The packaged build performed its launch check. In the offline result it showed the complete GitHub failure copy and a compact Check again action inside Updates; retry repeated the operation without moving feedback to a Settings-wide banner. Existing workflow coverage exercises checking, current, available, failed, and unavailable-build states and their unchanged actions. |
| Configuration recovery | Pass | A rejected schema opened the real read-only recovery frame above Home. Home and Stats remained enabled; Modes, Models, History, and Settings were disabled. Quit and Reset Configuration remained reachable, Voice to Text guidance stayed available, the rejected file remained untouched, and no Settings-only recovery banner existed. |
| Global success and error | Pass | Sidebar persistence success appeared as a compact bottom-right Continuous Frame toast and cleared after the production lifetime. Making only the isolated configuration directory read-only produced a persistent bottom-edge permission error; it remained after the success timeout and never appeared inside a Settings section. Directory permissions were restored immediately after capture. |
| Keyboard | Pass | With Full Keyboard Access temporarily enabled, Tab traversed titlebar, ordered navigation, and Settings controls. Navigation and the reset action showed the separated visible focus treatment, and the accessibility tree reported the reset action as focused. |
| VoiceOver | Pass | VoiceOver was started for the real compact app and Control-Option traversal exercised the window. The live tree exposed ordered destination selection, shortcut assigned/capturing semantics, input selected/not-selected values and hints, switch value, all Appearance labels/descriptions/selected values, update action, recovery permissions, and no duplicate hidden controls. |
| Increase Contrast | Pass | The real candidate relaunched with Increase Contrast and visibly strengthened titlebar, navigation, section, row, control, tile, divider, and focus boundaries without changing layout or clipping content. |
| Differentiate Without Color | Pass | Selection remained readable through ingress shape, filled/empty icon, text weight, checkmark, border, and accessibility value. Warnings, errors, success, capture, and recovery retained icon, text, shape, and ingress cues. |
| Reduce Motion | Pass | With Reduce Motion enabled, changing Light to Dark committed the palette, tile selection, checkmark, and owner-attached success state on the next captured frame without ordinary-state travel or geometry change. |

Full Keyboard Access, Increase Contrast, Differentiate Without Color, and Reduce
Motion were restored to their original values after the run. VoiceOver was
stopped, the isolated read-only directory was made writable again, and the
installed FoldWise Voice app was relaunched. Captures remain gitignored because
the real input roster contains user-specific device names.

This is the issue-specific Settings, recovery, global-feedback, and
assistive-technology verification requested by the review bounce. It does not
claim completion of the broader release-candidate smoke matrix in
`docs/TESTING.md`.
