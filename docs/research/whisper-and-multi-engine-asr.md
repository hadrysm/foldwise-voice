# Adding Whisper to foldwise-voice: a multi-engine ASR adapter, learning from Handy

**Summary:** foldwise-voice transcribes with exactly one engine — Parakeet TDT v3
on the Neural Engine via FluidAudio — behind a single Swift protocol,
`Transcribing`. Adding Whisper means adding a *second* engine behind that same
seam, because **FluidAudio has no Whisper backend and no engine abstraction you
can ride** — it is Parakeet-only. The reference implementation for "many ASR
engines, one app" is **[Handy](https://github.com/cjpais/Handy)**, which runs 65+
models across two native backends (whisper.cpp for the Whisper family, ONNX for
Parakeet et al.) behind one `Vec<f32>@16 kHz → String` boundary — the same shape
as our `transcribe(_ samples: [Float]) async throws -> String`. The good news:
our `Transcribing` protocol is already the adapter seam; the work is a second
conformer plus the *surrounding* machinery Handy proves you need — a model
catalog, per-engine capability flags, model download/storage, and selection UX.
On the Swift side there are two true drop-in Whisper routes today
(**WhisperKit** — CoreML/ANE, and **whisper.cpp/SwiftWhisper** — Metal/GGUF), both
of which accept our `[Float]` buffer verbatim, plus a strategically interesting
*future* option in Apple's **SpeechAnalyzer** (macOS 26+ only).
**Date:** 2026-07-07

This is an engineering note, not a survey. Every non-obvious claim is tied to a
primary source inline: Handy's own source as `Handy <path>:<line>` (read from a
shallow clone of `cjpais/Handy` at its current `main`), and external facts as a
linked citation. The full URL list is in *Further reading*. Where a claim could
not be pinned to a primary source, it says so at the end.

---

## 1. Where foldwise-voice is today

The dictation pipeline's transcribe stage already sits behind a protocol — this
is the seam an adapter system extends, not something we need to invent:

```swift
// Sources/FoldWiseVoiceKit/Pipeline.swift:21
protocol Transcribing: AnyObject {
    var ready: Bool { get }
    var onLoading: ((Bool) -> Void)? { get set }
    func warmup()
    func transcribe(_ samples: [Float]) async throws -> String
}
```

- There is **one conformer**, `Transcriber` (`Sources/FoldWiseVoiceKit/Transcriber.swift`),
  which loads FluidAudio's `AsrModels.downloadAndLoad()` and calls
  `AsrManager.transcribe(samples, decoderState:)`. Audio arrives as `[Float]` at
  16 kHz mono; the output is a trimmed `String`.
- The seam was introduced by **ADR-0002** as a deliberate test boundary (the
  async loading-model dance is the highest-value untested behaviour), and the
  **composition root (`AppMain`) constructs the concrete adapter**
  (`Sources/FoldWiseVoiceKit/AppMain.swift:81`) — so swapping or adding an engine
  is a change at one construction site, by design (`docs/adr/0002-pipeline-hybrid-seams.md`).
- The config schema **already reserves a per-mode ASR-model slot**: `Mode.asrModel`
  (`Sources/FoldWiseVoiceKit/Config.swift:16`), parsed from `asr_model` in
  `modes.json` and, tellingly, defaulting to `"mlx-community/whisper-large-v3-turbo"`
  when absent (`Config.swift:268`). Today it is **preserved on save but ignored** —
  "this app always transcribes with Parakeet v3" (`Config.swift:2-3`). That default
  string is a fossil from the app's Python/MLX era, when Whisper *was* the ASR.
  Adding Whisper is, in a real sense, reviving a field that already exists.

So the two structural pieces an adapter needs — an interface and a
per-mode selector field — are already present but dormant. What's missing is
everything *around* a second engine: choosing it, describing it, downloading its
weights, and reflecting its state in the UI.

