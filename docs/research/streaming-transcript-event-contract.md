# Streaming transcript event contract

Research answer for **Define the streaming transcript event contract across
engines**, audited on 2026-07-19. This note distinguishes model output truth
from presentation stability and keeps recorder, ASR engine, and Dictation
session responsibilities separate.

> **Status: withdrawn as a FoldWise decision.** While this research was in
> progress, the parent map rejected external catalog parity and reopened the
> runtime investigation against a FoldWise-owned ASR catalog baseline. The
> transcribe.cpp findings below remain source-backed reference material, but the
> seven-model inventory, selected runtime, and proposed contract are not an
> accepted FoldWise product or architecture decision. Re-run the ticket after
> the independent runtime strategy is resolved.

## Executive answer

The seven entries in the pinned Handy catalog that declare streaming reduce to
three streaming architecture families in the selected transcribe.cpp v0.1.3
runtime: Parakeet/Nemotron, Moonshine Streaming, and Voxtral Realtime. They all
fit one FoldWise boundary, but not a boundary containing only `committed` and
`tentative` text.

transcribe.cpp defines `full_text` as the authoritative current hypothesis.
Its `committed_text` is an append-only display aid and its `tentative_text` is a
volatile suffix. A growing-context model can revise bytes that were already
committed; in that case `committed_text + tentative_text` deliberately stops
reconstructing `full_text`. Successful finalization also does not rewrite an
incompatible committed prefix. FoldWise must therefore carry authoritative
current and final text separately from the committed/tentative presentation
pair ([canonical stream text contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L1701-L1745),
[finalization semantics](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L1908-L1945)).

The smallest truthful engine-neutral boundary is an ordered sequence of full
snapshot updates followed by exactly one terminal outcome:

```swift
struct StreamingTranscriptSnapshot: Sendable, Equatable {
    /// Monotonic within one stream; it is an ordering/deduplication key,
    /// not proof that visible text changed.
    let revision: UInt64

    /// The engine's authoritative current raw hypothesis.
    let currentText: String

    /// Append-only, flicker-resistant presentation text.
    let committedText: String

    /// Volatile presentation text. It may be replaced on every update.
    let tentativeText: String
}

enum StreamingTranscriptCompleteness: Sendable, Equatable {
    case complete
    case truncated
}

enum StreamingTranscriptTerminal: Sendable, Equatable {
    case completed(text: String, completeness: StreamingTranscriptCompleteness)
    case cancelled
    case failed(ASRStreamingFailure, lastSnapshot: StreamingTranscriptSnapshot?)
}

enum StreamingTranscriptEvent: Sendable, Equatable {
    case update(StreamingTranscriptSnapshot)
    case terminal(StreamingTranscriptTerminal)
}
```

`feed(audio:)`, `finishInput()`, and `cancel()` are commands on the captured ASR
session, not transcript events. The adapter serializes native calls, publishes
only whole owned-string snapshots, and emits one terminal event. This preserves
ADR-0002 and ADR-0005: Pipeline still holds an opaque Dictation-session handle,
while concrete transcribe.cpp state stays inside the lifecycle's engine adapter.

## Streaming catalog coverage

The pinned Handy catalog at commit
[`cdbc223`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/catalog/catalog.json)
marks exactly these seven entries as streaming:

| Handy catalog entry | transcribe.cpp family | Live hypothesis and commitment |
| --- | --- | --- |
| `parakeet-unified-en-0.6b` | Parakeet buffered streaming | Native emitted tokens advance the committed boundary; finalization drains the remaining right-context/tail audio. |
| `nemotron-3.5-asr-streaming-0.6b` | Parakeet cache-aware streaming | Native token commitment with a selectable trained lookahead; finalization emits a final partial chunk. |
| `nemotron-speech-streaming-en-0.6b` | Parakeet cache-aware streaming | Native token commitment with constant-memory caches; finalization emits a final partial chunk. |
| `moonshine-streaming-tiny` | Moonshine Streaming | Re-decodes a growing prefix; commitment uses token-ID agreement, three agreeing hypotheses by default. |
| `moonshine-streaming-small` | Moonshine Streaming | Same event semantics as Tiny. |
| `moonshine-streaming-medium` | Moonshine Streaming | Same event semantics as Tiny. |
| `Voxtral-Mini-4B-Realtime-2602` | Voxtral Realtime | Throttled revisable hypotheses; generic UTF-8 text agreement commits a prefix, while finalization runs the authoritative final path. |

