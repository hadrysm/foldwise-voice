# foldwise-voice

A local, private, personal-use dictation app for macOS — a lightweight
[superwhisper](https://superwhisper.com/) clone. Hold a global hotkey, speak,
release: your speech is transcribed **on-device** and pasted into whatever app
is focused. Optionally, a local LLM served by **Ollama** cleans up or reshapes
the transcript first ("modes").

Nothing ever leaves your machine.

Native Swift app: **Parakeet TDT v3** on the Apple **Neural Engine** via
[FluidAudio](https://github.com/FluidInference/FluidAudio), SwiftUI HUD and
settings, tiny memory footprint. Requires an Apple Silicon Mac on macOS 14+.

## Install / run

```sh
python3 scripts/build_swift_app.py        # builds + installs "FoldWise Voice Native.app"
# or run it directly from the repo:
swift run -c release
```

- ASR is **Parakeet TDT v3** (25 European languages) running on the Neural
  Engine. The model (~600 MB) downloads once on first launch, then everything
  is offline.
- Permissions: grant **Microphone** on first dictation and add the app under
  *Privacy & Security → Accessibility* for auto-paste. If the hotkey doesn't
  fire, also add it under *Input Monitoring*.
- [Ollama](https://ollama.com) is only needed for LLM modes; dictation works
  without it. Install models from the app's Settings → Models pane, or
  `brew install ollama && ollama pull qwen2.5:3b`.

While running:

- **🎤 menu-bar icon** — mode switcher, Settings, Check for Updates, Quit.
  The icon turns **🔴 while listening** and shows a waveform while working.
- **Floating HUD** — a pill near the bottom of the screen showing
  "Listening…" with a live waveform, then "Transcribing…", then
  "Inserted ✓". Drag it anywhere — the position is remembered. Hover to
  reveal the ⚙ settings button.
- **Audio ducking** — Spotify / Apple Music pause and other audio mutes
  while you dictate; everything resumes when you stop. Toggle in Settings.
- **Settings** — pick/install Ollama models with speed & quality guidance,
  switch modes, record hotkeys, choose the HUD style. Every change saves
  straight to `modes.json`.

## How it works

```
🎤 audio ──▶ [ Stage 1: Parakeet ASR ] ──▶ raw text ──▶ [ Stage 2: Ollama LLM ] ──▶ clean text ──▶ ⌘V paste
                (always, on-device)                       (optional, per mode)
```

- **Stage 1 (ASR)** — Parakeet TDT v3 on the Neural Engine turns audio into
  text. Always runs, fully offline after the one-time model download.
- **Stage 2 (LLM)** — Ollama receives the *text* transcript (never audio) via
  its OpenAI-compatible API and rewrites it per the active mode's system
  prompt. Optional: modes with `"llm_model": null` skip it entirely.

## Modes (`modes.json`)

Edit `modes.json` (or use Settings) to configure hotkeys and modes. Ships with:

| Mode | LLM | What it does |
|---|---|---|
| Voice to Text | — | raw transcript, no LLM |
| Clean | qwen2.5:3b | fixes punctuation, removes filler words (um, uh…) |
| Email | qwen2.5:3b | rewrites dictation as a professional email body |
| Bullets | qwen2.5:3b | converts dictation into a bulleted list |

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
- `hud_style` — `classic` or `minimal` recording bar.

Per-mode fields:

- `llm_model` — Ollama model tag (`llama3.2:3b`, `qwen2.5:7b`, …) or `null`
  for raw transcription.
- `system_prompt` — instruction the LLM applies to your transcript.
- `vocab` — names/terms the LLM must preserve (e.g. product names).
- `asr_model` — kept for compatibility with older configs; the app always
  transcribes with Parakeet and ignores it.

Add a mode by copying an existing block under `"modes"` and restarting.

`modes.json` is git-ignored and generated on first run — it holds local machine
state (HUD position, hotkey, model picks), so it won't appear in a fresh clone.

Transcripts shorter than ~40 characters skip the LLM to keep short
dictations snappy.

## Distribute as a .dmg

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

Gatekeeper: by default the app is only ad-hoc signed, so on first launch a
downloaded copy shows *"Apple could not verify … is free of malware"* with
only **Done** / **Move to Bin** buttons (macOS 15 removed the right-click →
*Open* bypass). To open it anyway: click **Done**, then go to **System
Settings → Privacy & Security**, scroll down, and click **Open Anyway** —
needed once only. Alternatively, clear the quarantine flag:
`xattr -dr com.apple.quarantine "/Applications/FoldWise Voice.app"`.
These steps are also printed on the .dmg background. For a frictionless
install you need an Apple Developer Program membership ($99/yr): set
`CODESIGN_IDENTITY="Developer ID Application: …"` when building, then
notarize the .dmg (`xcrun notarytool submit --wait`) and staple it
(`xcrun stapler staple`).

## Development

The repo is a standard Swift package: `Package.swift` at the root, app code
in `Sources/FoldWiseVoiceKit` (a library, so it's testable), a thin
`Sources/FoldWiseVoice` executable, and tests in
`Tests/FoldWiseVoiceKitTests`.

```sh
swift build              # debug build
swift test               # run the test suite
swift run -c release     # run the app from the repo
swiftformat .            # format (Prettier equivalent)
swiftlint                # lint (ESLint equivalent)
```

Install the tools with `brew install swiftformat swiftlint`, then enable the
pre-commit hook (formats and lints staged Swift files, like lint-staged):

```sh
git config core.hooksPath .githooks
```

CI runs `swiftformat --lint`, `swiftlint --strict`, and `swift test` on every
pull request (`.github/workflows/ci.yml`). Releases are automated with
release-please: conventional-commit messages on `main` drive the version, and
each release gets a .dmg built and attached automatically
(`.github/workflows/release-please.yml`).

> Maintainer note: for the `lint` and `test` checks to gate merges, enable
> branch protection on `main` (GitHub → Settings → Branches → require status
> checks) once the first PR has run.

## Troubleshooting / known limitations

- **Ollama not running / model not pulled** → the app logs a warning and
  pastes the raw transcript. Dictation never breaks.
- **Nothing pastes** → Accessibility isn't granted; the transcript is on the
  clipboard. Grant Accessibility and restart.
- **Hotkey doesn't fire** → grant Input Monitoring (and Accessibility),
  restart the app. After app updates the grant can go stale: remove and
  re-add the app in System Settings.
- Clipboard is saved and restored around the paste, but apps with clipboard
  managers may still see the transcript.
- Push-to-talk uses a plain key (right Option by default) — holding it while
  typing other keys may trigger app shortcuts. Pick a dedicated key like
  `f19` if that bothers you (Settings → Keyboard Shortcuts).
- Model changes in Settings apply to all LLM modes at once; per-mode models
  can still be set by editing `modes.json` directly.
- The locally installed bundle points at this repo's `modes.json` — deleting
  or moving the repo breaks it (re-run `scripts/build_swift_app.py` after
  moving). The .dmg build has no such dependency.
