# Independent ASR catalog baseline

Status: research decision for [Establish FoldWise's independent ASR catalog baseline](https://github.com/hadrysm/foldwise-voice/issues/202), 2026-07-19

## Decision

FoldWise should launch its independently reviewed catalog with seven model rows:

1. NVIDIA Parakeet TDT 0.6B v3 — INT8
2. NVIDIA Parakeet TDT-CTC 110M — float32 Core ML
3. NVIDIA Parakeet Unified EN 0.6B — streaming INT8
4. NVIDIA Nemotron 3.5 ASR Streaming Multilingual 0.6B — mixed precision
5. OpenAI Whisper small
6. OpenAI Whisper large-v3 Turbo — Argmax 626 MB package
7. OpenAI Whisper large-v3

This is a reviewed baseline, not a mirror of FluidAudio or WhisperKit's downloadable
directories. A row belongs only when FoldWise can state its publisher identity,
capabilities, runtime path, device eligibility, immutable artifact identity, and
license posture.

Two artifact-license questions remain release gates for [Verify licenses and immutable artifacts for FoldWise's ASR catalog](https://github.com/hadrysm/foldwise-voice/issues/200):

- FluidInference labels the Unified conversion CC-BY-4.0 while NVIDIA's source model
  uses the NVIDIA Open Model License.
- Argmax's Whisper conversion repository supplies no model-card license or repository
  LICENSE, even though OpenAI's source weights are MIT.

Those questions block redistribution, not the catalog design.

## Recommended rows

| Catalog row | Publisher truth | FoldWise runtime truth | Initial eligibility |
| --- | --- | --- | --- |
| Parakeet TDT 0.6B v3 INT8 | 600M parameters; 25 European languages; automatic language choice; punctuation and capitalization | FluidAudio 0.15.4 uses the INT8 Core ML package by default | Apple Silicon, macOS 14+ |
| Parakeet TDT-CTC 110M | 110M; English only; punctuation and capitalization | FluidAudio has a dedicated model manager and float32 Core ML package | Apple Silicon, macOS 14+ |
| Parakeet Unified EN 0.6B streaming INT8 | 600M; English; batch and buffered streaming; punctuation and capitalization | The pinned public factory uses 1.04 s audio chunks plus 1.04 s right context, about 2.08 s theoretical latency | Apple Silicon, macOS 14+ |
| Nemotron 3.5 multilingual mixed precision | 600M; 32 out-of-box language-locales plus 8 adaptation-ready locales; prompt or automatic language selection; punctuation and capitalization | FluidAudio has a native cache-aware RNNT manager; 560, 1120 and 2240 profiles are runtime/artifact profiles, not separate models | Apple Silicon, macOS 14+; 2240 default, 560 low-latency option |
| Whisper small | 244M; multilingual transcription, language detection, timestamps, and speech translation to English | Supported by WhisperKit's M1 and M2–M4 device tables | M1 and newer |
| Whisper large-v3 Turbo, 626 MB | 809M; multilingual transcription, detection, timestamps; no reliable translation-to-English capability | The package config is Turbo despite its folder name; supported on M1 and M2–M4 | M1 and newer |
| Whisper large-v3, 947 MB | 1.55B; multilingual transcription, detection, timestamps, and translation to English | Full 32-layer encoder/decoder package; supported on M1 and M2–M4 | M1 and newer, with a heavier prewarm and memory warning |

## Capability presentation

Capabilities must be attached to exact rows rather than inferred from family names.

- Parakeet v3 lists exactly its 25 published languages:
  Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French,
  German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish,
  Portuguese, Romanian, Slovak, Slovenian, Spanish, Swedish, Russian, and Ukrainian.
- Parakeet v3 must not claim Japanese.
- TDT-CTC 110M and Unified EN are English-only.
- Nemotron lists NVIDIA's 32 out-of-box language-locales as supported: 19
  transcription-ready plus 13 broad-coverage locales. The eight adaptation-ready
  locales and extra artifact prompt IDs are not supported-language claims.
- Whisper can display broad multilingual support and automatic detection.
- Non-Turbo multilingual Whisper rows may advertise translation from speech to English.
- Turbo must not advertise translation; OpenAI says it was not trained for that task
  and returns the original language when translation is requested.
- “Streaming” must not imply a universal latency. Unified's pinned path has about
  2.08 seconds of algorithmic lookahead, while Nemotron offers profile-specific latency.

Quantization and context are deployment facts, not separate publisher models. Nemotron
Latin/full vocabulary packages and 560/1120/2240 context folders should therefore be
profiles beneath one catalog row. The same rule applies to Whisper conversion sizes.

## Immutable artifact baseline

The reviewed baseline must store repository, immutable revision, required file list,
byte count, and SHA-256 for every downloaded file. A directory name or moving
`main` URL is not identity.

| Row/profile | Conversion repository revision | Required bytes | Representative LFS SHA-256 |
| --- | --- | ---: | --- |
| Parakeet v3 INT8 | `FluidInference/parakeet-tdt-0.6b-v3-coreml@aed02740059203c4a87495924f685de3722ae9ce` | 483,105,645 | Encoder: `e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421` |
| TDT-CTC 110M | `FluidInference/parakeet-tdt-ctc-110m-coreml@9bc92ead6e8f17eca92a869fd578ae76842b82ba` | 227,466,209 | Frontend: `a1c90b88b52667ee4f349b39994003cc2a9fb1b12c310752399d90c880286a7b` |
| Unified EN streaming INT8 | `FluidInference/parakeet-unified-en-0.6b-coreml@4252711f6f060f9a2f91e5f081a806d7f45eebd8` | 610,062,293 | Encoder: `259e5818cf4acee1155409a048ec408eecd8cfc27ade04ba18bca243398cc9b6` |
| Nemotron full 2240 | `FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML@1a41b75758b0337ff67db7d5408280aaaf23074e` | 664,846,846 | Encoder: `2e00be98049a22e095452c020f183d2b23728e145cc814ba031436931b4f2e8f` |
| Whisper small | `argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808` | 486,487,465 | Audio encoder: `fe35cef2c9406993a635639b16f373f6debb0215ac115b7bf93fa03c8e10310b`; decoder: `bfea8044a8f38e8d33f56585b1e75ce023d3845e2a945e20480bd7e16558016e` |
| Whisper Turbo 626 MB | same Argmax revision | 626,718,238 | Audio encoder: `e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1`; decoder: `d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db` |
| Whisper large-v3 947 MB | same Argmax revision | 948,108,786 | Audio encoder: `9b819fb62291e63c6b5596238a73964bfbdaccb8a12fd5672e7eb32639a57f83`; decoder: `e53c8476c43310ad9fd2f4be996b7d803208428b0b137848972932406a30ef2f` |

These are representative blobs, not complete package manifests. FoldWise still needs
a complete SHA-256 manifest for every required file before shipping any package.

FluidAudio's downloader enumerates `tree/main` and resolves moving `main` files.
WhisperKit's convenience download also defaults to an unpinned repository revision.
Neither current FoldWise adapter establishes immutable identity. Catalog availability
must therefore require FoldWise's manifest validation, not merely a successful download.

## Include, defer, supersede

### Include now

- Parakeet v3 INT8: multilingual default and existing FoldWise path.
- TDT-CTC 110M float32: materially smaller, fast English tier; FluidAudio reports 96.5x
  real-time and 3.01% WER on LibriSpeech test-clean on an M2.
- Unified EN streaming INT8: distinct English buffered-streaming behavior.
- Nemotron 3.5: native multilingual streaming with explicit latency profiles.
- Whisper small: established lighter multilingual Whisper tier.
- Turbo 626 MB: Argmax-recommended Turbo package and supported on M1 onward.
- Full large-v3 947 MB: highest-capability non-Turbo Whisper tier.

### Defer

- Parakeet v3 INT4: FluidAudio supports it, but FoldWise currently hardcodes INT8;
  include only after quality acceptance and adapter work.
- Whisper small 216 MB: artifact exists but is absent from Argmax's supported-device
  arrays and checksum table.
- Whisper Turbo 547 MB: has Argmax metadata but is absent from supported-device arrays.
- Nemotron 4480 and alternate vocabulary/context combinations: expose after memory,
  latency, and quality acceptance on FoldWise's supported Macs.
- Any source model without a reviewed Core ML conversion and runtime adapter.

### Supersede

- Unified EN FP16: about 1.20 GB, while FluidAudio says INT8 gives nearly identical
  accuracy and latency at roughly half the storage.
- Turbo 632 MB: duplicates the 626 MB package's principal weights and adds a decoder
  context-prefill component removed in WhisperKit 1.0; it is also not M1-eligible.
- Treating every artifact folder as a user-facing model: folders are deployment profiles.

## License and access posture

| Component | Authoritative license | Catalog consequence |
| --- | --- | --- |
| Parakeet v3 and TDT-CTC source models | CC-BY-4.0 | Preserve attribution, copyright, license/disclaimer link, and modification notice when sharing |
| Parakeet Unified source model | NVIDIA Open Model License | Redistribution requires the license and Notice attribution; review Trustworthy AI and termination terms |
| Nemotron 3.5 source model | OpenMDW 1.1 | Distribution retains the agreement and applicable copyright/origin notices |
| OpenAI Whisper code and weights | MIT | Retain copyright and permission notice |
| FluidAudio runtime | Apache-2.0 | Include Apache notices as applicable |
| WhisperKit runtime | MIT | Retain copyright and permission notice |

The Nemotron conversion repository API reports `gated: false` at the pinned revision,
although its README still describes a Discord access flow. Record current access truth
separately from license and recheck it when publishing the manifest.

## Device and lifecycle requirements

- Keep the current product floor: Apple Silicon and macOS 14+.
- Use runtime-supported device tables only as an eligibility floor, not a performance promise.
- Present download size separately from peak install/prewarm memory.
- WhisperKit prewarm invokes Core ML specialization and writes compiled caches outside
  the app; peak compilation memory can exceed the combined model weights.
- Prewarm large components sequentially and surface disk/memory failures as unavailable,
  never as selected-but-silently-falling-back.
- Preserve the current single-resident-engine lifecycle and transactional model selection.

## Downstream decisions

[Evaluate macOS runtimes for FoldWise's independent ASR catalog](https://github.com/hadrysm/foldwise-voice/issues/193) should define a FoldWise-owned downloader that resolves only pinned revisions, verifies a complete SHA-256 manifest, stages atomically, and reports profile eligibility.

[Decide catalog parity, updates, quantizations, and device support](https://github.com/hadrysm/foldwise-voice/issues/197) should model capability claims at exact model/profile level: language set, translation, punctuation, streaming mode, context/latency, quantization, size, and device floor.

[Verify licenses and immutable artifacts for FoldWise's ASR catalog](https://github.com/hadrysm/foldwise-voice/issues/200) should close the Unified conversion-license mismatch, establish permission and notices for Argmax conversions, and produce the complete redistribution manifest.

## Primary sources

- [NVIDIA Parakeet v3 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/tree/7c35754d166cca382ad1e53e68b01e7c575f3a1d)
- [NVIDIA TDT-CTC 110M model card](https://huggingface.co/nvidia/parakeet-tdt_ctc-110m/tree/431a349f3051ab85c22b9b7a2741b5fe77065665)
- [NVIDIA Unified EN model card](https://huggingface.co/nvidia/parakeet-unified-en-0.6b/tree/fe53cd885760c96b6a5f51a0bfd362cb4584a98b)
- [NVIDIA Nemotron 3.5 model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b/tree/f3d333391852ba876df169dcc9ba902d25b6ab0b)
- [FluidAudio 0.15.4 source](https://github.com/FluidInference/FluidAudio/tree/b9d43724cbdb5a980e441fd54180964e94d470f7)
- [WhisperKit 1.0.0 source](https://github.com/argmaxinc/argmax-oss-swift/tree/25c62997041c134b03ca82731ce2f6fd2cae1eb9)
- [OpenAI Whisper source and model table](https://github.com/openai/whisper/tree/04f449b8a437f1bbd3dba5c9f826aca972e7709a)
- [Argmax Core ML artifacts](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808)
- [Creative Commons Attribution 4.0 legal code](https://creativecommons.org/licenses/by/4.0/legalcode)
- [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)
- [OpenMDW License 1.1](https://openmdw.ai/license/1-1/)

## Bottom line

The first catalog should be small and intentionally asymmetric: two efficient Parakeet
tiers, two genuinely different streaming tiers, and three established Whisper tiers.
Exact capability truth and immutable validated artifacts matter more than exhaustively
listing every downloadable conversion.