The family behaviors are documented and implemented in the pinned runtime:

- Parakeet selects native commitment rather than agreement and supports both
  buffered and cache-aware variants
  ([stable-prefix dispatch](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/src/transcribe.cpp#L1042-L1073),
  [Parakeet feed/finalize](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/src/arch/parakeet/model.cpp#L2725-L2990)).
- Moonshine Streaming uses family token agreement and has no timestamps
  ([family capabilities](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/src/arch/moonshine_streaming/capabilities.cpp),
  [model-family contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/models/moonshine-streaming.md)).
- Voxtral Realtime falls back to generic repeated-text agreement. Its trained
  delay and publication cadence affect latency, but they do not create an
  engine-level end-of-utterance signal
  ([family contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/models/voxtral-realtime.md),
  [feed/finalize implementation](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/src/arch/voxtral_realtime/model.cpp#L1967-L2031)).

The remaining 58 catalog entries are not streaming-capable in this baseline.
FoldWise should use their existing batch-shaped path and must not synthesize live
events by repeatedly rerunning batch transcription.

## Exact semantic decisions

### Committed, tentative, and revision

- `currentText` is the only authoritative live hypothesis.
- `committedText` is append-only during one stream and is appropriate for the
  Badge's stable visual emphasis. “Committed” does not mean immutable model
  truth or guaranteed membership in the final transcript.
- `tentativeText` is volatile and may be wholly replaced.
- The UI may normally render `committedText + tentativeText`, matching the
  selected Badge prototype, but must replace that presentation with the
  terminal completed text after finalization. Consumers that require exact live
  truth render `currentText`.
- `revision` is stream-local and monotonic. Native revision advances for any
  observable snapshot or lifecycle change, including a finalize transition with
  unchanged visible text. Adapters for future engines may synthesize the same
  monotonic sequence; consumers must not interpret a bump as “text changed”
  ([update contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L1838-L1906),
  [revision accessor](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L2121-L2133)).

Snapshots contain owned Swift strings. Native pointers are borrowed and may be
invalidated by every feed/finalize mutation; the official Swift binding already
copies them at the FFI boundary
([Swift `StreamText`](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/bindings/swift/Sources/TranscribeCpp/Streaming.swift#L54-L69)).

### Timing and timestamps

transcribe.cpp exposes three per-call audio cursors: input received, audio
committed, and buffered milliseconds. They are family-reported progress/drain
hints, not text offsets. `audio_committed_ms` does not map to a byte boundary in
`committedText`; `buffered_ms` describes internal audio waiting for family
context rather than total recognition latency
([cursor contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L1867-L1885)).

They are not reliable enough for the engine-neutral transcript event:

- `ON_FINALIZE` deliberately reports zero committed audio during feeds.
- Voxtral reports zero buffered milliseconds despite its model delay, and its
  v0.1.3 cursor bookkeeping is tied to an internally trimmed PCM buffer.
- Family cadence and lookahead differ materially, so equal cursor values do not
  imply equal transcript stability.

Keep these values in adapter diagnostics and performance tests. Add optional
progress metadata later only if a concrete product consumer earns it.

Recognition timestamps are a different capability. Parakeet entries expose
token/word timing; Moonshine Streaming and Voxtral Realtime expose none. An
active stream may also carry structural token rows even when it has no real
token timestamps. The final-result layer must therefore use the runtime's
reported timestamp granularity, never infer timestamps from token rows
([streaming timestamp rule](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L1724-L1738)).
Timestamps are not required by the selected Badge behavior and stay outside the
small live-event contract.

### End of utterance and flush

None of the three runtime families exposes a VAD, endpoint, or spontaneous
end-of-utterance event. A stream remains active until the caller explicitly
finalizes or resets it. FoldWise's record Stage therefore owns the decision
that input ended—hotkey release, Badge stop, recorder failure, or a separately
specified VAD policy—and then calls `finishInput()`.

`finishInput()` maps to native `finalize()`: it consumes every feed queued
before it, flushes buffered audio, satisfies right-context/lookahead, and emits
remaining text. Only a successful native finalize followed by the terminal
state/completeness checks may publish `.completed`; native `is_final` merely
means “this update came from the finalize call” and is set even when that call
fails
([finalize contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L2084-L2096),
[Swift finalize wrapper](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/bindings/swift/Sources/TranscribeCpp/Streaming.swift#L135-L149)).

### Cancellation and failure

There are two native mechanisms with different meanings:

- the abort callback interrupts in-flight feed/finalize compute at chunk or
  decode-step boundaries, returns `ABORTED`, transitions the stream to failed,
  and preserves readable partial results; and
- `reset()` abandons the stream without flushing and clears all result-visible
  state.

FoldWise user cancellation needs both: signal the cancellation token so any
in-flight compute unwinds, then reset/release the native stream. The public
terminal outcome is `.cancelled`; partial text is discarded and the Dictation
session inserts and saves nothing, matching the selected Badge behavior. An ASR
fault is `.failed(error:lastSnapshot:)`, preserving the last snapshot for
diagnostics or a later product-level fallback decision without presenting it as
a successful transcript
([native cancellation contract](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/include/transcribe.h#L1740-L1745),
[Swift cancellation token](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/bindings/swift/Sources/TranscribeCpp/Cancellation.swift)).

### Final result and truncation

After successful finalize, the adapter reads authoritative `full` text, not the
presentation `display` string. It then checks truncation before publishing the
terminal outcome. Streaming truncation is exceptional in v0.1.3: Moonshine
Streaming can reach its decoder output window and Voxtral can reach its absolute
position cap while finalize still returns success. The only truthful signal is
`wasTruncated`
([streaming input-limit exception](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/input-limits.md#L177-L191)).

The terminal contract retains `.completed(..., completeness: .truncated)` so
the adapter never lies about completeness. Whether FoldWise blocks insertion,
offers recovery, or accepts a truncated transcript is a product decision for
**Define end-to-end streaming Dictation session semantics**, not an engine
adapter decision.

## Handy reference behavior

Handy's pinned implementation validates the useful orchestration shape but is
not sufficient as FoldWise's truth boundary:

- audio feeds and finalize/cancel share a FIFO command channel, ensuring all
  accepted audio precedes flush;
- its UI event contains only committed and tentative strings;
- revision and audio cursors are logged, not emitted;
- cancel resets and discards the stream; and
- finalize returns `stream.text().display()` and falls back to batch on an
  unusable stream.

See Handy's
[`StreamCmd` and `StreamTextEvent`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/managers/transcription.rs#L47-L157),
[`feed`/`finalize`/`cancel` worker](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/managers/transcription.rs#L917-L1020),
and
[`finalize_stream`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/managers/transcription.rs#L1041-L1083).

FoldWise should preserve the FIFO command ordering, but add authoritative
current/final text, explicit terminal outcomes, and completeness. That is the
minimum needed to keep the Badge and Pipeline truthful across all seven
streaming catalog entries.

## Consequences for later wayfinding tickets

- **Choose the adapter and runtime ownership architecture** can place the event
  sequence behind the existing opaque ASR session handle; no model identifier or
  transcribe.cpp type needs to leak into Pipeline.
- **Define end-to-end streaming Dictation session semantics** owns recorder
  endpoint policy, batch fallback, truncation UX, Polish transition, insertion,
  History, and what the Badge displays when stable presentation diverges from
  authoritative live text.
- No new ticket is required from this research. Performance acceptance can
  measure time-to-first-update, revision cadence, finalize latency, cancellation
  latency, and final-vs-batch equality without promoting native cursor hints into
  the product contract.
