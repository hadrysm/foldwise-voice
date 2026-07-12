# Changelog

## [0.14.0](https://github.com/hadrysm/foldwise-voice/compare/v0.13.0...v0.14.0) (2026-07-12)


### Features

* improve Home overview and sidebar interactions ([#147](https://github.com/hadrysm/foldwise-voice/issues/147)) ([dc7b64b](https://github.com/hadrysm/foldwise-voice/commit/dc7b64bc8cd6daf50c0ca3bc70a76f6a9405b058))


### Refactoring

* organize Swift project by feature ([#136](https://github.com/hadrysm/foldwise-voice/issues/136)) ([2b9be7b](https://github.com/hadrysm/foldwise-voice/commit/2b9be7b3a552139875052c07bb9fae870e8cdece))

## [0.13.0](https://github.com/hadrysm/foldwise-voice/compare/v0.12.0...v0.13.0) (2026-07-09)


### Features

* **ui:** Editorial redesign — window shell, Home view, and floating Badge ([#111](https://github.com/hadrysm/foldwise-voice/issues/111)) ([4dd0b2e](https://github.com/hadrysm/foldwise-voice/commit/4dd0b2e4ffbdb885d62697feb4061a7d759a52f4))

## [0.12.0](https://github.com/hadrysm/foldwise-voice/compare/v0.11.0...v0.12.0) (2026-07-07)


### Features

* **stats:** usage stats pane — words, WPM, active days, streak, time saved ([#102](https://github.com/hadrysm/foldwise-voice/issues/102)) ([d039a21](https://github.com/hadrysm/foldwise-voice/commit/d039a214335fb1f2a5ebb6b2ad72e6bab55afd2e))


### Refactoring

* extract shared Polish keep-or-fall-back decision into Polish.run ([#88](https://github.com/hadrysm/foldwise-voice/issues/88)) ([f246065](https://github.com/hadrysm/foldwise-voice/commit/f24606562808dc616886340f37d66dd38e0b0153))

## [0.11.0](https://github.com/hadrysm/foldwise-voice/compare/v0.10.0...v0.11.0) (2026-07-07)


### Features

* **history:** local text-only dictation history pane ([#86](https://github.com/hadrysm/foldwise-voice/issues/86)) ([c54fbd7](https://github.com/hadrysm/foldwise-voice/commit/c54fbd78c0bb5c75062b187a364e064926796b82))

## [0.10.0](https://github.com/hadrysm/foldwise-voice/compare/v0.9.0...v0.10.0) (2026-07-06)


### Features

* **models:** kebab overflow menu replaces right-click uninstall ([#77](https://github.com/hadrysm/foldwise-voice/issues/77)) ([59d6ca1](https://github.com/hadrysm/foldwise-voice/commit/59d6ca1b4f6bfa7cec3185636ba47a77e6d447ab))
* **models:** uninstall an installed Ollama model from the Models pane ([#67](https://github.com/hadrysm/foldwise-voice/issues/67)) ([a2e0db2](https://github.com/hadrysm/foldwise-voice/commit/a2e0db21bb7ef48708283ecd434b83f6016127d2))


### Maintenance

* stop tracking runtime modes.json ([#76](https://github.com/hadrysm/foldwise-voice/issues/76)) ([55f774b](https://github.com/hadrysm/foldwise-voice/commit/55f774b3fe7ebb290ec216754bdd0b8a644ffb95))

## [0.9.0](https://github.com/hadrysm/foldwise-voice/compare/v0.8.0...v0.9.0) (2026-07-03)


### Maintenance

* force release 0.9.0 (Ollama Polish output hardening + qwen2.5:3b default) ([fdb1fb8](https://github.com/hadrysm/foldwise-voice/commit/fdb1fb83e705fbcbf90bbf9df0bf812cafbe79d1))

## [0.8.0](https://github.com/hadrysm/foldwise-voice/compare/v0.7.0...v0.8.0) (2026-07-03)


### Features

* **config:** Config owns change propagation — mutate, persist, notify ([#57](https://github.com/hadrysm/foldwise-voice/issues/57)) ([69556fb](https://github.com/hadrysm/foldwise-voice/commit/69556fb3c7b2fc82626af6d9794ab294bdfaa465))

## [0.7.0](https://github.com/hadrysm/foldwise-voice/compare/v0.6.3...v0.7.0) (2026-07-03)


### Features

* **sandcastle:** PRD-scoped reviewer runner + agent config ([#30](https://github.com/hadrysm/foldwise-voice/issues/30)) ([6184806](https://github.com/hadrysm/foldwise-voice/commit/61848067ec72ad56bbaf51d58dfe05b2634c5de8))

## [0.6.3](https://github.com/hadrysm/foldwise-voice/compare/v0.6.2...v0.6.3) (2026-07-03)


### Maintenance

* force release for the tests/lint/restructure PR ([aa8f3f7](https://github.com/hadrysm/foldwise-voice/commit/aa8f3f735788f977968537c0e948caed1eb96384))

## [0.6.2](https://github.com/hadrysm/foldwise-voice/compare/v0.6.1...v0.6.2) (2026-07-02)


### Bug Fixes

* stop trusting tap creation as proof the global hotkey works ([#26](https://github.com/hadrysm/foldwise-voice/issues/26)) ([e6f04dd](https://github.com/hadrysm/foldwise-voice/commit/e6f04ddc714eec02113d7a8d6694377ff96e7c12))

## [0.6.1](https://github.com/hadrysm/foldwise-voice/compare/v0.6.0...v0.6.1) (2026-07-02)


### Bug Fixes

* global hotkey without focus; feat: minimal recording-bar style ([#24](https://github.com/hadrysm/foldwise-voice/issues/24)) ([1309af3](https://github.com/hadrysm/foldwise-voice/commit/1309af3232f8ce40793a44481c5c6256e2c0d3c4))

## [0.6.0](https://github.com/hadrysm/foldwise-voice/compare/v0.5.0...v0.6.0) (2026-07-02)


### Features

* HUD stop button, sidebar update check, optional CI signing ([#21](https://github.com/hadrysm/foldwise-voice/issues/21)) ([e6b8502](https://github.com/hadrysm/foldwise-voice/commit/e6b850240ae3dc5832e7f6f99fbc2f0567648413))

## [0.5.0](https://github.com/hadrysm/foldwise-voice/compare/v0.4.4...v0.5.0) (2026-07-02)


### Features

* check-for-updates button in Settings and menu bar ([#19](https://github.com/hadrysm/foldwise-voice/issues/19)) ([15d0dfb](https://github.com/hadrysm/foldwise-voice/commit/15d0dfb35385a34a580a2f3840059d041a52fc4a))

## [0.4.4](https://github.com/hadrysm/foldwise-voice/compare/v0.4.3...v0.4.4) (2026-07-02)


### Bug Fixes

* show FoldWise Voice menu bar while settings window is open ([#17](https://github.com/hadrysm/foldwise-voice/issues/17)) ([9c3f845](https://github.com/hadrysm/foldwise-voice/commit/9c3f8453f6b0ae2d499f4658d68f3c8b961dd1c8))

## [0.4.3](https://github.com/hadrysm/foldwise-voice/compare/v0.4.2...v0.4.3) (2026-07-02)


### Bug Fixes

* reduce sidebar top gap below traffic lights in settings window ([#16](https://github.com/hadrysm/foldwise-voice/issues/16)) ([1f878e8](https://github.com/hadrysm/foldwise-voice/commit/1f878e84de8bc06db4895097a21241b9d76e0b05))
* styled installer DMG with app icon and Gatekeeper guidance ([#14](https://github.com/hadrysm/foldwise-voice/issues/14)) ([21e2fb2](https://github.com/hadrysm/foldwise-voice/commit/21e2fb2a5ccc5a5c63a2a165ca4673464cd869c0))

## [0.4.2](https://github.com/hadrysm/foldwise-voice/compare/v0.4.1...v0.4.2) (2026-07-02)


### Bug Fixes

* break up HUD waveform expressions to avoid Swift type-check timeout ([#12](https://github.com/hadrysm/foldwise-voice/issues/12)) ([c659eb8](https://github.com/hadrysm/foldwise-voice/commit/c659eb89b580a9a0d8d5deb09d3ce2224f3e1165))

## [0.4.1](https://github.com/hadrysm/foldwise-voice/compare/v0.4.0...v0.4.1) (2026-07-02)


### Maintenance

* add shared Conductor settings with setup, run, and archive scripts ([#10](https://github.com/hadrysm/foldwise-voice/issues/10)) ([367a261](https://github.com/hadrysm/foldwise-voice/commit/367a26179c989a0769117c8ae50da90da3477354))

## [0.4.0](https://github.com/hadrysm/foldwise-voice/compare/v0.3.0...v0.4.0) (2026-07-02)


### Features

* notify users in the menu bar when a newer release is available ([#7](https://github.com/hadrysm/foldwise-voice/issues/7)) ([34a072b](https://github.com/hadrysm/foldwise-voice/commit/34a072b6926e00aa56f4a139cb202c70b3d433f2))

## [0.3.0](https://github.com/hadrysm/foldwise-voice/compare/v0.2.0...v0.3.0) (2026-07-02)


### Features

* add gemma3 and phi4-mini to the Ollama model catalog ([84702ff](https://github.com/hadrysm/foldwise-voice/commit/84702ffa2ecdc4222e0e98272edc94d81b5791f4))
* automated version bumping (release-please) and version display in settings ([ef7c419](https://github.com/hadrysm/foldwise-voice/commit/ef7c419bc9a383b81e2c0e72d4985f225d069c55))
* build a distributable .dmg installer for the native Swift app ([e26b425](https://github.com/hadrysm/foldwise-voice/commit/e26b42597bbd2f515da110fc71f5a23adb0ddd56))
* build a distributable .dmg installer for the native Swift app ([e361055](https://github.com/hadrysm/foldwise-voice/commit/e3610559db38cef116e5da5f37839ac4fe8c0e12))
* local on-device dictation app (mlx-whisper + Ollama modes) ([734823c](https://github.com/hadrysm/foldwise-voice/commit/734823c3dd51d9b55860c0dbf3d70ddee2dfd61b))
* native Swift app (Parakeet ANE + SwiftUI) and HUD drag-bug fix ([9216cd9](https://github.com/hadrysm/foldwise-voice/commit/9216cd9631c7f3f8cbde2d5a392bb2055c63d1a1))
* sidebar settings UI with Ollama model picker and in-app installs ([527c446](https://github.com/hadrysm/foldwise-voice/commit/527c446a1ba505df34c5e188bab568e55dc2ee79))


### Bug Fixes

* prompt for Accessibility at launch so auto-paste isn't silently skipped ([#5](https://github.com/hadrysm/foldwise-voice/issues/5)) ([d21a942](https://github.com/hadrysm/foldwise-voice/commit/d21a942f3934e12a49b831e352d333fb0b1dde95))
* prompt for Microphone and Accessibility at first launch ([#6](https://github.com/hadrysm/foldwise-voice/issues/6)) ([0cdd518](https://github.com/hadrysm/foldwise-voice/commit/0cdd518ea602e6eadd8e72d1371fa1392440bbbd))
* seven bugs found in deep review of both apps ([f6f0fdc](https://github.com/hadrysm/foldwise-voice/commit/f6f0fdc1e9ab61771d198799491382e9c2e48324))


### Maintenance

* local config — cmd_r hotkey and updated HUD position ([d847cfa](https://github.com/hadrysm/foldwise-voice/commit/d847cfa4d44556d6b86b50ff11225978c1bf9559))
* persist HUD position from Swift app ([7950b68](https://github.com/hadrysm/foldwise-voice/commit/7950b686d812bef72e907a623830e21e2e317e72))
* persist updated HUD position ([9fa3f48](https://github.com/hadrysm/foldwise-voice/commit/9fa3f48534904c84ec7fcc059e053d38ab816908))

## 0.2.0

### Features

* native Swift app (Parakeet ANE + SwiftUI) and HUD drag-bug fix ([9216cd9](https://github.com/hadrysm/foldwise-voice/commit/9216cd9))
* sidebar settings UI with Ollama model picker and in-app installs ([527c446](https://github.com/hadrysm/foldwise-voice/commit/527c446))
* add gemma3 and phi4-mini to the Ollama model catalog ([84702ff](https://github.com/hadrysm/foldwise-voice/commit/84702ff))

### Bug Fixes

* seven bugs found in deep review of both apps ([f6f0fdc](https://github.com/hadrysm/foldwise-voice/commit/f6f0fdc))

## 0.1.0

### Features

* local on-device dictation app (mlx-whisper + Ollama modes) ([734823c](https://github.com/hadrysm/foldwise-voice/commit/734823c))
