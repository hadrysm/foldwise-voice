# Models view state and token constraints

Audit date: 2026-07-21  
Scope: the current `Models` settings destination and the runtime facts it presents.  
Purpose: input to the comparison-first Models view designs; this records behavior and content that a redesign must preserve, not the current structure as a required design.

## Current surface hierarchy

`SettingsView` presents `Models` as a vertically scrolling page with a page title and 36 pt horizontal/top content padding. `ModelsCombinedPane` then stacks two independent model families with 24 pt between them:

1. **Speech recognition** — the global ASR model catalog, selection, availability, and lifecycle management.
2. **Polish (Ollama)** — the locally installed Ollama inventory and ways to add or remove models that are assigned separately in each Mode.

The two families share cards, rows, dividers, rating dots, progress indicators, and small action controls, but they do **not** share selection semantics. Speech recognition has one global ASR model selection; an Ollama model is inventory only on this page and is assigned per Mode elsewhere.

The whole Models page is disabled in a configuration recovery state. The window-level recovery banner remains visible and offers **Quit** and **Reset Configuration**.

The settings window has a minimum size of 880 × 640 pt. The page has no Models-specific breakpoint or maximum content width: it fills the space left by either the 190 pt expanded sidebar or 52 pt collapsed rail. At minimum window width, the expanded-sidebar content area after page padding is about 617 pt wide. The current surface is always one column and relies on vertical scrolling.

Sources: [`SettingsView.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsView.swift), [`ModelsCombinedPane.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsCombinedPane.swift), [`CONTEXT.md`](../../CONTEXT.md).

## Non-negotiable domain and behavior distinctions

- **ASR model selection**, **ASR model availability**, and **Effective ASR model** are separate facts. A persisted selection can be unavailable or unknown while Parakeet is the effective fallback. The UI must not imply that fallback silently changed the saved selection.
- Downloading an optional ASR model changes availability only. It never selects or loads that model.
- Selecting a downloaded ASR model is a cancelable transaction. The new choice is committed only after activation succeeds; failure or cancellation keeps the previous saved selection.
- Only one ASR management operation can run at a time. While any ASR download, bootstrap, switch, restore, or deletion is active, competing ASR management actions are disabled.
- The built-in Parakeet TDT v3 default cannot be deleted. Optional downloaded ASR models can be deleted. Deleting the selected optional model first commits Parakeet for future Dictation sessions.
- Several downloaded ASR models may coexist on disk, while only one engine may be loaded in memory.
- Ollama models have no page-level selection. Installing one does not reassign any Mode. Uninstalling one leaves every referencing Mode intact; those Modes use raw text until another available model is assigned.
- ASR and Ollama operations are independent in the current model. The single-operation exclusion is per family, not across both families.

Sources: [`ADR-0005`](../adr/0005-second-asr-engine-behind-transcribing.md), [`ADR-0006`](../adr/0006-global-asr-selection-over-revived-asr-model.md), [`README.md`](../../README.md).

## Speech recognition inventory

### Stable catalog content

Catalog order is meaningful and currently fixed:

| ASR model | Coverage | Size | Speed | Quality | Availability at first launch | Deletable | Description pressure |
| --- | --- | ---: | ---: | ---: | --- | --- | --- |
| Parakeet TDT v3 | 25 languages | 600 MB | 5/5 | 4/5 | Built-in/default; automatically bootstrapped if missing | No | Long: default, Neural Engine, power-efficient, European languages plus Japanese |
| Parakeet TDT v2 | English | 600 MB | 5/5 | 4/5 | Adapter-validated local data | Yes when available | Long: English-only alternative with the same Neural Engine speed |
| Whisper large-v3-turbo | ~99 languages | 632 MB | 3/5 | 4/5 | Downloadable | Yes when available | Long hyphenated name and long on-device/language description |
| Whisper small | ~99 languages | 483 MB | 4/5 | 3/5 | Downloadable | Yes when available | Long: size/speed/accuracy trade-off |
| Whisper large-v3 | ~99 languages | 947 MB | 2/5 | 5/5 | Downloadable | Yes when available | Long: maximum-accuracy trade-off |

Every row must accommodate name, language coverage, size, a one-to-five speed rating, a one-to-five quality rating, and a sentence-length blurb. `streaming` and `translate` flags exist in the catalog but are intentionally inert and are not current user-visible capabilities.

An unknown stored ASR identifier must not create a synthetic catalog row. Its raw identifier can still appear in the recovery notice.

