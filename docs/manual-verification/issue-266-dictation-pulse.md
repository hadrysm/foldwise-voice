# Issue 266 Dictation Pulse manual verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#266` — Migrate Stats to Dictation Pulse |
| Commit | `0973443790f40a0deb30c0b6636e8d26a0498b5b` |
| App | FoldWise Voice `0.15.0`, ad-hoc signed release bundle |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | Pass |

The candidate was built with `python3 scripts/build_swift_app.py --dmg` and
launched from `dist/dmg/FoldWise Voice.app`. Synthetic configurations, History,
streak state, and captures lived under the gitignored
`.context/issue-266-manual` directory. `CFFIXED_USER_HOME` redirected the
candidate's Application Support directory, so the installed app's History and
configuration were not changed.

The approved references were rendered with
`./Prototypes/StatsVisualGrammar/run.sh --render` and compared against the
`c-pulse-*` gallery images. Computer Use captured each real app window and its
contemporaneous accessibility tree. The installed FoldWise Voice app was
stopped only for the single-instance candidate runs and relaunched afterward.

## Evidence

| State | Result | Observation |
| --- | --- | --- |
| Dark, wide, populated | Pass | The real `1180 × 720` window kept Words dictated, Speaking speed, Current streak, and Time saved in their existing order in one compressed row. The seven-column Monthly activity calendar was the primary surface and required no horizontal scroll. The opaque Ember Edge layers, orange ingress, metric typography, calendar geometry, and restrained signal treatment matched the approved Dictation Pulse gallery. |
| Light, compact, populated | Pass | The Light palette retained warm opaque layers, legible text, neutral em dashes, waveform cues, today treatment, and boundaries at the minimum width without clipping or horizontal scroll. All four metrics remained in one row and all seven calendar columns remained visible. |
| Exact compact contract | Pass | Computer Use measured the minimum app window at `880 × 672` pixels: `880 × 640` content plus the 32-point titlebar. The navigation automatically used the rail while the four-metric row and seven-column calendar remained intact. |
| Waveform mapping | Pass | Synthetic elapsed days used exact threshold representatives: 80, 320, 720, 1,200, and 1,700 spoken words. Their permanent cues filled exactly one, two, three, four, and five of the five fixed bars. Neutral elapsed days retained an em dash. Pointer detail and accessibility output retained the exact spoken-word values and session counts. |
| Today and future days | Pass | July 24 retained its dot and outline. Later days stayed visually quiet. The real accessibility tree exposed `stats.day.1` through `stats.day.24` and omitted July 25–31 entirely. |
| Hover | Pass | Moving the real pointer from the neutral surface to July 20 raised only that day's dedicated hover surface and immediately replaced the owner-attached detail with `1,700 spoken words across 1 saved session` plus its timing estimate. |
| Keyboard focus and navigation | Pass | Clicking today established the separated accent focus ring. Left Arrow moved the roving focus to July 23 while pointer detail retained hover precedence. Return and Space left the focused day and Stats destination unchanged. The compact pass retained the same focus ring and navigation behavior. |
| Empty | Pass | With no History and saving enabled, the no-stats notice appeared once. Metrics truthfully showed `0`, `—`, `—`, and `—`; the complete current month stayed visible with `0 spoken words, 0 active days`. |
| Saving off with retained activity | Pass | The saving-off notice replaced ordinary content notice copy while all retained metrics and all six active calendar days remained visible and unchanged. `Open History` navigated in place and selected the existing History destination owner. |
| Notice precedence | Pass | With saving off and no retained History, only the saving-off notice appeared; the no-stats notice was suppressed. Metrics and calendar truthfully showed zero activity. |
| Quiet current month | Pass | A retained June session kept lifetime values (`480` words, `137 wpm`, and the saved-time estimate) while July truthfully showed `0 spoken words, 0 active days` without an empty-History notice. |
| Partial timing | Pass | Two July 18 sessions aggregated to 260 spoken words and a two-bar cue. Because only one session had timing, pointer detail and accessibility both reported `Timing unavailable for some sessions` without changing the month or lifetime aggregation. |
| English formatting | Pass | The English launch exposed `July 2026`, English weekday order, grouped numbers, English plurals, exact dates, and duration/save estimates in the real accessibility tree. |
| Polish formatting | Pass | The Polish launch exposed `lipiec 2026`, Monday-first Polish weekday abbreviations, `4200 wypowiedzianych słów`, `6 aktywnych dni`, `153 sł./min`, `4 dni`, and localized day/session/timing detail without clipping. |
| Arabic formatting | Pass | The Arabic launch used right-to-left layout, Arabic-Indic digits and grouping (`٤٬٢٠٠`), Arabic plurals, localized weekdays and Islamic-calendar dates, and exact localized day/session/timing accessibility values. Future days remained excluded. |
| VoiceOver | Pass | With VoiceOver running, Control-Option traversal operated on the real compact app. The live accessibility tree exposed destination selection, the grouped metrics, one calendar context and summary, exact elapsed/today day values, and no duplicate hidden weekday/detail regions or future days. |
| Increase Contrast | Pass | With Increase Contrast enabled, essential navigation, calendar, day, today, and focus boundaries visibly strengthened to the approved high-contrast treatment without changing layout, clipping content, or obscuring the waveform cue. |
| Differentiate Without Color | Pass | Every intensity remained understandable through the permanent five-bar fill count, neutral em dash, today dot/outline, separated focus ring, and exact accessibility value; no state depended on orange alone. |
| Reduce Motion | Pass | With Reduce Motion enabled, moving between July 3 and July 20 committed both the detail and intensity state on the next captured frame with no visible ordinary-state fade or travel. Geometry remained stable. |

The final repository gate passed 1,089 XCTest cases without retries. Coverage
passed at 84.58% overall production, 96.62% included core, and 100% of changed
included lines against `origin/main`. SwiftFormat lint, strict SwiftLint, and
`git diff --check` also passed.

The three macOS accessibility display preferences were unset before the run and
were restored to unset afterward. Full Keyboard Access was temporarily enabled
and restored to its original unset value. VoiceOver and the Computer Use helper
were stopped after their checks, the saved app window size was restored, and
the previously running installed FoldWise Voice app was relaunched.

This is the issue-specific Stats gallery and assistive-technology verification
requested by the review bounce. It does not claim completion of the broader
release-candidate smoke matrix in `docs/TESTING.md`.
