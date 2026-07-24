# Issue 269 integrated accessibility and visual parity verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#269` — Verify integrated accessibility and visual parity |
| Implementation commit | `48b4183cd7a914af482b9f3ca1b824d111b1561f` |
| App | FoldWise Voice `0.15.0`, ad-hoc signed release candidate |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | **Blocked — required external-hardware and complete smoke evidence remain** |

## Release blockers

The code and automated gate pass, but this candidate cannot be called
release-ready or close #269 yet:

1. `docs/TESTING.md` section 9 requires built-in, USB, and Bluetooth inputs,
   live default-route changes, deferred switching, physical loss/reconnect,
   permission denial, and relaunch recovery. This Mac exposes the built-in
   microphone, an iPhone Continuity microphone, and Microsoft Teams' virtual
   device, but no USB input or Bluetooth input. Substituting virtual or
   Continuity devices would not exercise the required hardware boundaries.
2. The complete step-by-step release record is still required for smoke
   sections 7 and 10–13, plus regression sections 2, 4, 5, and 9. The focused
   surface records below prove many individual behaviors, but they are not a
   substitute for recording every required real-app step. In particular, the
   deterministic Whisper inference check does not replace the section 4
   Parakeet → Whisper → Parakeet real-app sequence, and pipeline coverage does
   not replace a healthy-Ollama then stopped-Ollama section 5 run.

Per issue #269, these criteria are release-blocking rather than waived.

This verification is the integration gate for the production migrations in
#262–#268. The release candidate was built with
`python3 scripts/build_swift_app.py --dmg` and exercised as a real macOS app.
The focused evidence for the migrated surfaces remains recorded in:

- [Command Ledger](issue-264-command-ledger.md)
- [Trace Ledger](issue-265-trace-ledger.md)
- [Dictation Pulse](issue-266-dictation-pulse.md)
- [Signal Ledger](issue-267-signal-ledger.md)
- [Ember Trace](issue-268-ember-trace.md)

Those runs include the detailed keyboard, VoiceOver, Increase Contrast,
Differentiate Without Color, Reduce Motion, English/Polish/Arabic formatting,
failure, destructive-flow, and Badge state matrices. This run rechecked their
cross-surface composition in one final candidate and closed the remaining
canonical-token and responsive-spacing gaps.

## Integrated real-app evidence

