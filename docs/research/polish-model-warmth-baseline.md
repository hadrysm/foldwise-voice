# Polish model warmth baseline

Measured on 2026-07-27 to verify the model-residency policy from issue
[#341](https://github.com/hadrysm/foldwise-voice/issues/341).

## Contract

When a Dictation session starts, FoldWise schedules an empty, non-streaming
request to Ollama's native `/api/chat` endpoint for the model captured in that
session's `Mode`. The request uses `keep_alive: "10m"` and has no messages, so
it loads the model without generating output. Voice to Text sessions do not
warm a model.

Ollama documents empty native chat requests as a way to preload a model and
duration strings as valid `keep_alive` values in its
[FAQ](https://docs.ollama.com/faq#how-can-i-preload-a-model-into-ollama-to-get-faster-response-times).

## Environment

- Ollama 0.32.4
- `qwen2.5:3b` (`Q4_K_M`, 2.2 GB resident allocation)
- MacBook Pro with Apple M1 Pro, 10 CPU cores, 16 GB memory
- macOS 26.5
- Native Ollama chat API on localhost

## Method

1. Unload the model with an empty request using `keep_alive: 0`.
2. Send a representative non-streaming Polish request and record the native
   Ollama timing fields from its response.
3. Send the empty warm-up request using `keep_alive: "10m"`.
4. Repeat the same representative Polish request and record its timing fields.
5. Confirm residency with `ollama ps`.

The empty warm-up response reported `done_reason: "load"` and no timing fields
on this Ollama version. The following real request is therefore the measured
proof of the warm state.

## Results

| State | Model load | Prompt evaluation | Generation | Total |
| --- | ---: | ---: | ---: | ---: |
| Cold | 952.705 ms | 80.763 ms | 117.653 ms | 1152.898 ms |
| Warm | 129.919 ms | 89.299 ms | 120.574 ms | 341.650 ms |

Warm-up reduced model-load duration by 822.786 ms (86.4%) and total request
duration by 811.248 ms (70.4%). After the request, `ollama ps` showed
`qwen2.5:3b` resident with approximately nine minutes remaining.

The policy trades a bounded 2.2 GB resident allocation for avoiding most of the
load delay during Dictation. Failures remain silent to the user and do not
change the existing raw-transcript fallback.
