# FoldWise Voice

FoldWise Voice is a private, local dictation app for Apple Silicon Macs. Hold a
global shortcut, speak, and release: the app transcribes your voice on-device
and inserts the text at your cursor. Optional **Modes** can send the transcript
to a local [Ollama](https://ollama.com/) model first to clean it up or reshape
it for a specific job.

Audio is never uploaded or saved. After their one-time downloads, speech
models run locally through
[FluidAudio](https://github.com/FluidInference/FluidAudio) or
[WhisperKit](https://github.com/argmaxinc/argmax-oss). Ollama receives text,
never audio, over localhost. The app's automatic update check is the only
routine external request: it checks GitHub release metadata without sending
audio, transcripts, or personal data.

FoldWise Voice requires an Apple Silicon Mac running macOS 14 or later.

## Install and start dictating

Download the latest `.dmg` from
[GitHub Releases](https://github.com/hadrysm/foldwise-voice/releases), open it,
and drag **FoldWise Voice** into Applications.

Release builds are currently ad-hoc signed. The first time you open one, macOS
may say that Apple could not verify it. Click **Done**, then open **System
Settings → Privacy & Security** and choose **Open Anyway**. This is required
only once for that installation.

On first launch:

1. Allow **Microphone** access so the app can record while you dictate.
2. Allow **Accessibility** so it can paste the result into other apps.
3. Allow **Input Monitoring** so shortcuts work while another app is focused.
   Accessibility also satisfies the global-shortcut requirement.
4. Wait for the default Parakeet TDT v3 speech model (about 600 MB) to finish
   downloading and loading.

FoldWise Voice is a menu-bar app and does not appear in the Dock. Put the cursor
where the text should go, hold **right Option**, speak, and release. The default
**Casual** Mode fixes punctuation, capitalization, obvious transcription
errors, and filler words when Ollama and its assigned model are available.
Choose **Voice to Text** from the menu-bar menu if you always want the raw
transcript.

Ollama is optional. Dictation and Voice to Text work without it. To use the
built-in Casual and Email Modes, install and start Ollama, then install their
default model from **Models → Polish (Ollama)** or from Terminal:

```sh
brew install ollama
ollama pull qwen2.5:3b
```

## How a Dictation session works

```text
record audio → transcribe on-device → optionally Polish with Ollama → insert with ⌘V
```

1. **Record** captures the selected input device only while a Dictation session
   is active. Audio is discarded after transcription.
2. **Transcribe** runs the globally selected Parakeet or Whisper speech model
   on the Mac.
3. **Polish** optionally sends the transcript text to the Mode's local Ollama
   model. Voice to Text and transcripts of 40 characters or fewer skip this
   stage.
4. **Insert** briefly places the result on the clipboard and sends ⌘V to the
   focused app, then restores the previous clipboard contents.

Dictation is designed to degrade safely. If Ollama is stopped, an assigned
model is missing, or a model produces an off-task response, FoldWise Voice uses
the raw transcript. If Accessibility is unavailable, the result remains on the
clipboard for manual pasting.

## Badge and menu bar

The always-on-top **Badge** shows the current state without taking focus away
from the app receiving the Dictation. It displays microphone activity and a
timer while recording, progress while transcribing or Polishing, and a brief
success or error result. Drag it to reposition it; the position is remembered.

Hover over the idle Badge to reveal controls for choosing the Dictation
selection, starting a Dictation, and opening the main window. The Badge also
confirms Mode-cycle changes.

The menu-bar microphone provides the same Dictation-selection menu plus
**Settings**, **Check for Updates**, and **Quit FoldWise Voice**. Its icon turns
red while listening and becomes an orange waveform while work is in progress.
If it is missing on a notched MacBook, make room by Command-dragging less
important menu-bar items away.

## App guide

Open **Settings** from the Badge or menu bar to access the six areas below. The
sidebar can collapse to an icon rail; use its titlebar button or `⌘\` to toggle
it. The explicit choice is remembered, while a narrow window may collapse it
temporarily.

### Home

Home is the at-a-glance view. It shows the configured Push to Talk shortcut,
recent Dictations, speech and Polish status, Accessibility status, and summary
figures for words, speaking speed, streak, and estimated time saved. Recent
rows can be copied or flagged, and the full list opens in History.

### Modes

A **Dictation selection** is either the permanent **Voice to Text** option or a
custom **Mode**. Voice to Text inserts the transcript without Polish and cannot
be edited or deleted.

Each custom Mode has a unique name, icon, Ollama model, transformation style,
Polish instructions, and preserved vocabulary. The transformation style can
keep the original wording closely or allow a broader rewrite. Modes can be
created, edited, duplicated, reordered, selected, and deleted. Stable IDs keep
the correct selection and History attribution when a Mode is renamed or moved.
Deleting a Mode does not delete its History or uninstall its Ollama model.

A fresh configuration includes **Casual** and **Email**, both assigned to
`qwen2.5:3b`, with Casual selected. The optional Mode-cycle shortcut follows
the displayed Mode order and wraps at the end.

### Models

The Models pane manages two independent local model libraries:

- **Speech recognition** selects one ASR model for every Dictation selection.
  Parakeet TDT v3 is the built-in default. Parakeet TDT v2 provides an
  English-only option; downloadable Whisper models extend coverage to about 99
  languages. Downloading does not select a model. If the stored selection is
  unavailable, FoldWise Voice attempts to use Parakeet TDT v3 without silently
  changing the saved choice. Deleting the selected optional model selects the
  default.
- **Polish (Ollama)** lists locally installed models, offers a curated library
  with size, speed, and quality guidance, and can install any Ollama model by
  name. Ollama models are assigned per Mode. Uninstalling a model leaves its
  Modes intact; those Modes use raw text until another available model is
  assigned.

Only one speech-model management operation runs at a time. Downloads and model
switches report progress, and optional speech models can be removed to recover
disk space.

### History

History stores a text-only, on-device record of Dictations. Saving is enabled
by default with a **30-day** retention window; choose 7 days, 30 days, 90 days,
or Forever, or turn saving off entirely. Turning saving off stops new entries
and offers to delete the entries already stored. No audio is saved.

History is grouped by date and supports live search across raw and Polished
text, a flagged-only filter, copying the inserted or raw text, re-running
Polish with a current Mode, deleting one entry, and clearing all History.

### Stats

Stats reports words dictated, speaking speed, active days, the current streak,
and a conservative time-saved estimate against a 52 WPM typing baseline. Most
figures are calculated from retained History, so deleting or pruning History
reduces them. The streak is stored separately so routine retention pruning does
not erase it, but clearing all History resets it. Turning History saving off
stops Stats from updating.

### Settings

Settings changes save immediately.

| Area | Control | Default and behavior |
|---|---|---|
| Keyboard shortcuts | Push to Talk | **right Option**; hold to record and release to finish |
| Keyboard shortcuts | Toggle Recording | Unassigned; one press starts and the next stops |
| Keyboard shortcuts | Cycle Modes | Unassigned; advances through custom Modes and wraps |
| Input | Input device | **System Default**; follows the current macOS input device |
| Sound | Pause other audio | **On**; pauses supported media and mutes other output during Dictation, then restores it |
| Appearance | System, Light, or Dark | **System**; applies across the main window and Badge |
| Updates | Check for updates | Compares the installed version with the latest GitHub release |

Click a shortcut control and press a modifier, function key, or single
character. Push to Talk, Toggle Recording, and Cycle Modes must be distinct.

Selecting a specific microphone makes it the preferred input. If it disconnects,
FoldWise Voice temporarily uses the macOS default and keeps the preference so
it can recover when the device returns. A failed live device change leaves the
previous working selection in place and reports the problem.

## Privacy and local data

The distributable app stores its files in:

```text
~/Library/Application Support/FoldWise Voice/
├── config.json       # Modes and preferences
├── history.jsonl     # optional text-only Dictation history
└── stats.json        # streak state
```

`config.json` is versioned, validated, and written atomically before a change
becomes active. If an existing file is malformed or uses an unsupported schema,
FoldWise Voice preserves it and opens in a read-only configuration-recovery
state. Voice to Text remains available with built-in runtime defaults. You can
quit without changing the file or explicitly reset it; reset backs up the
rejected data before creating a fresh configuration.

The locally installed development bundle is different: it points
`FOLDWISE_CONFIG` at `config.json` in the repository so configuration edits are
easy to inspect. History and Stats still use Application Support. Moving or
deleting the repository breaks that installed bundle until it is rebuilt.

## Troubleshooting

- **Nothing records:** Enable FoldWise Voice under **System Settings → Privacy
  & Security → Microphone**. Confirm that the selected input device is
  connected, or switch Input back to System Default.
- **The shortcut works only while FoldWise Voice is focused:** Enable either
  Input Monitoring or Accessibility. If an enabled entry belongs to an older
  build, remove it, add the current app again, and retry; the listener can
  recover without relaunching.
- **The shortcut does nothing anywhere:** Check for a shortcut collision and
  verify the app is still running in the menu bar. Function keys such as `F19`
  are useful dedicated bindings.
- **Text is not pasted:** Enable Accessibility and try again. The transcript is
  left on the clipboard when automatic insertion fails.
- **Ollama is unavailable or a model is missing:** Start the Ollama app or run
  `brew services start ollama`, then retry in Models. The current Dictation
  still uses raw text.
- **A speech model is unavailable or damaged:** Open Models to retry its
  download or select another downloaded model. FoldWise Voice attempts to
  restore the default Parakeet model when possible and blocks Dictation if no
  speech model can load.
- **The first speech-model download is slow:** Keep the app running and online.
  Model files are downloaded only once and used locally afterward.
- **The menu-bar icon is missing:** On a notched MacBook it may be hidden behind
  the notch or crowded icons. Command-drag other items to make room.
- **macOS blocks the downloaded app:** Click Done in the warning, then use
  **System Settings → Privacy & Security → Open Anyway**. Alternatively run
  `xattr -dr com.apple.quarantine "/Applications/FoldWise Voice.app"`.
- **The app says it is already running:** Use the existing menu-bar instance or
  quit it before launching another build.

## Contributing

You need an Apple Silicon Mac, macOS 14 or later, a Swift 5.10-compatible or
newer toolchain, Git, and Python 3 for app packaging. Ollama is needed only for
manual Polish testing. Install the formatting tools with Homebrew:

```sh
brew install swiftformat swiftlint
```

Clone, resolve dependencies, and run a development build:

```sh
git clone https://github.com/hadrysm/foldwise-voice.git
cd foldwise-voice
swift package resolve
swift run FoldWiseVoice --show-settings
```

Useful commands:

```sh
swift build                         # debug build
swift run -c release                # optimized run from the repository
python3 scripts/build_swift_app.py  # install a dev app that opens Settings
swift test                          # complete Swift test suite
./scripts/coverage.sh               # tests plus the repository coverage policy
swiftformat --lint .                # verify formatting without rewriting files
swiftlint lint --strict             # run the same strict lint used by CI
```

Enable the repository's pre-commit hook once per clone:

```sh
git config core.hooksPath .githooks
```

The hook formats and lints staged Swift files when SwiftFormat and SwiftLint are
installed. CI runs formatting, strict lint, and the coverage policy. Read the
[testing guide](docs/TESTING.md) for coverage rules and the required macOS smoke
test, and [coding standards](docs/CODING_STANDARDS.md) before changing behavior
or interfaces.

### Project structure

FoldWise Voice is a Swift package with a testable library and a thin executable:

```text
Package.swift
Sources/
├── FoldWiseVoice/       # executable entry point
└── FoldWiseVoiceKit/    # application, features, configuration, and integrations
Tests/
└── FoldWiseVoiceKitTests/
scripts/                 # packaging, assets, and coverage tooling
```

Feature code is grouped around the Badge, Dictation stages, Home, Modes,
History, Stats, and Settings. macOS boundaries such as hotkeys, permissions,
updates, and audio ducking live under `SystemIntegrations`. `CONTEXT.md` defines
the repository's domain vocabulary, and `docs/adr/` records durable design
decisions.

### Design system

[`Theme.swift`](Sources/FoldWiseVoiceKit/DesignSystem/Theme.swift) is the source
of truth for shared colors, type, spacing, radii, window metrics, and animation
timings. The main window uses a warm editorial palette that adapts to System,
Light, and Dark appearances; the Badge keeps its dark violet-and-ribbon identity
in every appearance. New UI should consume `Theme` tokens instead of copying
values into feature views.

### Build a distributable DMG

```sh
python3 scripts/build_swift_app.py --dmg
```

The result is `dist/FoldWise-Voice-<version>.dmg`, containing a self-contained
**FoldWise Voice.app** with no repository paths. Builds are ad-hoc signed unless
`CODESIGN_IDENTITY` is set to a Developer ID Application identity. A signed
release still needs notarization and stapling before Gatekeeper accepts it
without the Open Anyway step:

```sh
xcrun notarytool submit dist/FoldWise-Voice-<version>.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/FoldWise-Voice-<version>.dmg
```

GitHub releases are managed by release-please. Conventional Commit subjects on
`main` drive versioning and changelog entries, and the release workflow builds
and attaches the DMG automatically.