Source: [`ASRModelCatalog.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelCatalog.swift).

### Baseline states

The catalog is partitioned by adapter-validated availability:

- **Your Models**: all available/downloaded entries. A row can be selected or unselected.
- **Available**: all unavailable entries. A row cannot be selected and offers **Download**.
- A section is omitted when its collection is empty. In practice the built-in default normally ensures **Your Models** is present after bootstrap, but failure/bootstrap transitions must not assume that.

Before the first lifecycle snapshot arrives, the ASR catalog is empty and the current view shows only its introductory copy—there is no explicit “checking speech models” state. During recovery, selection circles continue to reflect the **saved** selection, not the Effective ASR model. Consequently an unavailable saved selection can sit in **Available** with no circle while the downloaded Parakeet fallback also appears unselected; the recovery notice is the only explanation of which model is effective.

An available row shows:

- model name and language coverage in the lead line;
- description;
- size, speed, and quality;
- selected or unselected radio-like circle state;
- an overflow menu with **Delete…** only when the model is not the default.

An unavailable row shows the same comparison content plus **Download**, with no selection affordance.

### Operations and progress states

| Operation | Current presentation | Cancellation | Other ASR actions |
| --- | --- | --- | --- |
| Optional download, fractional | Progress bar, integer percent, inline cancel icon | Yes | Disabled |
| Optional download, indeterminate | Spinner, “Downloading…”, inline cancel icon | Yes | Disabled |
| Default bootstrap, fractional | Default row progress bar and integer percent | No cancel control | Disabled |
| Default bootstrap, indeterminate | Default row spinner and “Downloading…” | No cancel control | Disabled |
| Switch | Separate spinner and “Switching to {name}…”, plus **Cancel** | Yes | Disabled |
| Automatic restore | Separate spinner and “Restoring {name}…” | No | Disabled |
| Delete | Target row spinner and “Deleting…” | No | Disabled |

The row being deleted suppresses ratings and selection state while deletion is active. The row being downloaded replaces its **Download** action with progress. ASR progress may be determinate or indeterminate, including the post-download preparation/compilation interval.

### Recovery and failures

The design must provide space and hierarchy for these distinct notices:

- Stored known selection unavailable: “{selection} is unavailable. Using {fallback} until you download it again.”
- Stored selection unknown: includes the raw stored identifier and names the fallback.
- Optional download failed, including the runtime reason.
- Download completed but data is incomplete or corrupt.
- Default bootstrap failed, including the runtime reason.
- Engine load failed, including the runtime reason.
- Selection failed, including the runtime reason.
- Restoration degraded to a fallback, with an optional runtime reason.
- Deletion failed or selection-before-deletion failed, including the runtime reason.
- A canceled selection produces no visible error.

Download/load/selection failures and deletion failures occupy separate error rows. Errors currently use a red filled warning-triangle label. A **Retry** action is shown only when Dictation is blocked, no operation is active, and the failure supports default-bootstrap retry.

### Delete confirmation

Optional model deletion uses a destructive confirmation alert:

- title: “Delete {name}?”;
- body always states that downloaded weights are removed and names the catalog size;
- if it is the saved ASR model selection, the body also states that Parakeet will be selected instead;
- actions: destructive **Delete** and **Cancel**.

Sources: [`SpeechPane.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SpeechPane.swift), [`SettingsModel.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsModel.swift), [`ASRModelLifecycle.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelLifecycle.swift).

## Polish (Ollama) inventory

### Top-level availability states

The installed-model list has a three-way state encoded by `installed`:

1. `nil`: checking; show a card row with “Checking Ollama…” and a small spinner.
2. empty: Ollama is unreachable; show “Ollama isn't running,” startup guidance for both the app and Homebrew service, and **Retry**.
3. non-empty: show the complete inventory-management surface.

The empty list cannot currently distinguish a reachable Ollama server with zero models from an unreachable server. Any redesign based on current state must preserve that limitation unless a later implementation specification explicitly changes the data model.

### Installed models

Installed entries come from Ollama and are sorted by name. Names are external, arbitrary strings; sizes are optional formatted byte counts. A row shows:

- raw model name;
- size when Ollama reports a positive byte count;
- matched catalog blurb and speed/quality ratings when exact, size-tier, or family guidance can be found;
- no invented blurb or ratings for an unrecognized custom model;
- overflow menu with destructive **Uninstall…**.

During uninstall, the target row replaces ratings/actions with a spinner and “Uninstalling…”. Other uninstall menus are disabled while either one Ollama pull or one Ollama deletion is active. Install controls are disabled during a pull; during deletion they currently still look enabled, but the workflow rejects the action. That affordance/state mismatch is an implementation fact, not a behavior a redesign should preserve: the actual invariant is still one Ollama mutation at a time.

