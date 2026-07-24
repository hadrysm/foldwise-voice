# Issue 264 Command Ledger manual verification

## Candidate

| Field | Value |
| --- | --- |
| Issue | `#264` — Migrate Modes and the Mode editor to Command Ledger |
| Commit | `5c1a2c7bd6c9c3831c850a3e6992aff8dc7600f6` |
| App | FoldWise Voice `0.15.0`, ad-hoc signed release bundle |
| macOS | `26.5` (`25F71`) |
| Hardware | MacBook Pro (`MacBookPro18,1`), Apple M1 Pro, 16 GB |
| Tester | Codex AFK agent using Computer Use against the real macOS app |
| Date | 2026-07-24 (Europe/Warsaw) |
| Result | Pass |

The candidate was built with `python3 scripts/build_swift_app.py --dmg` and
launched from `dist/dmg/FoldWise Voice.app`. Test configurations lived under
the gitignored `.context/issue-264-manual` directory so no user configuration
was changed. The approved references were rendered with
`./Prototypes/ModesLibrary/run.sh --render` and compared against the
`a-command-ledger-*` gallery images.

## Evidence

| State | Result | Observation |
| --- | --- | --- |
| Dark | Pass | The permanent Voice to Text selection was visually separate from the ordered editable library. The selected Mode used a two-point ingress mark, active icon, stronger text, and checkmark without an orange row wash. The stable inspector showed icon, name, transformation, model, long Polish instructions, vocabulary, and library actions without clipping. |
| Light | Pass | The same composition and selection hierarchy remained legible in the warm Light palette. Borders, secondary text, destructive action, ingress, and checkmark matched the approved `a-command-ledger-light-selected-mode.png` treatment. |
| Voice to Text | Pass | Selecting Voice to Text retained the editable Mode library and replaced the inspector with owner-attached guidance. Accessibility exposed it as `Voice to Text, protected system selection` with `Value: Selected`; no edit, duplicate, reorder, or delete action was presented for it. |
| Empty library | Pass | A configuration with `modes: []` kept Voice to Text selected and usable, showed `No Modes yet`, and exposed an owner-attached Add Mode action. |
| Unavailable model | Pass | A Mode using `foldwise-manual-missing:latest` retained its identity and selection. The inspector showed a warning, `Dictation falls back to raw text`, and an Open Models action. The editor repeated the unavailable-model guidance beside the model field. |
| Delete confirmation | Pass | Delete opened a confirmation naming the Mode, preserving History, and stating that the AI model would not be uninstalled. Cancel returned to the same selected Mode without mutation. |
| Validation failure | Pass | Saving an empty name kept the editor open, focused the invalid name field, displayed `Enter a Mode name`, and kept the complete draft available for correction. The unavailable-model validation remained attached to its field. |
| Persistence Retry | Pass | The isolated configuration directory was made read-only and a valid rename was saved. The sheet stayed open, showed the permission error at its owner, and changed Save to Retry. The committed file still contained the original `Casual` name, confirming that live/config state was not mutated before persistence. |
| Icon palette | Pass | The labeled popover exposed the curated symbol set, marked Magic wand selected with icon, label, border, and checkmark, and stayed contained within the fixed editor. |
| Editor geometry | Pass | The real sheet screenshot measured exactly `820 × 570` pixels. Save/Retry and Cancel remained explicit, and the editor did not dismiss while validation or persistence errors were present. |
| Keyboard | Pass | The name field received initial edit focus, Tab advanced through the editor input order, and Escape dismissed the complete draft without writing it. A final rebuild of the recorded commit confirmed visible native focus feedback on the navigation, Add Mode, and Command Ledger selection rows, including Voice to Text. |
| VoiceOver | Pass | With VoiceOver running, Control-Option navigation traversed the real app. The destination exposed ordered navigation, selected/not-selected values, the protected Voice to Text description, Mode name/transformation/model summaries, inspector sections, unavailable-model guidance, and labeled edit/duplicate/reorder/delete actions without duplicate hidden controls. |
| Increase Contrast | Pass | Relaunching with Increase Contrast enabled produced visibly stronger essential boundaries around Voice to Text, the Mode library, inspector, buttons, and dividers without changing layout or clipping content. |
| Differentiate Without Color | Pass | The selected Mode remained identifiable through ingress shape, active icon, text weight, checkmark, and accessibility `Selected` value; unavailable, validation, retry, and destructive states retained icon, text, and shape cues. |
| Reduce Motion | Pass | With Reduce Motion enabled, changing selection from Casual to Email updated the ingress, checkmark, inspector, and owner-attached success status immediately with no visible ordinary-state tween. |

The three macOS accessibility preferences were unset before the run and were
restored to unset afterward. Full Keyboard Access was temporarily enabled for
the final focus-feedback pass and restored to its original disabled value.
VoiceOver was stopped after its check, and the previously running installed
FoldWise Voice app was relaunched.

This is the issue-specific Modes/editor gallery verification requested by the
review bounce. It does not claim completion of the broader release-candidate
smoke matrix in `docs/TESTING.md`.
