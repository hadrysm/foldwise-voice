# Current Mode configuration and runtime dependency surface

Research answer for **Audit the current Mode configuration and runtime dependency
surface**, audited at repository commit `d39227c2f440de3b96c013825d7166f190351397`.
This note uses only repository primary sources: production source, tests,
`CONTEXT.md`, and accepted ADRs.

## Executive answer

The runtime is closer to per-Mode AI models than the UI suggests. A `Mode` already
carries its own `llmModel`, `systemPrompt`, and `vocab`, and the Pipeline passes the
selected `Mode` value through Polish to Ollama. The shared-model behavior is a
`Config`/Settings convention: `Config.llmModel` reads the first LLM-enabled Mode,
and `setLLMModel` rewrites every LLM-enabled Mode. Existing files can therefore
already contain meaningful per-Mode differences, and a safe migration must
preserve them rather than copying the first model across the library
([Config.swift:22-49](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L22-L49),
[Config.swift:161-174](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L161-L174),
[Pipeline.swift:138-143](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L138-L143),
[Pipeline.swift:312-321](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L312-L321)).

The unsafe part is identity and mutation. A Mode name is simultaneously the JSON
object key, dictionary key, order entry, active selection, menu command payload,
History attribution, and display label. There is no Config-owned CRUD/reorder API
or Mode-library change event. Renaming, deletion, and reordering therefore cannot
be added safely as UI-only operations; they require a versioned migration and a
stable-identity Mode collection owned by `Config`
([Config.swift:60-63](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L60-L63),
[Config.swift:114-139](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L114-L139),
[Config.swift:196-216](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L196-L216)).

The other critical mismatch is session freezing. The Pipeline displays the
active name when recording starts but snapshots the full `Mode` only when
recording stops. A Mode switch or edit during recording therefore changes the
current session even though the listening state announced the earlier Mode. Once
stopped, the copied value correctly isolates the queued job from later mutations
([Pipeline.swift:182-219](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L182-L219),
[Pipeline.swift:263-270](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L263-L270)).

## Current persistence and identity

### The persisted shape is name-keyed and unversioned

