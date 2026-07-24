# Issue 269 integrated accessibility and visual parity verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#269` — Verify integrated accessibility and visual parity |
| Implementation commit | `0bd2f86a79186d674181fc3c2492abb74f3bb66e` |
| App | FoldWise Voice `0.15.0`, ad-hoc signed release candidate |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | Pass |

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
| Input routing | Pass | Settings exposed System Default and connected inputs. Selecting the explicit MacBook Pro microphone produced owner-attached success and selected/in-use cues; returning to System Default produced the same committed feedback. The app's real recorder subsequently captured through System Default. |
| Real ASR engines | Pass | Parakeet completed the real app recorder → pipeline → History path using the built-in microphone. Whisper large-v3-turbo loaded its actual downloaded Core ML pipeline and transcribed the dependency's known 16 kHz speech fixture; the deterministic live-engine smoke passed in 73.160 seconds. No mock engine or transcript was used. |
| Dictation and Polish outcomes | Pass | The Parakeet run produced a representative raw Voice to Text entry. Existing pipeline integration and real-app evidence cover committed Polish output and raw fallback when optional polishing is unavailable, including owner-attached feedback and transactional history behavior. |
| Destructive and failure flows | Pass | The combined completed-surface evidence covers Mode/model/History/Settings/Configuration consequences, rollback, retry, disabled ownership, and owner-attached status. No operation changed its reducer, persistence, or pipeline ownership during the visual migration. |
| Gallery parity | Pass | Side-by-side review against the approved complete gallery found no missing component, exceptional token, behavior regression, accessibility regression, or reopened visual decision. |

## Automated release gate

| Check | Result |
| --- | --- |
| Focused red/green and hosted suites | Pass without retry |
| Full XCTest suite | Pass — `1,092` tests, `0` failures |
| SwiftFormat lint | Pass — `0/173` files require formatting |
| Strict SwiftLint | Pass — `0` violations in `161` files |
| Git diff check | Pass |
| Overall production coverage | Pass — `84.76%` (`17,736/20,926`), required `47.82%` |
| Included core coverage | Pass — `96.66%` (`8,445/8,737`), required `90.00%` |
| Changed included lines | Pass — `100.00%` (`141/141`), required `85.00%` |
| Release app and DMG build | Pass |

The final full suite ran once through `./scripts/coverage.sh origin/main`; no
failed criterion was retried or waived.

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
