# macOS runtime strategy for FoldWise's independent ASR catalog

Status: research decision for
[Evaluate macOS runtimes for FoldWise's independent ASR catalog](https://github.com/hadrysm/foldwise-voice/issues/193),
2026-07-19. The model and artifact scope comes from
[FoldWise's independent ASR catalog baseline](independent-asr-catalog-baseline.md).

## Decision

Keep a deliberate **two-runtime, in-process Core ML strategy**:

- **FluidAudio 0.15.4** for Parakeet TDT 0.6B v3, Parakeet TDT-CTC
  110M, Parakeet Unified EN 0.6B, and Nemotron 3.5 ASR Streaming
  Multilingual 0.6B.
- **WhisperKit 1.0.0** for Whisper small, Whisper large-v3 Turbo 626 MB,
  and Whisper large-v3 947 MB.

These are two packaged runtime dependencies, not two simultaneously loaded
engines. They remain behind FoldWise's actor-owned `ASRModelLifecycle`, which
must preserve drop-before-load replacement and one resident engine at a time
([ADR-0005](../adr/0005-second-asr-engine-behind-transcribing.md)). Recognition
stays local and in process after a model has been downloaded.

Do not add transcribe.cpp, ONNX Runtime, MLX, a service process, or FoldWise-owned
raw Core ML inference for this baseline. None consumes all seven reviewed Core ML
profiles through a proven ASR API. A new runtime would therefore require new
conversions or duplicate the preprocessing, decoding, tokenization, streaming,
and validation work already present in FluidAudio and WhisperKit without adding
catalog coverage.

FoldWise must nevertheless own the **artifact supply chain around both
runtimes**: immutable repository revisions, complete file manifests, SHA-256
verification, atomic staging, availability validation, and explicit runtime
upgrade review. The libraries' convenience downloaders are transport helpers,
not the catalog's identity or integrity authority.

## Coverage proof

The recommendation covers the exact seven catalog rows selected in the baseline.

| Catalog row | Runtime path | Evidence and integration consequence |
| --- | --- | --- |
| Parakeet TDT 0.6B v3 INT8 | FluidAudio `AsrManager` / `AsrModels` | FluidAudio's public `AsrModelVersion` and loader include v3; FoldWise already uses this path. [Pinned source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift) |
| Parakeet TDT-CTC 110M float32 | FluidAudio `AsrManager` / `AsrModels` | The same public loader has a dedicated `tdtCtc110m` version and repository mapping. It is a distinct catalog profile, not the custom-vocabulary CTC model. [Pinned source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrModels.swift) |
| Parakeet Unified EN 0.6B streaming INT8 | FluidAudio `StreamingUnifiedAsrManager` | FluidAudio owns the chunk windower, RNNT decoder, INT8/FP16 selection, loading, and stream API. [Pinned manager](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift) |
| Nemotron 3.5 ASR Streaming Multilingual 0.6B | FluidAudio `StreamingNemotronMultilingualAsrManager` | FluidAudio owns the cache-aware RNNT pipeline, prompt/language state, and profile-specific model layout. [Pinned manager](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift) |
| Whisper small | WhisperKit `WhisperKit` | Argmax's M1 and M2-M4 support tables include `openai_whisper-small`; the public API loads a local model folder and transcribes `[Float]` samples. [Pinned support table](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Models.swift) [Pinned API](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/WhisperKit.swift) |
| Whisper large-v3 Turbo 626 MB | WhisperKit `WhisperKit` | The support tables include the 626 MB folder on M1 and M2-M4, and Argmax recommends it for multilingual accuracy. [Pinned support table](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Models.swift) [Pinned README](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/README.md#model-selection) |
| Whisper large-v3 947 MB | WhisperKit `WhisperKit` | Argmax's M1 and M2-M4 support tables include `openai_whisper-large-v3_947MB`. [Pinned support table](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Models.swift) |

FluidAudio's own model inventory describes the four NVIDIA pipelines and their
separate batch or streaming managers. It also makes clear that its streaming
managers are cache-aware ASR implementations rather than a generic wrapper over
arbitrary Core ML packages
([pinned model inventory](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Documentation/Models.md)).
WhisperKit is specifically the Whisper family runtime; its generated device
tables are the appropriate minimum compatibility evidence for the three reviewed
Argmax packages, not a promise about every directory in the conversion repository.

## Strategy comparison

| Strategy | Exact baseline coverage | Packaging and maintenance | Decision |
| --- | --- | --- | --- |
| FluidAudio + WhisperKit | **7/7 reviewed rows** using the exact Core ML artifact families already selected | Two native Swift packages and two family APIs; both already integrated. FoldWise must pin upgrades and own artifact verification. | **Choose** |
| FluidAudio alone | 4/7; no OpenAI Whisper decoder/runtime | One dependency, but dropping three rows would violate the baseline. | Reject |
| WhisperKit alone | 3/7; no Parakeet/Nemotron pipelines | One dependency, but dropping four rows and the default would violate the baseline. | Reject |
| Direct Core ML | Models can be loaded, but there is no shared ASR execution layer | FoldWise would own feature extraction, tokenizer formats, TDT/RNNT/CTC/Whisper decoding, cache state, and model-shape evolution. | Reject |
| transcribe.cpp, ONNX Runtime, or MLX | No verified execution path for the seven pinned Core ML packages | Requires parallel conversions and a second artifact-validation/quality program; transcribe.cpp's prior relevance came only from the rejected external GGUF catalog. | Reject |
| Out-of-process service | Could wrap the chosen libraries but adds no model coverage | IPC, crash recovery, signing, lifecycle, and duplicated resident-memory ownership conflict with the current in-process architecture. | Reject for this baseline |

No primary source establishes one existing runtime that executes all seven exact
reviewed packages. “One runtime” is therefore not a simplification available to
this baseline; it would be a new conversion and inference project.

## Packaging and artifact ownership

Both chosen libraries are ordinary source Swift packages. FluidAudio declares
macOS 14 and has no third-party package dependency in its library product
([pinned `Package.swift`](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Package.swift)).
Argmax OSS declares macOS 13 for the package and exposes WhisperKit as a separate
library product, while its installation documentation requires macOS 14 and Xcode
16
([pinned `Package.swift`](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Package.swift),
[pinned installation requirements](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/README.md#prerequisites)).
This fits FoldWise's macOS 14 product floor without a bundled dynamic sidecar.

Release packaging should pin the reviewed runtime versions/revisions rather than
depend on a floating compatible-version range:

- FluidAudio `0.15.4` / `b9d43724cbdb5a980e441fd54180964e94d470f7`;
- Argmax OSS / WhisperKit `1.0.0` /
  `25c62997041c134b03ca82731ce2f6fd2cae1eb9`.

That pin is independent of model identity. Each model profile must separately
pin its conversion repository revision and complete manifest. FluidAudio's
download helpers resolve repository files and WhisperKit's public downloader
selects folders from a repository; neither current FoldWise path verifies the
complete immutable manifest required by the catalog baseline
([FluidAudio download source](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/DownloadUtils.swift),
[WhisperKit download source](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/WhisperKit.swift)).

The FoldWise-owned artifact layer should:

1. request only the catalog's immutable revision and allowlisted paths;
2. stream into an isolated staging directory;
3. verify byte counts and SHA-256 for every required file;
4. validate that Core ML packages compile/load on the current device;
5. atomically promote the complete profile; and
6. make availability false for partial, extra, corrupt, or unknown data.

Library managers should receive validated local directories. Their convenience
download functions may remain useful for development, but must not define release
identity or availability.

## Hardware and performance truth

Set the initial execution envelope to **Apple Silicon, macOS 14 or later**. This
matches FoldWise's present product floor, FluidAudio's Core ML/ANE design, and
WhisperKit's M1/M2-M4 device tables. Do not infer Intel eligibility from SwiftPM's
ability to compile a macOS target: the reviewed catalog and performance evidence
are Apple-silicon-specific.

Upstream measurements establish feasibility, not FoldWise support claims:

- FluidAudio reports TDT-CTC 110M at 96.5x real time and 3.01% WER on
  LibriSpeech test-clean on an M2 in its model inventory.
- FluidAudio's checked-in Unified benchmark reports 2.15% WER / 123x for batch
  and 2.21% / 29x for streaming, but one upstream benchmark is not a device
  support matrix
  ([pinned benchmark](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/benchmark.md)).
- WhisperKit's device tables distinguish supported and disabled model packages;
  they are compatibility guidance, not FoldWise cold-load, memory, power, or
  accuracy measurements
  ([pinned table](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/Models.swift)).

Before marking a model/profile eligible on a hardware tier, FoldWise must measure:

- cold download validation, Core ML compilation, and first load;
- peak resident memory and disk expansion during compile/prewarm;
- short-utterance latency and long-form real-time factor;
- committed/tentative emission latency for streaming profiles;
- cancellation, flush, repeated load/unload, and memory reclamation;
- sustained thermal and power behavior; and
- correctness on the languages and capabilities the exact row claims.

Prewarm large components sequentially. A package that is present on disk but
cannot compile or load within the device envelope remains unavailable; the
lifecycle must never persist it as the effective ASR model.

## Runtime semantics and architecture boundary

The selected runtimes expose different model-specific APIs:

- TDT v3 and TDT-CTC are complete-buffer/sliding-window paths.
- Unified is buffered streaming with a stateless re-run window and right
  context.
- Nemotron is cache-aware RNNT streaming with profile-specific chunks and
  language prompt state.
- WhisperKit offers complete-buffer transcription and its own audio stream
  helper, but the catalog rows selected here are not publisher-native streaming
  models.

The runtime decision therefore must not flatten all rows into one fake capability.
The later event-contract and adapter-ownership decisions should normalize only
semantics proven by each engine. At the runtime boundary, model-specific wrappers
may differ internally while all remain lifecycle-owned and vend opaque Dictation
session handles to Pipeline.

## Maintenance posture

The cost of the chosen strategy is tracking two upstream APIs and four materially
different NVIDIA execution paths. Contain that cost at the family-adapter boundary:

- keep FluidAudio/WhisperKit types out of catalog identity, Config, Pipeline,
  Settings, and Badge;
- pin dependency and artifact revisions together in a reviewed baseline;
- run adapter conformance, known-audio, load/unload, cancellation, and corruption
  tests before accepting any runtime upgrade;
- treat new upstream model folders as unknown until a later FoldWise baseline
  admits them; and
- preserve the single-resident lifecycle even if an upstream manager can run
  multiple streams.

FluidAudio is still pre-1.0 and its model surface is expanding, so compatible
version ranges are too broad for an evidence-backed release baseline. WhisperKit
has reached 1.0, but its model support tables, Core ML packages, and convenience
download behavior can still change independently; it needs the same explicit
upgrade gate.

## Licensing

The runtime libraries are permissively licensed:

- FluidAudio is Apache-2.0
  ([pinned license](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/LICENSE));
- Argmax OSS / WhisperKit is MIT
  ([pinned license](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/LICENSE)).

FoldWise must ship the applicable runtime license/notices. These runtime grants
do **not** settle the model and converted-artifact rights. The Unified conversion
license mismatch, Argmax conversion provenance, model notices, and complete
redistribution manifests remain gates for
[Verify licenses and immutable artifacts for FoldWise's ASR catalog](https://github.com/hadrysm/foldwise-voice/issues/200).
Catalog representation may precede redistribution approval; download, selection,
or bundled distribution may not bypass an unresolved gate.

## Acceptance gates

The runtime decision is implementation-ready when downstream work preserves these
constraints:

1. Map the four NVIDIA rows to their actual FluidAudio manager shapes and the
   three Whisper rows to WhisperKit.
2. Keep both runtimes behind one lifecycle and retain drop-before-load engine
   replacement.
3. Replace moving-revision convenience downloads with FoldWise-owned immutable,
   manifest-verified staging.
4. Pin runtime revisions and require adapter/fixture regression tests for every
   upgrade.
5. Gate model/profile eligibility on FoldWise measurements for supported Apple
   Silicon tiers.
6. Keep capability presentation exact: batch, buffered streaming, native
   cache-aware streaming, and translation are not family-wide synonyms.
7. Complete the separate artifact-license and notices review before release.

## Bottom line

FoldWise already has the right runtime families. The smallest truthful strategy
is to deepen their adapters, not replace them: FluidAudio executes the four
reviewed NVIDIA rows, WhisperKit executes the three reviewed Whisper rows, and
the existing lifecycle ensures only one engine is resident. FoldWise's new
ownership belongs around artifact identity, integrity, eligibility, and upgrade
acceptance—not inside reimplementations of mature ASR decoders.
