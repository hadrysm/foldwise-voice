# Handy catalog parity baseline

Research answer for **Establish the exact Handy catalog parity baseline**, audited
on 2026-07-19. This note separates the catalog Handy declares from facts FoldWise
must verify independently before presenting them as product truth.

## Executive answer

FoldWise's full-parity reference is the catalog present on Handy `main` at the
time this wayfinding map was charted:

- Handy source commit
  [`cdbc22390987643237756382ef367f7244b2844f`](https://github.com/cjpais/Handy/commit/cdbc22390987643237756382ef367f7244b2844f)
- bundled catalog Git blob `08b1a126c71eb9a22ffb3b7cc7f09b798c6d683f`
- catalog SHA-256 `89c67fce9c95cda50976449ba63751c23b3642d77d89f537f24b1e271f461684`
- [`catalog.json` at that commit](https://raw.githubusercontent.com/cjpais/Handy/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/catalog/catalog.json)
- catalog schema version `1`, generated at `2026-07-01T13:30:59+00:00`

That immutable JSON is the normative, complete inventory. It contains 65 model
entries and 337 downloadable quantization files. Every entry's `id`, `slug`,
display metadata, architecture, family, parameter label, base-model reference,
declared license, languages, capability flags, scores, quantization filenames,
exact byte sizes, default quantization, and recommendation metadata belong to the
baseline. FoldWise should not reconstruct the baseline from today's live
Hugging Face organization or from a hand-maintained summary.

Handy v0.9.0 is useful provenance but is not the chosen snapshot. The
[`v0.9.0` tag](https://github.com/cjpais/Handy/releases/tag/v0.9.0) points to
[`9b0d8a1120810dac1b139f480d37ba5f704e4856`](https://github.com/cjpais/Handy/commit/9b0d8a1120810dac1b139f480d37ba5f704e4856),
the original July 1 catalog. Handy later corrected four GigaAM descriptions and
twelve localized Moonshine descriptions. No identifiers, files, sizes,
quantizations, capability flags, or other fields changed between that release
catalog and the observed July 19 `main` catalog.

## Exact catalog shape

The 65 entries cover 16 runtime architectures:

| Architecture | Entries |
| --- | ---: |
| `canary` | 4 |
| `canary_qwen` | 1 |
| `cohere_asr` | 1 |
| `funasr_nano` | 2 |
| `gigaam` | 4 |
| `granite_speech` | 3 |
| `granite_speech_nar` | 1 |
| `medasr` | 1 |
| `moonshine` | 14 |
| `moonshine_streaming` | 3 |
| `parakeet` | 12 |
| `qwen3_asr` | 2 |
| `sensevoice` | 1 |
| `voxtral` | 2 |
| `voxtral_realtime` | 1 |
| `whisper` | 13 |

Across the catalog, Handy offers `BF16`, `F16`, `F32`, `Q4_K_M`, `Q5_K_M`,
`Q6_K`, and `Q8_0`. Availability is per entry rather than Cartesian: the exact
337 filename/quantization/byte-size triples are the `files` arrays in the pinned
JSON. Forty-four entries default to `Q8_0`; 21 default to `Q5_K_M`.

The seven entries Handy marks `streaming: true` are:

1. `handy-computer/parakeet-unified-en-0.6b-gguf`
2. `handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf`
3. `handy-computer/Voxtral-Mini-4B-Realtime-2602-gguf`
4. `handy-computer/moonshine-streaming-tiny-gguf`
5. `handy-computer/moonshine-streaming-small-gguf`
6. `handy-computer/moonshine-streaming-medium-gguf`
7. `handy-computer/nemotron-speech-streaming-en-0.6b-gguf`

The remaining 58 entries are declared non-streaming. Handy also declares 17
translation-capable entries, 17 language-detecting entries, and timestamp modes
of `none` (34), `segment` (13), `token` (17), and `word` (1). The catalog's
license labels total Apache-2.0 (23), CC-BY-4.0 (14), CC-BY-NC-4.0 (1), MIT
(21), and `other` (6). These are Handy-declared labels, not yet FoldWise legal
conclusions.

## Identity and download semantics

The catalog `id` is a `handy-computer` Hugging Face conversion repository, not
the original model identifier. `base_model` points toward the original model.
Handy's pinned
[`catalog` consumer](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/catalog/mod.rs)
chooses the declared default quantization and constructs runtime identity as:

```text
descriptor id = {catalog.id}/{default filename}
source = HuggingFace { repo_id: catalog.id, revision: "main" }
```

The exact runtime identity at baseline therefore has three layers:

- catalog identity: the conversion repository in `models[].id`;
- artifact identity: the selected `files[].filename` appended to that repository;
- upstream lineage: the separate `models[].base_model` reference.

The checked-in catalog freezes repository names, filenames, and expected byte
sizes, but Handy downloads from mutable Hugging Face `main`. The catalog does
not contain the Hugging Face commit SHA or LFS object SHA-256. A URL such as
`https://huggingface.co/{id}/resolve/main/{filename}` is therefore Handy's
behavioral download source, but not an immutable artifact identity.

The audit reconstructed the latest conversion-repository revision at or before
the catalog timestamp for all 65 repositories. All 65 lookups succeeded and
matched the catalog's file lists, byte sizes, conversion-card license,
base-model, language, and capability metadata; those repository heads were
still unchanged on 2026-07-19. This corroborates the snapshot but does not make
the catalog reproducible by rerunning the generator: the generator enumerates
live repositories and reads live cards, files, and GGUF headers.

An immutable artifact URL and integrity record require the historical Hugging
Face revision and LFS SHA-256:

```text
https://huggingface.co/{catalog.id}/resolve/{hf-revision}/{files[].filename}
https://huggingface.co/api/models/{catalog.id}/revision/{hf-revision}?blobs=true
```

Whether FoldWise pins those revisions or intentionally follows an update policy
is a later product/architecture decision; this baseline makes the choice
visible instead of treating mutable `main` as exact identity.

## Where each field comes from

Handy's pinned
[`gen_catalog.py`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/scripts/gen_catalog.py)
defines the field provenance:

- `license`, `base_model`, languages, capability flags, and benchmarks come from
  each `handy-computer` conversion repository's Hugging Face card.
- filenames and exact byte sizes come from Hugging Face repository sibling
  metadata.
- quantization labels are parsed from GGUF filenames.
- display name, architecture, and parameter label are range-read from a GGUF
  header.
- descriptions, recommendation membership, and recommendation rank can be
  Handy-local editorial curation.
- `granite-4.0-1b-speech` and `granite-speech-4.1-2b` receive local timestamp
  overrides pending card corrections.

The runtime consumes only part of this schema. In particular, `timestamps` is
present in JSON but is explicitly not wired into Handy's `CapabilityProbe`;
license and `base_model` are ignored by the runtime deserializer. A field being
present in Handy's catalog therefore does not prove Handy enforces or exercises
it at runtime.

## Independent verification boundary

The pinned catalog is authoritative for **what Handy declared and offered**.
It is not independently authoritative for the original model's legal terms,
behavior, compatibility, or immutable bytes.

Before FoldWise presents catalog fields as product truth, verify:

1. **Licenses and redistribution terms** against the pinned original
   `base_model` card plus its license/legal files. Do not inherit the conversion
   repository's short license label blindly.
2. **Lineage** against the original model and conversion documentation,
   including whether the GGUF is an authorized/faithful derivative and whether
   attribution or notice files must accompany it.
3. **Artifact integrity** against a pinned conversion-repository commit and its
   LFS SHA-256. Filename and byte size alone are insufficient.
4. **Capabilities and languages** against original documentation and the actual
   chosen runtime. Streaming, translation, language detection, timestamp
   granularity, and language codes need behavioral validation; a conversion
   card flag is evidence of Handy's declaration, not a FoldWise guarantee.
5. **Compatibility and performance** on the supported Mac/device envelope.
   Handy's speed/accuracy scores are generated from specific benchmarks and
   editorial fallbacks; they are not portable FoldWise acceptance results.

The original-base-model license audit found 16 discrepancies or missing values
across 62 distinct base-model repositories:

- `nvidia/parakeet-unified-en-0.6b`: Handy says CC-BY-4.0; the pinned official
  metadata identifies the NVIDIA Open Model License
  ([official revision API](https://huggingface.co/api/models/nvidia/parakeet-unified-en-0.6b/revision/fe53cd885760c96b6a5f51a0bfd362cb4584a98b)).
- `FunAudioLLM/Fun-ASR-MLT-Nano-2512` and
  `FunAudioLLM/Fun-ASR-Nano-2512`: Handy says `other`; the official cards say
  Apache-2.0.
- six localized Moonshine Tiny base models: Handy says MIT; official metadata
  says `other`.
- six localized Moonshine Base base models: Handy says MIT; official cards have
  no license metadata.
- `openai/whisper-large-v3-turbo`: Handy says Apache-2.0; the pinned official
  card says MIT
  ([official revision API](https://huggingface.co/api/models/openai/whisper-large-v3-turbo/revision/41f01f3fe87f28c78e2fbf8b568835947dd65ed9)).

The official Cohere Transcribe and Google MedASR repositories returned HTTP 401
because they are gated, so their legal and access conditions require an
authenticated review. These discrepancies do not remove entries from the Handy
parity baseline; they prevent FoldWise from treating Handy's license labels as
verified facts.

## Reproduce the complete inventory

The pinned JSON is the single source for the complete 65-model/337-file answer.
This command emits one row per artifact with the model identifier, display name,
base model, Handy-declared license and capabilities, default quantization,
artifact quantization, filename, exact byte size, and Handy-style moving
download URL:

```bash
REV=cdbc22390987643237756382ef367f7244b2844f

curl -fsSL \
  "https://raw.githubusercontent.com/cjpais/Handy/$REV/src-tauri/src/catalog/catalog.json" |
jq -r '
  .models[] as $m
  | $m.files[]
  | [
      $m.id,
      $m.name,
      $m.base_model,
      $m.license,
      ($m.capabilities | tojson),
      $m.default_quant,
      .quant,
      .filename,
      .size_bytes,
      ("https://huggingface.co/" + $m.id + "/resolve/main/" + .filename)
    ]
  | @tsv
'
```

This extraction avoids creating a second, manually copied catalog that can
drift from the pinned baseline while still yielding every exact row required by
implementation and acceptance work.
