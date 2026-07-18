# ADR-0002: Pipeline dependencies are hybrid seams; the composition root owns construction

## Status

Accepted (2026-07-03). Amended (2026-07-10): issue #123 extracted audio-duck
coordination after an in-flight duck could outlive a superseding restore.
Amended again (2026-07-18) by PRD #179: Pipeline captures opaque ASR session
handles instead of observing a transcriber's loading lifecycle.

## Context

The Pipeline module sequences a dictation session (record → transcribe →
polish → insert) and drives the `onState` machine behind the HUD and menu-bar
icon. Historically it constructed all of its collaborators itself —
`AudioRecorder`, `Transcriber`, and the static `OllamaClient` / `TextInserter`
— so its interface could only run with a live microphone, a ~600 MB ASR model,
a running Ollama, and the real pasteboard plus a synthetic Cmd+V. The session
state machine — silence-skip, transcribe, LLM-polish fallback, insert, the
`onState` emissions, and silent double-tap queueing — therefore had zero test
coverage (issue #42).

The obvious fix (issue #42 as written) was to give each of the four
collaborators a protocol with two adapters, real and fake. But the four
collaborators are not alike:

- `polish` and `insert` are pure-ish functions — text in, result out — reached
  only by Pipeline.
- `record` carries state reached from outside Pipeline because Badge polls the
  recorder's level. Transcription is session-scoped: Pipeline captures an
  opaque handle from the ASR lifecycle and releases it after the transcribe
  Stage.
- The audio ducker emits no state the machine reads.

## Decision

Inject Pipeline's dependencies as **hybrid seams**, matched to each
collaborator's actual shape:

- **Closures for the pure stages** (`polish`, `insert`), with production
  defaults — mirroring the boundary-closure injection `TextInserter.insert`
  already uses (`trusted:`, `postPaste:`).
- **Small protocols for the stateful stages.** `AudioRecording` exposes capture.
  `ASRSessionHandleProviding` captures a session-scoped transcription handle;
  Pipeline sees neither model identifiers nor loading/selection callbacks.
  Concrete engines remain behind the lifecycle's internal `Transcribing` seam.
- **Pipeline owns the "am I recording" flag** rather than reading it back
  through the record seam, so the guards are self-contained and a fake recorder
  needn't track it.
- **The composition root (`AppMain`) constructs the concrete adapters**, shares
  the single `AudioRecorder` between Pipeline and Badge, and starts the shared
  ASR lifecycle. Pipeline no longer constructs collaborators.
- **Audio ducking uses a small command seam.** `Pipeline` injects `AudioDucking`,
  while `AudioDuckCoordinator` injects the multi-operation system-effects
  boundary. This keeps AppleScript execution in a thin adapter and makes the
  ordering and restoration guarantee observable without changing real audio.

## Rejected alternative: a uniform protocol + two adapters per seam (issue #42 as written)

Forcing all four collaborators into protocol/real/fake triples adds ceremony to
`polish`/`insert` that buys nothing, diverges from the boundary-closure
precedent already in the codebase, and still would not cover the ducker.
Uniformity was rejected in favour of matching each seam's mechanism to its
shape.

## Consequences

- The Pipeline interface becomes its own test surface: a fake-driven session
  drives `startRecording()` / `stopRecording()` and asserts the `onState`
  sequence (silence-skip, empty transcript, transcribe error, LLM-fallback
  threshold, and inserted vs clipboard). ASR management state is tested and
  observed through lifecycle snapshots instead.
- An internal `awaitPendingJob()` lets tests drain the chained-`Task` job queue
  deterministically, making silent double-tap queueing assertable.
- Follow-up work (the OllamaClient transport seam, HotkeyListener) gets smaller,
  since construction has already moved to the composition root.