### Curated model library

The library contains the catalog entries that are not exact-name matches in the installed inventory. Current order:

| Model | Size | Speed | Quality |
| --- | ---: | ---: | ---: |
| gemma3:1b | 815 MB | 5/5 | 2/5 |
| llama3.2:1b | 1.3 GB | 5/5 | 2/5 |
| llama3.2:3b | 2.0 GB | 4/5 | 3/5 |
| qwen2.5:3b | 1.9 GB | 4/5 | 3/5 |
| gemma2:2b | 1.6 GB | 4/5 | 2/5 |
| phi4-mini:3.8b | 2.5 GB | 4/5 | 3/5 |
| gemma3:4b | 3.3 GB | 4/5 | 4/5 |
| qwen2.5:7b | 4.7 GB | 3/5 | 4/5 |
| llama3.1:8b | 4.9 GB | 2/5 | 4/5 |
| mistral:7b | 4.4 GB | 3/5 | 3/5 |

Each curated row must accommodate name, size, speed, quality, a sentence-length task-specific blurb, and **Install**. When every exact catalog name is installed, the card remains and shows “All recommended models are installed.”

The blurbs carry meaningful comparison content: minimum hardware/memory guidance, multilingual strength, speed, prompt adherence, and suitability for in-place versus expanding Modes. A redesign may normalize their grammar, but cannot discard those trade-offs without replacing them with equally informative comparison content.

### Install by name

The **Other** card includes:

- “Install by name”;
- guidance that any `ollama.com/library` model is valid and an example such as `qwen2.5:14b`;
- a rounded text field with placeholder `model:tag`, currently fixed to 160 pt wide;
- **Install**, disabled for an empty/whitespace-only name or while another pull is active.

The submitted name is trimmed only for surrounding spaces. On success the custom field is cleared and the installed inventory is refreshed. On failure its contents remain and a named error is shown.

### Pull progress and failures

- The active row replaces **Install** with a 110 pt progress bar when a fraction exists, plus “{integer}% — {runtime status}”.
- Without a fraction, it shows the runtime status only; initial status is “contacting Ollama…”.
- Status is one line, so arbitrary runtime status text must tolerate truncation.
- Pulls have no user-facing cancel action in the current contract.
- Install failure: “Couldn't install {name}: {reason}”.
- Uninstall failure: “Couldn't uninstall {name}: {reason}”.
- Install and uninstall failures are separate red warning labels and may persist until their respective next operation clears them.

### Uninstall confirmation

The alert includes:

- title: “Uninstall {name}?”;
- permanent-removal wording;
- freed size when available;
- every Mode name whose `llmModel` exactly matches the target, joined in a comma-separated list;
- warning that affected Modes will use raw text until another model is assigned;
- destructive **Uninstall** and **Cancel**.

The affected-Mode list is unbounded user content. Long Mode names and several references must wrap without hiding the consequence.

Sources: [`ModelsPane.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsPane.swift), [`ModelCatalog.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/ModelCatalog.swift), [`OllamaClient.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift), [`SettingsWorkflow.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift).

## Actions and affordance rules at a glance

| Action | Scope | Preconditions | Consequence that must remain legible |
| --- | --- | --- | --- |
| Select ASR model | Global | Model available; no ASR operation | Transactional switch; applies to later Dictation sessions |
| Download ASR model | One unavailable ASR entry | No ASR operation | Adds availability only; does not select |
| Cancel ASR download | Active optional download | Not default bootstrap | Returns row to pre-download state; safe partial data may remain unavailable |
| Cancel ASR switch | Active switch | Switch is cancelable | Previous saved/effective choice is restored |
| Retry ASR bootstrap | Default recovery | Dictation blocked; retryable failure; idle | Attempts to restore recognition |
| Delete ASR model | Optional available ASR entry | No ASR operation | Reclaims data; selected target commits Parakeet first |
| Retry Ollama check | Ollama-unreachable state | None | Refreshes inventory |
| Install curated Ollama model | Missing exact catalog entry | Non-empty name; no Ollama mutation | Adds inventory only; does not assign a Mode |
| Install custom Ollama model | Arbitrary model name | Trimmed name non-empty; no Ollama mutation | Adds inventory only |
| Uninstall Ollama model | Installed entry | No Ollama mutation; confirmation | Leaves Modes intact; affected Modes fall back to raw text |

## Existing Theme-token usage

Every proposed visual direction must remain token-faithful to the existing Theme. Component-level semantic aliases may be derived later, but no new base visual system is needed.

