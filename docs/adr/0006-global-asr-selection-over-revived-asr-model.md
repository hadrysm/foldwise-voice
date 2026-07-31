# ADR-0006: ASR model selection is global and transactional

## Status

Accepted (2026-07-07). Amended (2026-07-16) for the user-managed Mode schema and
again (2026-07-18) by SPEC #179.

## Context

ASR model choice describes the language and recognition engine used before any
Mode-specific Polish behavior, so it is global. Config schema version 1 stores
that choice once as top-level `asr_model`.

A persisted choice is not proof that its model data is usable. Data may be
missing, partial, corrupt, deleted externally, or associated with an identifier
a newer build does not recognize. Persisting a candidate before it loads can
also leave Config and the runtime disagreeing. Availability, stored intent, and
the model safe to use for the next Dictation session must therefore remain
distinct facts.

## Decision

Config remains the sole persistence and typed change-propagation owner for the
global **ASR model selection**. `ASRModelLifecycle` is the sole requester of ASR
selection changes; Settings cannot write `asr_model` directly.

Selection is an exclusive, cancelable transaction:

1. wait for active transcription handles to release and block new capture;
2. release the old engine before constructing the candidate;
3. prepare the candidate engine;
4. persist the new selection through Config only after activation succeeds; and
5. publish the committed snapshot and resume Dictation sessions.

Candidate-load, persistence, or cancellation failure restores the previous
engine while leaving the previous persisted selection intact. If restoration
fails, the lifecycle attempts the default Parakeet fallback and publishes a
typed degraded failure. If the fallback also fails, recognition remains
blocked. No transition owns two loaded engines.

The lifecycle snapshot distinguishes the stored **ASR model selection** from
the **Effective ASR model**. A known selection with unavailable data remains
stored while Parakeet is effective. An unrecognized stored identifier is also
preserved, named in recovery state, and does not create a synthetic catalog row.
Fallback becoming effective never rewrites Config. A later successful repair
makes the stored selection effective again without another selection write,
warming it when active sessions no longer hold the fallback engine.

**ASR model availability** comes from each adapter's validation of its real
local model data. Directory existence is insufficient; missing, incomplete,
corrupt, or unrecognized data is unavailable. Availability is reconciled at
launch, when Settings opens, after every lifecycle operation, and after an
engine load failure. Canceled downloads may retain safe library-managed partial
data for retry, but partial data is never reported as available.

Download and selection remain separate actions. Optional download is
storage-only and preserves both stored and effective selection. Only one ASR
management operation runs at a time.

Optional deletion is ordered by the lifecycle. The default Parakeet model
cannot be deleted. Deleting the selected optional model first commits Parakeet
for future sessions, waits for every handle using the old model to release,
unloads it, and then removes its data. A disk-removal failure after the fallback
commit leaves the old model available but unselected; the selection is not
rolled back. Non-selected deletion likewise waits only for handles using that
model.

Schema version 1 is unchanged. It stores the global selection only. Availability,
effective fallback, loaded-engine state, progress, and failures are runtime
facts: there is no availability manifest and no migration.

## Consequences

- Settings keeps the curated Download-then-Select presentation while rendering
  lifecycle descriptors and one immutable snapshot.
- Unknown and unavailable selections preserve user intent without sacrificing a
  safe default.
- Config and the loaded engine cannot expose a committed selected-new/loaded-old
  state.
- Repair, fallback, and deletion remain truthful after relaunch because adapters
  validate local data rather than reconstructing availability from Config.
- The domain terms in `CONTEXT.md` remain presentation-neutral and contain no
  implementation ownership details.

## Rejected alternatives

- **Persist before loading.** A failed candidate would make Config claim a model
  that never became active.
- **Persist the effective fallback.** It silently destroys the user's stored
  intent.
- **Treat a model directory as availability.** Partial or corrupt data can still
  be unusable.
- **Persist an availability manifest.** It creates a second source of truth and
  requires schema work without improving adapter validation.
- **Delete selected data before committing fallback or draining sessions.** It
  can break current transcription and leave future sessions without a valid
  selection.
