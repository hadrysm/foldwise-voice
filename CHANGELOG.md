# Changelog

## [0.20.0](https://github.com/hadrysm/foldwise-voice/compare/v0.19.0...v0.20.0) (2026-08-02)


### Features

* **menu-bar:** tint one waveform icon across all states ([#439](https://github.com/hadrysm/foldwise-voice/issues/439)) ([c32e4dd](https://github.com/hadrysm/foldwise-voice/commit/c32e4dd2633ff1dcc74da021e88bfbd5eedde36f))
* **sandcastle:** add selectable workflows and Review Only ([#388](https://github.com/hadrysm/foldwise-voice/issues/388)) ([a4d77f8](https://github.com/hadrysm/foldwise-voice/commit/a4d77f8578bfb710b0cc4dc3abc39d89d6147998))
* **sandcastle:** add the Planner and the Merger to the wave-parallel driver ([#445](https://github.com/hadrysm/foldwise-voice/issues/445)) ([0c8fd9d](https://github.com/hadrysm/foldwise-voice/commit/0c8fd9d249222f12691dfbd4effa96901c6df078))
* **sandcastle:** add the pure Work scope snapshot, ordering and level model ([#435](https://github.com/hadrysm/foldwise-voice/issues/435)) ([e6737f0](https://github.com/hadrysm/foldwise-voice/commit/e6737f0f72c2d243b01e01858c948462e7275bd0)), closes [#419](https://github.com/hadrysm/foldwise-voice/issues/419)
* **sandcastle:** add the wave-parallel driver's worktrees, fan-in and cleanup ([#444](https://github.com/hadrysm/foldwise-voice/issues/444)) ([04c56bc](https://github.com/hadrysm/foldwise-voice/commit/04c56bc171bd40fd01aad85232ae17c68027ff84)), closes [#425](https://github.com/hadrysm/foldwise-voice/issues/425)
* **sandcastle:** flip the contract to an allow-list and drive it ([#441](https://github.com/hadrysm/foldwise-voice/issues/441)) ([2fd81ee](https://github.com/hadrysm/foldwise-voice/commit/2fd81ee15581cac2bfdc113a5d4dc106287d47b2)), closes [#422](https://github.com/hadrysm/foldwise-voice/issues/422)
* **sandcastle:** make the picker scope-first and teach the store to remember it ([#440](https://github.com/hadrysm/foldwise-voice/issues/440)) ([404e7ae](https://github.com/hadrysm/foldwise-voice/commit/404e7aeb1714b75cdb7508f0ad82b3e9c4a97a9b)), closes [#421](https://github.com/hadrysm/foldwise-voice/issues/421)
* **sandcastle:** per-phase model selection, Claude Opus 5, and workflow-seam docs ([#384](https://github.com/hadrysm/foldwise-voice/issues/384)) ([9336d3a](https://github.com/hadrysm/foldwise-voice/commit/9336d3a17877b264b9fd53e58ad8537b418d17fd))
* **sandcastle:** register the wave-parallel workflow and render the run ledger ([#446](https://github.com/hadrysm/foldwise-voice/issues/446)) ([eee1b58](https://github.com/hadrysm/foldwise-voice/commit/eee1b5875e6979dc9c3b8c6d86be53b8ce2708ec))
* **sandcastle:** resolve Work scope against GitHub, with a schema canary ([#438](https://github.com/hadrysm/foldwise-voice/issues/438)) ([d6fb570](https://github.com/hadrysm/foldwise-voice/commit/d6fb570a5cfe28feac2a47b12f351253bb283bd0))
* **sandcastle:** rewrite the three prompts for {{WORK}} and {{ANCHOR}} ([#443](https://github.com/hadrysm/foldwise-voice/issues/443)) ([0e53d81](https://github.com/hadrysm/foldwise-voice/commit/0e53d813edb7e368b3ca454ccbb68efd38a82619)), closes [#424](https://github.com/hadrysm/foldwise-voice/issues/424)
* **sandcastle:** select a workflow first, and add cross-provider Review Only ([#386](https://github.com/hadrysm/foldwise-voice/issues/386)) ([2d8b8cb](https://github.com/hadrysm/foldwise-voice/commit/2d8b8cba683a15ae8b1a5b94fc3bc9f4e18cea81))
* **sandcastle:** teach the draining driver outcomes, skips and the handoff ([#442](https://github.com/hadrysm/foldwise-voice/issues/442)) ([4d56106](https://github.com/hadrysm/foldwise-voice/commit/4d56106e597644f163b56c6ac832b454fbb8a769))


### Bug Fixes

* **sandcastle:** chain Review Only's reads onto their own fetch ([#449](https://github.com/hadrysm/foldwise-voice/issues/449)) ([6f8bb53](https://github.com/hadrysm/foldwise-voice/commit/6f8bb53e37b64ee85d1de1144ff667d349a9255a)), closes [#417](https://github.com/hadrysm/foldwise-voice/issues/417)
* **settings:** make the whole model ledger card clickable ([#437](https://github.com/hadrysm/foldwise-voice/issues/437)) ([8ea4d2e](https://github.com/hadrysm/foldwise-voice/commit/8ea4d2e266a162a4947a7062ccd06f334e3646a8))


### Refactoring

* **sandcastle:** delete the inert completion signal from every prompt ([#450](https://github.com/hadrysm/foldwise-voice/issues/450)) ([20e78b2](https://github.com/hadrysm/foldwise-voice/commit/20e78b2cf25f842fb79972c5cc26ee718a273801)), closes [#418](https://github.com/hadrysm/foldwise-voice/issues/418) [#430](https://github.com/hadrysm/foldwise-voice/issues/430)
* **sandcastle:** move repo-shaped configuration into repo.mts ([#434](https://github.com/hadrysm/foldwise-voice/issues/434)) ([d0f5c9c](https://github.com/hadrysm/foldwise-voice/commit/d0f5c9c3dec3447912bba7e87e4882173dd8a8a1)), closes [#433](https://github.com/hadrysm/foldwise-voice/issues/433)


### Documentation

* **adr:** amend ADR-0001 and ADR-0010 for Work scope and parallel worktrees ([#397](https://github.com/hadrysm/foldwise-voice/issues/397)) ([#414](https://github.com/hadrysm/foldwise-voice/issues/414)) ([c2cca85](https://github.com/hadrysm/foldwise-voice/commit/c2cca85b341f3227f712739b06ad97892ea984e8))
* **adr:** record the reopen rule, the testing rules and the measurements ([#452](https://github.com/hadrysm/foldwise-voice/issues/452)) ([6e11a58](https://github.com/hadrysm/foldwise-voice/commit/6e11a58d5f58e0a173150d1fc7720564edba1ac6)), closes [#432](https://github.com/hadrysm/foldwise-voice/issues/432)
* capture scope-first picker prototype ([#402](https://github.com/hadrysm/foldwise-voice/issues/402)) ([93bcdc0](https://github.com/hadrysm/foldwise-voice/commit/93bcdc0ca8494d03706b984a47710adc2b5cd0be)), closes [#391](https://github.com/hadrysm/foldwise-voice/issues/391)
* **context:** refresh the Batch workflow glossary for drivers, levels and waves ([#451](https://github.com/hadrysm/foldwise-voice/issues/451)) ([3f070d1](https://github.com/hadrysm/foldwise-voice/commit/3f070d19662c9ae97a98261aa10157033a51156f)), closes [#418](https://github.com/hadrysm/foldwise-voice/issues/418) [#431](https://github.com/hadrysm/foldwise-voice/issues/431)
* document GitHub work scope snapshots ([#400](https://github.com/hadrysm/foldwise-voice/issues/400)) ([134f5c8](https://github.com/hadrysm/foldwise-voice/commit/134f5c8c5ca84f711abc3e6735a5b5069c00226b)), closes [#390](https://github.com/hadrysm/foldwise-voice/issues/390)
* rename PRD to SPEC across docs and agent prompts ([#399](https://github.com/hadrysm/foldwise-voice/issues/399)) ([002cb26](https://github.com/hadrysm/foldwise-voice/commit/002cb26b1d798e4ef7cef4355f36f297f3567b6b))
* settle Guided setup design (vocabulary, ordering, Ollama, takeover prototype) ([#385](https://github.com/hadrysm/foldwise-voice/issues/385)) ([e8fa7a7](https://github.com/hadrysm/foldwise-voice/commit/e8fa7a7277c8a87109d4b2e667adc221446dd355))
* settle the wave-parallel run display on an append-only ledger ([#413](https://github.com/hadrysm/foldwise-voice/issues/413)) ([cc61e90](https://github.com/hadrysm/foldwise-voice/commit/cc61e909e094217a2ab6ac88597dbb7d759d8474))


### Maintenance

* **scripts:** add worktree setup script ([#382](https://github.com/hadrysm/foldwise-voice/issues/382)) ([26232dd](https://github.com/hadrysm/foldwise-voice/commit/26232dd3c4d7f71ef9b5d1880743f8fc91a18875))

## [0.19.0](https://github.com/hadrysm/foldwise-voice/compare/v0.18.3...v0.19.0) (2026-07-29)


### Features

* stream ASR transcripts live and gate dictation latency ([#368](https://github.com/hadrysm/foldwise-voice/issues/368)) ([f6f9858](https://github.com/hadrysm/foldwise-voice/commit/f6f985888fa9337eafc92a327d25a8d79ed9ff9d))

## [0.18.3](https://github.com/hadrysm/foldwise-voice/compare/v0.18.2...v0.18.3) (2026-07-27)


### Performance

* deliver sub-100 ms pane navigation ([#337](https://github.com/hadrysm/foldwise-voice/issues/337)) ([837d143](https://github.com/hadrysm/foldwise-voice/commit/837d143e2efbc49ff698965e8fc639c66c2d7c82)), closes [#325](https://github.com/hadrysm/foldwise-voice/issues/325)

## [0.18.2](https://github.com/hadrysm/foldwise-voice/compare/v0.18.1...v0.18.2) (2026-07-26)


### Bug Fixes

* **releases:** avoid priming cached archive misses ([#316](https://github.com/hadrysm/foldwise-voice/issues/316)) ([e07f87c](https://github.com/hadrysm/foldwise-voice/commit/e07f87cee815e2adb00d196c6b9de8936fd05f35))

## [0.18.1](https://github.com/hadrysm/foldwise-voice/compare/v0.18.0...v0.18.1) (2026-07-26)


### Bug Fixes

* **ci:** restore routine release finalization ([#311](https://github.com/hadrysm/foldwise-voice/issues/311)) ([84c2898](https://github.com/hadrysm/foldwise-voice/commit/84c2898b16ce433034c7b0d066629baef6a5a428))
* **releases:** harden recovery publication ([#315](https://github.com/hadrysm/foldwise-voice/issues/315)) ([a3a63ad](https://github.com/hadrysm/foldwise-voice/commit/a3a63ad8489b7b6e17d4fa7509e1ba061b919d53))
* **releases:** identify public verification requests ([#313](https://github.com/hadrysm/foldwise-voice/issues/313)) ([3d63eff](https://github.com/hadrysm/foldwise-voice/commit/3d63eff0db1da2b706b7083f3e4bfc2ceef652ed))
* **releases:** preserve recovery publication toolchain ([#314](https://github.com/hadrysm/foldwise-voice/issues/314)) ([f95b59f](https://github.com/hadrysm/foldwise-voice/commit/f95b59fcd00132c53241d48f330f0bc103ea36d5))

## [0.18.0](https://github.com/hadrysm/foldwise-voice/compare/v0.17.0...v0.18.0) (2026-07-25)


### Features

* ship safe signed Sparkle updates and release recovery ([#310](https://github.com/hadrysm/foldwise-voice/issues/310)) ([f0418b1](https://github.com/hadrysm/foldwise-voice/commit/f0418b1d3e7b4c2e12a9ca1bcc51e9906c9efeb7)), closes [#309](https://github.com/hadrysm/foldwise-voice/issues/309)


### Documentation

* confirm transition release verification ([89a4c7d](https://github.com/hadrysm/foldwise-voice/commit/89a4c7d602ca85fb2c55ebae557e2e47ddd9addb))
* record transition release artifact ([4cc7a82](https://github.com/hadrysm/foldwise-voice/commit/4cc7a82566a7a59d06b10e6e71a6121c49549b3d))

## [0.17.0](https://github.com/hadrysm/foldwise-voice/compare/v0.16.0...v0.17.0) (2026-07-25)

### Existing users: one manual update and permission refresh

This is the first Developer ID-signed and notarized FoldWise Voice release.
Download the DMG, replace FoldWise Voice in Applications, and open it. Because
macOS treats this build as a new app identity, you’ll need to allow Microphone
and Accessibility again. FoldWise Voice’s Permission recovery guide will walk
you through it.

This is a one-time transition—future signed updates retain the same identity
and permissions. If System Settings shows an enabled FoldWise Voice entry but
the guide still reports missing access, follow the guide to remove the old entry
and add the installed app again. You do not need to run `tccutil`.

### Features

* add transition-release permission recovery ([b215faa](https://github.com/hadrysm/foldwise-voice/commit/b215faab4a3d75a11188c8d1f184fba0d347818b))
* modernize dark-mode views with the new visual system ([#272](https://github.com/hadrysm/foldwise-voice/issues/272)) ([fe4949f](https://github.com/hadrysm/foldwise-voice/commit/fe4949f92006afac9bf58bda3234de6a42a157a9)), closes [#270](https://github.com/hadrysm/foldwise-voice/issues/270)


### Bug Fixes

* **ci:** stabilize hosted visual tests ([#274](https://github.com/hadrysm/foldwise-voice/issues/274)) ([a908d73](https://github.com/hadrysm/foldwise-voice/commit/a908d73bda79f48c3f022b04a60fbc61fe0a0dbb))
* clip EmberSurface content to its rounded silhouette ([#275](https://github.com/hadrysm/foldwise-voice/issues/275)) ([b1f8502](https://github.com/hadrysm/foldwise-voice/commit/b1f8502db2a4691aeab361f4eceb64778829d116))
* smooth sidebar selection movement ([#276](https://github.com/hadrysm/foldwise-voice/issues/276)) ([cc7888b](https://github.com/hadrysm/foldwise-voice/commit/cc7888b21e614298d5e25c2e131b203c2ced2ac1))

## [0.16.0](https://github.com/hadrysm/foldwise-voice/compare/v0.15.0...v0.16.0) (2026-07-23)


### Features

* modernize the Models workspace ([#233](https://github.com/hadrysm/foldwise-voice/issues/233)) ([8271819](https://github.com/hadrysm/foldwise-voice/commit/82718193bc1f2cee72dc08a35f4bbd00fcb4432a))
* redesign Stats with a monthly activity calendar ([#247](https://github.com/hadrysm/foldwise-voice/issues/247)) ([8f02369](https://github.com/hadrysm/foldwise-voice/commit/8f0236986eed2174dcf9c04a599cee77cb376fbc))


### Bug Fixes

* prevent CoreAudio capture startup loop ([#271](https://github.com/hadrysm/foldwise-voice/issues/271)) ([b6f2db9](https://github.com/hadrysm/foldwise-voice/commit/b6f2db95a70bca197f832554be3d25a0b0668275))


### Documentation

* rewrite README with settings guide ([#190](https://github.com/hadrysm/foldwise-voice/issues/190)) ([f416a6e](https://github.com/hadrysm/foldwise-voice/commit/f416a6ed05fbcebadb30a955f4e6d9a10d3dd21e))


### Maintenance

* **ci:** add PR size labeling workflow ([#188](https://github.com/hadrysm/foldwise-voice/issues/188)) ([7ec0dd1](https://github.com/hadrysm/foldwise-voice/commit/7ec0dd13a81dc55263149321f8a289161646d19e))

## [0.15.0](https://github.com/hadrysm/foldwise-voice/compare/v0.14.0...v0.15.0) (2026-07-19)


### Features

* add audio input, appearance, and shared dictation rows ([#159](https://github.com/hadrysm/foldwise-voice/issues/159)) ([9f8293e](https://github.com/hadrysm/foldwise-voice/commit/9f8293e51aa3c9ec7c4a5b74dd81bc6cd276f9c9))
* add custom modes UI and cycling hotkey ([#178](https://github.com/hadrysm/foldwise-voice/issues/178)) ([98bccc4](https://github.com/hadrysm/foldwise-voice/commit/98bccc4b25e9753bcb6fa928b134d2ab2770be5e))
* unify the ASR model lifecycle ([#186](https://github.com/hadrysm/foldwise-voice/issues/186)) ([b53372d](https://github.com/hadrysm/foldwise-voice/commit/b53372d18cc0604cecf91a028b3de2a3a3b154fa))


### Bug Fixes

* clear stale speech model switching badge ([#187](https://github.com/hadrysm/foldwise-voice/issues/187)) ([c474d70](https://github.com/hadrysm/foldwise-voice/commit/c474d7050c0a7f43f732a351635d02eb2036cd0e))

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
