# Wispr Flow and Handy: mechanics behind perceived speed

Issue: [#343](https://github.com/hadrysm/foldwise-voice/issues/343)

Researched: 2026-07-27

Handy source pin: `v0.9.4`-era `main`,
[`6cad594`](https://github.com/cjpais/Handy/tree/6cad594cdba3aaa99555183fcb1e7b5a3967168e)
(2026-07-25)

## Executive result

The issue's starting premise is no longer literally true. Handy's default
transcription shortcut is still a one-step local-ASR path with no LLM, but
Handy is no longer uniformly "record, release, then run thin ASR." Since
v0.9.0 it can stream compatible local models and show committed and tentative
text while the user speaks. It also has a separate, optional post-processing
shortcut that can call a local or cloud LLM.

Wispr Flow takes the opposite presentation approach. First-party material says
dictation is processed in real time in the cloud, and Wispr's public API can
stream audio and partial ASR results, but the proprietary consumer transport is
not documented. The desktop product deliberately withholds unstable text.
While the user speaks it shows a waveform/status bar; after release it inserts
the formatted result. There is no evidence that the consumer desktop client
puts partials into the target field.

| Path | Work during speech | Visible during speech | Second pass | Final insertion |
| --- | --- | --- | --- | --- |
| Wispr Flow desktop | Cloud audio processing; exact consumer transport is private | Flow Bar waveform, not transcript text | Always-on Smart Formatting on desktop; cloud | Full processed transcript after stop |
| Handy, streaming-capable model, raw shortcut | Local streaming ASR | Committed prefix plus revisable tentative suffix | None | One paste of finalized ASR |
| Handy, batch model, raw shortcut | Local recording | Compact recording indicator | None | Batch ASR after stop, then one paste |
| Handy, post-processing shortcut | Same ASR path as above | ASR preview if the model streams; then a Processing state | Optional local or cloud LLM, awaited as a complete response | One paste of the processed result |

The shared speed technique is overlap plus honest stage feedback, not simply
having fewer stages. Wispr's architecture supports overlapping cloud work with
recording and its product hides unstable intermediate text. Handy overlaps
local ASR with recording when the model supports it, exposes uncertainty
explicitly, and keeps the target application untouched until it has a final
string.

## Wispr Flow

### Streaming internally, deferred writing visibly

Wispr's own design account contrasts conventional real-time ASR—which visibly
streams words that are often wrong and can feel "overstimulating" or
"jarring"—with Flow's approach: let the system wait, understand, and then
write. The normal desktop recording surface is the persistent Flow Bar, whose
documented recording controls and waveform do not include a transcript
preview. ([design rationale](https://wisprflow.ai/post/designing-a-natural-and-useful-voice-interface),
[Flow Bar documentation](https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android))

That is a presentation decision, not evidence of batch-only transport.
Wispr's data-controls page says audio and text are processed in real time in
the cloud. Its public WebSocket API accepts audio chunks—ideally around one
second at a time—and returns partial and final transcriptions. The API also has
a warm-up endpoint. These prove that Wispr's platform can overlap upload and
ASR with recording. They do **not** prove that the proprietary consumer client
uses these exact public endpoints or chunk sizes.
([data controls](https://wisprflow.ai/data-controls),
[WebSocket API](https://api-docs.wisprflow.ai/websocket_api),
[warm-up API](https://api-docs.wisprflow.ai/warm_up_api))

The useful distinction is therefore:

- **Transport/backend:** streaming is available and real-time cloud processing
  is first-party documented.
- **Desktop target field:** no incremental insertion while speaking is
  documented; the Flow Bar carries recording feedback instead.
- **Public API consumers:** can choose to expose partials, but that is a
  different UI contract from the Flow desktop app.

An older/general help article says Flow "types out your words in real time."
Read alongside the more specific design article and current Flow Bar docs,
this is best understood as a broad speed claim rather than evidence of
word-by-word insertion into the active desktop field.
([What is Flow?](https://docs.wisprflow.ai/articles/2772472373-what-is-flow))

### The formatting pass is real and cloud-hosted

On desktop, Smart Formatting is always on. It adds punctuation, removes filler
words, and can use later speech to revise earlier intent through Backtrack—for
example, "coffee 2 actually 3" yields only the corrected value. The original
transcript can be recovered with **Undo AI edit**; raw insertion is documented
as an iOS option, not the normal desktop path.
([Smart Formatting and Backtrack](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack))

Wispr's security FAQ separately names the speech-to-text output, formatted
result, and downstream AI formatting/rewrite layers as data artifacts. The
data-controls page says transcription always uses the cloud and that Wispr
uses both open-source and proprietary language models. Thus the supported
mechanical account is:

1. audio is sent for cloud processing during dictation;
2. ASR produces text;
3. an AI formatting/rewrite layer uses whole-utterance context;
4. the formatted result is returned for insertion.

The public material does not expose whether ASR tokens are fed incrementally
into the formatter, whether the formatter itself streams tokens internally, or
the production model names.
([security FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq),
[data controls](https://wisprflow.ai/data-controls))

### Final insertion and preview replacement

Wispr's hands-free documentation says that stopping a desktop dictation causes
the transcript to be pasted into the active field. Its paste troubleshooting
guide says the desktop app temporarily uses the clipboard and restores the
previous contents after the paste. That supports a full-result, post-stop paste
rather than incremental target-field typing. Because the client is
proprietary, "atomic" here means the observable product-level operation, not a
guarantee about every application's internal handling of a paste event.
([hands-free flow](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free),
[paste behavior](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation))

There is no normal raw live-text preview for the formatter to replace. The
semantic change happens off-screen: waveform/status during speech, then the
restructured final text appears in the target application. This avoids a
visually disruptive raw-to-polished swap, at the cost of giving the user no
textual evidence of recognition until the operation finishes.

### Latency evidence

Wispr published an engineering target of completing the transcript and LLM
work within **700 ms after speech ends**, with component targets below 200 ms
for ASR, below 200 ms for the LLM, and at most 200 ms for networking. These are
design budgets, not production percentiles. A REST API example reports
`total_time: 432`, but an example response is not a benchmark. Wispr has not
published a production p50/p95/p99 for stop-to-paste or time-to-first-visible
text.
([technical challenges](https://wisprflow.ai/post/technical-challenges),
[REST transcription example](https://api-docs.wisprflow.ai/rest_api_transcribe))

The July 9, 2026 changelog says latency had fallen 30% year-to-date, again
without an absolute distribution. The same first-party changelog records
users reporting missed course corrections, swapped words, ignored
punctuation, and slower dictation in June. Those reports demonstrate that
users notice both semantic rewriting failures and delay, but they are not
evidence about reactions to live-preview replacement because Flow normally
does not show such a preview.
([Wispr Flow changelog](https://wisprflow.ai/whats-new))

## Handy

### The current product is model-dependent

Handy changed materially in v0.9.0. Its release notes say `transcribe.cpp`
became the primary engine, compatible models could stream text while the user
spoke, and streaming became the default experience with a compatible model.
The notes recommend Parakeet Unified EN and Nemotron Streaming. Any account of
Handy as universally release-triggered batch ASR describes older behavior or
a current non-streaming model, not the whole current product.
([v0.9.0 release notes](https://github.com/cjpais/Handy/blob/v0.9.0/src/content/release-notes/0.9.0.md))

There is no single fixed Handy model. The current engine enum accepts
GGML/GGUF families through `transcribe.cpp`—including Whisper, Parakeet,
Voxtral, Qwen3-ASR, and Nemotron—and retains several legacy `transcribe-rs`
engines. The catalog ranks the streaming Parakeet Unified EN model first and
Nemotron Streaming second, followed by batch models, but onboarding ultimately
records a user-selected downloaded model.
([engine families](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/managers/model.rs#L25-L38),
[current model catalog](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/catalog/catalog.json#L1-L115),
[model selection](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/managers/model.rs#L1363-L1410))

The precise current record-to-insert path is:

1. On hotkey press, Handy starts ASR-model and VAD loading in parallel. It
   checks the selected model's `supports_streaming` capability, starts a stream
   if supported, chooses the live or compact overlay, and begins local audio
   capture.
   ([start path](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/actions.rs#L463-L610))
2. The recorder's audio callback forwards frames to the active stream router.
   A non-streaming model merely records them for later batch transcription.
   ([audio routing](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/managers/audio.rs#L262-L302))
3. A streaming engine emits snapshots containing an append-only `committed`
   prefix and a volatile `tentative` suffix. The overlay replaces its state
   with each snapshot and styles both spans separately.
   ([stream semantics](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/managers/transcription.rs#L57-L64),
   [stream loop](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/managers/transcription.rs#L944-L1004),
   [overlay rendering](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src/overlay/RecordingOverlay.tsx#L210-L259))
4. On hotkey release, Handy finalizes the active stream. If no usable stream
   result exists, it batch-transcribes the recorded samples.
   ([stop/fallback path](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/actions.rs#L613-L705))
5. It optionally post-processes the completed ASR string, saves history, and
   calls `paste` once with the final string. The normal clipboard path saves the
   old clipboard, writes the whole result, sends the paste chord, and restores
   the clipboard.
   ([output and paste](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/actions.rs#L738-L819),
   [clipboard paste](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/clipboard.rs#L15-L99))

This makes final target insertion atomic at the Handy pipeline boundary:
the target app receives no live ASR edits, only one call with the final text.
Alternative configured output methods such as direct typing or an external
script may implement that call differently, but Handy does not repeatedly
insert and correct target-field text during recognition.
([paste dispatch](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/clipboard.rs#L611-L684))

### Handy now has an optional second pass

Handy defines separate raw and post-processing actions. On macOS their default
shortcuts are Option-Space and Option-Shift-Space respectively, and
post-processing is disabled by default. Therefore **the default raw shortcut
is genuinely one-step local ASR**, but "Handy has no LLM" is no longer true.
([action map](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/actions.rs#L904-L916),
[shortcut defaults](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/settings.rs#L787-L827),
[post-processing default](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/settings.rs#L578-L580))

The second pass can be local—native Apple Intelligence on supported
Apple-silicon Macs or a custom OpenAI-compatible endpoint defaulting to
`localhost:11434/v1`—or cloud-hosted through the built-in providers. The
default prompt fixes spelling, capitalization, punctuation, number forms, and
fillers while instructing the model to preserve meaning and word order.
([provider defaults](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/settings.rs#L596-L684),
[default prompt](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/settings.rs#L713-L718))

The implementation awaits Apple Intelligence or an OpenAI-compatible chat
completion and only then returns the complete processed string. It does not
consume an SSE/token stream. Post-processing therefore adds a serial
completion-shaped stage after ASR, even when ASR itself streamed.
([post-processing call](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/actions.rs#L104-L340),
[HTTP completion client](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/llm_client.rs#L108-L218))

### What happens to the live preview

For streaming ASR, tentative text can change while the user speaks; committed
text is explicitly append-only. On release, the overlay retains the ASR text
while switching its row to Transcribing, and, for the post-processing action,
then to Processing.
([event contract](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/managers/transcription.rs#L57-L93),
[retained-text UI](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src/overlay/RecordingOverlay.tsx#L210-L259))

**Code-derived inference:** the polished result does not replace the raw ASR
inside the overlay. After entering the Processing phase, the current path emits
no new `StreamTextEvent`; it awaits post-processing, passes the resulting
`final_text` once to `paste`, and hides the overlay. The observable semantic
jump is therefore from retained ASR preview in Handy's overlay to processed
text in the target application—not an animated in-overlay replacement.
([processing and final paste](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src-tauri/src/actions.rs#L738-L819),
[preview state listener](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/src/overlay/RecordingOverlay.tsx#L97-L105))

### Latency evidence and user reactions

Handy's README says Parakeet V3 runs at about **5x real time** on a mid-range
i5. That is model throughput, not stop-to-paste latency. The v0.9.0 notes say
streaming models "typically" finish sooner, but the project publishes no
controlled p50/p95/p99 end-to-end measurements.
([README](https://github.com/cjpais/Handy/blob/6cad594cdba3aaa99555183fcb1e7b5a3967168e/README.md#L229-L242),
[v0.9.0 release notes](https://github.com/cjpais/Handy/blob/v0.9.0/src/content/release-notes/0.9.0.md))

First-party GitHub reports show why hardware and backend must be attached to
any number:

- A v0.9.4 Windows CPU report using Parakeet Unified EN Q8 logged 5.43 seconds
  of audio against 17.97 seconds of model compute, while shorter samples varied
  substantially; the reporter described text arriving many seconds after
  release. ([issue #1754](https://github.com/cjpais/Handy/issues/1754))
- Another v0.9.4 report measured 26.31 seconds of audio against 5.67 seconds of
  cumulative model compute on a hybrid-GPU path (4.64x real time), with the
  full paste call taking 226.4 ms. The same model on CPU was much slower.
  ([issue #1775](https://github.com/cjpais/Handy/issues/1775))

These are individual user measurements, not comparable benchmarks. They do
show that "local" does not by itself guarantee low release latency.

The strongest first-party reaction to visible streaming predates v0.9.0. A
contributor said a prototype live preview increased confidence and exposed
empty-transcript failures; the maintainer rejected that repeated-batch
implementation because moving text could be visually unstable and repeated
work could pin the CPU. The shipped committed/tentative stream addresses those
failure modes differently. A later v0.9.4 user reacted negatively when their
streaming configuration still pasted several seconds after release.
([PR #864](https://github.com/cjpais/Handy/pull/864),
[issue #1754](https://github.com/cjpais/Handy/issues/1754))

There is no first-party user evidence about Handy replacing live raw text with
restructured text in the overlay, because the current implementation does not
perform that replacement.

## Techniques available to a local-first macOS app

1. **Stream local ASR into a separate overlay.** Handy demonstrates the complete
   pattern: capability-gated streaming, frame routing, committed/tentative
   spans, and batch fallback. It provides confidence before release without
   mutating the user's document.
2. **Keep target insertion final-only.** Both products separate status/preview
   from the target field and paste only when the result is ready. This avoids
   cursor drift, undo pollution, and application-specific correction logic.
3. **Make the second stage explicit.** A local-first app can run formatting
   locally with Apple Intelligence or a localhost model. Handy's retained text
   plus Processing state is a useful minimum; the formatter still lies on the
   post-release critical path unless it can safely begin from stable ASR
   prefixes.
4. **Warm and overlap expensive components.** Handy begins model and VAD work
   at press time; Wispr exposes a warm-up API and streams cloud audio. Local
   model residency and early audio-frame processing are directly transferable.
5. **Choose preview semantics deliberately.** Neither reference product shows
   a live raw transcript and then visibly replaces it with a heavily
   restructured final transcript. Wispr avoids the discontinuity by showing no
   text; Handy labels recognition uncertainty and preserves the ASR preview
   through a Processing phase, then inserts the processed result elsewhere.
   If FoldWise exposes text, it should distinguish stable from revisable ASR
   and clearly signal the polish transition rather than imply that preview text
   is the final document.

What is not directly transferable is Wispr's exact cloud model stack and its
claimed component budgets: model identities, consumer endpoints, formatter
streaming behavior, and production latency distributions are not public.
FoldWise should benchmark its own press-to-capture, release-to-ASR-final,
polish, and paste segments rather than treating marketing examples or isolated
user logs as an end-to-end baseline.
