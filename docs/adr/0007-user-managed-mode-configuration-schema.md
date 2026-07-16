# User-managed Modes use a versioned ordered configuration schema

## Status

Accepted (2026-07-16). Amended (2026-07-16) by the cross-surface Mode lifecycle
decision: invalid configuration now enters a read-only recovery state, Mode-name
normalization collapses internal whitespace, and duplicate suggestions use a
capitalized `Copy` suffix.

FoldWise's initial public configuration lives in `config.json` with required
`schema_version: 1`. It stores editable Modes as one ordered array, gives each
Mode an immutable UUID independent of its unique mutable name, and represents
the Dictation selection explicitly as either Voice to Text or a Mode UUID.
Voice to Text is a permanent system selection outside the Mode array. Array
position is the sole display and cycle order; fresh configuration contains
Casual followed by Email, with Casual selected.

Each Mode requires a curated SF Symbol name, its own Ollama model reference, an
`in_place` or `expanding` transformation, a non-empty system prompt, and an
ordered vocabulary array. Model references remain valid when the model is not
installed, allowing Polish to fall back to raw text without rewriting the Mode.
The global ASR model moves to the top level as amended by ADR-0006, because a
valid library may contain zero Modes.

Mode names are canonically Unicode-normalized for storage after trimming outer
whitespace and collapsing internal whitespace runs. Uniqueness comparison is
case-insensitive but accent-sensitive while preserving the cleaned display
spelling. Duplicate drafts propose `<name> Copy`, then the lowest available
numbered suffix such as `<name> Copy 2`; duplicating an already suffixed name
continues that sequence.

Persistence uses strict versioned DTOs: unknown keys, missing required fields,
wrong types, invalid enum values, duplicate or malformed Mode IDs, non-unique
normalized names, and dangling active Mode IDs invalidate the whole file. Writes
are deterministic and atomic. Config-owned mutations validate and persist a
complete candidate before swapping live state or notifying observers, as
amended by ADR-0003. Missing files create defaults; invalid or unsupported files
remain untouched while the app enters the Configuration recovery state: only
Voice to Text is usable with built-in runtime defaults, and the entire
configuration is read-only. Settings presents the recovery cause and offers
Reset or Quit. An explicit reset preserves the original as a timestamped backup
before atomically writing fresh defaults.

There is no migration or backward-writing contract for the pre-release
name-keyed `modes.json` shape. Dual-writing was rejected because competing
representations would permit an older writer to discard stable identities and
per-Mode behavior.
