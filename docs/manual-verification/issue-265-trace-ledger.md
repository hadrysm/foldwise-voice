# Issue 265 Trace Ledger manual verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#265` — Migrate Models to Trace Ledger |
| Commit | `fa119438429c4638252402932fd1e46b475288ff` |
| App | FoldWise Voice `0.15.0`, ad-hoc signed release bundle |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex AFK agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | Pass |

The candidate was built with `python3 scripts/build_swift_app.py --dmg` and
launched from an isolated copy of `dist/dmg/FoldWise Voice.app`. Test
configurations and captures lived under the gitignored
`.context/issue-265-manual` directory, so no user configuration was changed.
The approved references were rendered with
`./Prototypes/ModelsVisualGrammar/run.sh --render` and compared against the
`a-trace-*` gallery images.

The full state matrix was first exercised at `2faf075`. Review then found that
commit `86b7ef1` had removed the inspected row's half of the linked ingress.
The hosted test was changed to fail on that regression, the canonical row
ingress was restored in `fa11943`, and the release app was rebuilt. A focused
real-app pass on that final candidate confirmed the ingress at both ends in
Light mode, moved it by pointer and keyboard inspection, and verified that the
saved `Whisper small` selection in the isolated configuration did not change.
The correction only restores row chrome; it does not change any lifecycle,
operation, fallback, focus, or accessibility ownership exercised by the full
matrix.

## Evidence

| State | Result | Observation |
| --- | --- | --- |
| Dark, default width | Pass | The real `980 × 720` content window kept the comparison ledger and inspector side by side. Speech recognition and Polish stayed in one aligned scan, with opaque Ember Edge layers, compact two-line rows, monospaced facts, semantic status text, and a restrained orange ingress connecting the inspected row to the inspector. |
| Light, compact width | Pass | The real minimum `880 × 640` content window kept both panes visible with the navigation rail. The Light palette retained warm opaque layers, legible secondary facts, status colors, checkmarks, and boundaries without clipping an action. Expanding the navigation at the minimum width also retained the side-by-side composition. |
| Exact compact contract | Pass | Candidate hosted coverage rendered `ModelsCombinedPane` at exactly `617` points and asserted the `340 + 1 + 276` split. The live minimum-window pass confirmed the same non-stacking behavior at its supported wider Models pane width. |
| Review correction | Pass | A fresh `fa11943` release build showed the orange ingress on the inspected ledger row and inspector edge. Pointer inspection moved both ends from saved `Whisper small` to Parakeet TDT v3; Down Arrow moved both to Parakeet TDT v2. The saved checkmark stayed on Whisper small, and `config.json` still contained `asr_model: whisper-small`. |
| Inspection ingress | Pass | Pointer inspection and Up/Down ledger navigation moved the ingress, rating emphasis, and inspector together. The isolated `config.json` retained its original `asr_model` after both paths, proving inspection did not change the saved ASR model selection. |
| Saved selection semantics | Pass | The saved model kept a checkmark, explicit `Saved · unavailable` text, and accessibility value distinct from inspection and availability. Speech recognition remained `Global selection`; Polish remained `Mode inventory`, with no Polish page selection, state tabs, or Models-wide feedback banner. |
| Fallback and restoration | Pass | With unavailable `Whisper small` still saved, the family notice named `Parakeet TDT v3` as the Effective ASR model. The fallback row separately read `Effective fallback`, and its inspector explained that it was temporarily handling Dictation while the saved selection remained unchanged. Loading first appeared as owner-attached `Restoring`, then resolved to the stable fallback without rewriting the isolated configuration. |
| Download progress | Pass | Downloading the saved unavailable Whisper model attached `0%`, then `8%`, to its row and inspector. Accessibility exposed both the fractional progress value and a specifically labeled cancel action; unrelated model controls explained that another Speech recognition operation was in progress. |
| Cancellation | Pass | Cancel returned the affected row and inspector to `Saved · unavailable` plus `Download again`, restored focus to the inspected row, kept Parakeet as the Effective fallback, and left the saved `Whisper small` intent unchanged. |
| Repair | Pass | Invalid default Parakeet data surfaced `Saved · unavailable` and `Download again`. The lifecycle later exposed owner-attached restoration while preparing valid data, then made Parakeet ready as the Effective fallback without conflating repair with selection. |
| Error and Retry | Pass | Installing the deliberately invalid local Ollama name `foldwise-manual-invalid:missing` produced an owner-attached row and inspector error. The complete failure reason remained visible and focus returned to the Install retry action; no Models-wide banner appeared. |
| Destructive confirmation | Pass | The qwen2.5:3b uninstall confirmation named the model, `1,93 GB` of removed storage, affected `Casual` and `Email` Modes, and raw-text fallback before mutation. Cancel preserved the installed model, inspection, and focus. |
| Keyboard | Pass | With Full Keyboard Access temporarily enabled, Tab traversed the titlebar, navigation, ledger, and inspector controls. Up/Down inspection retained the visible separated two-point focus ring and never changed the saved ASR model selection. |
| VoiceOver | Pass | With the VoiceOver service running, Control-Option traversal and the live accessibility tree exposed destination order, selected/not-selected values, the comparison-ledger name/value, complete row summaries, saved-selection wording, Effective fallback, operation-disabled explanations, progress values, cancellation, inspector actions, and no duplicate hidden controls. |
| Increase Contrast | Pass | Essential navigation, row, notice, split, inspector, input, and button boundaries became visibly stronger without changing layout, hiding the ingress, or clipping compact content. |
| Differentiate Without Color | Pass | Saved selection remained identifiable by checkmark and text, inspection by ingress shape and inspector linkage, fallback by notice and `Effective fallback`, progress by meter and percentage, and failure by icon and complete error text. |
| Reduce Motion | Pass | Pointer and arrow inspection updated ingress, row emphasis, and inspector immediately, while fallback restoration and progress changes retained stable geometry and no visible ordinary-state travel. |

The three macOS accessibility display preferences were unset before the run
and were restored to unset afterward. Full Keyboard Access was temporarily
enabled and restored to its original disabled value. The isolated candidate
was quit and the previously running installed FoldWise Voice app was
relaunched.

This is the issue-specific Models gallery verification requested by the review
bounce. It does not claim completion of the broader release-candidate smoke
matrix in `docs/TESTING.md`.
