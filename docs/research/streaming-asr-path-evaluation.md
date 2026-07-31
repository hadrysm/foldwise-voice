# Streaming ASR path evaluation

Audit date: 2026-07-27<br>
Issue: [#344](https://github.com/hadrysm/foldwise-voice/issues/344), under
[Wayfinder map #339](https://github.com/hadrysm/foldwise-voice/issues/339)<br>
Repository baseline: `2ec7c7639a86970719f6c595073b3dae1def1ced`<br>
Dependency baseline: FluidAudio 0.15.4 at
`b9d43724cbdb5a980e441fd54180964e94d470f7`; argmax-oss-swift 1.0.0 at
`25c62997041c134b03ca82731ce2f6fd2cae1eb9`
([Package.resolved:4-20](../../Package.resolved#L4-L20)).

## Executive answer

None of the four paths is simultaneously live, model-neutral, accuracy-neutral,
and compatible with the current one-loaded-engine rule.

- WhisperKit's `callback:` is the safest additive path, but in FoldWise it starts
  only **after hotkey release** because the app supplies the completed `[Float]`
  buffer to `transcribe` after `recorder.stop()`. It can improve feedback during
  the post-recording decode, not show a transcript while the user is speaking
  ([Pipeline.swift:225-262](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L225-L262),
  [WhisperTranscriber.swift:155-167](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/WhisperTranscriber.swift#L155-L167)).
- FluidAudio's default `SlidingWindowAsrManager` does **not** trail by merely its
  2 s right context. Its first normal update waits for the 11 s center chunk plus
  2 s right context: **13 s of captured audio, then inference**. A shorter
  dictation produces no update until `finish()`. The advertised 1–2 s
  `hypothesisChunkSeconds` is stored but never used by the manager's processing
  loop
  ([SlidingWindowAsrManager.swift:346-383](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift#L346-L383),
  [SlidingWindowAsrManager.swift:710-768](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift#L710-L768)).
- The cache-aware FluidAudio managers are the only pinned paths with a
  sub-second architectural emission cadence. On the reference M1 Pro, a
  prewarmed EOU 320 manager produced first non-empty text at **1.000 s**; a
  prewarmed Nemotron 560 manager took **1.237 s**, and a prewarmed Unified
  2080 manager took **3.201 s**. They require separate, English-only model
  artifacts and cover FluidAudio, not the selected Whisper models
  ([ParakeetModelVariant.swift:14-40](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift#L14-L40),
  [ParakeetModelVariant.swift:56-78](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift#L56-L78)).
- VAD can mark speech start/end and trim silence, but it never supplies text. It
  is an adjunct to a preview path, not a preview path
  ([VadManager+Streaming.swift:5-27](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/VAD/VadManager%2BStreaming.swift#L5-L27),
  [VadTypes.swift:189-217](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/VAD/VadTypes.swift#L189-L217)).

**Recommendation:** keep the captured Effective ASR model's existing batch call
as the authoritative final transcript and make preview an optional capability
on the lifecycle-owned session handle. A missing or failed preview must silently
fall back to that batch call. Use the Whisper callback first to build and test
the partial-delivery/Badge plumbing, while documenting that it is post-release
feedback. For true during-speech English preview, prototype **Parakeet EOU
320 ms** first: it reached visible text 237 ms before Nemotron on the probe and
its standalone peak physical footprint was about **287 MB**, versus about
**1.09 GB** for Nemotron. EOU's preview loses punctuation/capitalization, but
the authoritative batch final restores it. Do not ship the default
sliding-window path as the live preview and do not add a second resident
streaming model without first amending ADR-0005 and measuring the combined
FoldWise footprint.

## What “latency” means in this comparison

The architectural number is the earliest point at which source code permits an
update: a buffer/window gate plus inference. Practical latency also includes
recorder delivery, actor/task scheduling, Core ML execution, and token
availability. The measurements below cover those components in a standalone
dependency probe, but not the Pipeline's queued-job wait or Badge rendering.

The probe used WhisperKit's first-party 11-second `jfk.wav` fixture, delivered
in real time to each pinned manager on a MacBook Pro 18,1 (M1 Pro, 16 GiB,
macOS 26.5). True-streaming managers received 80 ms buffers; each buffer was
withheld until its audio end-time, then processed before the next deadline.
Each manager received a 3.2-second silent warm-up and `reset()` before the
timed run. TDT sliding-window received 250 ms buffers. WhisperKit received the
complete buffer, matching today's post-release batch call. Times are single
directional observations, not p50/p95 ship thresholds.

Memory came from macOS `/usr/bin/time -l` around a release-built standalone
process. “Peak footprint” is the reported peak physical memory footprint;
maximum RSS is also retained in the table. These numbers include the candidate
manager but **not** a simultaneously resident FoldWise batch engine, Badge, or
Polish model, and Core ML may place/mmap weights outside ordinary process RSS.
They establish relative cost on this Mac, not the combined app budget.

First-party FluidAudio model cards do publish model-level WER/RTFx runs on
specific hardware, but those are not integrated FoldWise latency or memory
measurements. For example, the EOU card reports an Apple M2 LibriSpeech run, and
the pinned Nemotron documentation reports an Apple M5 Pro 100-file run; the
different machines, sample counts, and paths make their WER values unsuitable
as a direct cross-model ranking
([EOU CoreML model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/blob/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355/README.md),
[Nemotron.md:13-33](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Documentation/ASR/Nemotron.md#L13-L33)).

## Comparison

| Path | Earliest architectural partial | Final accuracy versus current batch | Extra download / RAM | Engine and language coverage | Can current batch remain authoritative? |
| --- | --- | --- | --- | --- | --- |
| WhisperKit `callback:` | Only after recording stops in today's Pipeline. On Whisper small, first user text arrived **1.708 s after the 11 s buffer entered `transcribe`**; final returned at 2.112 s. Callback iterations were token-granular. The 30 s Whisper window does not mean waiting for 30 s of live audio. | Same transcription invocation and decoder result when the callback returns `nil`/`true`; no final-quality change by construction. The probe matched the reference words. Callback text is provisional. | **0 MB** new model data. Standalone Whisper-small peak footprint / max RSS: **473.9 / 472.7 MB**. This is the existing engine cost, not incremental callback cost. | Existing Whisper selections only. No Parakeet preview. | **Yes — already the same batch call.** Ignoring a callback failure leaves the current result path intact. |
| FluidAudio `SlidingWindowAsrManager` | Default gate is **13 s + inference** (11 s chunk + 2 s right context). The 11 s fixture therefore emitted only while flushing at **11.751 s**, 751 ms after release. A quality-risking 1 s chunk emitted first text at 3.020 s. | Default-window final matched the reference. The 1 s-window final degraded to “And so, my fellow Americans! Ask not! … Ask what you your.” `finish()` is still a different merge path from FoldWise's current batch call. | **0 MB** new weights if selected TDT `AsrModels` are reused. Standalone default-window peak footprint / max RSS: **39.6 / 82.5 MB** after Core ML caches were warm. | FluidAudio Parakeet TDT v2/v3 only. No Whisper preview. | **Yes in product shape, not through the current manager API:** retain the full recorder buffer and run the existing batch engine after stop. |
| `StreamingAsrManager`: Parakeet EOU | The 320 tier first buffers 630 ms and shifts 320 ms. The prewarmed probe's first non-empty partial arrived at **1.000 s** after 960 ms of audio had been delivered; final returned at 11.030 s. | The reference words were all present, but lowercased and unpunctuated, as expected. Official M2 model-card WER is 8.29% at 160 ms and 4.87% at 320 ms on LibriSpeech test-clean; one fixture does not establish app WER. | Logical required set: **224.0 / 224.2 / 224.5 MB** for 160/320/1280. The pinned downloader actually selects **449.2 / 447.8 / 438.9 MB**; see Artifact cost. EOU 320 standalone peak footprint / max RSS: **287.2 / 462.4 MB**. | FluidAudio only; English-only, no punctuation/capitalization. | **Yes only as a separate additive preview.** That entails a second model resident beside the captured Effective ASR model unless policy changes. |
| `StreamingAsrManager`: Nemotron | Complete 560, 1120, or 2240 ms chunks, then inference. The prewarmed 560 probe's first non-empty partial arrived at **1.237 s** after 1.120 s of audio; final returned at 11.101 s. | The reference words were all present with capitalization/punctuation, though the sentence boundary differed from the TDT batch reference. Pinned FluidAudio reports 2.28% WER at 560/1120 ms and 2.46% at 2240 ms on 100 test-clean files; no same-run corpus comparison exists. | **626.4 / 626.8 / 627.5 MB** required/downloaded for 560/1120/2240. Nemotron 560 standalone peak footprint / max RSS: **1.092 / 1.227 GB**. | FluidAudio and Apple Silicon only; English-only. No Whisper preview. | **Yes only as a separate additive preview,** with the same two-resident-model conflict. |
| `StreamingAsrManager`: Parakeet Unified 2080 | Architectural gate is 2080 ms (1.04 s chunk + 1.04 s right context). The prewarmed probe's first non-empty partial arrived at **3.201 s** after 3.120 s of audio; final returned at 11.067 s. | The probe final matched the reference words and punctuation. FluidAudio's 2620-file run reports 2.21% average WER streaming versus 2.15% Unified batch, not comparison with the selected FoldWise model. | **610.1 MB** required/downloaded. Warm standalone peak footprint / max RSS was **65.6 / 80.6 MB**, but the first load reached **74.9 / 678.8 MB**; Core ML placement makes this result non-comparable to EOU/Nemotron without an app-level trace. | FluidAudio only; English-only. No Whisper preview. | **Yes only with a separate final batch path.** The current FoldWise batch model remains a different lifecycle-owned engine. |
| FluidAudio streaming VAD | One 4096-sample unit is 256 ms. On the fixture, the first speech-start event arrived at **0.529 s** after 512 ms was available; default speech end still requires 0.75 s below threshold. It emits no transcript. FluidAudio labels it beta. | No ASR final by itself. If used only for events, it need not alter batch text; trimming samples can alter results and needs measurement. | **1.1 MB** required/downloaded. Standalone peak footprint / max RSS: **12.6 / 25.8 MB**. | Capture-level and potentially engine-neutral, despite being implemented by FluidAudio. | **Yes.** VAD failure should disable trimming/events and leave the complete buffer and batch path untouched. |

Sources for the table:

- WhisperKit exposes `TranscriptionCallback` as a lightweight
  `(TranscriptionProgress) -> Bool?`; the decoder constructs progress after each
  non-prefill token iteration and dispatches the callback, while preprocessing
  and encoding happen before the decoder
  ([Models.swift:718-728](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Models.swift#L718-L728),
  [TextDecoder.swift:723-750](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/TextDecoder.swift#L723-L750),
  [TranscribeTask.swift:115-172](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/TranscribeTask.swift#L115-L172),
  [Models.swift:1455-1457](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Models.swift#L1455-L1457)).
- Sliding-window updates are yielded only after `processWindow`; `finish()` then
  returns accumulated/merged tokens rather than delegating to FoldWise's current
  one-shot batch call. The manager can accept preloaded `AsrModels`, but the
  current `Transcriber` retains only its loaded `AsrManager`
  ([SlidingWindowAsrManager.swift:426-534](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift#L426-L534),
  [SlidingWindowAsrManager.swift:240-293](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift#L240-L293),
  [SlidingWindowAsrManager.swift:123-150](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift#L123-L150),
  [Transcriber.swift:34-59](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/Transcriber.swift#L34-L59)).
- EOU and Nemotron process complete buffered chunks and invoke partial callbacks
  only when decoding produced tokens. EOU's variant label is not always its
  first-buffer duration: the 320 tier requires 10,080 samples (630 ms) and then
  advances by 5,120 samples (320 ms)
  ([StreamingEouAsrManager.swift:49-86](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift#L49-L86),
  [StreamingEouAsrManager.swift:121-149](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift#L121-L149),
  [StreamingEouAsrManager.swift:605-609](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift#L605-L609),
  [StreamingEouAsrManager.swift:675-684](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift#L675-L684),
  [StreamingNemotronAsrManager.swift:346-360](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronAsrManager.swift#L346-L360),
  [StreamingNemotronAsrManager+Pipeline.swift:192-198](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronAsrManager%2BPipeline.swift#L192-L198)).
- EOU's English-only/no-punctuation constraint comes from NVIDIA's source
  model card; Nemotron and Unified identify themselves as English models
  ([NVIDIA EOU model card](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1/blob/a7e2b4629593dce0ec19f600e00e9904353fda2d/README.md),
  [NVIDIA Nemotron model card](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b/blob/df1f0fe9dfdf05152936192b4c8c7653d53bf557/README.md),
  [Unified CoreML model card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/blob/4252711f6f060f9a2f91e5f081a806d7f45eebd8/README.md)).
- Nemotron rejects Intel, and Unified derives 2080 ms from 13 chunk plus 13
  right-context frames at 80 ms each
  ([StreamingNemotronAsrManager.swift:92-99](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronAsrManager.swift#L92-L99),
  [UnifiedConfig.swift:43-77](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedConfig.swift#L43-L77),
  [Unified benchmark](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/benchmark.md)).
- VAD consumes 4096 samples at 16 kHz, and its default segmentation configuration
  requires 0.75 s of silence; the manager's own API documentation marks the
  implementation beta
  ([VadManager.swift:7-26](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/VAD/VadManager.swift#L7-L26),
  [VadTypes.swift:24-47](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/VAD/VadTypes.swift#L24-L47)).

## Artifact cost

“Required bytes” below are reproducible sums of the official Hugging Face
`size` fields for exactly the files FluidAudio 0.15.4 lists as required.
“Pinned-loader transfer” applies `DownloadUtils.downloadRepo`'s actual filter.
They differ for EOU: inside a subpath, the downloader includes every `.bin`
file as metadata, so it downloads the duplicate `.mlpackage` weight binaries
as well as the required compiled `.mlmodelc` bundles. The measured EOU 320
cache occupied 449,424 KiB (about 460.2 decimal MB) after download.

All byte values are decimal MB, matching FoldWise's catalog convention.
FluidAudio's required-file sets and downloader are the authorities
([ModelNames.swift:489-593](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ModelNames.swift#L489-L593)).
The broad subpath `.bin` rule is at
[DownloadUtils.swift:398-447](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/DownloadUtils.swift#L398-L447).

| Candidate artifact set | Required bytes / MB | Pinned-loader transfer bytes / MB | Increment over current model data |
| --- | ---: | ---: | --- |
| Whisper callback | 0 / 0 | 0 / 0 | None |
| TDT sliding window | 0 / 0 | 0 / 0 | None if the Effective TDT model data is reused |
| Parakeet EOU 160 ms | 224,047,838 / 224.0 | **449,190,189 / 449.2** | Separate model |
| Parakeet EOU 320 ms | 224,238,270 / 224.2 | **447,774,022 / 447.8** | Separate model |
| Parakeet EOU 1280 ms | 224,525,706 / 224.5 | **438,893,464 / 438.9** | Separate model |
| Nemotron 560 ms | 626,449,022 / 626.4 | 626,449,022 / 626.4 | Separate model |
| Nemotron 1120 ms | 626,803,815 / 626.8 | 626,803,815 / 626.8 | Separate model |
| Nemotron 2240 ms | 627,511,334 / 627.5 | 627,511,334 / 627.5 | Separate model |
| Parakeet Unified streaming 2080 ms, INT8 encoder | 610,062,293 / 610.1 | 610,062,293 / 610.1 | Separate model |
| Silero streaming VAD | 1,063,425 / 1.1 | 1,063,425 / 1.1 | Separate auxiliary model |

Official immutable metadata used for the sums:
[EOU tree](https://huggingface.co/api/models/FluidInference/parakeet-realtime-eou-120m-coreml/tree/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355?recursive=true&expand=false&limit=1000),
[Nemotron tree](https://huggingface.co/api/models/FluidInference/nemotron-speech-streaming-en-0.6b-coreml/tree/e673531caa6d25ab7baf5a8c14c9b99ba1551838?recursive=true&expand=false&limit=1000),
[Unified tree](https://huggingface.co/api/models/FluidInference/parakeet-unified-en-0.6b-coreml/tree/4252711f6f060f9a2f91e5f081a806d7f45eebd8?recursive=true&expand=false&limit=1000),
and
[VAD tree](https://huggingface.co/api/models/FluidInference/silero-vad-coreml/tree/b419383c55c110e2c9271fa6ee0ea83d03c70d96?recursive=true&expand=false&limit=1000).

No primary source gives comparable peak memory for these exact FoldWise
configurations. The standalone probe supplies one-machine directional
measurements, but Core ML compiled-file bytes still cannot be converted into
resident memory: mapping, compute-unit placement, caches, temporary tensors,
and shared pages differ. Before shipping, measure inside FoldWise on the
supported Apple Silicon floor and a current machine, with both the batch engine
and proposed preview engine warm.

## The additive-final and fallback constraint

Today the lifecycle captures one opaque handle for the Effective ASR model at
recording start. The handle exposes only a final
`transcribe([Float]) -> String`; Pipeline stops the recorder, then invokes it.
The captured engine is either the available stored selection or the default
Parakeet fallback, because unavailable or unknown stored selections resolve to
the default without rewriting saved intent
([Pipeline.swift:12-37](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L12-L37),
[ASRModelLifecycle.swift:145-159](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelLifecycle.swift#L145-L159),
[ASRModelLifecycle.swift:691-700](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelLifecycle.swift#L691-L700)).

That yields a safe preview contract:

1. Capture the Effective ASR model exactly as today.
2. Let the lifecycle/session handle optionally accept recorder buffers and
   publish volatile preview text; Pipeline and Badge must not receive concrete
   model identifiers.
3. On hotkey release, always run the captured handle's existing batch
   `transcribe` over the complete recorder buffer and use only that result for
   Polish, History, and atomic insertion.
4. If preview setup, download, inference, or callback delivery is unavailable
   or fails, stop preview and continue the batch path. Do not mutate the saved
   selection, Effective ASR model, or model availability.

This contract preserves ADR-0006's fallback semantics, but a separate EOU,
Nemotron, or Unified preview model conflicts with ADR-0005. That ADR assigns the
lifecycle the **sole loaded ASR engine** and mandates drop-before-load
replacement; it explicitly rejects owning two loaded engines
([ADR-0005:20-58](../adr/0005-second-asr-engine-behind-transcribing.md#L20-L58),
[ADR-0005:78-86](../adr/0005-second-asr-engine-behind-transcribing.md#L78-L86),
[ADR-0006:27-47](../adr/0006-global-asr-selection-over-revived-asr-model.md#L27-L47)).
Consequently, a SPEC must choose one of these honest policies:

- amend ADR-0005 to permit one measured, lifecycle-owned auxiliary preview model
  alongside the captured Effective ASR model;
- make a streaming model a normal selectable Effective ASR model and accept
  that its streaming `finish()` is the final rather than today's batch model; or
- keep the one-engine rule and ship preview only where the selected engine can
  produce it without another resident model. Under the pinned code, that means
  Whisper's post-release callback, not live Parakeet TDT preview.

## Recommended next decision and measurements

1. **Build the optional preview seam before selecting a new model.** Use the
   Whisper callback as the first adapter because it adds no model data and its
   final result stays the existing batch result. Acceptance must say
   “post-release partial” so this tracer is not mistaken for live ASR.
2. **Reject default sliding-window TDT for the Badge experiment.** Its 13 s
   first-window gate misses ordinary dictation, and reducing the chunk changes
   the manager's stated 10–11 s best-quality configuration. The unused
   hypothesis field is not evidence of a working fast path
   ([SlidingWindowAsrManager.swift:709-750](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/SlidingWindowAsrManager.swift#L709-L750)).
3. **Prototype EOU 320 as the true-streaming preview.** It was the best measured
   latency/memory corner: 1.000 s to first non-empty text and about 287 MB peak
   footprint, versus Nemotron 560 at 1.237 s and about 1.09 GB. Its lowercase,
   unpunctuated preview is acceptable only because the Effective ASR model's
   batch result replaces it atomically. Treat it as an English-only preview
   accelerator, never a silent replacement for a multilingual Effective ASR
   model
   ([EOU CoreML model card](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/blob/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355/README.md),
   [NemotronChunkSize.swift:3-20](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/NemotronChunkSize.swift#L3-L20)).
4. **Keep Nemotron, Unified, and VAD out of the first preview prototype.**
   Nemotron's punctuation/capitalization does not justify roughly 805 MB more
   standalone footprint while batch remains authoritative. Unified first text
   arrived at 3.201 s. VAD is worth an independent test for
   leading/trailing-silence trimming or auto-end behavior, but it cannot create
   text.
5. **Measure before changing the resident-engine policy.** For each EOU/Nemotron
   trial record: audio-to-first-nonempty-partial p50/p95; partial age relative to
   the newest spoken word; release-to-authoritative-batch-final p50/p95; final
   WER against the current selected batch model on the same English fixtures;
   correction distance from last preview to batch final; warm idle RSS; peak RSS
   while preview and batch are resident; model-load time; and behavior when
   preview data is absent/corrupt or inference fails. Run on the minimum
   supported Apple Silicon machine and one current machine. No numerical ship
   threshold is justified by the available primary evidence.

## Reproduction

The probes were temporary release executables linked against the repository's
pinned packages; they were not production changes. Their contracts were:

```text
SlidingWindow: 250 ms real-time buffers, default 11/2/2 window and a 1/2/2 stress case
Whisper callback: complete 11 s buffer, Whisper small, callback returns true
True streaming: 80 ms real-time buffers, 3.2 s silent warm-up, then reset
VAD: 256 ms real-time chunks, default segmentation configuration
Memory: /usr/bin/time -l <probe>
```

Reference transcript:

```text
And so, my fellow Americans, ask not what your country can do for you,
ask what you can do for your country.
```

The current TDT v3 batch CLI, after Core ML caches were warm, returned that
reference in 0.45 s end-to-end as a standalone process, with a 40.9 MB peak
footprint. This reinforces the additive design: the preview should overlap
speech, while the selected batch engine remains the fast, authoritative final.

Nemotron 560 and Unified 2080 both printed Core ML's
`Failed to PropagateInputTensorShapes ... zero shape error` warning during
startup/warm-up but continued and produced correct final words. Treat that as a
prototype risk to investigate, not as a measured transcription failure.
