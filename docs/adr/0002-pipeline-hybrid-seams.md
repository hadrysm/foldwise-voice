# ADR-0002: Pipeline dependencies are hybrid seams; the composition root owns construction

## Status

Accepted (2026-07-03)

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
- `record` and `transcribe` carry state the machine reads (`isRecording`;
  `ready` + `onLoading`) and are reached from *outside* Pipeline: the HUD polls
  `recorder.level`, and AppMain calls `transcriber.warmup()`.
- The audio ducker emits no state the machine reads.

## Decision

Inject Pipeline's dependencies as **hybrid seams**, matched to each
collaborator's actual shape:

- **Closures for the pure stages** (`polish`, `insert`), with production
  defaults — mirroring the boundary-closure injection `TextInserter.insert`
  already uses (`trusted:`, `postPaste:`).
- **A small protocol each for the stateful stages** (`AudioRecording`,
  `Transcribing`). `Transcribing` mirrors `Transcriber`'s full surface
  (`ready`, `onLoading`, `warmup`, `transcribe`) precisely because the
  asynchronous `.loadingModel` dance is the highest-value untested behavior.
- **Pipeline owns the "am I recording" flag** rather than reading it back
  through the record seam, so the guards are self-contained and a fake recorder
  needn't track it.
- **The composition root (`AppMain`) constructs the concrete adapters** and
  shares the single `AudioRecorder` instance between Pipeline and the HUD, and
  calls `warmup()` — so HUD level-metering and launch warmup are unchanged.
  Pipeline no longer news up its own collaborators.
- **The audio ducker is deliberately not a seam.** It emits no observable
  state; tests set `pauseAudio = false`, leaving it inert (it guards `ducked`
  before any `osascript`, so it spawns nothing).

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
  threshold, inserted vs clipboard, and the loading-model dance).
- An internal `awaitPendingJob()` lets tests drain the chained-`Task` job queue
  deterministically, making silent double-tap queueing assertable.
- Follow-up work (the OllamaClient transport seam, HotkeyListener) gets smaller,
  since construction has already moved to the composition root.
