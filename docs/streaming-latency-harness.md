# Streaming latency release gate

The issue #358 harness turns the locked perceived-latency budget (issue #342)
into a permanent fixed-Mac Release gate for the streaming shape shipped by
[SPEC #351](https://github.com/hadrysm/foldwise-voice/issues/351).

Three limits are absolute, and they live in `StreamingLatencyGate` rather than in
any file a run can edit:

| Measured interval | Fixture | Limit |
|---|---|---|
| Speech onset → first non-empty Live transcript caption render | either | **1200 ms p95** per Streaming ASR model |
| Hotkey release → completed insert effect | Short, all three shapes | **1000 ms p95** per class |
| Hotkey release → completed insert effect | Long, Voice to Text | **1500 ms p95** |

Long In-place and Expanding are measured and retained but **never gated**:
long-form Polish generation is explicitly out of this SPEC's budget. The report
records `postReleaseLimitMilliseconds: null` for those two classes, and the gate
re-derives that fact from the class rather than trusting the report.

## Measurement origins and endpoints

- **Speech onset** is the instant the fixture's first sample at or above 0.005
  was captured — a property of the audio, computed from the first voiced sample
  index, not of a 100 ms chunk boundary. It is recorded per fixture as
  `speechOnsetSeconds`.
- **First visible feedback** ends at the caption's own AppKit draw. The marker is
  a one-point view inside `LiveTranscriptCaptionView`'s tree, the same mechanism
  the pane harness uses for first-meaningful-frame. It is present only when
  `LiveTranscriptCaptionModel.onRender` is set, so the shipping app's view tree
  is unchanged. A sample that reports a first-feedback time without
  `captionRendered: true` fails the run.
- **Hotkey release** is read immediately before `Pipeline.stopRecording()`.
- **Completed insert effect** is the insertion stub returning, **plus** the
  separately measured Accessibility paste constant. The automated matrix
  deliberately stubs insertion — a synthetic ⌘V would paste into whatever app is
  frontmost — so the permission-bound constant is measured once by hand and
  passed in with `--insert-constant-milliseconds`. Every sample records both
  `stubbedPostReleaseMilliseconds` and the gated
  `postReleaseMilliseconds = stubbed + constant`. A constant below the
  unconditional 50 ms clipboard settle is rejected: it proves Accessibility was
  never exercised.

The harness drives the real packaged Release `Pipeline`, the real resident
Effective ASR model, the real Ollama Polish path, the real `BadgeController`, and
the real Live transcript caption. It replaces only the microphone (a private WAV
played at capture pace through the production `CaptureSampleBuffer`), audio
ducking (a no-op), and insertion (the stub above). It exists only in builds
compiled with `STREAMING_LATENCY_HARNESS`.

## Capture the private fixtures

Keep the recordings under `.context/`, which is gitignored because the fixtures
contain the tester's voice. Both Streaming ASR models are English-only, so these
fixtures are English and both clear the 40-character Polish floor:

| Fixture | Script | Aim |
|---|---|---|
| Short | `Tomorrow at eight I will send Anna a short summary of our conversation.` | ~5 s |
| Long | `Tomorrow at eight I will send Anna a summary of our conversation, then a list of decisions, the important dates, who owns what, the plan for this week, and three goals for each morning.` | ~17 s |

List capture devices and note the audio device index:

```sh
ffmpeg -f avfoundation -list_devices true -i ""
```

Record each fixture as 16 kHz mono PCM WAV, replacing `<audio-index>`, and press
`q` after speaking:

```sh
mkdir -p .context/streaming-latency-fixtures
ffmpeg -f avfoundation -i ":<audio-index>" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  .context/streaming-latency-fixtures/short.wav
ffmpeg -f avfoundation -i ":<audio-index>" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  .context/streaming-latency-fixtures/long.wav
```

Re-record clipped, truncated, or noisy takes; do not publish either WAV. Once a
baseline is accepted the fixture hashes are pinned in
[`streaming-latency-baselines.json`](streaming-latency-baselines.json), and a
later run with different audio fails as fixture drift rather than quietly
measuring something else.

## Measure the Accessibility insert constant

Do this first, against an installed app built from the same commit:

1. `python3 scripts/build_swift_app.py`.
2. Confirm FoldWise Voice Native is enabled in System Settings → Privacy &
   Security → Accessibility.
3. Open a disposable TextEdit document and keep it focused.
4. Complete five Dictation sessions and verify every one actually pastes.
5. Read the five `insertMilliseconds` values out of History and take their p95:

```sh
tail -n 5 "$HOME/Library/Application Support/FoldWise Voice/history.jsonl" \
  > .context/streaming-latency-insert.jsonl
python3 scripts/report_dictation_performance.py \
  .context/streaming-latency-insert.jsonl \
  --output .context/streaming-latency-insert-report.json
```

Any value below 50 ms proves Accessibility was not exercised. Retain the five
raw samples beside the run and pass the p95 as the insert constant.

## Run

One packaged Release process per Streaming ASR model, so each model's integrated
peak footprint and maximum RSS belong to that model alone:

```sh
python3 scripts/run_streaming_latency.py \
  --short-audio .context/streaming-latency-fixtures/short.wav \
  --long-audio .context/streaming-latency-fixtures/long.wav \
  --insert-constant-milliseconds 62.5 \
  --memory-ceiling-reviewed
```

For a smoke run while changing the harness:

```sh
python3 scripts/run_streaming_latency.py \
  --short-audio .context/streaming-latency-fixtures/short.wav \
  --long-audio .context/streaming-latency-fixtures/long.wav \
  --insert-constant-milliseconds 62.5 \
  --samples 1 --models parakeet-eou-320 \
  --output-directory .context/streaming-latency-smoke
```

A smoke run is deliberately non-authoritative: the gate does not ask it for
matrix completeness or 20 samples, and it can never update the accepted
baseline. `--no-build` reuses the existing packaged app and is safe only when
that bundle was built from the revision being measured. `--skip-xctest` runs the
Python launcher without the independent Swift re-check.

Run the flag-specific harness tests explicitly after changing the harness:

```sh
swift test -Xswiftc -DSTREAMING_LATENCY_HARNESS \
  --filter 'StreamingLatencyHarnessBuildTests|StreamingLatencyHarnessTests'
```

## What fails an authoritative run

The Swift gate is the only judge, and the lane runs it twice: once through the
Python launcher and once independently against the retained artifact.

- Either shipped Streaming ASR model over 1200 ms first-feedback p95.
- Any gated class over its 1000 ms or 1500 ms post-release p95.
- A missing matrix class, or a class without exactly 20 recorded samples.
- **Authority**: a healthy streaming session that ran any batch transcription;
  Pipeline and History disagreeing on the raw final; anything other than exactly
  one insertion; a Voice to Text session whose inserted text is not the raw
  final; a first-feedback time claimed without a caption render.
- **Evidence**: a sample without caption-render timing or without finish timing;
  a fixture with no hash or no duration.
- **Environment**: a Mac that is not the documented reference, a non-Release
  configuration, an attached debugger, coverage instrumentation, sanitizers, or
  any unrecorded environment fact (commit, app version, hardware model, chip,
  memory, macOS, Xcode, power, thermal).
- **Residency**: anything other than exactly one resident ASR engine, a missing
  peak footprint or maximum RSS, or a memory-ceiling comparison against a number
  other than the documented standalone observation.
- **Fixture drift** from an accepted hash.

An unreviewed memory ceiling does not fail the duration gate — the ceiling is a
human judgment and the limits are not — but it blocks baseline acceptance.

## Reference Mac and the release lane

The supported lane is the repository's dedicated `foldwise-streaming-reference`
Apple-silicon runner. Do not substitute a hosted runner or another Mac when
accepting a baseline: hosted timing is a broad regression signal only. The
`streaming-latency` job in `release-validation.yml` runs for release-please pull
requests and manual release validation, retains the report, raw per-model
samples, plans, and app output for 90 days, and does not retry a failure. A
rerun is evidence for a changed implementation, not a way to discard a bad
sample.

Ordinary PR CI runs the deterministic checks everywhere: the full XCTest suite
including `StreamingLatencyGateTests`, the Python policy tests, the formatter,
the strict linter, and the coverage gate. Those never claim that hosted Debug
timing enforces the Release budget.

## Single-model residency

Each per-model process reports the kernel's own high-water marks —
`ledger_phys_footprint_peak` and `resident_size_peak` — read once at the end of
the run rather than polled, so no sampling gap can understate the peak. It also
reports how many ASR engines were resident, which must be exactly one
(ADR-0005). There is no two-resident-model budget and the harness must not be
changed to produce one.

Nemotron 560's integrated numbers are compared against the **1.227 GB** standalone
maximum RSS recorded in
[`docs/research/streaming-asr-path-evaluation.md`](research/streaming-asr-path-evaluation.md)
(1 227 000 000 bytes, the decimal-GB figure that artifact used). The comparison
appears in every report and a maintainer must review it — passing
`--memory-ceiling-reviewed` is that record — before the run may become a
baseline.

## Accepting a baseline

1. Run the lane from a clean source commit under stable AC power and thermal
   conditions on the reference Mac.
2. Confirm the report is `authoritative: true`, `permitsBaselineUpdate` holds,
   and the artifact belongs to that exact commit.
3. Review the Nemotron memory comparison and the recorded long-form Polish
   evidence. Investigate rather than retry any violation.
4. Complete the manual acceptance matrix in
   [`docs/manual-verification`](manual-verification): packaged app, real
   microphone, real EOU and Nemotron downloads, ASR switching both ways, Voice to
   Text and Polish, long dictation, live rewrites, stream recovery, overlapping
   sessions, input-route changes, Accessibility insertion, Reduce Motion,
   VoiceOver, Badge dragging and edge clamping, and another app kept frontmost.
5. Update `docs/streaming-latency-baselines.json` from the accepted run only:
   set `acceptedRun` to its commit and pin both fixture hashes. The three
   duration limits are not baseline values and are never relaxed here.
