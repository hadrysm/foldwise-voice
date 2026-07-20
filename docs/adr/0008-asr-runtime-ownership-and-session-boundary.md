# ADR-0008: ASR lifecycle separates artifact storage from runtime sessions

## Status

Accepted (2026-07-20) by issue #198. Extends ADR-0005 and supersedes
ADR-0006 only where it keeps ASR selection in Config schema version 1.

## Context

FoldWise's first independent ASR catalog baseline has seven ASR models, exact
artifact profiles, two in-process Core ML runtimes, and four materially different
execution paths. Parakeet Unified and multilingual Nemotron expose truthful
native streaming, while sliding-window Parakeet and the selected Whisper profiles
remain batch. The existing `ASRModelFamilyAdapting` seam combines storage,
validation, raw string routing, and engine construction, and its single
`Transcribing.transcribe([Float])` call cannot represent session-scoped streaming
without leaking runtime state into Pipeline.

The architecture must preserve the existing invariants: one application-facing
ASR owner, one loaded engine, exact selection captured at Dictation-session start,
transactional activation, local recognition, and no model or runtime details in
Pipeline.

## Decision

### Ownership and internal planes

`ASRModelLifecycle` remains the sole application-facing ASR owner shared by
Settings, Badge, and Pipeline. Pipeline receives only an opaque captured session
capability; Settings and Badge observe lifecycle snapshots and request lifecycle
operations. None of them owns catalog routing, artifact state, runtime objects,
or load timing.

The lifecycle coordinates two separate internal planes:

- The **artifact plane** installs, verifies, repairs, and removes exact ASR
  artifact profiles without constructing an engine. A FoldWise-owned repository
  performs isolated staging, complete byte/SHA-256 verification, atomic
  promotion, deletion, and storage accounting. Small runtime-specific verifiers
  add semantic checks that hashes cannot prove, such as Core ML loadability and
  tokenizer or package layout. Upstream convenience downloaders may transport a
  pinned artifact but never define its identity, completeness, availability, or
  location.
- The **runtime plane** receives a verified local profile and constructs a
  loaded `ASREngine`. `FluidAudioRuntimeAdapter` and
  `WhisperKitRuntimeAdapter` are the only library-coupled boundaries. Beneath
  them, execution drivers match the real API shapes: sliding-window Parakeet,
  Unified streaming, a FoldWise-owned multilingual Nemotron streaming wrapper,
  and WhisperKit batch. The sliding-window and Whisper drivers are parameterized
  by their reviewed profiles rather than duplicated per catalog row.

Installation integrity, catalog visibility, artifact release eligibility, ASR
device eligibility, ASR model availability, stored selection, and effective
execution remain separate facts. The artifact plane reports integrity; the
lifecycle combines it with catalog policy, device evidence, and runtime health
to derive availability.

### Identity and capabilities

Catalog and lifecycle APIs use opaque string-backed identities:

- `ASRModelID` is FoldWise's stable source-model identity.
- `ASRArtifactProfileID` is stable and scoped to one ASR model.
- `ASRSelection` is the exact model/profile pair.
- `ASRRuntimeID` is internal catalog routing and is never persisted as user
  intent.

Unknown persisted identities remain representable. Runtime repository names,
folders, checkpoints, model versions, and execution-driver routes are profile
metadata rather than domain identity. Runtime adapters no longer advertise
duplicated sets of raw model identifiers.

Capabilities belong to the exact artifact profile. Each profile declares its
reviewed batch or native-streaming recognition mode, locales, translation
support, and any streaming-context facts. Runtime adapters must implement this
declaration and cannot broaden it from incidental upstream APIs. In particular,
WhisperKit's repeated-buffer microphone helper does not make the three reviewed
Whisper profiles native streaming profiles.

### Engine and recognition-session boundary

`ASREngine` represents the heavyweight loaded weights and is owned by the
lifecycle. It vends one per-Dictation `ASRRecognitionSession`, which owns decoder
and stream state. Every profile uses the same session-shaped boundary:

- `feed`, `finish`, and `cancel` are commands serialized by the session.
- One ordered asynchronous event sequence emits zero or more transcript updates
  followed by exactly one completed, cancelled, or failed terminal event.
- Native-streaming profiles may emit truthful whole-text updates. Batch profiles
  buffer accepted audio and emit no updates before completion.
