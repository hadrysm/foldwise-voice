# macOS runtime strategy for the Handy catalog

Research answer for
[**Evaluate macOS runtimes for all Handy model architectures**](https://github.com/hadrysm/foldwise-voice/issues/193),
audited on
2026-07-19 against the catalog baseline established in
[`handy-catalog-parity-baseline.md`](handy-catalog-parity-baseline.md).

## Executive answer

Use **transcribe.cpp v0.1.3 as the one runtime for every Handy catalog entry**.
It is the only evaluated runtime that consumes the catalog's exact GGUF files,
registers all 16 catalog architectures, runs in-process and locally on macOS,
and exposes both batch and native streaming through an official Swift/C API.

Adopt it through a **temporary hybrid rollout**, not a hybrid catalog:

- route all 65 Handy entries and all 337 of their quantized artifacts through
  one new transcribe.cpp adapter;
- preserve FoldWise's existing FluidAudio and WhisperKit models during
  hardware, quality, packaging, and migration acceptance; and
- retire or deliberately classify those five existing Core ML selections only
  after the replacement data exists.

Do not distribute Handy architectures across FluidAudio, WhisperKit, ONNX, and
family-specific ports. Such a mosaic still needs transcribe.cpp for the missing
families, cannot consume the baseline's exact files in the other engines, and
multiplies model conversion, capability, download, lifecycle, and test work.
The hybrid is therefore a rollout safety measure; transcribe.cpp remains the
complete-catalog execution path.

This is a technically complete runtime answer, not a claim that every catalog
model is practical on every Mac. In particular, the default Voxtral Small 24B
artifact is 17.14 GB before inference overhead, its F16 artifact is 48.55 GB,
and its own M4 Max benchmark calls CPU impractical. FoldWise needs model-level
hardware eligibility and measured acceptance rather than a single “macOS
compatible” promise.

## What “complete coverage” requires

The pinned Handy catalog contains 65 entries and 337 files under 16 exact
`general.architecture` labels. These are not interchangeable model formats:
every catalog download is a transcribe.cpp GGUF published by
`handy-computer`. FoldWise's current engines instead download their own Core ML
model directories. Sharing a family name such as Whisper or Parakeet does not
make the artifacts interchangeable.

The coverage proof is unusually direct:

1. Handy's pinned catalog consumer assigns **every** catalog descriptor
   `EngineType::TranscribeCpp`, constructs its identity from the selected GGUF
   filename, and keeps its old ONNX engines only for separate legacy entries
   ([Handy catalog adapter](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/catalog/mod.rs),
   [Handy model manager](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/managers/model.rs)).
2. transcribe.cpp v0.1.3 registers all 16 runtime architecture handlers in its
   dispatch table
   ([architecture registry](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/src/transcribe-arch.cpp))
   and lists the corresponding supported variants
   ([runtime README](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/README.md)).
3. The three catalog labels whose implementation-directory names differ are
   not gaps: the registered model names are `cohere_asr`, `granite_speech`, and
   `granite_speech_nar`
   ([Cohere registration](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/src/arch/cohere/model.cpp),
   [Granite registration](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/src/arch/granite/model.cpp),
   [Granite NAR registration](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/src/arch/granite_nar/model.cpp)).

| Catalog architecture | Entries | Artifacts | transcribe.cpp v0.1.3 handler |
| --- | ---: | ---: | --- |
| `canary` | 4 | 24 | `canary` |
| `canary_qwen` | 1 | 6 | `canary_qwen` |
| `cohere_asr` | 1 | 6 | `cohere_asr` |
| `funasr_nano` | 2 | 12 | `funasr_nano` |
| `gigaam` | 4 | 24 | `gigaam` |
| `granite_speech` | 3 | 18 | `granite_speech` |
| `granite_speech_nar` | 1 | 6 | `granite_speech_nar` |
| `medasr` | 1 | 6 | `medasr` |
| `moonshine` | 14 | 42 | `moonshine` |
| `moonshine_streaming` | 3 | 9 | `moonshine_streaming` |
| `parakeet` | 12 | 72 | `parakeet` |
| `qwen3_asr` | 2 | 12 | `qwen3_asr` |
| `sensevoice` | 1 | 6 | `sensevoice` |
| `voxtral` | 2 | 12 | `voxtral` |
| `voxtral_realtime` | 1 | 6 | `voxtral_realtime` |
| `whisper` | 13 | 76 | `whisper` |
| **Total** | **65** | **337** | **16/16** |

Counts come from the immutable
[`catalog.json`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/catalog/catalog.json).
That file, rather than the summary table, remains the normative artifact
inventory.

## Strategy comparison

| Strategy | Exact Handy coverage | macOS execution | Packaging and maintenance | Conclusion |
| --- | --- | --- | --- | --- |
| transcribe.cpp for the full catalog | **65/65 entries, 337/337 artifacts, 16/16 architectures** | In-process; Metal + CPU on Apple silicon, CPU on Intel; macOS 13+ Swift surface | One GGUF runtime and one catalog adapter; young pre-1.0 ABI and unfinished SwiftPM distribution are material risks | **Target runtime** |
| Existing FoldWise engines only | 0/337 exact files; semantic coverage is only Parakeet and Whisper | FluidAudio uses Core ML/ANE; WhisperKit uses Core ML with FoldWise's encoder on GPU and decoder on ANE | Already integrated and packaged, but only five curated selections | Cannot meet full parity |
| Add more native/Core ML or ONNX family engines | Still 0/337 unless FoldWise creates and maintains parallel conversions | Potentially excellent family-specific acceleration | One converter, artifact set, adapter, capability interpretation, and validation suite per family | Reject as the catalog strategy |
| Permanent split by architecture | Can reach 65/65 only because transcribe.cpp handles every catalog file that the other engines cannot | Mixed Metal, ANE, and CPU behavior | Three or more runtime stacks; duplicate family identities and inconsistent capabilities/performance | No coverage benefit; avoid |
| Temporary hybrid rollout | Full Handy coverage through transcribe.cpp, with the five current selections retained temporarily | Keeps today's known-good default while measuring the new path | Temporary duplication with an explicit exit/retention decision | **Recommended rollout** |

### Existing Swift engines

FoldWise currently exposes two FluidAudio Parakeet variants and three
WhisperKit Whisper variants in
[`ASRModelCatalog.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelCatalog.swift).
Their adapters validate Core ML packages/directories, not `.gguf` files
([`ASRModelAdapters.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelAdapters.swift)).
Therefore their exact baseline-artifact coverage is zero even where their model
lineage overlaps Handy.

