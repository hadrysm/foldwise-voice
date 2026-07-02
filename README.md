# foldwise-voice

A local, private, personal-use dictation app for macOS — a lightweight
[superwhisper](https://superwhisper.com/) clone. Hold a global hotkey, speak,
release: your speech is transcribed **on-device** and pasted into whatever app
is focused. Optionally, a local LLM served by **Ollama** cleans up or reshapes
the transcript first ("modes").

Nothing ever leaves your machine.

Two implementations live in this repo and share one `modes.json`:

- **Native Swift app** (`swift/`, recommended) — Parakeet TDT v3 on the
  Apple **Neural Engine** via [FluidAudio](https://github.com/FluidInference/FluidAudio)
  (~10× faster transcription than Whisper-large on MLX), SwiftUI HUD and
  settings, tiny memory footprint. See [Native app](#native-swift-app-recommended).
- **Python app** (`foldwise_voice/`) — the original mlx-whisper implementation,
  documented below.

## Native Swift app (recommended)

```sh
python3 scripts/build_swift_app.py        # builds + installs "FoldWise Voice Native.app"
# or run it directly from the repo:
cd swift && swift run -c release
```

- ASR is **Parakeet TDT v3** (25 European languages) running on the Neural
  Engine — the `asr_model` field in `modes.json` is ignored by the native
  app. The model (~600 MB) downloads once on first launch, then everything
  is offline. Ollama modes work exactly as in the Python app.
- Same hotkeys, modes, HUD behavior, and `modes.json` as the Python app;
  per-mode `vocab` biases only the LLM stage (Parakeet has no prompt biasing).
- Permissions: grant **Microphone** on first dictation and add the app under
  *Privacy & Security → Accessibility* for auto-paste. If the hotkey doesn't
  fire, also add it under *Input Monitoring*.

### Distribute as a .dmg

```sh
python3 scripts/build_swift_app.py --dmg   # → dist/FoldWise-Voice-<version>.dmg
```

This builds a self-contained **FoldWise Voice.app** in a drag-to-Applications
disk image. Unlike the locally installed bundle, it has no repo paths baked
in: on first launch the app creates its own `modes.json` in
`~/Library/Application Support/FoldWise Voice/`, so it works on any Apple
Silicon Mac running macOS 14+. Recipients still install Ollama themselves if
they want LLM modes; plain dictation needs nothing else.

Every GitHub release also gets a .dmg attached automatically by CI, and the
installed app checks that releases feed once a day: when a newer version
exists, an "Update Available" item appears in the menu-bar menu linking to
the download page. This is the app's one exception to "nothing leaves your
machine" — a single anonymous HTTPS request to api.github.com that carries
no audio, text, or personal data.

Gatekeeper: by default the app is only ad-hoc signed, so a downloaded copy
shows "cannot verify the developer" — recipients bypass it once with
right-click → *Open* (or `xattr -dr com.apple.quarantine
"/Applications/FoldWise Voice.app"`). For a frictionless install you need an
Apple Developer Program membership: set
`CODESIGN_IDENTITY="Developer ID Application: …"` when building, then
notarize the .dmg (`xcrun notarytool submit --wait`) and staple it
(`xcrun stapler staple`).

## How it works

```
🎤 audio ──▶ [ Stage 1: mlx-whisper ASR ] ──▶ raw text ──▶ [ Stage 2: Ollama LLM ] ──▶ clean text ──▶ ⌘V paste
                     (always, offline)                        (optional, per mode)
```

- **Stage 1 (ASR)** — `mlx-whisper` (Apple Silicon) turns audio into text.
  Always runs, fully offline after a one-time model download.
- **Stage 2 (LLM)** — Ollama receives the *text* transcript (never audio) via
  its OpenAI-compatible API and rewrites it per the active mode's system
  prompt. Optional: modes with `"llm_model": null` skip it entirely.

> Note: Ollama serves text LLMs only — it cannot transcribe audio. ASR is a
> separate engine.

## Prerequisites

- Apple Silicon Mac (mlx-whisper requires it)
- Python 3.11+
- [Ollama](https://ollama.com) — only needed for LLM modes; dictation works
  without it

## Install

```sh
python3 -m venv .venv            # or: uv venv --python 3.12 .venv
.venv/bin/pip install -r requirements.txt   # or: uv pip install -r requirements.txt

# For LLM modes (optional):
brew install ollama
ollama serve &                   # or run the Ollama.app
ollama pull llama3.2:3b
```

## macOS permissions

Run the app from a terminal; **the terminal app is what holds the
permissions**, not "Python."

1. **Microphone** — macOS prompts automatically on first recording. Accept it.
2. **Accessibility** — required to auto-paste (synthetic ⌘V) into other apps:
   *System Settings → Privacy & Security → Accessibility → enable your
   terminal app.* Without it, the app still works but leaves the transcript on
   the clipboard for you to paste manually.
3. **Input Monitoring** — usually **not** required. Only if the hotkey doesn't
   fire: *System Settings → Privacy & Security → Input Monitoring → enable
   your terminal app.*

After granting a permission, restart the app (and sometimes the terminal).

## Run as a Mac app (recommended)

Build and install the app bundle once:

```sh
.venv/bin/python scripts/build_app.py
```

This creates **FoldWise Voice.app** in `/Applications` — launch it from
Launchpad/Spotlight like any app. It's a menu-bar app (🎤 icon, no Dock icon)
that wraps this repo's code, so the app and the terminal version share the
same `modes.json`. Re-run the script if you move the repo.

While running:

- **🎤 menu-bar icon** — click for the mode switcher, Settings, and Quit.
  The icon turns **🔴 while listening** and **⏳ while transcribing**.
- **Floating HUD** — a tiny pill near the bottom of the screen that expands
  to show "Listening…" with a live waveform while you hold the hotkey, then
  "Transcribing…", then "Inserted ✓". Drag it anywhere — the position is
  remembered. Hover over it to reveal a ⚙ button that opens Settings.
- **Audio ducking** — while you dictate, Spotify / Apple Music are paused
  and other system audio is muted; everything resumes when you stop.
  Toggle with *Pause music & mute other audio while dictating* in Settings.
- **Settings…** — switch the Ollama model (dropdown lists your installed
  models), switch the active mode, and edit both hotkeys (click *Record…*
  and press the key you want). Shows Accessibility status with a shortcut
  to the right System Settings pane. Changes are saved to `modes.json`
  and applied immediately. Open it from the menu-bar icon or by hovering
  over the HUD and clicking ⚙.

Because the .app is its own permission identity, grant it **Microphone**
(prompted on first dictation) and **Accessibility** (add *FoldWise Voice* in
System Settings → Privacy & Security → Accessibility) separately from your
terminal.

## Run from the terminal

```sh
.venv/bin/python -m foldwise_voice          # headless
.venv/bin/python -m foldwise_voice --ui     # with menu-bar UI + HUD
```

- **Hold right Option (⌥)**, speak, release → transcript is pasted into the
  focused app.
- First run downloads the Whisper model (~1.6 GB) from Hugging Face — one
  time; everything is offline afterwards. The first transcription also warms
  up the model, so it's slower than the rest.

Options:

```sh
.venv/bin/python -m foldwise_voice --mode "Voice to Text"  # override active mode
.venv/bin/python -m foldwise_voice --config path/to/modes.json
.venv/bin/python -m foldwise_voice -v                      # debug logging
```

## Modes (`modes.json`)

Edit `modes.json` to configure hotkeys and modes. Ships with:

| Mode | LLM | What it does |
|---|---|---|
| Voice to Text | — | raw Whisper transcript, no LLM |
| Clean | llama3.2:3b | fixes punctuation, removes filler words (um, uh…) |
| Email | llama3.2:3b | rewrites dictation as a professional email body |
| Bullets | llama3.2:3b | converts dictation into a bulleted list |

Top-level settings:

- `active_mode` — mode used at startup (or pass `--mode`).
- `hotkey` — push-to-talk key, held while speaking. Default `alt_r` (right
  Option). Any [pynput key name](https://pynput.readthedocs.io/en/latest/keyboard.html#pynput.keyboard.Key)
  (`cmd_r`, `f19`, `ctrl_r`, …) or a single character.
- `toggle_hotkey` — optional tap-to-start / tap-to-stop key (e.g. `"f19"`).
  `null` disables it.
- `pause_audio` — pause Spotify / Apple Music and mute other output while
  dictating (default `true`).
- `hud_position` — saved HUD anchor (`[center_x, bottom_y]` in screen
  points); written automatically when you drag the pill. `null` = default
  bottom-center.

Per-mode fields:

- `asr_model` — Whisper model repo. Default
  `mlx-community/whisper-large-v3-turbo`.
- `llm_model` — Ollama model tag (`llama3.2:3b`, `qwen2.5:7b`, …) or `null`
  for raw transcription.
- `system_prompt` — instruction the LLM applies to your transcript.
- `vocab` — names/terms to recognize correctly (e.g. product names). Biases
  Whisper recognition and tells the LLM to preserve them.

Add a mode by copying an existing block under `"modes"` and restarting.

Transcripts shorter than ~40 characters skip the LLM to keep short
dictations snappy.

## Troubleshooting / known limitations

- **Ollama not running / model not pulled** → the app logs a warning and
  pastes the raw transcript. Dictation never breaks.
- **Nothing pastes** → Accessibility isn't granted; the transcript is on the
  clipboard. Grant Accessibility and restart.
- **Hotkey doesn't fire** → grant Input Monitoring to your terminal, restart.
- **No audio captured** → check the Microphone permission and input device
  (`python -c "import sounddevice; print(sounddevice.query_devices())"`).
- Clipboard is saved and restored around the paste, but apps with clipboard
  managers may still see the transcript.
- Push-to-talk uses a plain key (right Option by default) — holding it while
  typing other keys may trigger app shortcuts. Pick a dedicated key like
  `f19` if that bothers you (Settings → *Record…*).
- The .app bundle is a launcher for this repo's venv — deleting or moving the
  repo breaks it (re-run `scripts/build_app.py` after moving).
- Model changes in Settings apply to all LLM modes at once; per-mode models
  can still be set by editing `modes.json` directly.