- Runtime failures become the terminal failed event instead of competing command
  errors. Session creation may fail before an event sequence exists.
- Finish and cancel are idempotent, the first terminal transition wins, and no
  command has an effect after terminal.
- Cancelling an event consumer does not implicitly cancel recognition; the
  lifecycle-lease owner explicitly cancels and releases the session.

Baseline 1 executes exactly one recognition session at a time per loaded engine.
The lifecycle may retain multiple captured leases for queued Dictation sessions,
but a lifecycle-owned FIFO admission gate serializes driver access. Neither the
same stateful manager nor another engine runs concurrently. Each driver resets
or discards its session state before admitting the next session; failure to do so
is a fatal engine fault. Concurrency may expand only after the exact runtime path
proves multi-session safety.

### Lease, replacement, and residency policy

At Dictation-session start, the lifecycle captures the exact Effective ASR model
and profile. Its lease retains the loaded engine and owns the recognition session
until the terminal event and explicit release, before Polish and insert. A later
selection applies only to later Dictation sessions.

Switch, restoration, selected-profile deletion, and selected-profile repair are
exclusive operations:

1. Block new captures.
2. Let existing sessions finish or be cancelled by their callers; management
   never forcibly cancels an active Dictation session.
3. Wait for every lease on the loaded engine to release.
4. Drop the engine and yield teardown.
5. Load and prewarm the exact replacement profile.

This drain-then-drop-before-load order is mandatory. Failed activation restores
the previous exact engine when possible, then the exact default Parakeet fallback,
without rewriting stored intent.

The successful exact engine stays warm across idle periods. Baseline 1 has no
timer-based or ordinary memory-pressure unload. Downloads, repairs, profile
preference changes, validation, and storage accounting never load an engine.
Unload occurs only for an exclusive replacement, selected-profile deletion or
repair, a runtime-declared fatal engine fault, or shutdown. An individual failed
recognition session does not automatically poison its engine.

### Config persistence

Config remains the sole persistence and typed change-propagation owner. Config
schema version 2 stores the exact global model/profile selection and a sparse map
of per-model artifact-profile preferences; an absent preference means the
catalog's curated default. Runtime routes, eligibility, availability, effective
fallback, loaded state, progress, and failures are never persisted.

A recognized schema-1 `asr_model` value migrates to that baseline model's curated
default profile. An unknown schema-1 model identifier remains unresolved legacy
intent without an invented profile until the user explicitly chooses an eligible
pair. Unknown schema-2 model, profile, and preference values round-trip unchanged.
Profile preference changes and downloads never activate a profile; only a
successful explicit Use transaction commits a new exact selection.

This schema-2 migration supersedes ADR-0006's prior schema-version posture for
ASR selection. It does not add a persisted availability manifest.

## Consequences

- The one-resident-engine invariant has one owner and one enforceable replacement
  sequence even as native streaming is added.
- Pipeline tests fake a session provider and event contract; lifecycle tests fake
  artifact and runtime planes; execution-driver tests remain focused on pinned
  third-party APIs.
- A new reviewed profile normally adds catalog and artifact data. A new API shape
  adds an execution driver; a new library adds one runtime adapter. Settings and
  Pipeline ownership do not change.
- The downstream end-to-end streaming decision may choose how queued recording,
  audio buffering, and Badge presentation react to FIFO admission without
  reopening runtime ownership.

## Rejected alternatives

- **Keep one combined family adapter.** Storage may proceed while another engine
  is warm, whereas runtime loading is exclusive; combining the planes obscures
  that difference and conflates installed data with availability.
- **One adapter per catalog row.** It duplicates library and storage policy while
  hiding that seven rows reduce to two libraries and four execution shapes.
- **Expose separate batch and streaming APIs to Pipeline.** It makes Pipeline
  branch on catalog/runtime capability and duplicates terminal semantics.
- **Run multiple sessions against one manager.** The pinned stateful runtimes do
  not establish multi-stream safety.
- **Load a candidate before releasing the current engine.** It violates the
  resident-memory invariant.
- **Keep schema 1 and infer profiles at runtime.** It cannot preserve exact Use
  intent or per-model preference and lets catalog changes silently alter the
  effective profile.
- **Persist runtime or library identifiers.** They couple durable user intent to
  replaceable implementation details.
