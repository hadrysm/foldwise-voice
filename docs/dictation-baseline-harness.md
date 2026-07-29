# Dictation latency baseline harness

The issue #349 harness drives the real packaged Release `Pipeline` with the
real resident Effective ASR model and real Ollama Polish path. It replaces only
the microphone with private WAV fixtures, audio ducking with a no-op, and
insertion with a deterministic stub. The harness exists only in builds compiled
with `DICTATION_BASELINE_HARNESS`; normal development and production binaries
do not contain it.

## Capture the private fixtures

Keep the recordings under `.context/`. That directory is gitignored because
the fixtures contain the tester's voice.

These Polish scripts match the measured fixture classes and both clear the
40-character Polish floor:

| Fixture | Script | Raw characters | Words |
|---|---|---:|---:|
| Short | `Jutro o ósmej wyślę do Ani krótki opis naszej rozmowy.` | 54 | 10 |
| Long | `Jutro o ósmej wyślę do Ani opis naszej rozmowy, a potem dam listę ustaleń, ważne daty, role, plan na ten tydzień i trzy cele dla nas na każdy dzień rano.` | 153 | 30 |

List AVFoundation capture devices and note the audio device index:

```sh
ffmpeg -f avfoundation -list_devices true -i ""
```

Record each fixture as 16 kHz mono PCM WAV, replacing `<audio-index>`. Press
`q` after speaking:

```sh
mkdir -p .context/dictation-baseline-fixtures
ffmpeg -f avfoundation -i ":<audio-index>" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  .context/dictation-baseline-fixtures/short.wav
ffmpeg -f avfoundation -i ":<audio-index>" \
  -ar 16000 -ac 1 -c:a pcm_s16le \
  .context/dictation-baseline-fixtures/long.wav
```

Aim for roughly 5 seconds for Short and 17 seconds for Long. Re-record clipped,
truncated, or noisy takes; do not publish either WAV.

## Run

The authoritative run records 20 samples after one discarded warm-up for each
of the Short/Long × Voice to Text/In-place/Expanding classes:

```sh
python3 scripts/run_dictation_baseline.py \
  --short-audio .context/dictation-baseline-fixtures/short.wav \
  --short-transcript 'Jutro o ósmej wyślę do Ani krótki opis naszej rozmowy.' \
  --long-audio .context/dictation-baseline-fixtures/long.wav \
  --long-transcript 'Jutro o ósmej wyślę do Ani opis naszej rozmowy, a potem dam listę ustaleń, ważne daty, role, plan na ten tydzień i trzy cele dla nas na każdy dzień rano.'
```

Use `--samples 1` for a non-authoritative smoke run while changing the
harness. Use `--no-build` only when the existing baseline bundle was built from
the exact source revision being measured. Issue #345 can reuse the same matrix
with `--polish-model <candidate>`.

Run the flag-specific harness tests explicitly after changing its implementation:

```sh
swift test -Xswiftc -DDICTATION_BASELINE_HARNESS \
  --filter 'DictationBaselineHarnessBuildTests|DictationBaselineHarnessTests'
```

The evidence directory under `.context/` contains:

- the validated plan;
- every raw per-stage timing and median / observed p95 / worst by class;
- fixture duration, SHA-256, expected transcript, and all observed raw
  transcripts;
- packaged-app stdout and stderr; and
- an `authoritative` marker and any `authorityViolations`. Authoritative evidence
  uses the ticket's 20 samples, `whisper-small`, `qwen2.5:3b`, and documented
  Short/Long duration and transcript-size ranges.

The runner fails if either fixture is outside `.context/`, is not gitignored,
is not 16 kHz mono WAV, or has an expected transcript at or below the Polish
floor. The app fails rather than silently measuring a fallback ASR model or an
observed transcript at or below the Polish floor. Expected and observed text
remain separate in the evidence so ordinary ASR wording differences are visible.

## Measure the real insert constant

The automated matrix deliberately stubs insertion. Measure the permission-bound
constant separately against an installed app built from the same commit:

1. Build and install with `python3 scripts/build_swift_app.py`.
2. Confirm FoldWise Voice Native is enabled in System Settings → Privacy &
   Security → Accessibility.
3. Open a disposable TextEdit document and keep it focused.
4. Complete five Dictation sessions and verify every one actually pastes.
5. Copy the last five History lines into private evidence and report them:

```sh
tail -n 5 \
  "$HOME/Library/Application Support/FoldWise Voice/history.jsonl" \
  > .context/dictation-baseline-insert.jsonl
python3 scripts/report_dictation_performance.py \
  .context/dictation-baseline-insert.jsonl \
  --output .context/dictation-baseline-insert-report.json
```

Treat any `insertMilliseconds` value below the unconditional 50 ms paste delay
as proof that Accessibility was not actually exercised. Record the five raw
insert samples plus their median, observed p95, and worst in the ticket
resolution.