FluidAudio itself supports more Core ML ASR models than FoldWise currently
integrates, including SenseVoice and Nemotron streaming, but its official
inventory still uses separate `FluidInference/*-coreml` repositories and does
not cover all 16 families
([FluidAudio model inventory](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Documentation/Models.md)).
WhisperKit is specifically the OpenAI Whisper speech-to-text product and loads
`argmaxinc/whisperkit-coreml` variants
([Argmax OSS README](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/README.md)).

These engines remain valuable benchmarks: FluidAudio's ANE path is optimized
for low power and background use, while WhisperKit is already stable in the
FoldWise lifecycle. They do not reduce the runtime needed for the Handy files.

### Additional native engines and family ports

Handy's own older hybrid demonstrates the ceiling of the most plausible
alternative. Its pinned manifest uses `transcribe-rs` ONNX implementations for
Parakeet, Moonshine, SenseVoice, GigaAM, Canary, and Cohere, while using
transcribe.cpp for catalog GGUF
([Handy `Cargo.toml`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/Cargo.toml),
[engine enum and load paths](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/managers/transcription.rs)).
That ONNX path has neither exact GGUF compatibility nor implementations for
Canary-Qwen, FunASR Nano, either Granite architecture, MedASR, Qwen3-ASR,
either Voxtral architecture, or Whisper. It is also a Rust integration rather
than a Swift package.

Implementing those gaps directly over Core ML, ONNX Runtime, MLX, or ggml is
possible in the abstract, but it makes FoldWise responsible for ports and
converted artifacts already owned and numerically validated by transcribe.cpp.
There is no evidence-backed second runtime with complete exact coverage.

## macOS, hardware, and local-execution fit

The official Swift binding declares macOS 13+ and ships these backends:

- macOS arm64: Metal + CPU;
- macOS x86_64: CPU only.

