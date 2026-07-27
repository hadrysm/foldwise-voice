# Dictation session performance

Every completed Dictation session records processing timings in its
`HistoryEntry.timing` object. Existing history lines remain valid: entries
written before timing instrumentation simply omit that object.

The timings begin when the user stops speaking and end when the insert effect
completes:

| Field | Meaning |
|---|---|
| `totalMilliseconds` | Stop request to completed insert, including queueing |
| `queuedMilliseconds` | Time waiting behind an earlier Dictation session |
| `transcribeMilliseconds` | Effective ASR model transcription |
| `polishMilliseconds` | App-observed Polish request wall time; absent when Polish is skipped |
| `polishServerMilliseconds` | Ollama's server-observed total request time |
| `polishModelLoadMilliseconds` | Ollama model load reported by native `/api/chat` |
| `polishPromptEvalMilliseconds` | Ollama prompt evaluation |
| `polishGenerationMilliseconds` | Ollama token generation |
| `insertMilliseconds` | Clipboard and paste effect |
| `serialTailMilliseconds` | Frontmost-app lookup plus insert, after Polish finishes or is skipped |

Voice to Text uses the same measurement path. Its Polish and Ollama-owned
fields are absent, making it the reference floor for transcription and the
serial tail.

## Percentile report

Run the report against the live history file:

```sh
python3 scripts/report_dictation_performance.py
```

Pass another JSONL path for an isolated fixture, or retain a machine-readable
artifact:

```sh
python3 scripts/report_dictation_performance.py /path/to/history.jsonl \
  --output /path/to/dictation-performance.json
```

The report keeps every raw sample and calculates median, observed p95, and
worst values for all measured sessions, Voice to Text, and sessions where
Polish ran. Legacy and malformed lines are counted under `skippedSessions`.

## Live log

Completed sessions also emit a content-free public log line, including when
history saving is disabled:

```sh
log stream --info \
  --predicate 'subsystem == "com.foldwise.voice.native" AND category == "dictation-performance"'
```

The log contains timings and whether Polish ran; it never contains transcript
or polished text.