**Why add Whisper at all.** Parakeet TDT v3 covers 25 European languages plus
Japanese and runs beautifully on the ANE ([FluidAudio ASR docs](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md)),
but Whisper large-v3 covers ~99 languages ([whisper.cpp model card](https://huggingface.co/ggerganov/whisper.cpp)),
has a deep ecosystem, and is what many users expect by name. The goal is *choice*
of engine per user/mode, not replacement — exactly Handy's posture.

---

## 2. The reference design: how Handy runs many ASR engines behind one seam

Handy is a Tauri app (Rust backend in `src-tauri/src`, React/TS frontend in
`src`). It is the closest existing analogue to "add Whisper next to Parakeet,"
and its design is worth copying selectively. Five parts matter.

### 2.1 The engine boundary is `Vec<f32>@16 kHz mono → String`

Every engine, whatever its internals, is fed the same thing and returns the same
thing. The manager's own comment fixes the contract: *"Input PCM is 16 kHz mono"*
(`Handy src-tauri/src/managers/transcription.rs:1397`), and the public method is
`transcribe(&self, audio: Vec<f32>) -> Result<String>`
(`Handy src-tauri/src/managers/transcription.rs:1094`). Timestamps/segments are
computed by some engines but **discarded at the boundary** — every dispatch arm
ends in `.map(|r| r.text)` (e.g. `transcription.rs:1259-1268`). **This is the
same shape as our `Transcribing.transcribe([Float]) -> String`.** The lesson:
a plain-text boundary is enough for a dictation app; you don't need to thread
segment/timestamp types through the seam.

### 2.2 Dispatch is an enum + `match`, *not* a unifying trait — and that's deliberate

Handy has **two backend crates** (`Handy src-tauri/Cargo.toml:72-76`):
- `transcribe-cpp` (whisper.cpp / GGML / GGUF, native GPU backends) — the
  **Whisper family** and other GGUF architectures.
- `transcribe-rs` (ONNX Runtime) — Parakeet, Moonshine, SenseVoice, GigaAM,
  Canary, Cohere.

Rather than define its own `TranscriptionEngine` trait, Handy wraps each loaded
backend in one sum type and dispatches with a big `match`
(`Handy src-tauri/src/managers/transcription.rs:159-171`):

```rust
enum LoadedEngine {
    TranscribeCpp(Session),        // whisper family (+ other GGUF arches)
    Parakeet(ParakeetModel),
    Moonshine(MoonshineModel),
    MoonshineStreaming(StreamingModel),
    SenseVoice(SenseVoiceModel),
    GigaAM(GigaAMModel),
    Canary(CanaryModel),
    Cohere(CohereModel),
}
```

Which arm runs is decided by a persisted `EngineType` tag carried on each model
(`Handy src-tauri/src/managers/model.rs:26-38`), matched at load and again at
transcribe (`transcription.rs:520-654`, `:1213-1332`). **Handy chose enum-match
over a trait on purpose**: the two upstream crates don't share a type language —
their option structs (`ParakeetParams`, `SenseVoiceParams`, `TranscribeOptions`,
`RunOptions`) differ too much to unify cleanly. The honest cost, which Handy's
own author-comments acknowledge: adding an engine means editing the enum plus
**three-plus parallel match blocks** (load, transcribe, streaming, backend
reporting).

**Translation to Swift/foldwise-voice:** we are in a *better* position than
Handy, because we write our own conformers rather than adapting two foreign
crates. A Swift `protocol Transcribing` (which we already have) is the clean
analogue of the trait Handy couldn't build — each engine's per-model options stay
private behind its own conformer. So we should keep the protocol and *not* copy
the enum-match; Handy's enum is a workaround for a constraint we don't have.

### 2.3 Model lifecycle: one at a time, drop-before-load, idle-unload, panic-isolated

Handy holds exactly one engine, behind a mutex:
`engine: Arc<Mutex<Option<LoadedEngine>>>` (`transcription.rs:221`). The lifecycle
rules are worth adopting wholesale:

- **One model loaded at a time**, and the old engine is **dropped before the new
  one is built** to avoid holding two large models in memory at once
  (`transcription.rs:494-505`).
- **No dummy-inference warmup** — creating the session (`model.session()`) is the
  warmup (`transcription.rs:159-163`). (We do have a real warmup today; keep it.)
- **Idle unload**: a watcher thread unloads the model after a configurable idle
  timeout, refreshing the timer during recording so it never unloads mid-session
  (`transcription.rs:279-343`); an `Immediately` setting unloads right after each
  transcription (`transcription.rs:431-441`).
- **Inference never holds the mutex**: the engine is `take()`n out of the lock
  before the multi-second inference runs, so status queries never block
  (`transcription.rs:1177-1187`), and a **model-swap-during-inference guard**
  (`return_engine`, `:1019-1031`) refuses to put a now-stale engine back.
- **Panic isolation**: the engine call is wrapped in `catch_unwind`; on panic the
  engine is dropped (not returned) so a crash unloads rather than poisons the app
  (`transcription.rs:1213`, `:1342-1379`).

For us, "one at a time + drop-before-load + idle unload" matters most: Whisper
large-v3 is ~1.5–2.9 GiB and Parakeet is ~600 MB, so letting a user switch
engines without doubling resident memory is the whole game.

### 2.4 A model catalog + capability flags (the part we don't have yet)

Handy ships an **offline catalog** compiled into the binary via `include_str!`
(`Handy src-tauri/src/catalog/mod.rs:1-14`) — a `catalog.json` of ~65 models. Each
entry's schema (`Handy src-tauri/src/catalog/catalog.json:5-60`):

```jsonc
{
  "id": "handy-computer/parakeet-unified-en-0.6b-gguf",  // HF repo id
  "name": "Parakeet Unified EN 0.6B",
  "architecture": "parakeet",                            // maps to a backend
  "family": "parakeet",
  "parameters": "0.6B",
  "license": "cc-by-4.0",
  "languages": ["en"],
  "capabilities": { "streaming": true, "translate": false,
                    "lang_detect": false, "timestamps": "token" },
  "speed_score": 79, "accuracy_score": 90,               // 0–100, drives ranking
  "files": [ { "filename": "...-Q4_K_M.gguf", "quant": "Q4_K_M", "size_bytes": 477274496 },
             { "filename": "...-Q8_0.gguf",  "quant": "Q8_0",  "size_bytes": 731357568 }, … ],
  "default_quant": "Q8_0",
  "recommended": true, "recommended_rank": 1
}
```

The catalog holds **13 Whisper models** (tiny/base/small/medium/large v1/v2/v3,
turbo, `.en` variants, plus Breeze-ASR-25) and **12 Parakeet models**, among a
long tail (Moonshine, Canary, GigaAM, Voxtral, Qwen3-ASR, SenseVoice, Cohere…).
Notably Handy's **#1 recommended model is Parakeet, and Whisper Medium is only
rank 5** — corroboration that Parakeet is competitive and Whisper's pull is
language coverage + familiarity, not raw accuracy.

Capabilities are expressed as an all-`Option` probe
(`Handy src-tauri/src/managers/model_capabilities.rs:90-107`): `languages`,
`supports_streaming`, `supports_translation`, `supports_language_detect`, plus a
`Compatibility` verdict (`Compatible` / `MaybeIncompatible` / `Unsupported` /
`Unknown`). The clever bit: capabilities are canonical **inside the GGUF file**,
so Handy reads them two ways — a **pre-download header probe** (a minimal,
dependency-free GGUF KV reader that fetches a 64 KiB–16 MiB prefix,
`Handy src-tauri/src/managers/gguf_meta.rs`) to show honest capabilities *before*
download, then **reconciles against the live model after load**
(`model.rs:1210-1232`). The `timestamps` field exists in JSON but is deliberately
**not yet consumed** by the runtime (`catalog/mod.rs:53-60`) — capabilities the UI
actually uses are languages, translation, streaming, language-detect.

**Translation to us:** we already have a curated-model catalog pattern — but only
for *Ollama* models: `ModelCatalog.Entry { name, size, speed, quality, blurb }`
(`Sources/FoldWiseVoiceKit/ModelCatalog.swift`). An ASR catalog is the same idea,
one axis over (engine, model, size, languages, speed/quality, download source).
We won't need GGUF header-probing if we use CoreML engines (WhisperKit/FluidAudio
carry their own metadata); we'd need something GGUF-ish only if we go the
whisper.cpp/GGUF route.

### 2.5 Download, storage, and selection

- **Download**: Handy uses a git fork of `hf-hub` pinned for **cancellable
  downloads** (`Handy src-tauri/Cargo.toml:84-86`), pulling into the **shared
  Hugging Face cache** (`~/.cache/huggingface/hub`) with 8 parallel file chunks,
  progress events, cancellation, and resume delegated to hf-hub
  (`model.rs:1743-1824`). A legacy URL path adds manual `Range` resume + SHA-256
  verification + tar.gz extraction (`model.rs:1846-2172`).
- **Selection & state**: the active model is a single persisted string
  `settings.selected_model`; there is **no hardcoded default** — Handy
  auto-selects the first downloaded model in ranked order after onboarding
  (`model.rs:1363-1414`). Switching persists the choice *early*, then loads (or
  defers load if the unload-timeout is `Immediately`), and **reverts on load
  failure** (`Handy src-tauri/src/commands/models.rs:91-155`).
- **Frontend UX**: a Zustand `modelStore` listens to ~11 backend events
  (`download-progress`, `-complete`, `-failed`, `verification-*`, `extraction-*`,
  `-cancelled`, `model-state-changed`…) and drives a settings page with search, a
  language filter, "Your Models" vs "Available Models" sections, per-card
  progress/speed, and delete confirmation (`Handy src/stores/modelStore.ts`,
  `src/components/settings/models/ModelsSettings.tsx`).

**Translation to us:** most Swift ASR libraries *auto-download* their weights
from Hugging Face on first load (FluidAudio, WhisperKit), so we may not need a
hf-hub equivalent at all — but we *do* need the state model Handy exposes
(downloading / verifying / ready / active / error) surfaced through our existing
`onLoading` hook and HUD. whisper.cpp/GGUF is the one route where we'd own the
download UX ourselves.

### 2.6 Preprocessing is shared and engine-agnostic

Handy's audio pipeline — mono-downmix → resample to 16 kHz (rubato) → **Silero
VAD gate** — runs once in the recorder and feeds every engine the same clean
16 kHz mono `f32` frames (`Handy src-tauri/src/audio_toolkit/audio/recorder.rs`,
`.../vad/silero.rs`). Nothing about preprocessing is per-engine. We already
produce `[Float]` at 16 kHz upstream of the seam, so a new engine inherits our
recording/preprocessing untouched — a real simplification versus Handy, which had
to build the shared pipeline deliberately.

---

## 3. Whisper on Apple Silicon in a SwiftPM app: the concrete routes

All three routes below accept **16 kHz, mono, float32 PCM in [-1.0, 1.0]** — i.e.
our recorder's `[Float]` output plugs in with no resampling
([SwiftWhisper README](https://github.com/exPHAT/SwiftWhisper);
WhisperKit `AudioProcessor.swift`; [whisper.cpp README](https://github.com/ggml-org/whisper.cpp)).
So the audio wiring is mechanical in every case; the differences are dependency
shape, acceleration path, model provisioning, and maintenance health.

### 3.1 WhisperKit — CoreML/ANE, Swift-native (the natural sibling to FluidAudio)

- **What/where:** Argmax's pure-Swift, CoreML implementation
  ([argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)), **MIT** licensed.
  The most Apple-native and most actively maintained route.
- **Seam fit — direct:** `open func transcribe(audioArray: [Float], decodeOptions:) async throws -> [TranscriptionResult]`;
  concatenate `.text`. There is also an `AudioStreamTranscriber` for live mic
  dictation, and `wordTimestamps: Bool` in `DecodingOptions` (default false).
- **Acceleration:** each sub-model's compute unit is configurable via
  `ModelComputeOptions`; **encoder and decoder default to `.cpuAndNeuralEngine`
  (the ANE)** — the same ANE story we get from FluidAudio today.
- **Models:** auto-downloaded CoreML `.mlmodelc` bundles from
  [huggingface.co/argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml)
  on first use, then offline. Variants include `openai_whisper-large-v3-v20240930`
  and `_turbo` (+ palettized `_NNNMB` compressed variants), distil-large-v3, and
  all tiny/base/small/medium (`.en` too). "WhisperKit automatically downloads the
  recommended model for the device if not specified."
- **OS floor:** the WhisperKit product documents **macOS 14.0+ / Xcode 16** —
  exactly our floor (the package manifest's package-level floor is lower, but the
  WhisperKit product's is 14).
- **⚠️ Naming/version caveat — verify before adding the dep:** as of **v1.0.0
  (2026-05-01)** the repo was **renamed to `argmaxinc/argmax-oss-swift`** and
  WhisperKit folded into a 3-kit SDK (WhisperKit + SpeakerKit + TTSKit). The old
  `argmaxinc/WhisperKit` URL redirects, but the SPM URL is now
  `https://github.com/argmaxinc/argmax-oss-swift.git` and the current README pins
  `from: "0.9.0"` while the latest tag is `v1.0.0` — a floor inconsistency in
  their own docs. Pin an explicit recent version and use product `WhisperKit`.

### 3.2 whisper.cpp — Metal + optional CoreML encoder, GGUF quantization (Handy parity)

- **What/where:** the C/C++ port ([ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)),
  **MIT**, very active (v1.9.1, June 2026; ~51k stars). "Apple Silicon
  first-class citizen" — inference runs fully on the **GPU via Metal**, with the
  encoder optionally on the **ANE via a generated CoreML model** (">3× faster than
  CPU-only," `-DWHISPER_COREML=1`, first run slow while the ANE compiles).
- **SwiftPM story — XCFramework `binaryTarget`, not a root Package.swift:** the
  repo has **no root `Package.swift`** (verified 404 on `master`) and no `swift`
  binding dir. The official mechanism is the precompiled **XCFramework** consumed
  as a `binaryTarget` in *your* app manifest, e.g.
  `whisper-v1.9.1-xcframework.zip` from the release, then call the C API
  (`whisper_init_from_file`, `whisper_full`). ⚠️ The old community wrapper
  `ggerganov/whisper.spm` is **being archived** — do not use it.
- **Seam fit — direct but more C-bridging:** hand the `[Float]` to `whisper_full`
  as `const float*` + length; read segments and join. You own the FFI glue.
- **Models:** ggml/GGUF single-file binaries from
  [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp)
  (MIT). **You provision the file** (bundle or self-download). GGUF quantization
  (`q5_0`/`q5_1`/`q8_0`) roughly halves the footprint — e.g.
  large-v3-turbo `q5_0` ≈ 547 MiB vs 1.5 GiB unquantized.
- **Why consider it over WhisperKit:** smallest dependency surface, full-GPU
  Metal, GGUF quantization control, and **byte-for-byte parity with Handy's model
  set** (same ggml files). The cost: you write the C bridge and own model
  download/storage yourself.

### 3.3 SwiftWhisper — thin Swift wrapper over whisper.cpp (MVP-only)

- **What/where:** [exPHAT/SwiftWhisper](https://github.com/exPHAT/SwiftWhisper),
  **MIT**. The friendliest API of the three:
  `try await whisper.transcribe(audioFrames: [Float])` → segments; a
  `WhisperDelegate` gives progress + incremental segments. Model loaded from a
  local ggml file URL (`Whisper(fromFileURL:)`).
- **⚠️ Stale:** last release **1.2.0, Aug 2023**; vendors whisper.cpp at a
  2023-era submodule commit (`95b02d7`) — predates large-v3-turbo and recent
  Metal/CoreML work. Also **must** be built in Release / `-O3` or it's unusably
  slow. Fine for a quick MVP proof; not a foundation to build on.

### 3.4 Model size/speed/quality (ggml sizes; CoreML equivalents comparable)

| Model | ggml size | Multilingual | Note |
|---|---|---|---|
| tiny / tiny.en | 75 MiB (q5_1 ≈ 31 MiB) | multi + .en | fastest, lowest RAM, lowest accuracy |
| base / base.en | 142 MiB | multi + .en | common lightweight sweet spot |
| small / small.en | 466 MiB | multi + .en | better accuracy, still light |
| medium / medium.en | 1.5 GiB | multi + .en | heavier |
| large-v1/v2/v3 | 2.9 GiB each | multi only | best accuracy, no `.en` variant |
| **large-v3-turbo** | 1.5 GiB (q5_0 ≈ 547 MiB) | multi only | **near-large-v3 accuracy at ~medium size/speed — best dictation pick** |

Source: [ggerganov/whisper.cpp model card](https://huggingface.co/ggerganov/whisper.cpp),
[whisper.cpp README](https://github.com/ggml-org/whisper.cpp). `.en` models are
more accurate/faster for English at a given size but stop at `medium`. Per-chip
latency/RAM numbers are **not** authoritatively published — measure on the target
M-series (see *Unpinned claims*).

---

## 4. Apple-native and FluidAudio: the other engines you'd expose

### 4.1 FluidAudio is Parakeet-only — but exposes more Parakeet than we use

FluidAudio has **no Whisper backend and no general engine abstraction**; its
`Sources/FluidAudio/` tree is `ASR / Diarizer / ITN / Shared / TTS / VAD` with no
Whisper anywhere ([source tree](https://github.com/FluidInference/FluidAudio/tree/main/Sources/FluidAudio)).
The "whisper" mentions in its README are third-party apps in a *who-uses-this*
list. What it *does* expose beyond our current use:
- **Parakeet TDT v3** (default, 25 languages) — what we run now.
- **Parakeet TDT v2** (English-only, better long-form English recall).
- **Parakeet EOU** (streaming ASR with end-of-utterance detection) via
  `SlidingWindowAsrManager`.

Its `transcribe(_ samples:source:)` overload **already takes `[Float]` 16 kHz
mono** and returns `ASRResult` ([API.md](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md)) —
so exposing v2 or a streaming variant is nearly free within our existing
conformer. Version 0.12.4, `swift-tools-version: 6.0`, `.macOS(.v14)`; treat the
pre-1.0 API as subject to change.

### 4.2 Apple SpeechAnalyzer / SpeechTranscriber — compelling, but macOS 26+ only

The new Speech framework API (WWDC25) is **macOS 26 / iOS 26 only** — it **does
not exist on macOS 14–15** ([Apple: SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer),
[WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)). It is
fully on-device after a runtime model download via `AssetInventory`, ~10 languages
at launch, and Argmax measured it as matching "mid-tier Whisper" accuracy
([Argmax](https://www.argmaxinc.com/blog/apple-and-argmax)). But its input is an
`AsyncStream<AnalyzerInput>` wrapping `AVAudioPCMBuffer` converted to the
analyzer's `bestAvailableAudioFormat` — **it does not take a raw `[Float]`**. So
it's a **future adapter behind `#available(macOS 26, *)`**, bridging
`[Float]→AVAudioPCMBuffer` and folding async `AttributedString` results into a
`String` — attractive because it ships no model weights and gives volatile/live
results ideal for a dictation HUD, but it can't be our macOS 14 floor.

### 4.3 SFSpeechRecognizer — available on macOS 14, but a poor dictation fit

The older `SFSpeechRecognizer` runs on macOS 10.15+ and supports on-device
recognition (`requiresOnDeviceRecognition`) ([Apple docs](https://developer.apple.com/documentation/speech/sfspeechrecognizer)),
but the framework **stops tasks after ~1 minute** and is buffer/file-oriented
(no raw `[Float]` entry point). The 1-minute cap fights open-ended dictation;
not recommended unless we ever need macOS 10.15–13 reach.

---

## 5. What an adapter system for foldwise-voice would actually look like

Nothing here is a decision — it's the shape the research points to, so the later
decision has concrete options.

### 5.1 Keep the protocol; add conformers (don't copy Handy's enum)

The `Transcribing` protocol already *is* the adapter interface. A first Whisper
cut is one new file:

```swift
// e.g. Sources/FoldWiseVoiceKit/WhisperKitTranscriber.swift
final class WhisperKitTranscriber: Transcribing {
    var ready = false
    var onLoading: ((Bool) -> Void)?
    func warmup() { /* kick off WhisperKit(model:) load, flip onLoading */ }
    func transcribe(_ samples: [Float]) async throws -> String {
        let results = try await pipe.transcribe(audioArray: samples)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Because our recorder already yields `[Float]@16 kHz` and the protocol already
mirrors the loading dance, a WhisperKit or SwiftWhisper conformer is a near
drop-in. We do **not** need Handy's `enum LoadedEngine` + parallel matches — that
was a workaround for two foreign Rust crates with incompatible option types; in
Swift each conformer keeps its own options private.

### 5.2 The machinery around the seam (this is the real work)

Handy proves the interface is the easy 20%. The 80% is:

1. **Engine/model selection.** Introduce an `ASREngine` notion and either (a)
   revive the dormant per-mode `Mode.asrModel` field (`Config.swift:16`) so each
   Mode can pick engine+model, or (b) add a single global ASR-model setting like
   Handy's `selected_model`. Per-mode is more flexible and matches the existing
   schema; a global setting is simpler. (Decision deferred.)
2. **A dispatching `Transcribing` that owns lifecycle.** A small composite that,
   given the selected engine, lazily constructs the right conformer, and enforces
   Handy's lifecycle rules: **one engine loaded at a time, drop-before-load, idle
   unload** (Whisper large is ~1.5–2.9 GiB; switching must not double resident
   memory). It re-emits `onLoading` so the HUD's existing "loading model" state
   just works.
3. **An ASR model catalog.** Mirror the existing `ModelCatalog` pattern
   (`ModelCatalog.swift`) but keyed on ASR models: `{ engine, id, displayName,
   size, languages, speed, quality, downloadSource }`. Curated, small, honest —
   like Handy's, but we can hardcode it in Swift rather than ship a JSON.
4. **Capability flags per engine/model.** At minimum `languages` and (later)
   `streaming`/`translate`. Handy's all-`Option` "unknown until proven" posture
   and its **post-load reconciliation against the live model** are the pattern to
   copy — don't trust the catalog blindly; confirm against what actually loaded.
5. **Download + progress.** FluidAudio and WhisperKit **auto-download from HF on
   first load**, so for those we mostly need to surface progress/errors through
   `onLoading` + HUD (no hf-hub equivalent needed). Only the whisper.cpp/GGUF
   route makes us own download/storage/verification ourselves.
6. **Settings UX.** An ASR pane analogous to the Ollama "Models" pane in Settings:
   pick engine + model, show size/languages/speed guidance, download state. This
   is the visible surface of everything above.

### 5.3 A recommended default path (for the later decision to weigh)

- **Primary Whisper engine → WhisperKit.** It is the natural sibling to
  FluidAudio: Swift-native, CoreML/**ANE** (same acceleration story), MIT,
  actively maintained, `transcribe(audioArray: [Float])` fits the seam verbatim,
  auto-downloads models, and shares our macOS 14 floor. Its dep surface is the
  one meaningful cost — plus the `argmax-oss-swift` rename to verify.
- **Alternative Whisper engine → whisper.cpp XCFramework** if we want GGUF
  quantization control, minimal deps, full-Metal, and Handy model parity, at the
  cost of writing C-bridge + our own model download UX.
- **Avoid SwiftWhisper** except as a throwaway MVP spike (stale since 2023).
- **Keep FluidAudio/Parakeet as the default engine** (fast, tiny, ANE) and expose
  Parakeet v2 / streaming cheaply from the same conformer.
- **Treat SpeechAnalyzer as a future, `#available(macOS 26, *)`-gated adapter**;
  don't let it gate the macOS 14 floor.
- **Skip SFSpeechRecognizer** (1-minute cap).

### 5.4 Decisions to defer (candidates for an ADR)

- Per-mode `asr_model` vs a single global ASR-model setting.
- WhisperKit (CoreML/ANE, heavier dep, auto-download) **vs** whisper.cpp
  (Metal/GGUF, C-bridge, we own downloads) as the Whisper backend.
- Whether to ship any weights in-bundle or always download on first use (affects
  the .dmg size and the "nothing leaves your machine" story — note model
  downloads already hit HF/GitHub, same posture as the existing Parakeet download
  and the once-a-day update check).
- Catalog breadth: just Whisper large-v3-turbo + a small/base, or a fuller menu.
- Idle-unload policy and default engine per fresh install.

---

## 6. Further reading (primary sources)

Handy source (shallow clone of `github.com/cjpais/Handy` at `main`; paths relative
to `src-tauri/` unless noted):
- Engine enum + dispatch + lifecycle: `src/managers/transcription.rs`
- Engine type tag: `src/managers/model.rs:26-38`; model registry/download: `src/managers/model.rs`
- Capabilities probe + known arches: `src/managers/model_capabilities.rs`
- GGUF header reader: `src/managers/gguf_meta.rs`
- Offline catalog: `src/catalog/catalog.json`, `src/catalog/mod.rs`
- Backend feature matrix: `Cargo.toml:72-152`; hf-hub fork: `Cargo.toml:84-86`
- Shared preprocessing (VAD/resample): `src/audio_toolkit/audio/recorder.rs`, `src/audio_toolkit/vad/silero.rs`
- Frontend model UX: `src/stores/modelStore.ts`, `src/components/settings/models/ModelsSettings.tsx`

Whisper for Swift:
- whisper.cpp: <https://github.com/ggml-org/whisper.cpp> · models <https://huggingface.co/ggerganov/whisper.cpp> · (dead wrapper) <https://github.com/ggerganov/whisper.spm>
- SwiftWhisper: <https://github.com/exPHAT/SwiftWhisper>
- WhisperKit / argmax-oss-swift: <https://github.com/argmaxinc/WhisperKit> · models <https://huggingface.co/argmaxinc/whisperkit-coreml>

FluidAudio (current engine):
- Repo: <https://github.com/FluidInference/FluidAudio> · API <https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md> · ASR guide <https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md> · Parakeet v3 model <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml>

Apple speech APIs:
- SpeechAnalyzer: <https://developer.apple.com/documentation/speech/speechanalyzer> · SpeechTranscriber <https://developer.apple.com/documentation/speech/speechtranscriber> · WWDC25 session 277 <https://developer.apple.com/videos/play/wwdc2025/277/> · Argmax analysis <https://www.argmaxinc.com/blog/apple-and-argmax>
- SFSpeechRecognizer: <https://developer.apple.com/documentation/speech/sfspeechrecognizer> · on-device flag <https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition>

foldwise-voice source anchors:
- `Sources/FoldWiseVoiceKit/Pipeline.swift:21` (`Transcribing`), `Transcriber.swift`, `AppMain.swift:81`, `Config.swift:16,268` (`asr_model`), `ModelCatalog.swift`, `docs/adr/0002-pipeline-hybrid-seams.md`

---

## 7. Unpinned / uncertain claims (verify before relying on them)

- **WhisperKit package coordinates & current version.** The rename to
  `argmaxinc/argmax-oss-swift` (v1.0.0, 2026-05-01) and the `from: "0.9.0"`-vs-tag
  inconsistency come from the repo's release history and README; confirm the exact
  SPM URL, product name, and version floor against the live repo before adding the
  dependency.
- **Apple SpeechAnalyzer GA vs beta and exact launch language count.** Apple's doc
  pages render client-side (fetches returned empty bodies), so the API shape and
  macOS-26 floor come from the WWDC25 session, Apple's `swift-scribe` sample, and
  partner/community writeups. Re-confirm against the live Apple docs for the ship
  date.
- **Per-chip latency and RAM for Whisper models.** Not authoritatively published
  in the primary repos/model cards — only file sizes and relative speedups (e.g.
  "ANE encoder >3× vs CPU"). Treat any ms/GB figure as measure-on-device.
- **`transcribe-rs` / `transcribe-cpp` exact trait signatures.** The crates are not
  vendored in Handy's clone; the trait surfaces were inferred from Handy's call
  sites (authoritative for *how* they're used) corroborated by docs.rs summaries,
  not from the crate source directly.
- **FluidAudio pre-1.0 API stability.** No published stability guarantee; the
  Parakeet-v2/streaming surface described may shift before 1.0.
