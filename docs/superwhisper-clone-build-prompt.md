# Build Prompt — Local Superwhisper Clone (macOS + Ollama)

> **How to use this file.** This is a complete, self-contained task specification meant to be handed to a Claude Code coding agent (e.g. Fable). Point the agent at this repo and this file, or paste it as your opening prompt. Everything the agent needs to build a working app is here. Background/justification lives in [`superwhisper-clone-research-and-plan.md`](./superwhisper-clone-research-and-plan.md) — read it for the "why," but this file is the "what to build."

---

## Your task

Build me a **local, private, personal-use dictation app for macOS** — a lightweight clone of [superwhisper](https://superwhisper.com/). I press a global hotkey, speak, release, and my speech is transcribed **on-device** and inserted into whatever app is focused. Optionally, a local LLM served by **Ollama** cleans up / reshapes the transcript first ("modes"), exactly like superwhisper's "Super Mode."

Build it in **Python**, make it actually run, and hand me a README. Work incrementally through the milestones in the order below, verifying each one works before moving on. Assume **Apple Silicon macOS**.

---

## ⚠️ Non-negotiable architecture constraint: Ollama ≠ Whisper

**Ollama serves text LLMs. It CANNOT do speech-to-text.** Do not try to transcribe audio with Ollama. Do not run `ollama pull whisper` or use any "whisper" tag on ollama.com — those are non-functional placeholders.

The app is a **two-stage pipeline** with two different engines:

```
🎤 audio ──▶ [ Stage 1: ASR engine ] ──▶ raw text ──▶ [ Stage 2: Ollama LLM ] ──▶ clean text ──▶ paste
              (mlx-whisper / whisper.cpp)   (always)      (localhost:11434, OPTIONAL)   (optional)
```

- **Stage 1 (ASR)** is a dedicated Whisper engine (`mlx-whisper`) that turns audio → text. This always runs.
- **Stage 2 (LLM)** is **Ollama**, which only ever receives **already-transcribed text** and returns rewritten text. This is **optional** and per-mode. Ollama is reached via its **OpenAI-compatible endpoint** `POST http://localhost:11434/v1/chat/completions`.
- A mode with no LLM = superwhisper's "Voice to Text" (raw ASR). A mode with an LLM = "Super Mode."

If you internalize nothing else from this spec, internalize this boundary.

---

## Tech stack (use exactly these unless a dependency genuinely won't install)

| Concern | Use | Notes |
|---|---|---|
| Language | Python 3.11+ | virtualenv/venv |
| Audio capture | `sounddevice` + `numpy` | 16 kHz, mono, float32 (Whisper-native) |
| ASR (Stage 1) | `mlx-whisper` | Apple Silicon, fast. Model `mlx-community/whisper-large-v3-turbo`. Fallback: `pywhispercpp` or `faster-whisper` if MLX won't install. |
| Global hotkey | `pynput` | keyboard listener, push-to-talk |
| LLM (Stage 2) | **Ollama** via `requests` to `/v1/chat/completions` | Default model `llama3.2:3b`. Keep the HTTP call explicit. |
| Clipboard | `pyperclip` | for the paste-based insertion |
| Text insertion | `pynput` synthetic ⌘V | after copying to clipboard |
| Menu-bar UI (last) | `rumps` | optional Phase 5; app must work headless first |
| Config | a `modes.json` file | see F6 |

Pin nothing exotic. Keep dependencies minimal.

---

## Project structure to create

Create a small, clean package (adjust names sensibly if the repo already has conventions):

```
foldwise_voice/
  __init__.py
  __main__.py          # entrypoint: `python -m foldwise_voice`
  config.py            # load/validate modes.json, app settings
  audio.py             # AudioRecorder: start/stop, 16kHz mono capture
  asr.py               # transcribe(audio) -> str  (mlx-whisper)
  llm.py               # polish(text, mode) -> str (Ollama, optional)
  insert.py            # insert_text(text): clipboard + synthetic ⌘V, permission-gated
  hotkey.py            # global hotkey listener (push-to-talk + toggle)
  pipeline.py          # wires the stages: record -> asr -> (llm?) -> insert
  app.py               # orchestration / (later) rumps menu bar
modes.json             # user-editable modes config
requirements.txt
README.md
```

---

## Functional requirements

**F1 — Global hotkey.** Register a system-wide **push-to-talk** hotkey (default: hold **right Option**). Holding it starts recording; releasing it stops and triggers transcription. Also support a **toggle** hotkey (tap to start, tap to stop) as an alternative. Hotkeys must fire even when the app is unfocused. Make the keys configurable.

**F2 — Audio capture.** On hotkey-down, capture microphone audio at **16 kHz, mono, float32** via `sounddevice`. Buffer frames; on hotkey-up, assemble them into a single numpy array. **Never block the audio callback** — do transcription on a worker thread.

**F3 — ASR (Stage 1).** Transcribe the captured audio with `mlx-whisper` (`mlx-community/whisper-large-v3-turbo` by default; make the model configurable per mode). Return trimmed text. This always runs and is fully offline (model auto-downloads once from Hugging Face, then works with no network).

**F4 — Modes + Ollama (Stage 2, optional).** After ASR, if the active mode specifies an `llm_model`, POST the raw transcript to Ollama's `/v1/chat/completions` with the mode's `system_prompt`, and use the returned text instead. If `llm_model` is null, skip this entirely (raw "Voice to Text"). Only invoke the LLM when the transcript is longer than ~40 characters (skip cleanup on very short utterances to keep latency low).

**F5 — Text insertion.** Insert the final text into the focused app by: copy to clipboard (`pyperclip`) → post a synthetic **⌘V** (`pynput`). Gate this on macOS **Accessibility** permission (`AXIsProcessTrusted` — detectable; if you can't call it from Python cleanly, attempt the paste and detect failure). If Accessibility isn't granted, **fall back to clipboard-only** and notify the user ("Transcript copied — paste manually. Grant Accessibility to auto-insert."). Optionally save & restore the user's previous clipboard contents.

**F6 — Modes config.** Read modes from a user-editable `modes.json`. Ship with these starter modes:

```json
{
  "active_mode": "Clean",
  "hotkey": "alt_r",
  "modes": {
    "Voice to Text": {
      "asr_model": "mlx-community/whisper-large-v3-turbo",
      "llm_model": null,
      "system_prompt": null,
      "vocab": []
    },
    "Clean": {
      "asr_model": "mlx-community/whisper-large-v3-turbo",
      "llm_model": "llama3.2:3b",
      "system_prompt": "You clean up dictated speech. Fix punctuation, capitalization, and obvious transcription errors. Remove filler words (um, uh, like, you know). Do NOT change meaning, add content, or answer questions. Output ONLY the cleaned text.",
      "vocab": ["FoldWise", "Ollama", "Anthropic"]
    },
    "Email": {
      "asr_model": "mlx-community/whisper-large-v3-turbo",
      "llm_model": "llama3.2:3b",
      "system_prompt": "Rewrite this dictation as a clear, concise, professional email body. Output only the email text.",
      "vocab": []
    },
    "Bullets": {
      "asr_model": "mlx-community/whisper-large-v3-turbo",
      "llm_model": "llama3.2:3b",
      "system_prompt": "Convert this dictation into a tight bulleted list, one idea per bullet. Output only the list.",
      "vocab": []
    }
  }
}
```

**Custom vocabulary:** apply `vocab` two ways — (a) pass it as the Whisper `initial_prompt` at the ASR stage to bias recognition, and (b) append it to the LLM system prompt ("Preserve these terms exactly, correcting misspellings toward them: …").

**F7 — Menu-bar UI (optional, do last).** A `rumps` menu-bar item showing a mic/status icon, the active mode, a mode switcher, and quit. The app must be fully functional headless before you add this.

---

## Build in this order (verify each milestone before continuing)

1. **Skeleton + config.** Package layout, `requirements.txt`, load `modes.json`. `python -m foldwise_voice` runs and prints the active mode. ✔ when it starts cleanly.
2. **Audio capture.** Record 3s on a keypress, save/inspect a WAV to confirm 16 kHz mono. ✔ when audio is captured correctly.
3. **ASR.** Feed captured audio to `mlx-whisper`, print the transcript. ✔ when speech → correct text, offline.
4. **Push-to-talk loop + insertion.** Hold hotkey → speak → release → **raw** transcript pasted into a focused text field (e.g. Notes/TextEdit). ✔ when it inserts into another app. **This is the usable MVP.**
5. **Ollama modes.** Add Stage 2. With mode "Clean," verify the pasted text is cleaned (filler removed, punctuation fixed). With "Voice to Text," verify the LLM is skipped. ✔ when both paths work.
6. **Modes + vocab + robustness.** Mode switching, custom vocab, graceful error handling (below). ✔.
7. **(Optional) rumps menu bar.** ✔ when mode switching works from the menu.

---

## Reference snippets for the tricky bits (pin these APIs; write the rest yourself)

```python
# --- asr.py : Stage 1. This is Whisper, NOT Ollama. ---
import mlx_whisper
def transcribe(audio_f32_16k_mono, model, vocab=None) -> str:
    prompt = ("Terms: " + ", ".join(vocab)) if vocab else None
    r = mlx_whisper.transcribe(audio_f32_16k_mono, path_or_hf_repo=model, initial_prompt=prompt)
    return r["text"].strip()
```

```python
# --- llm.py : Stage 2. Ollama only ever sees TEXT. ---
import requests
def polish(text, model, system_prompt, vocab=None, url="http://localhost:11434/v1/chat/completions") -> str:
    if vocab:
        system_prompt += "\nPreserve these terms exactly, correcting misspellings toward them: " + ", ".join(vocab)
    try:
        resp = requests.post(url, timeout=60, json={
            "model": model, "stream": False,
            "messages": [{"role": "system", "content": system_prompt},
                         {"role": "user",   "content": text}]})
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        # Ollama down / model missing → fall back to raw transcript, don't crash.
        print(f"[llm] falling back to raw transcript: {e}")
        return text
```

```python
# --- insert.py : clipboard + synthetic Cmd+V (needs Accessibility permission) ---
import pyperclip
from pynput.keyboard import Controller, Key
def insert_text(text):
    pyperclip.copy(text)
    kb = Controller()
    with kb.pressed(Key.cmd):
        kb.press('v'); kb.release('v')
    # If nothing pastes, Accessibility is likely not granted → tell the user, leave text on clipboard.
```

```python
# --- audio.py : 16 kHz mono capture with sounddevice ---
import sounddevice as sd, numpy as np, queue
class Recorder:
    def __init__(self): self.q = queue.Queue(); self.on = False
        # stream = sd.InputStream(samplerate=16000, channels=1, dtype="float32", callback=self._cb)
    def _cb(self, indata, *_):
        if self.on: self.q.put(indata.copy())
    def result(self):
        chunks = [self.q.get() for _ in range(self.q.qsize())]
        return np.concatenate(chunks).flatten().astype(np.float32) if chunks else np.zeros(0, np.float32)
```

---

## macOS permissions — handle explicitly

- **Microphone** — prompted automatically on first capture.
- **Accessibility** — required to post the synthetic ⌘V into other apps. Detect if it's missing and print clear guidance: *System Settings → Privacy & Security → Accessibility → enable the Terminal (or the bundled app) you're running this from.* Fall back to clipboard-only if absent.
- **Input Monitoring** — **may or may not** be required depending on the key-capture path. **Do NOT assume it's mandatory** (this was specifically confirmed false in research). If the global hotkey doesn't fire, then instruct the user to grant Input Monitoring — but test first.
- When run from a terminal via `pynput`, the **terminal app** is what holds the permissions, not "Python."

---

## Error-handling requirements (the app must never hard-crash on these)

- **Ollama not running / model not pulled** → log a warning, fall back to the raw transcript, keep working.
- **Accessibility not granted** → clipboard-only + a one-time notice.
- **No microphone / no audio captured** → skip transcription, log it.
- **ASR model still downloading (first run)** → inform the user it's a one-time download.
- **Empty transcript** → do nothing quietly.

---

## Acceptance criteria (how I'll judge "done")

1. `python -m foldwise_voice` starts and registers the global hotkey.
2. Holding the hotkey, speaking, and releasing inserts an accurate transcript into a **different** focused app (Notes/TextEdit/browser).
3. Works **fully offline** for the ASR path (airplane mode) after the one-time model download.
4. With mode **"Clean,"** the inserted text is cleaned by Ollama (filler removed, punctuation fixed). With **"Voice to Text,"** the LLM is bypassed.
5. Switching the active mode changes behavior.
6. Custom `vocab` terms are respected.
7. Killing Ollama does **not** break dictation — it falls back to raw text.
8. A `README.md` documents install, `ollama pull llama3.2:3b`, permission grants, running, and configuring modes.

---

## Do NOT do these

- ❌ Do **not** attempt speech-to-text through Ollama, or pull/reference any "whisper" model on Ollama. ASR is a separate engine (`mlx-whisper`).
- ❌ Do **not** send any audio off-device. Everything is local.
- ❌ Do **not** assume Input Monitoring permission is mandatory — request **Accessibility** (for insertion); test hotkeys before demanding more.
- ❌ Do **not** run transcription or the LLM call on the audio callback or the keyboard-listener thread — use a worker thread so capture/hotkeys stay responsive.
- ❌ Do **not** over-build the UI before the core pipeline works — headless MVP first, `rumps` last.

---

## Deliverables

1. The `foldwise_voice/` package implementing the pipeline through at least Milestone 5 (ideally 6).
2. `modes.json`, `requirements.txt`.
3. A `README.md`: prerequisites (Python, Ollama), setup commands, permission-granting steps, how to run, how to add/edit modes, and known limitations.
4. A short note in your final message on what you verified working vs. what needs real-hardware testing (mic/hotkey/paste can't be fully tested headlessly — say so honestly).

Start with Milestone 1 and work down, keeping the Ollama ≠ Whisper boundary intact throughout.
