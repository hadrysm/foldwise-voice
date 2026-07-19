# FoldWise ASR catalog license and artifact audit

Status: research decision for [Verify licenses and immutable artifacts for FoldWise's ASR catalog](https://github.com/hadrysm/foldwise-voice/issues/200), 2026-07-19

## Decision

The seven-row catalog may be visible as a reviewed factual catalog, but its artifacts do not all have the same release posture.

| Exact reviewed profile | Catalog visibility | Direct in-app download from publisher | FoldWise-hosted redistribution |
| --- | --- | --- | --- |
| Parakeet TDT 0.6B v3, INT8 | Yes, with NVIDIA/FluidInference attribution | Release after FoldWise pins and verifies the 21-file manifest and ships conservative CC BY 4.0 **and** Apache-2.0 notices | Release after the same manifest and dual notices are in the product |
| Parakeet TDT-CTC 110M, float32 | Yes, with NVIDIA/FluidInference attribution | Release after FoldWise pins and verifies the 16-file manifest and ships CC BY 4.0 attribution | Release after the same manifest and notices are in the product |
| Parakeet Unified EN 0.6B, streaming `[70,13,13]` INT8 | Yes, but describe it as awaiting artifact clearance | **Blocked**: FluidInference must correct the source identity and confirm that NVIDIA Open Model License terms continue to govern the conversion | **Blocked** by the same two corrections plus the NVIDIA agreement and `Notice` file in the distribution |
| Nemotron 3.5 ASR Streaming Multilingual 0.6B, full-vocabulary `multilingual/2240ms` | Yes, with NVIDIA/FluidInference attribution | Release after FoldWise pins and verifies the 22-file manifest and carries OpenMDW-1.1 notices | Release after the same manifest, agreement, copyright, and origin notices are in the product |
| Whisper small, `openai_whisper-small` | Yes, attributed to OpenAI and identified as an Argmax Core ML conversion | **Blocked** until Argmax grants or publishes permission for the exact conversion revision; tokenizer closure must also be pinned | **Blocked** by the same permission and notice gate |
| Whisper large-v3 Turbo, `openai_whisper-large-v3-v20240930_626MB` | Yes; the exact package is Turbo despite the folder name | **Blocked** until Argmax grants or publishes permission and confirms the exact source-to-conversion provenance | **Blocked** by the same permission/provenance gate |
| Whisper large-v3, `openai_whisper-large-v3_947MB` | Yes, attributed to OpenAI and identified as an Argmax Core ML conversion | **Blocked** until Argmax grants or publishes permission for the exact conversion revision; tokenizer closure must also be pinned | **Blocked** by the same permission and notice gate |

“Direct download” means FoldWise instructs the installed app to copy the publisher's artifact to the user's Mac. Public readability is not itself a copyright license, so the two blocked publisher repositories remain blocked even if FoldWise does not re-host their bytes. This is a release-engineering conclusion; final legal approval remains a maintainer/counsel gate.

## Exact identities, access, and licenses

Every Hugging Face source, conversion, and tokenizer repository below was public, non-private, enabled, and reported `gated: false` at its immutable revision through the publisher's model API. The Nemotron conversion card still says to request access through Discord, but the immutable repository API and every reviewed file were anonymously readable; treat that prose as stale and recheck `gated` immediately before release ([NVIDIA source API](https://huggingface.co/api/models/nvidia/nemotron-3.5-asr-streaming-0.6b/revision/f3d333391852ba876df169dcc9ba902d25b6ab0b), [FluidInference conversion API](https://huggingface.co/api/models/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/revision/1a41b75758b0337ff67db7d5408280aaaf23074e), [immutable conversion card](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/blob/1a41b75758b0337ff67db7d5408280aaaf23074e/README.md)).

| Catalog row | Original source model | Conversion artifact | License result and duties |
| --- | --- | --- | --- |
| Parakeet v3 INT8 | `nvidia/parakeet-tdt-0.6b-v3@7c35754d166cca382ad1e53e68b01e7c575f3a1d` ([card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/blob/7c35754d166cca382ad1e53e68b01e7c575f3a1d/README.md)) | `FluidInference/parakeet-tdt-0.6b-v3-coreml@aed02740059203c4a87495924f685de3722ae9ce` ([card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/blob/aed02740059203c4a87495924f685de3722ae9ce/README.md)) | Source and machine-readable conversion metadata are CC BY 4.0. Sharing requires appropriate creator credit, supplied copyright/license/disclaimer notices, a license link, and an indication of FoldWise/FluidInference modifications; do not imply endorsement or add legal/technical restrictions ([CC BY 4.0 legal code](https://creativecommons.org/licenses/by/4.0/legalcode.en)). The conversion card's final “Apache 2.0” sentence conflicts with its CC BY YAML and does not say whether Apache applies to the conversion layer or merely the runtime. The two duty sets are compatible enough for a conservative release posture: retain CC BY as the source-weight license and also ship Apache-2.0 text/notices for the conversion/runtime layer, without claiming that dual compliance resolves the publisher's ambiguous declaration. |
| TDT-CTC 110M float32 | `nvidia/parakeet-tdt_ctc-110m@431a349f3051ab85c22b9b7a2741b5fe77065665` ([card](https://huggingface.co/nvidia/parakeet-tdt_ctc-110m/blob/431a349f3051ab85c22b9b7a2741b5fe77065665/README.md)) | `FluidInference/parakeet-tdt-ctc-110m-coreml@9bc92ead6e8f17eca92a869fd578ae76842b82ba` ([card](https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml/blob/9bc92ead6e8f17eca92a869fd578ae76842b82ba/README.md)) | Both cards declare CC BY 4.0; the same duties apply. The conversion card identifies the source model and describes the float32 conversion. |
| Unified EN streaming INT8 | `nvidia/parakeet-unified-en-0.6b@fe53cd885760c96b6a5f51a0bfd362cb4584a98b` ([card](https://huggingface.co/nvidia/parakeet-unified-en-0.6b/blob/fe53cd885760c96b6a5f51a0bfd362cb4584a98b/README.md)) | `FluidInference/parakeet-unified-en-0.6b-coreml@4252711f6f060f9a2f91e5f081a806d7f45eebd8` ([card](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/blob/4252711f6f060f9a2f91e5f081a806d7f45eebd8/README.md)) | The source is governed by the NVIDIA Open Model License; the conversion instead declares CC BY 4.0 and its YAML says `base_model: nvidia/parakeet-tdt-0.6b-v2`, while its prose and pinned `config.json` identify Parakeet Unified ([conversion config](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/blob/4252711f6f060f9a2f91e5f081a806d7f45eebd8/config.json)). NVIDIA Open Model License §3(c) expressly allows additional or different terms for a distributor's modifications or a Derivative Model as a whole, so a CC BY conversion layer is not inherently incompatible; it does **not** displace the NVIDIA conditions. Distribution must include that agreement and a `Notice` containing `Licensed by NVIDIA Corporation under the NVIDIA Open Model License`; Trustworthy AI, guardrail, termination, trade-compliance, and indemnity terms also remain ([NVIDIA license](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/)). The immutable conversion record does not state this layering, ships the erroneous source identity, and does not identify an exact input revision/checksum. FluidInference must correct those lineage/notice gaps, or FoldWise must independently reconvert the pinned NVIDIA source, before FoldWise downloads or redistributes this conversion. |
| Nemotron multilingual full 2240 | `nvidia/nemotron-3.5-asr-streaming-0.6b@f3d333391852ba876df169dcc9ba902d25b6ab0b` ([card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b/blob/f3d333391852ba876df169dcc9ba902d25b6ab0b/README.md)) | `FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML@1a41b75758b0337ff67db7d5408280aaaf23074e` ([card](https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/blob/1a41b75758b0337ff67db7d5408280aaaf23074e/README.md)) | Both declare OpenMDW-1.1. Distribution must retain a copy of the agreement and every applicable copyright and origin notice; the litigation-termination clause and downstream-rights due diligence also apply ([OpenMDW-1.1](https://openmdw.ai/license/1-1/)). |
| Whisper small | OpenAI Whisper small; OpenAI states that code and model weights are MIT at `openai/whisper@04f449b8a437f1bbd3dba5c9f826aca972e7709a` ([README](https://github.com/openai/whisper/blob/04f449b8a437f1bbd3dba5c9f826aca972e7709a/README.md#license), [MIT text](https://github.com/openai/whisper/blob/04f449b8a437f1bbd3dba5c9f826aca972e7709a/LICENSE)) | `argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-small` ([tree](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-small)) | OpenAI MIT permission requires retaining OpenAI's copyright and permission notice. The Argmax conversion repository has no license metadata, repository `LICENSE`, per-folder license, or copyright/permission notice ([repository card](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/README.md)); WhisperKit's MIT license covers the runtime code, not automatically a separate model repository ([pinned runtime license](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/LICENSE)). Obtain an explicit artifact license or written permission covering this revision and folder. |
| Whisper large-v3 Turbo 626 MB | OpenAI Whisper large-v3-turbo; the OpenAI repository's immutable download table identifies the official Turbo weights and SHA-256 `aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a` ([pinned source](https://github.com/openai/whisper/blob/04f449b8a437f1bbd3dba5c9f826aca972e7709a/whisper/__init__.py)) | `argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-large-v3-v20240930_626MB` ([tree](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-large-v3-v20240930_626MB)) | OpenAI's MIT duties apply to the source weights. Argmax permission is absent as above. Provenance is strong but incomplete: the Argmax folder's `config.json` has the same private `_name_or_path`, 32 encoder layers, 4 decoder layers, 128 mel bins, and 51,866 vocabulary entries as OpenAI's immutable Turbo config at `openai/whisper-large-v3-turbo@41f01f3fe87f28c78e2fbf8b568835947dd65ed9` ([Argmax config](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-large-v3-v20240930_626MB/config.json), [OpenAI config](https://huggingface.co/openai/whisper-large-v3-turbo/blob/41f01f3fe87f28c78e2fbf8b568835947dd65ed9/config.json)). This proves the catalog row is Turbo, but not which source-weight blob Argmax converted. Require Argmax to identify that input revision/checksum and license the conversion before release. |
| Whisper large-v3 947 MB | OpenAI Whisper large-v3 under the same MIT release ([pinned README](https://github.com/openai/whisper/blob/04f449b8a437f1bbd3dba5c9f826aca972e7709a/README.md#license)) | `argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-large-v3_947MB` ([tree](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-large-v3_947MB)) | OpenAI MIT duties apply; Argmax permission remains absent. Its folder config names `openai/whisper-large-v3` and has the expected 32-layer encoder/decoder, which supports identity but does not license Argmax's conversion ([config](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-large-v3_947MB/config.json)). |

The two tokenizer closures used by the three Whisper rows come from OpenAI-owned Hugging Face repositories whose immutable model cards declare Apache-2.0, rather than from the Argmax conversion repository ([small card](https://huggingface.co/openai/whisper-small/blob/973afd24965f72e36ca33b3055d56a652f456b4d/README.md), [large-v3 card](https://huggingface.co/openai/whisper-large-v3/blob/06f233fe06e710322aca913c1bc4249a0d71fce1/README.md)). Preserve the Apache license, applicable notices, and modification notices for those files. FluidAudio 0.15.4 is Apache-2.0 and WhisperKit 1.0.0 is MIT; their binary-notice duties are independent of the model artifacts ([FluidAudio license](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/LICENSE), [WhisperKit license and notices](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/NOTICES)).

## Runtime closure and immutable download requirements

The reviewed Core ML manifests contain **130 files and 4,046,795,482 bytes**. The three Whisper rows also require two separate pinned three-file tokenizer closures: small is 2,765,116 bytes and large-v3 is 2,764,732 bytes. Installing all seven profiles therefore requires **136 unique downloaded files and 4,052,325,330 bytes** before filesystem/container overhead; Turbo and full large-v3 share the same large-v3 tokenizer closure. Per-row runtime totals are 489,252,581 bytes for Whisper small, 629,482,970 bytes for Turbo 626 MB, and 950,873,518 bytes for large-v3 947 MB.

The upstream runtime paths establish exactly what these manifests close:

- FluidAudio 0.15.4 maps repository identities, cache folder names, required bundles, and precision variants in [`ModelNames.swift`](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ModelNames.swift). Its public downloader enumerates `tree/main` and resolves `main`, so it does not preserve the reviewed revisions ([`DownloadUtils.swift`](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/DownloadUtils.swift)). Local profile roots are `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3/`, `.../parakeet-tdt-ctc-110m/`, `.../parakeet-unified-en-0.6b/`, and `.../nemotron-multilingual/multilingual/2240ms/`; the Unified and Nemotron loaders select the exact profiles audited here ([Unified loader](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Unified/StreamingUnifiedAsrManager.swift), [Nemotron loader](https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager%2BShared.swift)).
- WhisperKit 1.0.0 searches a variant folder and calls an unrevisioned Hub snapshot by default ([`WhisperKit.download`](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/WhisperKit/Core/WhisperKit.swift)). FoldWise's present cache root is `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<variant>/`. Its adapter then creates a second Hub cache below that folder: `huggingface/models/openai/whisper-small/{config.json,tokenizer_config.json,tokenizer.json}` for small, and `huggingface/models/openai/whisper-large-v3/{...}` for both large profiles ([FoldWise adapter mapping](https://github.com/hadrysm/foldwise-voice/blob/47934f4b97582a8df3e6362e8d9ff05edcfc2850/Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelAdapters.swift), [storage seam](https://github.com/hadrysm/foldwise-voice/blob/47934f4b97582a8df3e6362e8d9ff05edcfc2850/Sources/FoldWiseVoiceKit/Features/Dictation/Transcribe/ASRModelLibraryStorage.swift), [pinned Hub wrapper](https://github.com/argmaxinc/argmax-oss-swift/blob/25c62997041c134b03ca82731ce2f6fd2cae1eb9/Sources/ArgmaxCore/HubWrapper.swift)).
- FoldWise must replace both convenience-download paths with a FoldWise-owned descriptor containing repository, immutable revision, exact path list, byte count, and SHA-256; download into staging, verify every file, reject extras/missing files, then atomically promote. Availability must verify that same manifest, not just loadable Core ML directories. This preserves ADR-0005's one-resident-engine rule and ADR-0006's transactional selection/availability truth.

For Git LFS entries, the Hugging Face tree API's `lfs.oid` is the SHA-256 of the resolved payload and `size` is the payload byte count; the ordinary `oid` is the Git blob identity of the pointer. For non-LFS entries below, SHA-256 was calculated over the bytes returned by the immutable `resolve/<revision>/<path>` URL. Hugging Face documents this distinction in its [`RepoFile`/`BlobLfsInfo` API](https://huggingface.co/docs/huggingface_hub/main/en/package_reference/hf_api#huggingface_hub.hf_api.RepoFile). A verifier must hash resolved payloads, never the small LFS pointer text.

## Complete required-file manifests

`HF LFS` means the hash is the publisher API's payload `lfs.oid`; `computed` means SHA-256 of the immutable resolved file. Paths are repository-relative and therefore append directly to the local profile roots above.

These are runtime-required files, not every file the current broad upstream downloader happens to copy. In particular, v3 does not require root `config.json` or the duplicate `parakeet_v3_vocab.json`, and TDT-CTC/Unified do not require root `config.json`; FoldWise's manifest downloader must select only the lists below.

### Parakeet TDT 0.6B v3 — INT8

Repository: [`FluidInference/parakeet-tdt-0.6b-v3-coreml@aed02740059203c4a87495924f685de3722ae9ce`](https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/aed02740059203c4a87495924f685de3722ae9ce?recursive=true&expand=true). **21 files; 483105645 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `Decoder.mlmodelc/analytics/coremldata.bin` | 243 | `4238c4e81ecd0dc94bd7dfbb60f7e2cc824107c1ffe0387b8607b72833dba350` | HF LFS |
| `Decoder.mlmodelc/coremldata.bin` | 554 | `18647af085d87bd8f3121c8a9b4d4564c1ede038dab63d295b4e745cf2d7fb99` | HF LFS |
| `Decoder.mlmodelc/metadata.json` | 3427 | `a39e93cd8371b8ded92635c7804fcd0590f0d1dd9415c6d19a0484be073077d9` | computed |
| `Decoder.mlmodelc/model.mil` | 13110 | `ef2a0a281695398a62fde86ac269c68f73d5b578d7ed3b31f2ba91a2d1ea1f35` | computed |
| `Decoder.mlmodelc/weights/weight.bin` | 23604992 | `48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41` | HF LFS |
| `Encoder.mlmodelc/analytics/coremldata.bin` | 243 | `42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105` | HF LFS |
| `Encoder.mlmodelc/coremldata.bin` | 485 | `d48034a167a82e88fc3df64f60af963ab3983538271175b8319e7d5720a0fb86` | HF LFS |
| `Encoder.mlmodelc/metadata.json` | 2921 | `da24da9cca943fb29d7fa8e376d57fca7cb3aa08ca51b956b0b0e56813f087e9` | computed |
| `Encoder.mlmodelc/model.mil` | 959769 | `ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808` | computed |
| `Encoder.mlmodelc/weights/weight.bin` | 445187200 | `e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421` | HF LFS |
| `JointDecisionv3.mlmodelc/analytics/coremldata.bin` | 243 | `26def4bf73dd56d29dee21c8ef97cb8969e62f6120ed1adc91e46828e2737b6c` | HF LFS |
| `JointDecisionv3.mlmodelc/coremldata.bin` | 521 | `f5fc08b741400f0088492c9e839418b1e18522f19cba28d361dd030c5f398342` | HF LFS |
| `JointDecisionv3.mlmodelc/metadata.json` | 3453 | `d9307211b9a37e0f0ac260c7660b1571a3de25841035cfdf9b58fd40425f890f` | computed |
| `JointDecisionv3.mlmodelc/model.mil` | 11775 | `be60732943389a047175111a83f8839f3eb39d4803adafa828a0871b2f39818d` | computed |
| `JointDecisionv3.mlmodelc/weights/weight.bin` | 12642764 | `4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e` | HF LFS |
| `Preprocessor.mlmodelc/analytics/coremldata.bin` | 243 | `c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d` | HF LFS |
| `Preprocessor.mlmodelc/coremldata.bin` | 486 | `dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d` | HF LFS |
| `Preprocessor.mlmodelc/metadata.json` | 2841 | `2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf` | computed |
| `Preprocessor.mlmodelc/model.mil` | 28181 | `4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93` | computed |
| `Preprocessor.mlmodelc/weights/weight.bin` | 491072 | `129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea` | HF LFS |
| `parakeet_vocab.json` | 151122 | `7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735` | computed |

### Parakeet TDT-CTC 110M — float32

Repository: [`FluidInference/parakeet-tdt-ctc-110m-coreml@9bc92ead6e8f17eca92a869fd578ae76842b82ba`](https://huggingface.co/api/models/FluidInference/parakeet-tdt-ctc-110m-coreml/tree/9bc92ead6e8f17eca92a869fd578ae76842b82ba?recursive=true&expand=true). **16 files; 227466209 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `Decoder.mlmodelc/analytics/coremldata.bin` | 243 | `dc7174d25586869ffb33e6c519cfcc882bf04b2f0e527b8b84a38fe4d469f618` | HF LFS |
| `Decoder.mlmodelc/coremldata.bin` | 562 | `407846e00c895ee447ee5795eb61c0437b4d5ed8ae33e603173fb3f79d871151` | HF LFS |
| `Decoder.mlmodelc/metadata.json` | 3418 | `31e061914a0e0106020800ac6b19a66e1d11e9194597dc238babfdfad9bd1163` | computed |
| `Decoder.mlmodelc/model.mil` | 8765 | `5d8fe2126ead2e4467931f563f0ca4d7747a1feee27c75672b66204f0e95feba` | computed |
| `Decoder.mlmodelc/weights/weight.bin` | 7871040 | `dd90b58597ee2c172c672dffe13b1110898ba07394c1a15efc96cc8c6b18411b` | HF LFS |
| `JointDecision.mlmodelc/analytics/coremldata.bin` | 243 | `42f7757cc6603cf025dd490169edef879c355b62a178243e1ca4d538e762af2f` | HF LFS |
| `JointDecision.mlmodelc/coremldata.bin` | 583 | `9ef957d12add316f594b2e8766202ce2b06341e3e5ebaea35b9ff2c3d7a0f4f7` | HF LFS |
| `JointDecision.mlmodelc/metadata.json` | 3565 | `d41758303b3430b38132b3d76b39bc88c16889be0dc0e8a88803226b891fa9b2` | computed |
| `JointDecision.mlmodelc/model.mil` | 11768 | `b8beac2b60a8b2b33854352784b2d37b3783b10eb262cf761095c8df5bf97d14` | computed |
| `JointDecision.mlmodelc/weights/weight.bin` | 2798028 | `b3f771cb65b190f1873e39629676ed79b65a8361522f451b37bdba8b1106e6ff` | HF LFS |
| `Preprocessor.mlmodelc/analytics/coremldata.bin` | 243 | `d813d089b82b1edfdc558d902d91421c527c2db4ba85e36c4a611ea99eba8248` | HF LFS |
| `Preprocessor.mlmodelc/coremldata.bin` | 499 | `69e29c6cf43349318661a4aaade4bc0cc124a5780582d283614056cc76eb2907` | HF LFS |
| `Preprocessor.mlmodelc/metadata.json` | 3133 | `c126b295f723abb241ee9b0e855670fb2b4c68a041caaf5149fcf991b3daf307` | computed |
| `Preprocessor.mlmodelc/model.mil` | 794623 | `2dbf6796267859d0677ffe1bc1c41e72320ef5aa23b256cd96a73c21ecf1cc44` | computed |
| `Preprocessor.mlmodelc/weights/weight.bin` | 215951360 | `a1c90b88b52667ee4f349b39994003cc2a9fb1b12c310752399d90c880286a7b` | HF LFS |
| `parakeet_vocab.json` | 18136 | `1d6e786d0c1842f45fd3a89044b099d4e3abf889ec986101166619d56bdb821e` | computed |

### Parakeet Unified EN 0.6B — streaming 70/13/13 INT8

Repository: [`FluidInference/parakeet-unified-en-0.6b-coreml@4252711f6f060f9a2f91e5f081a806d7f45eebd8`](https://huggingface.co/api/models/FluidInference/parakeet-unified-en-0.6b-coreml/tree/4252711f6f060f9a2f91e5f081a806d7f45eebd8?recursive=true&expand=true). **18 files; 610062293 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `metadata.json` | 1046 | `2b26a96b76fe1f7a04d3e867f50c75d6ce5dd1650d0dbcd4c35b591b22305f0e` | computed |
| `parakeet_unified_decoder.mlmodelc/analytics/coremldata.bin` | 243 | `9ae70f6559989f88b856b326e59315798f9f0d08207a19fcc2dd3287a30088a5` | HF LFS |
| `parakeet_unified_decoder.mlmodelc/coremldata.bin` | 560 | `ce99c4488840fc463d59f8d4d6d2a9e8ceae8138ead51e3c265dde4d2ba4a0e9` | HF LFS |
| `parakeet_unified_decoder.mlmodelc/model.mil` | 13102 | `6e60965b89c93943aa2be2d991c2461108145851fde05e1d048223a32d4cb20d` | computed |
| `parakeet_unified_decoder.mlmodelc/weights/weight.bin` | 14429952 | `96f990461a5986d5e7309ad1a0f36084fbf0f4b28aec35948f8b8d0dcbf8599e` | HF LFS |
| `parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/analytics/coremldata.bin` | 243 | `ffbbab2cbdc941dd88fc41c41d3f7ac61cc31475a17a1cb06ed7f3b0b25c611b` | HF LFS |
| `parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/coremldata.bin` | 515 | `e1ffdae252dcc276ff2964ee2259a63d9c519b8413302609300d692f6a79b824` | HF LFS |
| `parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/model.mil` | 949815 | `64a4bdf20760025c8df072872b9aa71fdbce938f469c976fda690354424cc93c` | computed |
| `parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/weights/weight.bin` | 590571264 | `259e5818cf4acee1155409a048ec408eecd8cfc27ade04ba18bca243398cc9b6` | HF LFS |
| `parakeet_unified_joint_decision_single_step.mlmodelc/analytics/coremldata.bin` | 243 | `163877ad14af97ec4107cd854fd1c6d336ee5d40ad25a657cc764fb763f452f5` | HF LFS |
| `parakeet_unified_joint_decision_single_step.mlmodelc/coremldata.bin` | 556 | `68a081570a48b52ec9379e153bd56748a5408a50be16767601563f231eaeff03` | HF LFS |
| `parakeet_unified_joint_decision_single_step.mlmodelc/model.mil` | 9611 | `03c21096090bcd0b71c896c5ae0eb815db31a91c6676f572a7868eee4299abe3` | computed |
| `parakeet_unified_joint_decision_single_step.mlmodelc/weights/weight.bin` | 3446978 | `06831afa6d1beb0c0b10350ebf7886bc37638e951d14e738d7e06fbd2a05012f` | HF LFS |
| `parakeet_unified_preprocessor.mlmodelc/analytics/coremldata.bin` | 243 | `be8e41eca751dabf693e0b319652c12637636b26e99be5881ece7a013d4abaca` | HF LFS |
| `parakeet_unified_preprocessor.mlmodelc/coremldata.bin` | 495 | `0bc9cffe8fafdf1b9d51fe460660a120252fefcf355c46876ea61901107ee11a` | HF LFS |
| `parakeet_unified_preprocessor.mlmodelc/model.mil` | 29955 | `7bb56a71d39dc638ceac0dc9e32306a68ac31057c8ebaa35342bddb6fd1f684f` | computed |
| `parakeet_unified_preprocessor.mlmodelc/weights/weight.bin` | 592384 | `d374edc6e5cdb6e0429cfee7cc43b3a899150c3c3ebc24edcfb460046a3a9bf1` | HF LFS |
| `vocab.json` | 15088 | `e1a7bff4f5df133c0f4ad47b8e43c96f6bf1865d99126a4c4725ef51d0108bec` | computed |

### Nemotron 3.5 multilingual — full vocabulary 2240 ms

Repository: [`FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML@1a41b75758b0337ff67db7d5408280aaaf23074e`](https://huggingface.co/api/models/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML/tree/1a41b75758b0337ff67db7d5408280aaaf23074e?recursive=true&expand=true). **22 files; 664846846 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `multilingual/2240ms/decoder.mlmodelc/analytics/coremldata.bin` | 243 | `fdb14a08e42b4806a2d1505501586be71e4f04ca9256c719544fd7ed6937e509` | HF LFS |
| `multilingual/2240ms/decoder.mlmodelc/coremldata.bin` | 433 | `3a89047b6f74ee3d0a74c72f8c8e5016d76d9487d030f0661fe80220b441a6fd` | HF LFS |
| `multilingual/2240ms/decoder.mlmodelc/model.mil` | 11743 | `f3ed3e9cac9b70e1b00df48b53868dbd3c4dd8cf158af79ded0d05a96e0bf5dc` | computed |
| `multilingual/2240ms/decoder.mlmodelc/weights/weight.bin` | 29870592 | `dcdeccd4ccf46e2675224f9f030d46c1a89e2bda4abb316e901e1a21f1597f8f` | HF LFS |
| `multilingual/2240ms/decoder_joint.mlmodelc/analytics/coremldata.bin` | 243 | `8a8e98a54ed1f16c3d5125816a002b991e167d620beb8fcc557f26d9a1c092f8` | HF LFS |
| `multilingual/2240ms/decoder_joint.mlmodelc/coremldata.bin` | 454 | `6404b542fb5d5faa79648fc96a79a0b981cbd087df0378adefd1f45ae56dd86e` | HF LFS |
| `multilingual/2240ms/decoder_joint.mlmodelc/model.mil` | 15801 | `62144df8c1928d571c1df508a576f2d574a6bd6b1f2dba7f3f15cf9605805d6a` | computed |
| `multilingual/2240ms/decoder_joint.mlmodelc/weights/weight.bin` | 48782272 | `01f21eb747fbc53bd0ed7efebea1bf0aa655ebf2816f21d0bb6554c9b7fcfc0b` | HF LFS |
| `multilingual/2240ms/encoder.mlmodelc/analytics/coremldata.bin` | 243 | `af569fd95237bdf8b91d38094691bfc990fcf3534316fa615bac5964c02809e4` | HF LFS |
| `multilingual/2240ms/encoder.mlmodelc/coremldata.bin` | 573 | `d5471a4edf55ce02dab51e5d01c86b419a7659bcdd6aac216ba6f0b795eae8bf` | HF LFS |
| `multilingual/2240ms/encoder.mlmodelc/model.mil` | 1010788 | `3ee65463908bbc06c92691ea9172499aea3f7ae4ba619d39783c4a639936fae5` | computed |
| `multilingual/2240ms/encoder.mlmodelc/weights/weight.bin` | 565336640 | `2e00be98049a22e095452c020f183d2b23728e145cc814ba031436931b4f2e8f` | HF LFS |
| `multilingual/2240ms/joint.mlmodelc/analytics/coremldata.bin` | 243 | `a1a90a7d5f8b86f564a42ab45b42a43eb0bbce6682176916bd94591b28cca447` | HF LFS |
| `multilingual/2240ms/joint.mlmodelc/coremldata.bin` | 341 | `8f750980da8ea3397d860f69e0755d3adf61ee763d7f189405d50d4e2d9f8ca0` | HF LFS |
| `multilingual/2240ms/joint.mlmodelc/model.mil` | 5072 | `521da827005ddcf3fbd439d12f85c34b1273642635b39a87bfbc931131cd3bf6` | computed |
| `multilingual/2240ms/joint.mlmodelc/weights/weight.bin` | 18911744 | `c0ef0a3a6598f962d2aad598dc6850e4428874033419817121e11f1fff4a9cfe` | HF LFS |
| `multilingual/2240ms/metadata.json` | 3005 | `070ae181941003ff3e7d7ff8e5c5d47aebd026e8458549cef0c9a6803dbec004` | computed |
| `multilingual/2240ms/preprocessor.mlmodelc/analytics/coremldata.bin` | 243 | `e918fd75105ef01a971d29b5ec28f531467b42dd60978c29afb1914c4af838af` | HF LFS |
| `multilingual/2240ms/preprocessor.mlmodelc/coremldata.bin` | 371 | `3d1aa8c8e7e283e4944af4b0b701db760ed99ef14919d3f989c599b9f63335a2` | HF LFS |
| `multilingual/2240ms/preprocessor.mlmodelc/model.mil` | 18449 | `12637d7ddfabea2d58e6b7986699c1be7fe970dc589eeac52fcb9ad25ae06ec9` | computed |
| `multilingual/2240ms/preprocessor.mlmodelc/weights/weight.bin` | 592384 | `297514e2b211d14b0e53cb97193d679bb89ead98d28e578f3f1d049ddbcc36b3` | HF LFS |
| `multilingual/2240ms/tokenizer.json` | 284969 | `fb70c8fcb6472cda2bdb799b156a8941e72762344a7c636d3b1275f1d53c4a6b` | computed |

### Whisper small — Argmax Core ML

Repository: [`argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808`](https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808?recursive=true&expand=true). **19 files; 486487465 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `openai_whisper-small/AudioEncoder.mlmodelc/analytics/coremldata.bin` | 243 | `211457b92a0ced67bb8625efe39799a0030c4fc71eb87d7284ea81043caccde7` | HF LFS |
| `openai_whisper-small/AudioEncoder.mlmodelc/coremldata.bin` | 347 | `d68f152b6573ac55203a3dc8383730e6ecde685c7d2a88815b89820c88e35371` | HF LFS |
| `openai_whisper-small/AudioEncoder.mlmodelc/metadata.json` | 1868 | `520e147851258b231299c5a13b0b6d7b973572445706af1ca1dfc6276ff42e77` | computed |
| `openai_whisper-small/AudioEncoder.mlmodelc/model.mil` | 1636668 | `760173a125b9fadb2f3fac45e1504781c081d619744bffb476eab06ae20a6972` | computed |
| `openai_whisper-small/AudioEncoder.mlmodelc/model.mlmodel` | 155271 | `68ca04660b8b050c68ca54c27d97c47e4133bc591422cb7009de8922d56fb8c9` | HF LFS |
| `openai_whisper-small/AudioEncoder.mlmodelc/weights/weight.bin` | 176323456 | `fe35cef2c9406993a635639b16f373f6debb0215ac115b7bf93fa03c8e10310b` | HF LFS |
| `openai_whisper-small/MelSpectrogram.mlmodelc/analytics/coremldata.bin` | 243 | `7f77e6457285248f99cd7aa3fd4cc2efbb17733e63e7023ac53abe1f95785d07` | HF LFS |
| `openai_whisper-small/MelSpectrogram.mlmodelc/coremldata.bin` | 328 | `dabdc5aa69f6ef4d97dc9499f5c30514e00e96b53b750b33a5a6471363c71662` | HF LFS |
| `openai_whisper-small/MelSpectrogram.mlmodelc/metadata.json` | 1848 | `66a60d0babfcae566910a6d699471efde002d92205a7d349e16989ca4d6729d3` | computed |
| `openai_whisper-small/MelSpectrogram.mlmodelc/model.mil` | 10176 | `b8063d8e57c113472ac7c2d248e44383568a018978a753c1884ac406b997a374` | computed |
| `openai_whisper-small/MelSpectrogram.mlmodelc/weights/weight.bin` | 354080 | `267017e533b5f542d195fd9a775f2ba649075128283ce8e86c63a2ec20de5b07` | HF LFS |
| `openai_whisper-small/TextDecoder.mlmodelc/analytics/coremldata.bin` | 243 | `39c0d6d55353bc61ef8071081bb958dd1ab7b0b7f2a3338a797f1a64211e084c` | HF LFS |
| `openai_whisper-small/TextDecoder.mlmodelc/coremldata.bin` | 633 | `b2ccd0b8920701386ab9554f7db47b43e55ee07863280ee5d829d5272839adc2` | HF LFS |
| `openai_whisper-small/TextDecoder.mlmodelc/metadata.json` | 4757 | `33870a8d1694071f75dfa29314d290e10a2bd693de7268f9419b381056677fc2` | computed |
| `openai_whisper-small/TextDecoder.mlmodelc/model.mil` | 392094 | `ebecbd1b3b0350c63541488217811c3f2a75ac72b178b4cfb357f4c300873bd0` | computed |
| `openai_whisper-small/TextDecoder.mlmodelc/model.mlmodel` | 313629 | `7ea861c6dfdd866ed0f2e7fe0c3df7459daa44481cb25236e03698dd6d259391` | HF LFS |
| `openai_whisper-small/TextDecoder.mlmodelc/weights/weight.bin` | 307287346 | `bfea8044a8f38e8d33f56585b1e75ce023d3845e2a945e20480bd7e16558016e` | HF LFS |
| `openai_whisper-small/config.json` | 1456 | `12f8d45c3e5da28148d88d257684e77296e4d922009e1bc5289b05b756859422` | computed |
| `openai_whisper-small/generation_config.json` | 2779 | `169e76633bb28ac383cdfaad2527e662d0d532a15f8437ce94c02c10bc713b71` | computed |

### Whisper large-v3 Turbo — Argmax 626 MB Core ML

Repository: [`argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808`](https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808?recursive=true&expand=true). **17 files; 626718238 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `openai_whisper-large-v3-v20240930_626MB/AudioEncoder.mlmodelc/analytics/coremldata.bin` | 243 | `56793886ab1adb9ca8a4e335efbe8af6640f40d958ab2d29c3ad2d7d6f712e95` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/AudioEncoder.mlmodelc/coremldata.bin` | 348 | `ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/AudioEncoder.mlmodelc/metadata.json` | 1922 | `a87a3375afe79e88e27af30247e234e706b98679dedfd1b021a74f7ee108c669` | computed |
| `openai_whisper-large-v3-v20240930_626MB/AudioEncoder.mlmodelc/model.mil` | 934263 | `3cec2580fb07b12a88087f0e1586c6ba2982980eb36499561e1ffca2b0950442` | computed |
| `openai_whisper-large-v3-v20240930_626MB/AudioEncoder.mlmodelc/weights/weight.bin` | 421968768 | `e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/MelSpectrogram.mlmodelc/analytics/coremldata.bin` | 243 | `c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/MelSpectrogram.mlmodelc/coremldata.bin` | 329 | `2bfc12cffc2e45e039c7a18f384f09adffb72c182fcd93f9413d405d1a6c1130` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/MelSpectrogram.mlmodelc/metadata.json` | 1850 | `2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f` | computed |
| `openai_whisper-large-v3-v20240930_626MB/MelSpectrogram.mlmodelc/model.mil` | 10143 | `c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463` | computed |
| `openai_whisper-large-v3-v20240930_626MB/MelSpectrogram.mlmodelc/weights/weight.bin` | 373376 | `009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/TextDecoder.mlmodelc/analytics/coremldata.bin` | 243 | `3913b8c9716b284a917cf3744f4d415f2a05e2b910594a14c6cc10092284d3f8` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/TextDecoder.mlmodelc/coremldata.bin` | 633 | `3faabaf66930e66956d8291d0ff485fb382496e30a91a7185548b9b898ce90a9` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/TextDecoder.mlmodelc/metadata.json` | 4924 | `994f6030d7b1a8be999940444c3cf5d6a57d40ddd4423cf1d1fc93520aa1b052` | computed |
| `openai_whisper-large-v3-v20240930_626MB/TextDecoder.mlmodelc/model.mil` | 217177 | `dbe833be9e64348c95b7fa598d0ae4309a91aedce4e82fa500a714b0e4b5d754` | computed |
| `openai_whisper-large-v3-v20240930_626MB/TextDecoder.mlmodelc/weights/weight.bin` | 203199860 | `d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db` | HF LFS |
| `openai_whisper-large-v3-v20240930_626MB/config.json` | 1149 | `f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1` | computed |
| `openai_whisper-large-v3-v20240930_626MB/generation_config.json` | 2767 | `7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6` | computed |

### Whisper large-v3 — Argmax 947 MB Core ML

Repository: [`argmaxinc/whisperkit-coreml@97a5bf9bbc74c7d9c12c755d04dea59e672e3808`](https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/97a5bf9bbc74c7d9c12c755d04dea59e672e3808?recursive=true&expand=true). **17 files; 948108786 bytes.**

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `openai_whisper-large-v3_947MB/AudioEncoder.mlmodelc/analytics/coremldata.bin` | 243 | `387cff66366595358aa7b02ca8a5c587000dcef963c3a38c24a77a765757881d` | HF LFS |
| `openai_whisper-large-v3_947MB/AudioEncoder.mlmodelc/coremldata.bin` | 348 | `63b4db8a854c7a64a10b0a0b97048d6d8ee557536367f44dc9fb95fad4bffcf6` | HF LFS |
| `openai_whisper-large-v3_947MB/AudioEncoder.mlmodelc/metadata.json` | 1933 | `b0deaf50cf43bbd8610b93ef694a1380ada2ee17680e6f881a7a03c26fb3c565` | computed |
| `openai_whisper-large-v3_947MB/AudioEncoder.mlmodelc/model.mil` | 1138803 | `4b06d167d112929866a7d8054772f4fd0b7804f40f4233aeff851eefbe57d0f5` | computed |
| `openai_whisper-large-v3_947MB/AudioEncoder.mlmodelc/weights/weight.bin` | 353908416 | `9b819fb62291e63c6b5596238a73964bfbdaccb8a12fd5672e7eb32639a57f83` | HF LFS |
| `openai_whisper-large-v3_947MB/MelSpectrogram.mlmodelc/analytics/coremldata.bin` | 243 | `7f478e6afa8fdee3711d97b00728f82ee4dcdf2912f7ff033ee0dfcf57bf28bb` | HF LFS |
| `openai_whisper-large-v3_947MB/MelSpectrogram.mlmodelc/coremldata.bin` | 329 | `a888718e98af679eee42db9e3609627472c32f77e4fdda28f3735960cbf526b3` | HF LFS |
| `openai_whisper-large-v3_947MB/MelSpectrogram.mlmodelc/metadata.json` | 1878 | `dcb839ca16e598dfb1720af0294a8e21ab18b3e5afab136093aa2fd5f5cfc923` | computed |
| `openai_whisper-large-v3_947MB/MelSpectrogram.mlmodelc/model.mil` | 10166 | `6e0c6fc2cb23de4e5b6c25897047c12402da201b5a8717fa5ee9f3108b1cb702` | computed |
| `openai_whisper-large-v3_947MB/MelSpectrogram.mlmodelc/weights/weight.bin` | 373376 | `81275398516781f9755514a5ab85db4687374dd611013625f3d4493588783968` | HF LFS |
| `openai_whisper-large-v3_947MB/TextDecoder.mlmodelc/analytics/coremldata.bin` | 243 | `1a999e3332b206c426f9252001a3593702d3542aa4a00242f99e9baaeda4a063` | HF LFS |
| `openai_whisper-large-v3_947MB/TextDecoder.mlmodelc/coremldata.bin` | 637 | `9b3e5707277d8c7297ea5e6075801c6d56a054e7ed1ab5dfec5692292c62e145` | HF LFS |
| `openai_whisper-large-v3_947MB/TextDecoder.mlmodelc/metadata.json` | 4959 | `6ee6819dc8ad4990c626c52c711cc65c5c19536577bc5b590a7d1afaecda68c5` | computed |
| `openai_whisper-large-v3_947MB/TextDecoder.mlmodelc/model.mil` | 1943315 | `939d1919af974fee08186a36131c617ff004d63ccf9ebbb4a6314274e88960ec` | computed |
| `openai_whisper-large-v3_947MB/TextDecoder.mlmodelc/weights/weight.bin` | 590719924 | `e53c8476c43310ad9fd2f4be996b7d803208428b0b137848972932406a30ef2f` | HF LFS |
| `openai_whisper-large-v3_947MB/config.json` | 1163 | `798b69c08cf93b2b03d94bea6eb3eb25fd4712259712d8a62ed2483fdf818a9e` | computed |
| `openai_whisper-large-v3_947MB/generation_config.json` | 2810 | `d24f9cca0f448609a71ae044b736023706382f45e9700e0dffb2559d10cf1fea` | computed |

### Whisper small tokenizer closure

Repository: [`openai/whisper-small@973afd24965f72e36ca33b3055d56a652f456b4d`](https://huggingface.co/api/models/openai/whisper-small/tree/973afd24965f72e36ca33b3055d56a652f456b4d?recursive=true&expand=true). **3 files; 2765116 bytes.** These are additional runtime dependencies and are not included in the 130-file Core ML total.

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `config.json` | 1967 | `e6a2b489da1b5aed65a8eb8d1e7466fa867ad5643a8bc138ba708bd56b2875c4` | computed |
| `tokenizer.json` | 2480466 | `27fc476bfe7f17299480be2273fc0608e4d5a99aba2ab5dec5374b4482d1a566` | computed |
| `tokenizer_config.json` | 282683 | `2a4c4281cf9f51ac6ccc406fdc711a087afe6530f671fa7b80953edc498275ce` | computed |

### Whisper large-v3 tokenizer closure (shared by Turbo and full large-v3)

Repository: [`openai/whisper-large-v3@06f233fe06e710322aca913c1bc4249a0d71fce1`](https://huggingface.co/api/models/openai/whisper-large-v3/tree/06f233fe06e710322aca913c1bc4249a0d71fce1?recursive=true&expand=true). **3 files; 2764732 bytes.** These are additional runtime dependencies and are not included in the 130-file Core ML total.

| Required repository path | Bytes | SHA-256 | Hash source |
| --- | ---: | --- | --- |
| `config.json` | 1272 | `ad0e8d1e46f4d01f7861a21509e5d0f977d6cc1f367a370603c92541d819807b` | computed |
| `tokenizer.json` | 2480617 | `6d8cbd7cd0d8d5815e478dac67b85a26bbe77c1f5e0c6d76d1ce2abc0e5f21ca` | computed |
| `tokenizer_config.json` | 282843 | `844b642c73a91359722f47b35705f7174686df33d252695d8572cf9ac03a6389` | computed |
