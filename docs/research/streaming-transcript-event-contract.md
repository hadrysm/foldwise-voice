# Streaming transcript event contract

Status: research decision for
[Define the streaming transcript event contract across engines](https://github.com/hadrysm/foldwise-voice/issues/194),
2026-07-19. This supersedes the withdrawn transcribe.cpp/Handy analysis that
previously occupied this note.

## Answer

The independent seven-row catalog contains exactly two streaming rows:
**Parakeet Unified EN 0.6B** and **Nemotron 3.5 ASR Streaming Multilingual
0.6B**. Both run through FluidAudio 0.15.4; the other five catalog rows are
batch or sliding-window paths and must not be made to look live by repeatedly
rerunning them. The selected catalog and runtime decisions establish this scope
([catalog baseline](independent-asr-catalog-baseline.md),
[runtime coverage](independent-asr-runtime-strategy.md#coverage-proof)).

At the pinned FluidAudio revision, both streaming managers expose the same
important text truth: a callback or getter returns the **whole running
transcript**, built only by appending newly emitted RNNT tokens. Neither manager
exposes a tentative suffix, replacement range, confidence that a suffix may
change, or engine revision number. Unified appends decoded pieces directly to
an accumulated text cache; Nemotron appends token IDs and re-decodes that
growing ID list after each token-bearing chunk
([Unified accumulation](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L281-L329),
[Nemotron accumulation and callback](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BPipeline.swift#L545-L581)).

The smallest FoldWise boundary that preserves that truth and the selected Badge
vocabulary is therefore an ordered sequence of full text snapshots followed by
exactly one terminal outcome:

```swift
struct StreamingTranscriptSnapshot: Sendable, Equatable {
    /// Stable, append-only text for this catalog baseline.
    let committedText: String

    /// Volatile replacement suffix. Always empty for both baseline engines;
    /// an adapter may populate it only for a future engine with native evidence.
    let tentativeText: String
}

enum StreamingTranscriptTerminal: Sendable, Equatable {
    /// Authoritative value returned by the engine's successful finish call.
    case completed(text: String)
    case cancelled
    case failed(ASRStreamingFailure)
}

enum StreamingTranscriptEvent: Sendable, Equatable {
    case update(StreamingTranscriptSnapshot)
    case terminal(StreamingTranscriptTerminal)
}
```

`appendAudio`, `processBufferedAudio`, `finishInput`, and `cancel` are session
commands, not transcript events. Event order is the revision order; the
boundary does not need an engine revision field that neither engine supplies.
Token timing is an optional adapter capability, not part of the live-text event,
because the two native timing APIs do not have one interchangeable meaning.
There is no end-of-utterance event: Dictation decides when input ends and sends
`finishInput`.

## Comparison matrix

| Semantic | Unified streaming | Nemotron 3.5 multilingual streaming | Truth at FoldWise boundary |
| --- | --- | --- | --- |
| Running text | Native full snapshot; token pieces append to `transcriptCache`; callback fires only when a window emits tokens ([source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L281-L329)) | Native full snapshot; emitted token IDs append and the complete filtered list is decoded for the callback/getter ([source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L1070-L1077), [callback](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BPipeline.swift#L572-L581)) | `.update` carries a full snapshot, not a delta. |
| Committed text | Native append-only token sequence; the stateless encoder re-encodes context but the decoder visits only not-yet-decoded frames ([windower](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedStreamingWindower.swift#L65-L78), [append](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L289-L299)) | Native append-only RNNT token sequence; callbacks decode accumulated IDs and language-tag IDs are filtered rather than displayed ([pipeline](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BPipeline.swift#L545-L581), [filter](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/NemotronMultilingualTokenizer.swift#L35-L58)) | Put all native running text in `committedText`. “Committed” means the engine will not retract the emitted token sequence, not that recognition is linguistically correct. |
| Tentative/revisable text | Not exposed | Not exposed | `tentativeText == ""`. Never invent a tentative suffix by chopping words or holding back tokens. |
| Revision | No counter or replacement range; callback is notification of a token-bearing window ([API](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L324-L356)) | No counter or replacement range; a language-tag-only emission can notify with unchanged visible text because tags are removed during decoding ([callback](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BPipeline.swift#L557-L581), [filter](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/NemotronMultilingualTokenizer.swift#L41-L58)) | Preserve actor/stream order and suppress duplicate snapshots. A sequence number may be adapter-synthesized for telemetry or UI deduplication, but is not engine semantics and is not required in the core event. |
| Publication timing | A first non-final window requires chunk plus right context; the reviewed `[70,13,13]` profile is 1.04 s chunk + 1.04 s right context, 2.08 s theoretical latency ([configuration](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedConfig.swift#L43-L77), [window rule](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedStreamingWindower.swift#L39-L65)) | Processes complete metadata-defined chunks and notifies only when a chunk emits visible or filtered tokens; the exact audited catalog artifact is `multilingual/2240ms` ([buffer drain](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L951-L991), [metadata-derived chunk](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/NemotronMultilingualStreamingConfig.swift#L73-L102), [audited profile](https://github.com/hadrysm/foldwise-voice/blob/a3b684f1b04c6165645a8a6787bb9fa7b566534b/docs/research/foldwise-asr-catalog-license-and-artifact-audit.md#L30-L43)) | An event has ordering, not an implied wall-clock cadence. Measure receipt time in FoldWise telemetry if needed; do not promise a fixed update interval. |
| Token timing | Native drain API returns newly accumulated token timings. Starts use global encoder frames; a frontier token has a provisional one-frame end, and a later token can back-fill the preceding end while it remains buffered ([API and caveat](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L181-L190), [construction](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L293-L318)) | Native current/final arrays contain absolute per-token start and one-frame end; language tags are omitted and confidence is hard-coded to `1.0` ([construction](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BDecode.swift#L494-L515), [current/final APIs](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L1080-L1097)) | Keep out of the minimal transcript event. A later timing capability must name provisionality, confidence provenance, token/text alignment, and snapshot-vs-drain behavior instead of flattening both arrays into “timestamps.” |
| End of utterance | None. The manager remains usable until caller `finish()` or `reset()` ([streaming API](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L158-L202)) | None. An optional, default-off RMS gate skips sustained-silence chunks for compute efficiency but publishes no endpoint and does not finish the stream ([gate configuration](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BBuffers.swift#L62-L94), [skip behavior](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BPipeline.swift#L78-L104)) | No `.endOfUtterance` event. Recorder/product policy decides when to send `finishInput`. FluidAudio's separate Parakeet EOU manager is not one of the two reviewed catalog rows. |
| Flush | Native `finish()` runs the final window with zero right-context holdback, including an exact-chunk-boundary re-encode, then returns current text ([finish](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L170-L175), [final-window rule](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/UnifiedStreamingWindower.swift#L39-L65)) | Native `finish()` zero-pads and processes a remaining partial chunk, then returns the decode of all accumulated IDs; if no partial chunk remains there is no extra decoder pass ([finish](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L994-L1042)) | `finishInput` is a serialized command. It may cause final `.update` events, and only its successful return permits `.terminal(.completed)`. |
| Final result | `finish()` returns the authoritative accumulated transcript and retains it until reset ([source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L170-L201)) | `finish()` returns the authoritative decode, snapshots final timing diagnostics, and clears working token IDs/timings. Its optional capitalization/punctuation heuristic is off by default and must remain off at the ASR truth boundary ([source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L69-L75), [finish](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L1024-L1042)) | Terminal completed text always comes from the successful `finish()` return; it replaces the Badge snapshot even if formatting differs. No separate native completeness/truncation signal exists. |
| Cancellation | No cancel/abort API or cancellation callback in the manager's public streaming surface; `reset()` clears buffer, text, timing, and decoder state ([source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L158-L202)) | No cancel/abort API or cancellation callback; `reset()` clears stream buffers, IDs, timing, and decoder/cache state ([reset](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L798-L823)) | `.cancelled` is adapter/session-synthesized from accepted user intent. Stop accepting audio, do not call `finish`, discard snapshots, reset before reuse, and emit one cancelled terminal. In-flight Core ML inference has no source-backed prompt-abort guarantee; cancellation latency must be measured. |
| Failure | Streaming calls throw `ASRError`; partial state may remain readable until reset ([API](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/StreamingAsrManager.swift#L21-L59)) | Streaming calls throw; the native getter explicitly supports salvaging token timings after a mid-stream failure ([source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L1092-L1097)) | Map the thrown failure to exactly one `.failed` terminal, then reset. Do not turn the last partial into success. |

## Native truth versus adapter synthesis

The two concrete managers' native facts are deliberately narrow:

- full running text notifications/getters;
- an append-only emitted-token history;
- explicit caller-driven flush returning final text;
- thrown processing failures; and
- engine-specific token timing accessors
  ([Unified API](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L158-L202),
  [multilingual Nemotron API](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L935-L1097)).

The FoldWise adapter must synthesize only boundary mechanics: serial command
ordering, duplicate suppression, the empty tentative suffix, terminal failure
mapping, and user-cancellation completion. It must not synthesize token
stability by timing, split a native transcript into guessed committed/tentative
regions, infer endpointing from silence, advertise a fabricated engine revision,
or publish a partial transcript as a successful final result.

One source-level integration wrinkle belongs to the later ownership ticket:
Unified conforms to FluidAudio's `StreamingAsrManager`, but the multilingual
Nemotron concrete manager does not; FluidAudio's generic Nemotron factory
constructs the English manager. FoldWise therefore needs its own concrete
multilingual wrapper rather than assuming both catalog rows can travel through
FluidAudio's generic factory
([protocol and documented conformers](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/StreamingAsrManager.swift#L1-L59),
[generic factory](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/ParakeetModelVariant.swift#L91-L127),
[Unified conformance](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift#L337-L357)).

The three reviewed Whisper profiles remain batch. WhisperKit 1.0.0 includes an
`AudioStreamTranscriber`, but the selected exact packages are not
publisher-native streaming catalog rows; routing repeated Whisper decodes into
this contract would change their reviewed capability rather than normalize it
([runtime decision](independent-asr-runtime-strategy.md#runtime-semantics-and-architecture-boundary),
[pinned WhisperKit helper](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift#L76-L205)).
That helper repeatedly retranscribes its accumulated buffer and classifies all
but the last two segments as “confirmed”; those confirmed/unconfirmed labels are
WhisperKit wrapper heuristics, not publisher-model commitment semantics
([state and confirmation count](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift#L6-L74),
[segment update heuristic](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift#L164-L205)).

## Contract invariants

1. A session emits zero or more `.update` events and exactly one `.terminal`;
   nothing follows the terminal.
2. Events preserve the actor-serialized order of accepted audio, processing,
   and `finishInput`/`cancel` commands.
3. For this baseline, each nonduplicate update's `committedText` has the previous
   update's `committedText` as a prefix and `tentativeText` is empty.
4. `.completed(text:)` is emitted only after native `finish()` returns
   successfully; its text is authoritative even when no final update fired.
5. Once cancellation wins command serialization, FoldWise accepts no more audio,
   never calls `finish()`, publishes no completion/failure from abandoned work,
   resets the manager before reuse, and emits only `.cancelled`.
6. A thrown append/process/finish operation yields `.failed`, never `.completed`.
   Any last snapshot is UI state or diagnostics, not a final transcript.
7. The adapter keeps Nemotron's display-only punctuation heuristic disabled.
   Capitalization, punctuation repair, and Polish remain downstream transforms.

## Limitations and downstream consequences

- “Committed” is structural decoder stability, not semantic certainty. A wrong
  word can be append-only.
- No native operation promises immediate interruption of an in-flight Core ML
  prediction. The implementation plan needs a cancellation-latency acceptance
  test and must keep insertion/History gated on the terminal outcome.
- Native timestamps are useful evidence but not yet one product contract. If
  word highlighting, diarization, or seeking earns a timing surface, specify it
  separately and validate text alignment, provisional ends, confidence meaning,
  and finalization behavior for each profile.
- The contract intentionally says nothing about microphone endpoint policy,
  Polish, insertion, History, batch fallback, or model switching. Those belong
  to **Define end-to-end streaming Dictation session semantics** and **Choose the
  adapter and runtime ownership architecture**.

## Primary-source baseline

- FoldWise pins FluidAudio `0.15.4` at
  [`b9d43724`](https://github.com/FluidInference/FluidAudio/tree/b9d43724cbdb5a980e441fd54180964e94d470f7)
  and WhisperKit `1.0.0` at
  [`25c62997`](https://github.com/argmaxinc/argmax-oss-swift/tree/25c62997041c134b03ca82731ce2f6fd2cae1eb9)
  ([local lockfile](../../Package.resolved)).
- Catalog membership and exact profile choice come from
  [FoldWise's independent catalog baseline](independent-asr-catalog-baseline.md).
- Runtime ownership and the exclusion of pseudo-streaming Whisper rows come from
  [the independent runtime strategy](independent-asr-runtime-strategy.md).

## Bottom line

For the reviewed baseline, live ASR is simpler than the withdrawn transcribe.cpp
design: both engines expose stable append-only full text plus caller-driven
finalization. Use full snapshots with an empty tentative suffix, followed by one
completed/cancelled/failed terminal. Do not put fabricated revisions, endpoint
events, or flattened token timings into the core boundary.