| Role in the Models view | Existing token or seam |
| --- | --- |
| Page title typography | `Theme.pageTitle` (`Theme.ui(28, .semibold)`), with current -0.56 kerning |
| Body/explanatory typography | `Theme.ui(12)` |
| Row title typography | `Theme.ui(13, .semibold)` |
| Row subtitle/status/error typography | `Theme.ui(11)` |
| Rating labels, sizes, compact progress | `Theme.ui(10)` |
| Section labels | `Theme.sectionLabel` (`Theme.ui(11, .bold)`), uppercase, 1.1 kerning |
| Primary model/title text | `Theme.textPrimary` |
| Explanations, blurbs, size/rating/status text, inactive menu icons | `Theme.textSecondary` |
| Section headers and unselected ASR circle | `Theme.textTertiary` |
| Selected ASR circle | `Theme.accent` |
| Card fill | `Theme.cardBackground` |
| Card border, dividers, empty rating dots | `Theme.hairline` |
| Card shape | `Theme.cardRadius` |
| Page horizontal/top inset | `Theme.contentPadding` |
| Settings-page background around the Models content | `Theme.windowBackground` |
| Font construction | `Theme.ui`; the Models page does not bypass the font seam |

The current cards use `Theme.cardBackground` with a one-point `Theme.hairline` stroke. Rating dots use `Theme.textSecondary` for filled values and `Theme.hairline` for empty values. All palette tokens adapt to Light and Dark appearances.

### Current non-tokenized metrics and system styles

These values describe current density and interaction geometry. They are evidence for the redesign, not permission to create a second token system:

- family gap 24; internal section gap 16;
- row horizontal padding 14 and vertical padding 10;
- row content gap 12, text stack gap 2, minimum trailing separation 16;
- divider leading inset 14;
- rating-stack gap 3, label-to-dots gap 4, dot gap 2.5, dot diameter 4.5;
- overflow hit target 28 × 28;
- progress bar width 110;
- custom-name field width 160;
- page bottom padding 24;
- standard SwiftUI/AppKit control styles for buttons, text fields, menus, alerts, dividers, and progress indicators;
- semantic `.red` for operation errors and `.orange` for configuration recovery are currently outside named Theme color tokens.

Any new component alias should derive from the base palette, typography, spacing/radius scale, or native macOS control semantics. The existing surface does not use Badge colors, keycap colors, sidebar colors, tooltip colors, monospace typography, or bespoke shadows.

Sources: [`Theme.swift`](../../Sources/FoldWiseVoiceKit/DesignSystem/Theme.swift), [`SettingsComponents.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsComponents.swift).

## Accessibility and interaction constraints

- Entire available ASR rows are plain buttons with rectangular content shapes, not just tiny selection circles.
- Download and delete controls are siblings of the ASR row-selection button; they must not accidentally trigger selection or inherit a disabled row's state.
- Overflow buttons have a 28 pt square hit area, hide the menu indicator, and expose “More actions for {name}” accessibility labels.
- Optional ASR download cancellation icons expose both help text and a model-specific accessibility label.
- Native confirmation alerts preserve destructive and cancel roles.
- Progress cannot rely on color alone: spinners/bars and status text identify every operation.
- ASR selection cannot rely on color alone: circle/checkmark shape distinguishes selected from unselected.
- Long external model identifiers, descriptions, runtime errors, progress statuses, and affected-Mode lists are valid input. Proposed layouts must define wrapping/truncation intentionally rather than assuming catalog samples are the maximum.

## Constraints for the comparison-first redesign

The current vertical sections and row anatomy are replaceable. The redesign still has to make all of these truths discoverable:

1. Which facts are comparable across every model: family, name, footprint, speed, quality, language/task fit, and availability.
2. Why Speech recognition has a global selection control while Polish models do not.
3. The difference between downloading and selecting an ASR model.
4. The difference between saved ASR model selection and Effective ASR model during recovery.
5. Which actions are unavailable because of a family-local management operation and how that operation can be canceled, if supported.
6. The non-deletable default and the consequences of deleting a selected optional ASR model.
7. The consequences of uninstalling an Ollama model referenced by one or more Modes.
8. Checking, unavailable-service, empty/completed-library, operation, recovery, error, and configuration-read-only states.
9. Catalog rows and arbitrary external names/descriptions at realistic text lengths.
10. The existing adaptive Theme palette, font seam, density scale, card radius, and native macOS interaction language.

No design produced from this audit should add streaming/translation controls, change model catalogs or lifecycle semantics, combine ASR and Ollama selection, assign Ollama models from this page, or silently resolve the Ollama empty-versus-unreachable ambiguity. Those changes sit outside the active Wayfinder destination.
