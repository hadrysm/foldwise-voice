# ADR-0009: Streaming is a selectable ASR model capability

## Status

Accepted (2026-07-27). Decided by wayfinder ticket #347 on map #339.

## Context

A Dictation session shows no text until the hotkey is released, and the batch
transcribe that then runs costs roughly 89 ms per second of audio. It does not
plateau: PRD #342 measured 1619 ms of transcription on the long fixture, making
ASR length-scaling the largest remaining cost against the locked
perceived-latency budget.

Research #344 evaluated every streaming path reachable without a dependency
bump and recommended treating live text as an *optional, disposable preview*
over a second resident model, leaving today's batch call authoritative. That
recommendation carried two costs. It required amending ADR-0005 to permit two
loaded engines, and it left ASR length-scaling entirely unfixed, because the
authoritative batch pass still ran over the whole buffer after release.

Research #343 established that Handy — the direct reference for this feature —
does not do that. Handy marks a model as streaming-capable, routes the
recorder's audio callback into a stream when a streaming model is selected, and
on release finalizes *that stream* as the text it pastes. Batch is its fallback,
not its authority. Its live text is the product, which is why it earns a place
on the insert path.

Two FluidAudio streaming models are viable finals in their own right. Measured
in #344 on an 11 s fixture: EOU 320 reached first text at 1.000 s and returned
its final at 11.030 s; Nemotron 560 reached 1.237 s and returned at 11.101 s.
Both finalize within roughly 30–100 ms of the last spoken sample.

## Decision

**Streaming is a property of an ASR model, not a preview bolted onto the
pipeline.** `ASRModelCatalog.Entry` already carries a `streaming` flag, stored
honestly from the engines' docs and so far inert. It becomes live.

A streaming model is an ordinary selectable ASR model. ADR-0006's selection,
availability, and Effective-ASR-model fallback semantics apply unchanged, and
the default remains `parakeet-v3`, which does not stream. No user gets streaming
without choosing it.

**When the Effective ASR model streams, its stream is authoritative.** Audio is
delivered incrementally during speech; on hotkey release the stream is finalized
and that result is the transcript — the input to Polish, the text recorded in
History, and the single atomic insertion. There is no second transcription pass
and no second authority.

Consequently **ADR-0005 is preserved, not amended.** Exactly one ASR engine
remains loaded; the streaming engine *is* the Effective one. Pipeline still
receives an opaque session handle and never learns a model identifier.

Four seams change, each additively:

1. **Record.** `AudioRecording` gains an incremental delivery hook alongside the
   existing final `stop()`. The tap already resamples to 16 kHz mono, and
   already retains the full buffer, so this adds a fan-out point rather than a
   path. A non-streaming model ignores it and behaves exactly as today. The hook
   must not run consumer code on the audio render thread and must not be invoked
   while the capture lock is held, because `AudioRecorder.stop()` acquires that
   lock second; delivery is therefore a non-blocking hand-off.

2. **Engine.** `Transcribing` is *refined*, not widened: a
   `StreamCapableTranscribing` refinement declares the streaming entry point, so
   the existing `Transcriber` and `WhisperTranscriber` conformers need no edits
   and capability is expressed in the type system rather than as a nil-returning
   method every adapter must remember. The lifecycle's session handle exposes
   capability as a yes/no question, never a model identity.

3. **Transcript state.** The adapter owns partial state and publishes snapshots
   of an append-only `committed` prefix plus a revisable `tentative` suffix,
   matching what the FluidAudio streaming managers already offer. Pipeline
   consumes and forwards; it does not accumulate.

4. **Presentation.** Snapshots reach the Live transcript caption on a dedicated
   Pipeline observer carrying the Dictation session id — a sibling of `onState`,
   not a new `PipelineState` case. `PipelineState` keeps its cases and its three
   exhaustive switch sites. This mirrors both Handy, whose overlay listens on its
   own event channel while the stream stays on the insert path, and FoldWise's
   own 30 Hz audio level, which already bypasses `PipelineState` for
   high-cadence audio-derived display data.

**A broken stream re-feeds, it does not truncate.** The streaming managers have
no batch mode and no other engine is resident, so the old degrade-to-batch net
does not exist. The recorder retains every sample regardless, so a failed stream
re-feeds the retained buffer through a fresh stream of the same model. Only if
that also fails does the session fall back to the confirmed prefix. Pasting the
confirmed prefix *first* is rejected: a truncated sentence looks complete and
the user may not notice missing words.

**Streaming sessions serialize.** A second Dictation session that overlaps a
still-processing one records without live preview and resolves through the same
re-feed path. This keeps one driver per engine, avoids relying on unverified
concurrent-manager behaviour, and preserves the state ordering
`PipelineAsyncBehaviorTests` pins.

**Two streaming models ship, honestly labelled**, so the trade is the user's:

- **EOU 320** — English, first text ~1.0 s, ~448 MB download, 287 MB peak
  footprint. Output is lowercase and unpunctuated. Under Polish that is
  invisible; under Voice to Text it is what lands in the app.
- **Nemotron 560** — English, first text ~1.24 s, ~627 MB download, 1.09 GB peak
  footprint, Apple Silicon only. Capitalizes and punctuates, so it stands alone
  without Polish.

## Consequences

- **Post-release ASR cost becomes flat.** A 60-second dictation finalizes as
  fast as a 5-second one, removing the length-scaling that #342 identified as the
  dominant remaining cost. This is the decision's main prize.
- **First feedback arrives during speech**, satisfying the budget's "from speech
  onset" framing rather than gaming it from release.
- **#344's "batch stays authoritative" conclusion is superseded for streaming
  models.** It still holds for every non-streaming model, which is all of
  today's roster.
- **The combined-RAM measurement #344 demanded is dissolved**, because two models
  are never resident. Single-model residency still needs measuring — Nemotron
  560's 1.227 GB max RSS is the number to justify.
- **Selecting a different model while recording now waits for the recording to
  end**, because a streaming session holds its handle for the whole capture
  rather than only after release. The lifecycle's existing cancellable drain
  covers the user-visible case.
- **English-only streaming is a real cliff** for a multilingual user who selects
  one. It is the same cliff `parakeet-v2` already presents, handled the same way:
  the catalog leads with language coverage.
- Voice to Text plus EOU 320 yields unpunctuated output. That combination is
  reachable and must read as an honest consequence of two explicit choices, not
  a bug.

## Rejected alternatives

- **A disposable preview on a side channel, batch still authoritative** (#344's
  recommendation). It leaves ASR length-scaling unfixed, needs two resident
  models, forces an ADR-0005 amendment, and creates two authorities for one
  transcript.
- **Widening `Transcribing` with an optional streaming method.** Every adapter
  would carry a nil-returning method, and capability would be a runtime fact the
  type system could not check.
- **A new `PipelineState` case per partial.** It pushes ASR-cadence updates
  through a pure Badge reducer and its resize path, and breaks the flat ordered
  state assertions that protect session serialization.
- **Making the catalog's `streaming` flag the runtime gate.** Two sources of
  truth. The adapter's capability is authoritative; the flag is what the Models
  pane renders, and a test asserts the two agree for every entry.
- **The WhisperKit `callback:` adapter** as a first increment. It yields partials
  only *after* release for a model whose final is batch anyway, so the caption
  would appear for a few hundred milliseconds and vanish. It was justified only as
  cheap plumbing toward a preview seam this decision does not build.
- **Nemotron or EOU as a hidden preview accelerator** beside a multilingual
  batch model. Silently swapping an English-only model under a multilingual
  selection is the dishonesty ADR-0006 exists to prevent.
