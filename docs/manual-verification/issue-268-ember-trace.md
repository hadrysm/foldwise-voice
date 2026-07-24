# Issue 268 Ember Trace manual verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#268` — Migrate the Badge to Ember Trace |
| Visual candidate | `09412e839e510cb8bb26ec06b6f5ab89a965cce7` (includes implementation `c500271fdb67c09bb43fbb099dcee96bb1eefab0`) |
| App | FoldWise Voice `0.15.0`, ad-hoc signed real app bundles |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | Pass |

The production `BadgeController` and `BadgeView` were exercised in separately
identified app bundles. A launch-only state injector in the gitignored manual
candidate reached otherwise transient presentations through the production
controller; it was not present in the tracked source. A production-identity
candidate used the real `AudioRecorder`, microphone permission, timers, and
Badge level-meter path. Configurations and captures lived under the gitignored
`.context/issue-268-manual` directory, so no installed-app configuration was
changed.

The production captures were compared with the approved Badge views in the
[immutable complete visual gallery](https://github.com/hadrysm/foldwise-voice/tree/db81ee0477b6cd3483e946074d603042b03136f6/Prototypes/CompleteVisualGallery),
including the Dark Standard/Motion working reference and the Light
Contrast+/Reduced error reference.

## Evidence

| State | Result | Observation |
| --- | --- | --- |
| Dark and Light materials | Pass | Dark used the opaque near-black graphite surface and Light used the warm ivory surface. Both retained a quiet neutral essential boundary, flat silhouette, and legible primary/secondary content without the previous translucent violet chrome, glow, or shadow. |
| Exact geometry | Pass | Computer Use captures measured Idle `88 × 38`, Hover `132 × 38`, Mode cycle `176 × 38`, and Recording, every Working variant, Done, clipboard fallback, and Error `208 × 38`. |
| Idle | Pass | The static orange dot/bar glyph remained the sole Idle cue. Captures in Dark and Light showed no ambient animation, glow, shadow, or silhouette change. |
| Hover and accessibility | Pass | Hover exposed, in order, `Change Dictation selection`, `Start Dictation, shortcut F19`, and `Open FoldWise`. The accessibility tree retained the current Dictation selection, help, shortcut, and identifiers. The panel remained a non-key/non-main system dialog. |
| Real Recording, standard motion | Pass | The production-identity candidate entered `208 × 38` Recording through the real toggle hotkey and `AudioRecorder`. The timer advanced from `0:00` to `0:01`; two microphone-driven ribbon samples changed visibly. Cropping out the timer produced ribbon-region SSIM `0.796123`, confirming live decorative motion and amplitude sampling. |
| Real Recording, Reduce Motion | Pass | With macOS Reduce Motion enabled, the same real microphone path remained `208 × 38` and the timer advanced from `0:00` to `0:17`, while the ribbon region stayed at the representative waveform. Samples 17 seconds apart produced SSIM `0.999652`; semantic time feedback continued while decorative amplitude/timeline motion froze. |
| Working variants | Pass | Spinner, `speech model unavailable`, `downloading 45%`, `preparing…`, and `switching speech model…` each measured `208 × 38`, retained calm fixed ribbons, and used the restrained orange active/work boundary and persistent spinner or text cue. |
| Done | Pass | Done measured `208 × 38`, used dedicated success green, exposed the filled checkmark as `Selected`, and retained `inserted`. Polling the real controller measured a `630 ms` visible dwell for the accepted `600 ms` policy. |
| Error and clipboard fallback | Pass | Error and `copied — press ⌘V` each measured `208 × 38`, used dedicated semantic red, exposed the warning icon, and retained their existing failure/recovery text. Polling measured `3,119 ms` for the accepted `3,000 ms` Error dwell. |
| Mode cycle | Pass | A live `ModeCycleCommand.perform()` advanced the isolated configuration and presented the next committed Mode at exactly `176 × 38`. The accessibility value reported `Casual` or `Email` with `Selected Mode`. The Standard run remained expanded for `1,410 ms`, consistent with resize/swap plus the accepted `900 ms` final dwell. With the real Reduce Motion preference, the same live command retained width, value, and dwell; the deterministic Mode-cycle presentation tests pin the standard opposed offsets and reduced opacity-only swap. |
| Increase Contrast | Pass | Enabling the real macOS preference strengthened Dark and Light essential capsule boundaries without changing any measured width, height, content, or control order. |
| Reduce Motion | Pass | Enabling the real macOS preference selected the frozen Working ribbon/spinner and real Recording waveform at legible representative states. Done/Error dwell, timer text, status text, semantic icons, borders, and live Mode-cycle selection remained present. The bounded motion-policy and hosted tests pin immediate ordinary crossfades/hover scale and the reduced opacity-only Mode swap. |
| Focus and non-activation | Pass | TextEdit was frontmost before inspecting and clicking the Badge and remained frontmost afterward (`com.apple.TextEdit` before and after). The Badge never became key or main, and its controls remained usable from the non-activating panel. |
| Anchor stability | Pass | The isolated persisted anchor remained exactly `[1552, 162]` after repeated `88 → 132 → 176 → 208 → 88` programmatic resizes, terminal dwells, Mode cycles, and real Recording. The existing bottom-center default and screen clamping were not changed. |
| Ownership and interruption | Pass | Real toggle start/stop followed the existing Pipeline and recorder path. Controlled lifecycle, terminal, clipboard, and Mode-cycle presentations changed only Badge presentation; reducer events, ASR lifecycle ownership, optional Polish behavior, click semantics, recording-stop semantics, and Mode-selection failure ownership remained unchanged and are covered by the focused suites. |

The run covered Dark/Light, Standard/Increase Contrast,
Motion/Reduce Motion, their combined contrast-and-motion adaptation, every
primary Badge state, every current Working label, live Mode cycle, real
microphone input, another app frontmost, exact geometry and dwell, and persisted
anchor stability. Capture dimensions and the live accessibility tree were read
through Computer Use; image similarity measurements used the captured real-app
frames.

Increase Contrast was restored to its original disabled value and the
previously absent Reduce Motion preference was restored to absent. The isolated
candidate was terminated and the previously running installed FoldWise Voice
app was relaunched. No TCC grant, user configuration, model data, or tracked
production source was changed during manual verification.

This is the issue-specific Ember Trace gallery and macOS boundary verification
requested by the review bounce. It does not claim completion of the broader
release-candidate smoke matrix in `docs/TESTING.md`.