That fits FoldWise's macOS 14 deployment target. The release's
`TranscribeCpp.xcframework.zip` contains one universal macOS dynamic framework
with arm64 and x86_64 slices; the same release also publishes separate native
macOS archives
([Swift binding README](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/README.md),
[v0.1.3 release](https://github.com/handy-computer/transcribe.cpp/releases/tag/v0.1.3)).
The API loads a model from a local filesystem path and accepts in-memory
16 kHz mono Float32 PCM. It has no inference service or network dependency, so
recognition stays in the FoldWise process after a model download
([Swift `Model`](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Sources/TranscribeCpp/Model.swift),
[Swift binding quick start](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/README.md)).

The API shape also fits FoldWise's existing lifecycle invariants. A loaded
model is shareable, sessions are single-threaded, and transcribe.cpp 0.x allows
only one compute operation or stream per loaded model. Its streaming API emits
separate append-only committed text and volatile tentative text
([C API concurrency contract](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/include/transcribe.h),
[Swift streaming API](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Sources/TranscribeCpp/Streaming.swift)).
FoldWise already serializes Dictation sessions and requires drop-before-load
with one resident engine in
[`ADR-0005`](../adr/0005-second-asr-engine-behind-transcribing.md), so a
single transcribe.cpp adapter deepens the existing seam rather than requiring a
Rust sidecar or new process owner.

## Packaging and distribution

The runtime binary is small relative to the models: the v0.1.3 xcframework zip
is 13,089,928 bytes with published SHA-256
`b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd`.
The models should remain on-demand downloads. The 65 default quantizations total
61.39 GB; bundling them would also collide with gated and model-specific legal
terms.

The present Swift integration is not turnkey:

- the official wrapper calls itself “in development”;
- its standalone SwiftPM mirror is planned but not published;
- the checked-in package expects a local xcframework path, while the release
  asset directly exposes only the raw `CTranscribe` module; and
- the native C ABI explicitly permits breaking changes across 0.x releases.

These facts require an exact runtime pin, matching headers/wrapper sources, an
artifact checksum, and an intentional upgrade test gate
([Swift package](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Package.swift),
[Swift distribution status](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/README.md),
[C ABI stability contract](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/include/transcribe.h)).
A practical initial integration is a remote binary target pinned to the v0.1.3
xcframework plus version-matched, locally owned Swift wrapper/adapter code;
replace that with the upstream SwiftPM mirror if and when it is published and
meets the same gates.

The inspected v0.1.3 artifact is a dynamic, ad-hoc-signed
`CTranscribe.framework`. FoldWise's current
[`build_swift_app.py`](../../scripts/build_swift_app.py) copies only the main
executable into the app before signing. It must instead embed the framework in
`Contents/Frameworks`, verify its runtime search path, sign nested code before
the containing app, and exercise notarization/Gatekeeper in release CI. This is
a release blocker, not a reason to choose another runtime.

## Performance and supported-device truth

Upstream performance evidence is promising but insufficient to establish a
FoldWise support envelope. On an Apple M4 Max with Metal, published v0.1.3 model
cards report:

- Parakeet TDT 0.6B v3 Q8: 74 ms for 11 seconds of audio (149× realtime);
- Moonshine Streaming Tiny Q8: 50 ms for 11 seconds (218× realtime);
- Cohere Transcribe Q8: 150 ms for 11 seconds (74× realtime); and
- Voxtral Small 24B: roughly 3–4× realtime on Metal, with CPU described as
  impractical.

See the upstream
[Parakeet](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/docs/models/parakeet-tdt-0.6b-v3.md),
[Moonshine Streaming](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/docs/models/moonshine-streaming-tiny.md),
[Cohere](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/docs/models/cohere-transcribe-03-2026.md),
and [Voxtral 24B](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/docs/models/voxtral-small-24b-2507.md)
model cards for methods and quantization-specific results.

These are single-machine publication measurements on macOS 26, not evidence
for FoldWise's whole macOS 14+ range. Before making a model selectable, measure
at least cold load, peak resident/device memory, short-utterance latency,
long-form realtime factor, cancellation, thermal behavior, and transcript
correctness on representative Apple-silicon tiers. Test Intel separately and
either publish a smaller CPU-qualified subset or state per-model unsupported
hardware explicitly. Architecture support must not be presented as a
performance guarantee.

## Licensing

Runtime licensing is straightforward: transcribe.cpp is MIT, and its vendored
ggml and miniz components are also MIT. The xcframework carries all three
license texts
([runtime license](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/LICENSE),
[third-party notices](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/THIRD-PARTY-LICENSES.md)).
FoldWise must reproduce the notices in its distribution. FluidAudio is
Apache-2.0 and Argmax OSS is MIT; retaining them temporarily does not introduce
a copyleft conflict
([FluidAudio license](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/LICENSE),
[Argmax license](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/LICENSE)).

Runtime permission does not grant model permission. The catalog baseline found
unverified or conflicting license metadata, a non-commercial entry, and gated
Cohere/MedASR sources. FoldWise should download selected artifacts on demand,
retain per-model legal metadata and notices, require authentication/term
acceptance where upstream requires it, and prevent redistribution or selection
where legal/hardware policy is unresolved. Changing engines does not remove
these obligations.

## Decision and acceptance gates

The implementation-ready runtime decision is:

1. Add one transcribe.cpp family adapter behind the existing lifecycle and use
   it for every pinned Handy descriptor and quantization.
2. Pin the runtime binary, Swift wrapper/header revision, checksum, catalog
   revision, and each downloaded model artifact independently.
3. Keep FluidAudio and WhisperKit selections during a measured migration; do
   not use them to execute Handy catalog identities or silently substitute
   Core ML artifacts for selected GGUFs.
4. Gate model availability by legal access, artifact integrity, architecture,
   memory/device eligibility, and a FoldWise-owned quality/performance matrix.
5. Ship only after the dynamic framework is embedded, signed, notarized, and
   exercised from the produced DMG on both supported architectures.
6. After acceptance, make an explicit follow-up decision: retire the existing
   engines to minimize maintenance, or retain named Core ML selections as a
   deliberately separate performance/power tier. Do not leave the temporary
   hybrid accidental or indefinite.

This resolves the engine-coverage question while leaving capability truth,
live-session ownership, and the exact supported-device thresholds to their
dedicated decisions and empirical acceptance work.