`Mode` is a value with `name`, `asrModel`, optional `llmModel`, optional
`systemPrompt`, vocabulary, and an in-memory `expands` calibration. It has no
stable identifier or icon. `expands` is deliberately omitted from persistence and
re-derived from the name: `Clean` and `Voice to Text` are In-place, every other
name is Expanding. A rename can consequently change behavior after reload even if
the prompt and model do not change
([Config.swift:22-58](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L22-L58),
[ConfigBehaviorTests.swift:223-260](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigBehaviorTests.swift#L223-L260)).

`Config` holds `activeMode: String`, `modeOrder: [String]`, and
`modes: [String: Mode]`. `modeOrder` is externally read-only, while `modes` is
publicly mutable. The active lookup uses the string key and falls back to the
first ordered Mode, then to a synthesized raw `Voice to Text` value if live
mutation empties the dictionary
([Config.swift:60-63](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L60-L63),
[Config.swift:114-159](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L114-L159),
[ConfigBehaviorTests.swift:93-132](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigBehaviorTests.swift#L93-L132)).

The hand serializer writes only known top-level fields and only Modes reachable
from `modeOrder`. Each Mode is an object under its name, with only `asr_model`,
`llm_model`, `system_prompt`, and `vocab`; unknown fields are not retained. The
whole file is replaced atomically
([Config.swift:244-280](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L244-L280)).
Because comma placement uses the original `modeOrder.count`, directly removing a
Mode from `modes` without updating the order can produce invalid trailing-comma
JSON; directly adding a dictionary entry without adding it to the order silently
omits it. This is an inference from that serializer and shows why new mutations
must maintain the collection invariant inside `Config`, not expose the dictionary.

Loading requires a non-empty `modes` object, reconstructs `Mode.name` from each
object key, defaults missing per-Mode fields, and changes an unknown
`active_mode` to the first recovered name. JSON object order is reconstructed by
searching the raw file for the first quoted occurrence of each name after the
`"modes"` key, rather than by decoding an ordered collection
([Config.swift:313-367](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L313-L367),
[Config.swift:369-384](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L369-L384),
[ConfigRoundTripTests.swift:31-72](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigRoundTripTests.swift#L31-L72)).
The raw search can mistake a name occurring in an earlier prompt or vocabulary
value for the later object key; a new ordered representation should not inherit
this heuristic.

There is no schema version or migration marker in the written fields. More
seriously, `loadOrCreate` treats every load error alike: it creates defaults and
best-effort saves them over the same path. A legacy or future schema that the new
decoder rejects can therefore be destroyed as if it were a missing file. Schema
detection/migration must happen before this fallback, and an unsupported or
failed migration must leave the original file intact
([Config.swift:246-280](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L246-L280),
[Config.swift:406-410](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L406-L410),
[ConfigBehaviorTests.swift:71-90](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigBehaviorTests.swift#L71-L90)).

The path is externally addressable through `--config`, `FOLDWISE_CONFIG`, local
`modes.json`, its parent, or Application Support. The CLI also accepts `--mode`
as a name override and `--print-config` reserializes the loaded shape. Stable IDs
must not accidentally break these diagnostics and launch workflows; name-based
CLI resolution can remain a compatibility adapter while persisted/internal
identity changes
([Config.swift:386-403](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L386-L403),
[AppMain.swift:355-390](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift#L355-L390)).

### Defaults and legacy values need explicit migration rules

Fresh configuration currently contains four ordinary dictionary entries in this
order: `Voice to Text`, `Clean`, `Email`, and `Bullets`; `Clean` is active, all
three polished Modes use `qwen2.5:3b`, and `Voice to Text` differs only by having
no LLM model/prompt. It is not structurally protected from edit or deletion
([Config.swift:413-446](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L413-L446),
[ConfigBehaviorTests.swift:25-35](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigBehaviorTests.swift#L25-L35)).

A non-destructive migration consequently needs policies for configurations that
the current schema permits but the target product model does not:

- a hand-edited `Voice to Text` entry with a model or custom prompt;
- additional raw entries whose `llm_model` is null or empty;
- LLM Modes with a missing/empty prompt (Ollama currently supplies a generic
  prompt);
- divergent LLM models across Modes;
- unknown ASR identifiers, which are intentionally preserved until the user
  explicitly picks a catalog model;
- the current `Clean` name-derived In-place calibration and unknown names'
  Expanding default.

The permissive states come directly from `usesLLM`, load defaults, and Ollama's
fallback prompt
([Config.swift:38-40](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L38-L40),
[Config.swift:324-334](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L324-L334),
[OllamaClient.swift:16-29](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L16-L29)).
Unknown ASR preservation is a tested compatibility contract
([ConfigRoundTripTests.swift:166-178](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigRoundTripTests.swift#L166-L178)).

Per-Mode AI model work must not turn ASR into a per-Mode setting. The domain
separates ASR models from Mode-owned Polish behavior, and ADR-0006 explicitly
keeps ASR selection global even though the legacy file stores `asr_model` inside
every Mode
([CONTEXT.md:43-51](../../CONTEXT.md#L43-L51),
[CONTEXT.md:72-83](../../CONTEXT.md#L72-L83),
[ADR-0006:21-43](../adr/0006-global-asr-selection-over-revived-asr-model.md#L21-L43),
[ADR-0006:74-77](../adr/0006-global-asr-selection-over-revived-asr-model.md#L74-L77)).

## Mutation and change propagation

The only semantic Mode helpers today are:

- `setActiveMode`, which accepts a name only if it exists;
- `setLLMModel`, which updates every already-LLM-enabled Mode and does not record
  a change event;
- `setASRModel`, which updates every Mode and records the global ASR event.

There are no add, duplicate, rename, update, delete, or reorder operations
([Config.swift:161-199](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L161-L199)).
In particular, `setLLMModel` cannot enable a raw Mode because its loop is gated by
the Mode's current `usesLLM` result
([Config.swift:38-40](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L38-L40),
[Config.swift:169-173](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L169-L173)).

ADR-0003 makes `Config` the authority for mutate → persist → notify. Tracked
mutations accumulate a typed `ChangeSet`; `saveAndNotify()` writes first, then
delivers one event to app-lifetime observers, and retains pending changes after a
failed save. The event currently has active Mode, hotkeys, ASR model, input
device, and appearance members, but none for Mode collection/content changes or
LLM changes
([ADR-0003:1-10](../adr/0003-config-owns-change-propagation.md#L1-L10),
[ADR-0003:24-40](../adr/0003-config-owns-change-propagation.md#L24-L40),
[Config.swift:201-242](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L201-L242),
[ConfigChangePropagationTests.swift:197-208](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigChangePropagationTests.swift#L197-L208),
[ConfigChangePropagationTests.swift:251-265](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigChangePropagationTests.swift#L251-L265)).

Stable user-managed Modes need Config-owned atomic operations and a new granular
Mode-library/content signal. Selection and library changes must remain distinct:
switching active identity only changes checks/Badge feedback, whereas renaming,
reordering, icon changes, deletion, or model/prompt changes require consumers to
re-resolve or rebuild their Mode presentations. Renaming the active Mode is the
important edge: its stable identity does not change, but every displayed active
name/icon still must refresh.

The existing `saveAndNotify()` contract also exposes a failure hazard. A failed
save does not notify, but the in-memory `Config` was already mutated. The menu-bar
and Badge Mode actions discard save errors, so runtime selection can diverge from
disk while other surfaces keep stale checkmarks
([MenuBarController.swift:124-127](../../Sources/FoldWiseVoiceKit/Application/MenuBarController.swift#L124-L127),
[BadgeController.swift:178-181](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeController.swift#L178-L181)).
A Mode-editor Save should surface failure and either roll the mutation back or
make the failed draft retryable; silent best-effort semantics are unsuitable for
library CRUD.

## Dictation selection and freezing

At start, the Pipeline reads `pauseAudio`, starts the recorder, and emits
`.listening(mode: config.activeMode)`. At stop, it reads `config.mode` and
`saveHistory`, then captures those values in the queued Task
([Pipeline.swift:182-219](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L182-L219)).
Because `Mode` is a struct, model, prompt, vocabulary, transformation calibration,
and name are frozen after stop. The worker uses that value for Polish and writes
its name into History
([Pipeline.swift:61-71](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L61-L71),
[Pipeline.swift:263-270](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L263-L270),
[Pipeline.swift:312-321](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L312-L321),
[Pipeline.swift:334-351](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L334-L351)).

The safe target seam is a `Mode`/selection snapshot taken when the dictation
session starts and retained until that session completes. Cycling or editing can
then change Config for the next session without changing the recording already in
progress. The listening event should carry snapshot identity/presentation rather
than independently re-read the active name, avoiding a start-name/stop-behavior
split.

This behavior is highly testable through existing Pipeline seams: fake recording
and transcribing protocols plus injected Polish, insert, History, and frontmost-app
closures; `awaitPendingJob()` drains queued jobs deterministically
([ADR-0002:31-53](../adr/0002-pipeline-hybrid-seams.md#L31-L53),
[Pipeline.swift:91-108](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L91-L108),
[Pipeline.swift:233-238](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L233-L238),
[PipelineTestSupport.swift:1-74](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/PipelineTestSupport.swift#L1-L74)).
The current shared fixture constructs only one Mode, and no test mutates selection
or Mode content between start and stop, so the present stop-time behavior is not
locked intentionally
([PipelineTestSupport.swift:171-185](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/PipelineTestSupport.swift#L171-L185),
[PipelineSessionTests.swift:74-97](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/PipelineSessionTests.swift#L74-L97)).

## History attribution and reprocessing

`HistoryEntry` persists only `modeName: String`; it has no stable Mode ID, icon,
or model/prompt snapshot. Pipeline records the frozen name after insertion
([History.swift:9-25](../../Sources/FoldWiseVoiceKit/Features/History/History.swift#L9-L25),
[Pipeline.swift:339-351](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L339-L351)).
Rows project that stored name directly into full, compact, and accessibility text,
without consulting Config
([DictationRowPresentation.swift:19-39](../../Sources/FoldWiseVoiceKit/Features/DictationRow/DictationRowPresentation.swift#L19-L39),
[DictationRowPresentationTests.swift:49-78](../../Tests/FoldWiseVoiceKitTests/Features/DictationRow/DictationRowPresentationTests.swift#L49-L78)).
Consequently, rename/delete behavior is currently simple snapshot behavior but
cannot show a current Mode icon or follow a renamed Mode.

Re-run Polish is also name-keyed end-to-end: Settings supplies the current LLM
Mode names, the row command carries a name, the workflow looks up
`config.modes[modeName]`, and the reprocessor overwrites the entry's stored name
with the selected current Mode's name
([HistoryView.swift:146-180](../../Sources/FoldWiseVoiceKit/Features/History/HistoryView.swift#L146-L180),
[DictationRowCommand.swift:1-16](../../Sources/FoldWiseVoiceKit/Features/DictationRow/DictationRowCommand.swift#L1-L16),
[SettingsWorkflow.swift:217-257](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L217-L257),
[HistoryReprocessor.swift:23-42](../../Sources/FoldWiseVoiceKit/Features/History/HistoryReprocessor.swift#L23-L42)).

The compatibility-safe History shape is additive: retain `modeName` as the
historical/fallback label and add an optional stable Mode ID for new and
reprocessed entries. Making the ID non-optional under synthesized `Codable` would
make every old line fail decoding; `readEntries()` silently skips any line that
does not decode, so old History would disappear from the UI. This is an inference
from the entry declaration and decoder loop
([History.swift:13-25](../../Sources/FoldWiseVoiceKit/Features/History/History.swift#L13-L25),
[History.swift:260-271](../../Sources/FoldWiseVoiceKit/Features/History/History.swift#L260-L271)).

A planning decision is still needed for resolution semantics: whether a resolvable
ID shows the Mode's current name/icon while `modeName` remains a fallback, and
what icon a deleted or pre-ID entry shows. Keep the History store protocol as the
persistence seam; it already isolates JSONL and provides deterministic temp-file
round trips
([History.swift:96-127](../../Sources/FoldWiseVoiceKit/Features/History/History.swift#L96-L127),
[HistoryStoreRoundTripTests.swift:46-92](../../Tests/FoldWiseVoiceKitTests/Features/History/HistoryStoreRoundTripTests.swift#L46-L92)).

## App surfaces

### Menu bar

`MenuBarController` builds its Mode items once at initialization from
`config.modeOrder`. It subscribes only to `.activeMode` and merely refreshes
checkmarks; it cannot reflect runtime add/delete/rename/reorder or icons. Selection
uses the menu item's title as command identity
([MenuBarController.swift:23-40](../../Sources/FoldWiseVoiceKit/Application/MenuBarController.swift#L23-L40),
[MenuBarController.swift:63-67](../../Sources/FoldWiseVoiceKit/Application/MenuBarController.swift#L63-L67),
[MenuBarController.swift:69-127](../../Sources/FoldWiseVoiceKit/Application/MenuBarController.swift#L69-L127)).

The safe seam is a rebuildable menu projection keyed by stable Mode ID, with the
ID stored in the item payload rather than inferred from its title. A Mode-library
change rebuilds titles/icons/order; an active-only change can keep the cheap
checkmark refresh.

### Badge

`BadgeController` caches only `activeModeName` and refreshes it on
`.activeMode`. Its Mode menu is built fresh on every click, so its roster does not
have the menu bar's construction-time staleness, but it is still name-keyed and
has no icons
([BadgeController.swift:48-61](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeController.swift#L48-L61),
[BadgeController.swift:162-181](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeController.swift#L162-L181)).
The view exposes that name only as the Mode button tooltip; its visible Badge
states contain no Mode identity presentation
([BadgeView.swift:10-19](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeView.swift#L10-L19),
[BadgeView.swift:108-128](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeView.swift#L108-L128)).

The pure `BadgeReducer` maps Pipeline and pointer events to the pill state machine
and ignores the associated name on `.listening`. Mode-cycle feedback therefore
needs an explicit reducer/presentation event or a separate testable presentation
state, with a rule for how it composes with recording/working/error states
([BadgePresentation.swift:70-117](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgePresentation.swift#L70-L117),
[BadgePresentation.swift:116-142](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgePresentation.swift#L116-L142),
[BadgeReducerTests.swift:29-74](../../Tests/FoldWiseVoiceKitTests/Features/Badge/BadgeReducerTests.swift#L29-L74)).
The panel is deliberately non-activating and never key/main, so feedback must
preserve that focus discipline
([BadgeController.swift:1-20](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeController.swift#L1-L20),
[CONTEXT.md:8-14](../../CONTEXT.md#L8-L14)).

### Settings

Settings owns one `activeMode`, one global `selectedModel`, and plain
non-`@Published` name collections (`modeNames`, `llmModes`). There is no Mode ID,
icon, ordered editable collection, or draft type
([SettingsModel.swift:46-75](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsModel.swift#L46-L75),
[SettingsModel.swift:101-136](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsModel.swift#L101-L136)).
Opening the window snapshots Config into those fields; the controller does not
subscribe Settings to Mode-library changes
([SettingsController.swift:57-90](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsController.swift#L57-L90),
[SettingsController.swift:129-136](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsController.swift#L129-L136),
[SettingsWorkflow.swift:122-144](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L122-L144)).

The current Modes pane can only select a Mode. Every LLM Mode subtitle uses the
same global `selectedModel`, and the pane explicitly advertises opening
`modes.json` to edit prompts and vocabulary
([SettingsView.swift:425-468](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsView.swift#L425-L468)).
The controller implements that action by opening `config.path`
([SettingsController.swift:82-85](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsController.swift#L82-L85)).
There is no file watcher or reload path, so an external edit cannot update the
running Config without relaunch.

Most Settings controls mutate the model and call one broad `commit()`, which
validates the two current hotkeys, rewrites the shared LLM model, copies every
preference into Config, and persists immediately
([SettingsWorkflow.swift:406-449](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L406-L449),
[SettingsController.swift:1-3](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsController.swift#L1-L3)).
A draft-based Mode sheet should not reuse this broad transaction: Save should
validate and apply only the intended Mode operation, while Cancel should leave
Config untouched. This also prevents stale Settings snapshots from overwriting
unrelated concurrent changes.

## Model management

The LLM management boundary is already cleanly injectable: list installed models,
pull by name with progress, and delete by name. Production delegates those calls
to Ollama
([SettingsWorkflow.swift:3-10](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L3-L10),
[AppMain.swift:22-36](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift#L22-L36)).
Ollama's runtime API also already accepts the explicit model name for each Polish
request and safely returns the raw transcript when the model/server fails
([OllamaClient.swift:16-49](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L16-L49),
[OllamaClient.swift:51-83](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L51-L83)).
No new runtime model router or reactor is needed for per-Mode LLM selection; the
selected Mode snapshot is the router.

The current workflow couples installation to global selection: a successful pull
calls `selectLLMModel`, which commits the model across all LLM Modes. Deletion
only refreshes the installed list and leaves Config references untouched
([SettingsWorkflow.swift:280-335](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L280-L335),
[SettingsWorkflowTests.swift:991-1063](../../Tests/FoldWiseVoiceKitTests/Features/Settings/SettingsWorkflowTests.swift#L991-L1063)).
The Models pane says one model applies to every LLM Mode, puts a global selection
control on installed rows, warns only when deleting that one selected model, and
represents a missing selected model as a raw-transcript fallback
([ModelsPane.swift:14-20](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsPane.swift#L14-L20),
[ModelsPane.swift:110-120](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsPane.swift#L110-L120),
[ModelsPane.swift:139-181](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsPane.swift#L139-L181),
[ModelsPane.swift:214-225](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsPane.swift#L214-L225)).

Per-Mode assignment should decouple inventory management from selection. Install
can make a model available without rewriting Modes; the Mode editor assigns it.
Uninstall needs dependency-aware presentation for every Mode that references the
model, plus an explicit policy for whether dangling assignments are allowed. The
runtime's raw fallback makes dangling references safe, but it does not make them
clear to the user.

The curated catalog and installed-model inventory both use Ollama names as their
stable identity. Catalog guidance may fuzzy-match family/tier, so assignment must
persist the actual installed name, not a fuzzy catalog match
([ModelCatalog.swift:6-18](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/ModelCatalog.swift#L6-L18),
[ModelCatalog.swift:71-89](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/ModelCatalog.swift#L71-L89),
[OllamaClient.swift:86-115](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L86-L115)).

## Cycle-shortcut integration seam

The global hotkey stack currently knows only push-to-talk and optional toggle.
`HotkeyListener` funnels both event sources into `HotkeyDispatcher`, which parses
two `KeySpec`s and gives push-to-talk precedence through an `if … else if`
dispatch. If both configured strings collide, toggle never fires
([HotkeyListener.swift:20-33](../../Sources/FoldWiseVoiceKit/SystemIntegrations/Hotkeys/HotkeyListener.swift#L20-L33),
[HotkeyDispatcher.swift:9-28](../../Sources/FoldWiseVoiceKit/SystemIntegrations/Hotkeys/HotkeyDispatcher.swift#L9-L28),
[HotkeyDispatcher.swift:42-53](../../Sources/FoldWiseVoiceKit/SystemIntegrations/Hotkeys/HotkeyDispatcher.swift#L42-L53)).
Settings validates only that the two strings parse; it does not reject conflicts
([SettingsWorkflow.swift:406-415](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L406-L415)).

The cycle shortcut can reuse `KeyMap`, the existing event tap, and
`ChangeSet.hotkeys`, but the dispatcher needs a third edge-triggered callback and
Settings needs a shared conflict validator across all three actions. Cycle order
must come from the visible editable-Mode order and exclude the protected raw
system option; zero editable Modes must be a no-op. The dispatcher is the correct
pure seam for precedence/repeat/conflict tests, while `HotkeyListener` remains the
thin macOS adapter
([KeyMap.swift:13-27](../../Sources/FoldWiseVoiceKit/SystemIntegrations/Hotkeys/KeyMap.swift#L13-L27),
[HotkeyListenerDispatchTests.swift:1-4](../../Tests/FoldWiseVoiceKitTests/SystemIntegrations/Hotkeys/HotkeyListenerDispatchTests.swift#L1-L4),
[HotkeyListenerDispatchTests.swift:64-69](../../Tests/FoldWiseVoiceKitTests/SystemIntegrations/Hotkeys/HotkeyListenerDispatchTests.swift#L64-L69),
[Config.swift:203-216](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L203-L216)).

## Test seams and coverage constraints

Repository policy expects decisions in pure collaborators, persistence tests, or
boundary fakes. The AppKit/SwiftUI shells relevant here—AppMain, MenuBarController,
BadgeController/View, SettingsController/View, Models panes, HistoryView, and
HotkeyListener—are coverage exemptions; their meaningful rules should be
extracted rather than buried in those shells
([TESTING.md:8-19](../TESTING.md#L8-L19),
[TESTING.md:83-113](../TESTING.md#L83-L113)).

Existing high-value seams are:

- Config behavior, exact-file round trips, and persist-before-notify propagation
  ([ConfigBehaviorTests.swift:93-152](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigBehaviorTests.swift#L93-L152),
  [ConfigRoundTripTests.swift:62-80](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigRoundTripTests.swift#L62-L80),
  [ConfigChangePropagationTests.swift:27-83](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigChangePropagationTests.swift#L27-L83));
- Pipeline fakes and effect closures, suitable for start-time snapshot and
  post-stop isolation tests
  ([PipelineTestSupport.swift:1-74](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/PipelineTestSupport.swift#L1-L74),
  [PipelineRecordTests.swift:19-44](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/PipelineRecordTests.swift#L19-L44));
- SettingsWorkflow's injected persistence/model managers and large decision test
  surface
  ([SettingsWorkflow.swift:31-120](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L31-L120),
  [SettingsWorkflowTests.swift:273-299](../../Tests/FoldWiseVoiceKitTests/Features/Settings/SettingsWorkflowTests.swift#L273-L299),
  [SettingsWorkflowTests.swift:387-425](../../Tests/FoldWiseVoiceKitTests/Features/Settings/SettingsWorkflowTests.swift#L387-L425));
- HistoryStore temp-file tests and HistoryReprocessor's injected Polish closure
  ([HistoryStoreRoundTripTests.swift:46-105](../../Tests/FoldWiseVoiceKitTests/Features/History/HistoryStoreRoundTripTests.swift#L46-L105),
  [HistoryReprocessorTests.swift:62-85](../../Tests/FoldWiseVoiceKitTests/Features/History/HistoryReprocessorTests.swift#L62-L85));
- Badge's pure reducer and HotkeyDispatcher's pure event seam
  ([BadgeReducerTests.swift:14-107](../../Tests/FoldWiseVoiceKitTests/Features/Badge/BadgeReducerTests.swift#L14-L107),
  [HotkeyListenerDispatchTests.swift:10-101](../../Tests/FoldWiseVoiceKitTests/SystemIntegrations/Hotkeys/HotkeyListenerDispatchTests.swift#L10-L101));
- TranscriberDispatcher's injectable factory/reactor tests as prior art for
  Config-subscribed runtime components
  ([TranscriberDispatcherTests.swift:93-109](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/Transcribe/TranscriberDispatcherTests.swift#L93-L109),
  [TranscriberDispatcherTests.swift:179-233](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/Transcribe/TranscriberDispatcherTests.swift#L179-L233)).

There are no MenuBarController tests and no BadgeController Config-integration
tests in the test target. Roster rebuilding, stable-ID menu commands, and cycle
feedback composition should therefore be put behind pure menu/presentation
projections or small reactors, leaving only AppKit wiring for the release smoke
test. The manual policy already requires real global hotkeys and Badge/menu
behavior to be exercised across app focus boundaries
([TESTING.md:141-160](../TESTING.md#L141-L160),
[TESTING.md:272-288](../TESTING.md#L272-L288)).

### Downstream documentation and smoke-test drift

The README is part of the compatibility surface because it currently documents
the old schema and workflow as user-facing behavior: four fixed defaults, raw
Modes expressed by `llm_model: null`, direct `modes.json` editing plus restart,
immediate saves, and one Settings model applied to all LLM Modes
([README.md:43-45](../../README.md#L43-L45),
[README.md:93-131](../../README.md#L93-L131),
[README.md:217-235](../../README.md#L217-L235)).
The implementation plan must update those instructions in the same delivery that
removes the raw-file editor and global selection; otherwise users will be told to
exercise unsupported paths.

The manual release procedure likewise names `Clean` as the polished Mode, asks
the tester to select one global Polish model, and checks only name/checkmark
synchronization across the current Badge/menu/Settings surfaces
([TESTING.md:165-180](../TESTING.md#L165-L180),
[TESTING.md:242-252](../TESTING.md#L242-L252),
[TESTING.md:272-288](../TESTING.md#L272-L288)).
It needs acceptance coverage for migration of an existing file, create/duplicate/
rename/reorder/delete including zero editable Modes, per-Mode model assignment and
missing-model fallback, cycle-shortcut conflict/no-op behavior, icon propagation,
and start-time freezing while cycling or saving an edit mid-dictation.

## Compatibility hazards to carry into planning

| Hazard | Required protection |
| --- | --- |
| Any decode failure currently overwrites `modes.json` with defaults. | Detect schema, decode legacy separately, migrate in memory, validate, then atomically write; preserve the original on any failure. |
| Names are identity everywhere, and `Mode.name` can disagree with its dictionary key. | Introduce one stable Mode ID and one ordered source of truth; make name display data with uniqueness validation. |
| Legacy files may already have different LLM models/prompts/vocabulary per Mode. | Migrate each Mode independently; never seed all Modes from `Config.llmModel`. |
| `expands` is name-derived and not persisted. | Infer legacy transformation type once, then persist it so rename cannot alter behavior. |
| `Voice to Text` is currently an ordinary, editable dictionary entry. | Define a lossless rule for legacy customizations/name collisions before extracting it as the protected system option. |
| Current raw custom Modes and empty prompts are valid. | Decide how legacy-invalid target Modes remain usable without silent deletion or blanket coercion. |
| Mode changes during recording affect the current session. | Snapshot stable identity plus the full Mode value at start; test switch/edit/delete before stop and after stop. |
| History has only a name; a required new ID would make legacy JSONL lines disappear. | Keep the name snapshot and add an optional ID/custom decoder; specify renamed/deleted/pre-ID icon fallback. |
| Menu items use titles as identity and the menu bar roster is built once. | Project stable-ID menu items; rebuild on library changes, refresh checks on active-only changes. |
| Settings is snapshot-based and `commit()` rewrites unrelated preferences. | Give the Mode sheet a local draft and narrow Save operation; subscribe/repopulate on committed library changes. |
| LLM install auto-selects globally; uninstall checks only one global selection. | Separate inventory from assignment and calculate all referencing Modes before uninstall. |
| Hotkeys can conflict today and PTT silently wins. | Add one normalized conflict rule before persistence and extend the pure dispatcher to cycle. |
| Surface selection actions discard save errors. | Surface/rollback failed Mode mutations so disk, Config, checks, and Badge feedback cannot diverge silently. |

## Likely planning seams

1. **Versioned Mode schema and migrator.** Define stable ID, name, icon,
   transformation type, model, prompt, vocabulary, and ordered collection; preserve
   global ASR and other top-level preferences. Separate legacy decode, migration,
   validation, and atomic persistence so `loadOrCreate` cannot destroy data.
2. **Config-owned Mode library.** Replace direct dictionary mutation with narrow
   create/duplicate/update/reorder/delete/select/cycle operations and typed
   library-versus-selection change events. Define active deletion and zero-library
   behavior around the protected system option.
3. **Start-time dictation snapshot.** Capture the selected stable ID and full Mode
   value at `startRecording`, use it through Polish/History, and ensure later cycle
   or editor Saves affect only the next session.
4. **History compatibility and resolution.** Add optional Mode ID while retaining
   the name snapshot; centralize current-name/icon resolution and deleted/legacy
   fallback before feeding `DictationRowPresentation` and Re-run Polish commands.
5. **Surface projections/reactors.** Give menu bar, Badge menu/feedback, Settings,
   and History small ID-keyed presentation values fed by Config changes. Keep
   AppKit/SwiftUI shells declarative and non-activating where required.
6. **Draft editor and model inventory split.** Validate unique name, curated icon,
   type, installed model, non-empty prompt, and vocabulary in an isolated draft;
   Save one Config operation. Make Models inventory-only and make uninstall aware
   of every referencing Mode.
7. **Cycle shortcut contract.** Persist an optional third hotkey, validate conflicts
   with both dictation shortcuts, extend the dispatcher/listener/composition root,
   and drive a testable Badge transition without changing an in-flight snapshot.
8. **Migration and lifecycle test matrix.** Pin legacy field preservation,
   deterministic/stable ID creation, old History decoding, active rename/delete,
   zero Modes, menu projections, install/uninstall references, shortcut conflicts,
   and start/stop mutation timing before implementing the UI shell.

These seams preserve the accepted architecture: Config remains the persistence
and propagation authority (ADR-0003), Pipeline keeps value/closure/protocol seams
and composition-root construction (ADR-0002), Polish remains inert text-to-paste
with its current fallback behavior (ADR-0004), and ASR selection remains global
(ADR-0006)
([ADR-0002:31-53](../adr/0002-pipeline-hybrid-seams.md#L31-L53),
[ADR-0003:24-40](../adr/0003-config-owns-change-propagation.md#L24-L40),
[ADR-0004:33-60](../adr/0004-polish-output-is-inert-text-to-paste.md#L33-L60),
[ADR-0006:30-56](../adr/0006-global-asr-selection-over-revived-asr-model.md#L30-L56)).