| Area | Result | Observation |
| --- | --- | --- |
| Canonical visual system | Pass | Source inspection found no previous palette literal, violet Badge token, private substitute palette, or temporary compatibility alias in production. The final candidate uses the single `Theme` owner, opaque canvas/navigation/surface layers, fine essential boundaries, restrained orange activity, dedicated outcome colors, and persistent non-color cues. |
| Production-only composition | Pass | All six destinations and the Badge were reviewed. No prototype review control, treatment name, mock state, screenshot renderer, or prototype-only layout abstraction appeared in the production app. |
| Light and Dark destinations | Pass | Home, Modes, Models, History, Stats, and Settings were traversed in the real app. Both appearances retained the approved hierarchy, typography, boundaries, semantic outcomes, and Cues+ treatment. |
| Shared Dictation rows | Pass | Home and History presented the same production 44-point Dictation-row geometry and interaction vocabulary. The shared hosted row suites pin identity, actions, raw/polished, flagged, deleted-Mode, focus, and accessibility output. |
| Live Appearance propagation | Pass | Settings changed the running app from Dark to Light and back to Dark without relaunch or lost navigation state. The main window updated immediately; closing it exposed the Badge in the matching appearance. `AppearancePropagationHostedTests` additionally hosts main window and Badge together for exact System/Light/Dark propagation. |
| Wide and minimum geometry | Pass | The candidate was reviewed at `1180 × 720` and at the `880 × 640` minimum content size. At minimum width the 52-point rail preserved Home's 2×2 metrics, Stats' four metrics and seven calendar columns, and the side-by-side Models ledger/inspector. Expanding to the 190-point navigation produced the expected compact content. |
| Exact responsive boundaries | Pass | The real app crossed the Home/navigation `940`, Models `617`, and Appearance `650` content breakpoints without clipping. The new canonical destination policy uses 28-point wide and 20-point compact padding; hosted tests calculate and verify the exact Appearance boundary rather than relying on a magic window width. The fixed Mode editor and exact Badge geometry remain pinned by their focused suites and manual records. |
| Configuration recovery | Pass | Hosted coverage reaches all six destinations: Home and Stats remain readable, Voice to Text remains usable, configuration-owning destinations are disabled, and Reset/Quit remain reachable. The real-app recovery and relaunch matrix from the completed surface runs remains green. |
| Accessibility adaptations | Pass | The combined evidence covers visible keyboard focus for custom controls; selected, inspected, progress, success, warning, error, raw/polished, flagged, and deleted-Mode states without color; real Increase Contrast and Reduce Motion preferences; and Differentiate Without Color policy. VoiceOver order/values/actions cover destinations, Dictation rows, Models, Stats days, and the Badge while decorative/duplicate elements remain excluded. |
| Localization stress | Pass | Existing production-hosted and real-app checks cover English, Polish, and Arabic/right-to-left dates, numbers, plurals, weekdays, long Mode/model names, truncation, focus, and accessibility output. The integrated minimum-width pass found no reopened clipping or ordering decision. |
| Badge integration | Pass | The completed real-app Badge matrix covers every state, real microphone amplitude, non-activation with another app frontmost, exact `88/132/176/208 × 38` geometry, Mode cycle, dwells, Reduce Motion, Increase Contrast, and persisted-anchor stability. The final candidate's live appearance pass confirmed the Badge and main window remain one token environment. |
| Input routing | Partial | Settings exposed System Default and connected inputs. Selecting the explicit MacBook Pro microphone produced owner-attached success and selected/in-use cues; returning to System Default produced the same committed feedback. The app's real recorder subsequently captured through System Default. The USB/Bluetooth, physical-loss, permission-denial, and relaunch steps remain blocked as recorded above. |
| Real ASR engines | Partial | Parakeet completed the real app recorder → pipeline → History path using the built-in microphone. Whisper large-v3-turbo loaded its actual downloaded Core ML pipeline and transcribed the dependency's known 16 kHz speech fixture; the deterministic live-engine smoke passed in 73.160 seconds. No mock engine or transcript was used, but the required real-app switch sequence remains outstanding. |
| Dictation and Polish outcomes | Partial | The Parakeet run produced a representative raw Voice to Text entry. Automated integration coverage protects committed Polish output and raw fallback when optional polishing is unavailable, but the required healthy-Ollama then stopped-Ollama real-app sequence has not been recorded for this candidate. |
| Destructive and failure flows | Partial | The combined completed-surface evidence covers individual Mode/model/History/Settings/Configuration consequences, rollback, retry, disabled ownership, and owner-attached status. The complete step-by-step sections 12 and 13 release record remains outstanding. |
| Gallery parity | Pass | Side-by-side review against the approved complete gallery found no missing component, exceptional token, behavior regression, accessibility regression, or reopened visual decision. |

## Automated release gate

| Check | Result |
| --- | --- |
| Focused red/green and hosted suites | Pass without retry |
| Full XCTest suite | Pass — `1,093` tests, `0` failures |
| SwiftFormat lint | Pass — `0/173` files require formatting |
| Strict SwiftLint | Pass — `0` violations in `161` files |
| Git diff check | Pass |
| Overall production coverage | Pass — `84.76%` (`17,742/20,931`), required `47.82%` |
| Included core coverage | Pass — `96.66%` (`8,441/8,733`), required `90.00%` |
| Changed included lines | Pass — `100.00%` (`137/137`), required `85.00%` |
| Release app and DMG build | Pass |

The final reviewed suite ran through `./scripts/coverage.sh origin/main`; no
test failure was retried and no coverage criterion was waived.

## Test hygiene

Manual candidates and configurations lived under the gitignored
`.context/issue-269-manual` directory. A launch-only state injector was used
only in a separately named ad-hoc manual bundle and was removed from tracked
source before the release candidate was built and tested.

The real recorder smoke added exactly one test History row and its associated
statistics. Both files were restored byte-for-byte from snapshots taken
immediately before the run. The temporary candidate was terminated and the
previously installed FoldWise Voice app was relaunched. No system audio route,
TCC grant, installed model data, user configuration, or tracked production
source remained changed by manual verification.
