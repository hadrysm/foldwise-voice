# ADR-0005: The ASR lifecycle owns multiple engine families

## Status

Accepted (2026-07-07). Amended (2026-07-18) by SPEC #179.

## Context

FoldWise supports Parakeet through FluidAudio and Whisper through WhisperKit.
Both libraries can keep hundreds of megabytes or more of model state resident,
so switching engines must never overlap their loaded state. Model data on disk
is different: several models may be downloaded without being loaded.

The original decision put engine choice and replacement in a `Transcribing`
composite. Settings then prepared a separate engine to download model data.
That split allowed two engines to load at once and left no single owner for
availability, selection, effective fallback, management operations, and active
Dictation sessions.

## Decision

One actor-owned `ASRModelLifecycle` is the application seam for ASR model
management and use. The composition root creates one instance and shares it
with Settings and Pipeline.

The lifecycle owns:

- catalog resolution and adapter selection;
- adapter-validated local availability;
- the sole loaded ASR engine;
- serialized download, selection, repair, retry, and deletion operations;
- typed failures and one immutable observable snapshot; and
- session capture, release, waiting, cancellation, and recovery.

Parakeet and Whisper remain internal engine-family adapters. Each adapter owns
its library identifiers, local path resolution, complete-data validation,
storage-only download, safe deletion, and concrete engine construction. This is
the only layer coupled to FluidAudio or WhisperKit.

Optional downloads are storage-only. They change availability without selecting
or loading the model and may run while dictation uses the warm engine. The
default Parakeet bootstrap is the sole automatic download; it blocks dictation
and publishes progress through the lifecycle snapshot.

Pipeline never receives model identifiers, catalog entries, engine-loading
callbacks, or concrete engines. At recording start it captures an opaque
session-scoped handle for the Effective ASR model. The handle retains that
engine through transcription and is released on every transcription completion
path, before Polish and insert. A later global selection therefore applies only
to later Dictation sessions, including sessions already queued with their own
captured handles.

Engine replacement is exclusive. Existing transcription finishes, new capture
is blocked, the old lifecycle-owned engine is released, and only then is the
candidate constructed and prepared. The lifecycle resumes capture after a
working engine is active or exposes a blocked failure. This drop-before-load
ordering is mandatory and enforces one loaded engine at a time. The successfully
selected effective engine stays warm while idle; idle unload remains deferred.

Settings and Badge observe lifecycle snapshots. Optional download progress stays
in Settings. Badge presents only lifecycle states that genuinely block
dictation, such as default bootstrap, switching/restoration, or recognition
unavailability.

## Consequences

- There is one production ASR lifecycle path and one owner of loaded engine
  state.
- Downloaded model data may coexist on disk without violating the one-engine
  invariant.
- Pipeline tests fake the session-handle provider; lifecycle tests fake both
  engine-family adapters; real adapter tests stay focused on library coupling.
- Adding another engine family means adding an adapter and catalog descriptors,
  without changing Pipeline or Settings ownership rules.
- WhisperKit remains the Whisper implementation chosen by the original ADR; ASR
  remains in-process and on-device after model download.

## Rejected alternatives

- **Settings-owned engine preparation for downloads.** It duplicates lifecycle
  ownership and can load a second engine.
- **Selection callbacks passed through Pipeline.** They expose lifecycle timing
  to a stage that only needs an opaque transcription capability.
- **Loading a candidate before dropping the current engine.** It violates the
  mandatory resident-memory invariant.
- **Idle unload.** It adds latency and scheduling complexity without evidence of
  a product need.
