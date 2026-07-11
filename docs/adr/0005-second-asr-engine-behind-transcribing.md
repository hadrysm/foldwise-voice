# ADR-0005: A second ASR engine (WhisperKit) lives behind the `Transcribing` seam, fronted by a dispatching composite

## Status

Accepted (2026-07-07)

## Context

Today the app transcribes with exactly one engine — Parakeet TDT v3 (FluidAudio)
on the Neural Engine — behind the `Transcribing` protocol introduced by ADR-0002
(`Pipeline.swift:21`). We want a second engine, Whisper, to widen language
coverage from Parakeet's 25 to Whisper's ~99 and make that breadth a visible
selling point (see `CONTEXT.md`: *ASR engine*, *ASR model*). FluidAudio has no
Whisper backend and no engine abstraction to ride — it is Parakeet-only — so a
second engine means a second conformer plus the machinery to choose, load, and
provision it.

Three questions had to be answered together: which Whisper library, who owns the
now-plural model lifecycle, and how the `Pipeline` stays ignorant of all of it.

The reference multi-engine app (Handy) dispatches engines with an `enum` +
`match` rather than a trait, but only because it adapts two foreign Rust crates
with incompatible option types — a constraint we do not have, since we write our
own conformers.

## Decision

**Keep the `Transcribing` protocol; add a second conformer; front both with a
dispatching composite that is itself a `Transcribing`.** The `Pipeline` keeps
calling `transcriber.transcribe(_:)` and never learns there is more than one
engine — the composition root (`AppMain.swift:81`) constructs the dispatcher in
the one place ADR-0002 already put engine construction.

- **Whisper backend → WhisperKit** (`argmaxinc/argmax-oss-swift`, product
  `WhisperKit`, pinned `from: "1.0.0"`; the repo was renamed from
  `argmaxinc/WhisperKit` at v1.0.0, 2026-05-01). It is the structural twin of
  FluidAudio: pure-Swift, CoreML on the ANE, MIT, macOS 14+, and its
  `transcribe(audioArray: [Float])` takes our recorder's `[Float]@16 kHz` buffer
  verbatim. Like FluidAudio it **auto-downloads weights from Hugging Face on
  first load**, so it needs no bespoke download stack. It runs **in-process** —
  the FluidAudio pattern, not the out-of-process Ollama pattern.

- **The dispatcher owns the model lifecycle: one engine loaded at a time, and
  the old engine is dropped before the new one is built.** Whisper large-v3-turbo
  is ~1.5 GiB on top of Parakeet's ~600 MB; drop-before-load is the only thing
  that stops a switch from putting ~2 GiB resident at once. It is **mandatory,
  not an optimization.**

- **The `Transcribing` seam gains a fractional download-progress channel.** The
  boolean `onLoading` is enough for Parakeet (usually already downloaded) but
  reads as a hang during Whisper's multi-minute first download. The seam carries
  *optional* progress; engines that cannot report it (FluidAudio may only flip
  the boolean) degrade to the existing spinner, and `Pipeline` maps progress to a
  new `downloadingModel(fraction:)` HUD state.

- **Idle-unload is deliberately deferred.** It would re-introduce load latency
  the app doesn't have today, fights the launch `warmup()` that makes the first
  dictation instant, and adds a timer/threading surface. Drop-before-load ships;
  idle-unload waits for evidence of real memory pressure.

## Rejected alternatives

- **Handy's `enum LoadedEngine` + parallel `match` blocks.** That is a workaround
  for two foreign crates whose option structs won't unify. In Swift each
  conformer keeps its per-model options private behind the protocol, so the enum
  buys nothing and costs "edit N match arms per new engine."
- **whisper.cpp XCFramework (Metal/GGUF).** Its only real wins — GGUF
  quantization control and Handy model-parity — don't serve a language-coverage
  driver, and they cost a hand-written C bridge plus our own
  download/storage/verification (WhisperKit gives that for free). Its one perf
  edge (memory via quantization) is on an axis press-to-talk dictation doesn't
  cash in; on the axis that matters for a laptop — power efficiency — the ANE
  path (WhisperKit) wins.
- **SwiftWhisper.** Stale since 2023 (vendors a pre-large-v3-turbo whisper.cpp);
  fine for a throwaway spike, not a foundation.
- **Apple SpeechAnalyzer / SFSpeechRecognizer.** SpeechAnalyzer is macOS 26+ only
  (below our floor; a future `#available`-gated adapter at best);
  SFSpeechRecognizer caps tasks at ~1 minute, fighting open-ended dictation.

## Consequences

- Adding a *third* engine later is one new conformer + one catalog entry + one
  dispatcher arm — no `Pipeline` change, because the seam already hides plurality.
- `Transcribing`'s test double (ADR-0002) must grow the progress channel, and the
  `Pipeline`→HUD mapping gains `downloadingModel(fraction:)`. The seam remains the
  app's transcribe-stage test surface.
- The "nothing leaves your machine" story is unchanged: the only new network
  touch is WhisperKit's one-time weight download from Hugging Face — the same
  posture as the existing Parakeet download and the daily update check.
- Selection and provisioning UX are specified in ADR-0006.
