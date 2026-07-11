# ADR-0006: ASR-model selection is global, persisted by reviving the per-mode `asr_model` field

## Status

Accepted (2026-07-07)

## Context

ADR-0005 adds a second ASR engine; users need to choose one, and the choice must
persist in `modes.json`. Two shaping facts:

- The schema already reserves a **per-mode** slot, `Mode.asrModel`
  (`Sources/FoldWiseVoiceKit/Configuration/Config.swift`), parsed from
  `asr_model`. It is preserved on save but ignored — "this app always transcribes
  with Parakeet" — and its default value is a
  fossil from the app's Python/MLX era (`mlx-community/whisper-large-v3-turbo`),
  an id namespace meaningless to WhisperKit and FluidAudio. A round-trip test
  locks in that we don't clobber it
  (`testASRModelIsPreservedEvenThoughUnusedBySwiftApp`). The "Python app" it was
  kept compatible with is a **retired predecessor**, not a live co-target.
- The app already treats *model choice as global-by-convention* for the LLM:
  `setLLMModel` points every mode at one model and `Config.llmModel` reads the
  first (also in `Sources/FoldWiseVoiceKit/Configuration/Config.swift`), even
  though `llm_model` is a per-mode field.

Whether you need Whisper's languages is a property of *the language you speak* —
constant across Modes — whereas a Mode governs *output formatting/polish*. So ASR
model is naturally global, not per-mode.

## Decision

**Selection is global from the user's point of view, realized by reviving the
per-mode `asr_model` field and driving it exactly like the LLM model.**

- Add `Config.asrModel` (reads the first mode, like `llmModel`) and
  `setASRModel` (writes every mode, like `setLLMModel`). One field, one pattern;
  genuine per-mode ASR stays a latent, UI-only change for the future with **no
  further schema churn**.
- **Mint our own stable, human-readable catalog ids** (`parakeet-v3`,
  `whisper-large-v3-turbo`, `whisper-small`, …). A catalog maps id → (engine,
  WhisperKit variant / FluidAudio call, languages, size, speed/quality, blurb),
  mirroring the existing `ModelCatalog` for Ollama. The stored id is *our* key,
  independent of WhisperKit's internal model names.
- **Unknown id on load → fall back to the default engine (Parakeet) without
  overwriting the stored string** until the user explicitly picks. Old MLX
  fossils therefore degrade gracefully and are preserved passively — no migration
  script, no data loss for anyone who never touches the setting.
- **Fresh-install default is `parakeet-v3`** (fast, tiny, ANE, already warmed at
  launch), not the old MLX fossil. Whisper is strictly opt-in — nobody eats a
  1.5 GiB download unless they choose it.
- **Propagation follows ADR-0003.** A new `Config.ChangeSet.asrModel` member fires
  from `saveAndNotify`; the dispatcher subscribes via `config.onChange` and does
  the drop-before-load swap — the same shape as the hotkey listener reacting to
  `.hotkeys`. User actions in the Speech pane (Download / Select / Delete) route
  through explicit `SettingsController` callbacks, the ASR analogues of
  `onSelectModel` / `onInstallModel` / `onDeleteModel`.
- **Selection surface: a dedicated "Speech" pane** cloning `ModelsPane` — a
  curated ~4–5-entry, all-multilingual catalog (Parakeet v3/v2 + a Whisper size
  tier, no `.en` variants, no tiny/base), **language-led rows** ("~99 languages"
  vs "25 languages"), two-step Download-then-Select reusing the `pullFraction`
  progress bar, and delete-to-free-space via the kebab. Capabilities are
  hardcoded in the catalog with no runtime reconciliation — there is no GGUF to
  probe, and 5 curated entries don't warrant Handy's probe-and-reconcile
  machinery.

## Rejected alternatives

- **A new top-level `asr_model` field, leaving the per-mode fossil untouched.**
  Preserves the old-config contract most literally and keeps the existing
  round-trip test green, but introduces a **name collision** (top-level and
  per-mode `asr_model`, one live and one dead) and makes the per-mode field
  permanent dead weight — and it declines to reuse the LLM pattern the app
  already has.
- **Genuine per-mode ASR selection as a user feature now.** More flexible, but
  forces a Polish-speaking user to set the engine in every Mode, conflates the
  ASR axis with the polish axis, and adds an ASR picker to every Mode editor for
  a need we have no evidence of.

## Consequences

- `testASRModelIsPreservedEvenThoughUnusedBySwiftApp` becomes wrong — the field
  is no longer unused. It is **replaced** by tests for the new semantics:
  preserve-until-picked, then owns-the-field, and unknown-id-falls-back-to-Parakeet.
- Once a user picks a model, `setASRModel` overwrites the old MLX fossils across
  all modes. This only matters if they return to the retired Python app, which
  won't happen.
- Per-mode ASR, delete, and idle-unload (ADR-0005) are all reachable later
  without schema or seam changes.
