# Ollama detection and Guided setup capabilities on macOS

Audit date: 2026-07-26

Repository snapshot: `6bba99964892f6ee91a805a3c20160c3fc8766d1`

Scope: what the Developer ID build of FoldWise can truthfully detect and do to
move a person from no known Ollama service to a working local Polish model.

## Executive answer

FoldWise can distinguish a reachable Ollama with zero models from an unreachable
endpoint, but it cannot exhaustively distinguish **not installed** from
**installed but stopped**. A successful `GET /api/version`, followed by a
successful `GET /api/tags`, proves that an Ollama-compatible service is
responding at FoldWise's configured endpoint and tells whether its local model
inventory is empty. When that endpoint is unreachable, finding the registered
Ollama application or a Homebrew formula is positive evidence of an
installation. Failing to find either is only **Ollama not detected**, because
Ollama supports a nonstandard app location, a changed model location, and a
changed server address
([Ollama version API](https://docs.ollama.com/api-reference/get-version),
[list-models API](https://docs.ollama.com/api/tags),
[macOS install locations](https://docs.ollama.com/macos),
[server configuration](https://docs.ollama.com/faq#how-do-i-configure-ollama-server)).

FoldWise can start a discovered `Ollama.app` with `NSWorkspace` under its
current signing profile. That should be an explicit **Start Ollama** action,
followed by HTTP readiness polling; it should not happen merely because a
screen appeared. Starting the current Ollama app can register its own background
login item and can prompt to create an `ollama` CLI symlink, so this is a
user-visible trust decision, not a neutral health probe
([Ollama login-item source](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/app/cmd/app/app_darwin.m#L371-L403),
[Ollama startup source](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/app/cmd/app/app.go#L160-L187)).

The app is technically capable of downloading or invoking an installer: it is
not App-Sandboxed and already executes a bounded external process. macOS does
not categorically forbid installation here. FoldWise nevertheless has no
Ollama payload, installer, privileged-helper/authorization workflow, integrity
verification, update ownership, or installation rollback. Installing software
or mutating a person's Homebrew installation is therefore not a supported or
honest setup promise. Guided setup should explain the dependency, open the
official download page, and offer copyable commands; after Ollama is responding,
FoldWise can own the model pull
([FoldWise signing profile](../../scripts/build_swift_app.py#L182-L220),
[existing bounded process](../../Sources/FoldWiseVoiceKit/SystemIntegrations/AudioDucking/AudioDucker.swift#L9-L57),
[official macOS installation](https://docs.ollama.com/macos#filesystem-requirements)).

The existing model-pull path is the right implementation seam, but not reusable
unchanged as a durable setup contract. It already streams progress, serializes
Polish-model mutations, retains target-specific failures, and refreshes
inventory. It still needs a typed availability result, cancellation ownership,
terminal-success validation, migration from deprecated request key `name` to
`model`, and explicit recovery/readiness behavior
([`OllamaClient.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L100-L157),
[`SettingsWorkflow.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L480-L541)).

Offer `qwen2.5:3b` for the first pull for now. It is FoldWise's configured and
tested default, its Ollama artifact is 1.9 GB, and its first-party catalog
describes strong instruction following and multilingual support. This is a
compatibility recommendation, not a claim that it remains the best small model:
newer Qwen 3/3.5 variants exist, but they are larger, advertise thinking
behavior, and have not been tested against FoldWise's transformation and
off-task contracts
([`ModelCatalog.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/ModelCatalog.swift#L18-L70),
[Ollama `qwen2.5:3b`](https://ollama.com/library/qwen2.5:3b),
[Ollama `qwen3:4b`](https://ollama.com/library/qwen3:4b),
[Ollama `qwen3.5:4b`](https://ollama.com/library/qwen3.5:4b)).

## 1. Distinguishing installation and runtime states

### What each signal actually proves

| Signal | Positive result proves | It does **not** prove |
| --- | --- | --- |
| `GET http://localhost:11434/api/version` with a 2xx response and a string `version` | An Ollama-compatible HTTP service is responding at the endpoint FoldWise uses. This is Ollama's documented health/version endpoint. | That the GUI app or Homebrew installed it, that the version is supported by FoldWise, or that any models exist. Another local process could imitate the small response shape. |
| `GET /api/tags` with a 2xx response and a decoded `models` array | The service exposes Ollama's inventory API. `models: []` is the exact **running with zero local models** state. | Installation origin, whether a model is presently loaded into memory, or whether a later pull/inference will succeed. `/api/ps`, not `/api/tags`, is the running-memory inventory. |
| `NSWorkspace.urlForApplication(withBundleIdentifier: "com.electron.ollama")` returns a URL | Launch Services knows an available app with Ollama's current official bundle identifier. It also handles Ollama's supported non-`/Applications` location. | That its HTTP server is healthy, that a CLI-only installation exists, or that an unregistered app bundle does not exist. |
| Homebrew reports the `ollama` formula installed | The CLI/formula installation exists. The current formula declares `ollama serve` as its service command. | That `brew services` registered it, that launchd started it, or that the service is healthy at port 11434. |
| A launchd/Homebrew service record exists | A service was registered. `brew services info ollama --json` can report Homebrew-managed state. | That the executable still exists or the HTTP server is responsive. Service files and registrations can be stale. |
| `/Applications/Ollama.app`, `/opt/homebrew/bin/ollama`, `/usr/local/bin/ollama`, or `~/.ollama/models` exists | Only that one conventional path exists. | A complete current installation. The app may live elsewhere; the CLI symlink may outlive the app; `~/.ollama` may outlive uninstall; `OLLAMA_MODELS` may relocate model data. |

Ollama documents `GET /api/version` and `GET /api/tags` separately, and the tags
response explicitly contains the local model array
([version API](https://docs.ollama.com/api-reference/get-version),
[tags API](https://docs.ollama.com/api/tags)). The official app currently uses
bundle identifier `com.electron.ollama`
([upstream `Info.plist`](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/app/darwin/Ollama.app/Contents/Info.plist#L5-L18)).
Apple's `NSWorkspace` can resolve applications by bundle identifier rather than
assuming a filesystem path
([`urlForApplication(withBundleIdentifier:)`](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication%28withbundleidentifier%3A%29)).

The current Homebrew formula conflicts with the GUI cask and defines its service
as `ollama serve`; the cask installs both `Ollama.app` and its embedded CLI
([formula source](https://github.com/Homebrew/homebrew-core/blob/07fac44cae95d2147d77797a654161e3be9e360c/Formula/o/ollama.rb#L47-L48),
[formula service](https://github.com/Homebrew/homebrew-core/blob/07fac44cae95d2147d77797a654161e3be9e360c/Formula/o/ollama.rb#L122-L130),
[cask source](https://github.com/Homebrew/homebrew-cask/blob/eb81f6ea7c4c30ed59e8aa6ecb8a81e8f514b284/Casks/o/ollama-app.rb#L16-L23)).
Homebrew documents that unsudoed services use the current user's
`~/Library/LaunchAgents`, and that `services start` registers launch-at-login
while `services run` starts without that registration
([Homebrew `services` manual](https://docs.brew.sh/Manpage#services-subcommand)).

Filesystem probes are weak negative evidence. Ollama recommends
`/Applications/Ollama.app` but expressly permits another app location. It stores
models under `~/.ollama/models` by default, while `OLLAMA_MODELS` can change that
location; its full uninstall instructions remove the application and
`~/.ollama` separately, so leftover data is expected
([Ollama macOS docs](https://docs.ollama.com/macos),
[model-location FAQ](https://docs.ollama.com/faq#where-are-models-stored)).

### Truthful state vocabulary

The Guided setup state should preserve uncertainty rather than force every machine into
the ticket's three informal labels:

| HTTP result | Positive installation evidence | Truthful presentation |
| --- | --- | --- |
| Version and tags succeed; models nonempty | Irrelevant | **Ollama is ready**; show installed inventory. |
| Version and tags succeed; models empty | Irrelevant | **Ollama is running; no models installed**; offer the first pull. |
| Version succeeds; tags fails or has an invalid shape | Irrelevant | **Ollama responded, but FoldWise couldn't read its models**; show the actual compatibility/HTTP error. Do not call this zero models. |
| Endpoint cannot be reached | Registered app found | **Ollama is installed but not responding here**; offer explicit app launch and Retry. “Stopped” is a likely explanation, not the only one. |
| Endpoint cannot be reached | Homebrew formula found | **Ollama is installed but not responding here**; explain the service command and Retry. |
| Endpoint cannot be reached | No positive evidence | **FoldWise couldn't find Ollama**; offer official download/help and copyable commands. Do not state “Ollama is not installed.” |

“Not responding here” matters because FoldWise hard-codes
`http://localhost:11434` for tags, pull, delete, and chat
([`Config.swift`](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L1-L7)),
while Ollama supports changing `OLLAMA_HOST`
([Ollama configuration FAQ](https://docs.ollama.com/faq#how-do-i-configure-ollama-server)).
An installed or even running service configured on another address is
indistinguishable from stopped at FoldWise's current boundary.

### Recommended probe

1. Make a short-timeout `GET /api/version` request and preserve transport,
   timeout, non-2xx, and decoding failures as typed results.
2. Only after a valid version response, request `/api/tags`. Preserve a valid
   empty array instead of collapsing it into failure.
3. If HTTP is unavailable, ask Launch Services for the current official app
   bundle identifier.
4. Optionally add Homebrew evidence by executing an already-discovered,
   absolute `brew` path and requesting machine-readable information. Do not
   launch a shell or infer an executable from FoldWise's GUI-launch `PATH`.
5. If all probes are negative, report **not detected** and let the person retry
   after a nonstandard installation.

Today `listModels()` returns `[]` for a valid empty inventory, transport errors,
non-2xx responses, invalid JSON, and invalid response shapes
([`OllamaClient.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L100-L115)).
The `installed` setting then interprets every empty array as “Ollama down”
([`SettingsModel.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsModel.swift#L78-L82),
[`SettingsModel.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsModel.swift#L320-L337)).
The first required implementation change is therefore a typed client result,
not an additional UI condition around the existing array.

## 2. Starting an Ollama installation FoldWise did not create

### `Ollama.app`

This is technically straightforward:

1. Resolve `com.electron.ollama` through `NSWorkspace`.
2. Launch that exact URL with
   `openApplication(at:configuration:completionHandler:)`.
3. Use an `NSWorkspace.OpenConfiguration` with `activates = false` and launch
   arguments `hidden` and `--fast-startup`.
4. Poll FoldWise's `/api/version` endpoint with a bounded deadline, then refresh
   `/api/tags`. Treat launch success and server readiness as separate events.

Apple documents both app launching and launch arguments on
`NSWorkspace.OpenConfiguration`
([launch API](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication%28at%3Aconfiguration%3Acompletionhandler%3A%29),
[open configuration](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration),
[arguments](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/arguments)).
Arguments are ignored for a sandboxed caller, but FoldWise is not sandboxed:
its release signing step applies only the audio-input entitlement and never
`com.apple.security.app-sandbox`
([`build_swift_app.py`](../../scripts/build_swift_app.py#L182-L220)).

The proposed arguments are current upstream behavior, not invented flags.
Ollama recognizes `hidden` and `--fast-startup`, and its own CLI launches the app
hidden, requests fast startup, then waits for the server
([app argument handling](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/app/cmd/app/app.go#L60-L100),
[Ollama CLI startup](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/cmd/start_darwin.go#L13-L32)).
Because they are not a versioned public FoldWise contract, launch failure or
future flag drift must fall back to “Open Ollama yourself,” never strand setup.

The trust cost remains material. Current Ollama startup may register its bundled
launch agent as a login item and checks/creates a CLI symlink. FoldWise should
explain “This opens your installed Ollama app in the background” before the
action, never auto-launch during a passive probe, and show the other app's own
prompt rather than trying to bypass it
([login registration](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/app/cmd/app/app_darwin.m#L371-L403),
[startup sequence](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/app/cmd/app/app.go#L160-L187)).

### Homebrew formula

FoldWise could execute an absolute Homebrew binary with `Process`; its current
profile needs no new entitlement for that user-level process. That does not make
silent service mutation appropriate. Homebrew defines:

- `brew services run ollama`: start without registering launch-at-login;
- `brew services start ollama`: start now **and register** launch-at-login;
- unsudoed service management: the current user's LaunchAgent, with no
  system-daemon privilege escalation.

Those effects are Homebrew's documented contract
([Homebrew manual](https://docs.brew.sh/Manpage#services-subcommand)).
If FoldWise ever offers a service-start button, it should be shown only after a
positive formula probe, name the exact command/effect, require a click, capture
bounded output, and poll HTTP afterward. `run` is the less persistent default;
`start` should be a separately disclosed choice. Do not invoke `sudo`, manipulate
launchd plists directly, or assume Homebrew's prefix.

The lower-trust initial product is the settled one: show and copy
`brew services start ollama`, let the person run it in Terminal, then provide
Retry. It avoids making FoldWise the owner of another package manager's service
state.

## 3. Installing Ollama

The honest answer is **not as a FoldWise-owned setup operation**, but not because
an entitlement makes it impossible.

FoldWise is a non-sandboxed Developer ID app. Apple documents that a
non-sandboxed macOS app can access files outside an app container, subject to
ordinary filesystem permissions
([Apple file-system guidance](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively#Access-the-rest-of-the-file-system-in-a-non-sandboxed-macOS-app)).
The repository also already uses `Process` for a bounded `/usr/bin/osascript`
integration
([`AudioDucker.swift`](../../Sources/FoldWiseVoiceKit/SystemIntegrations/AudioDucking/AudioDucker.swift#L9-L57)).
It could therefore technically download an archive into a writable location,
launch an official installer, or invoke a user-installed Homebrew.

Doing so safely would create a new product subsystem that does not exist:

- select and pin an official distribution source;
- verify transport, expected artifact, code signature, and version;
- handle replacement, quarantine, permissions, relocation, and rollback;
- obtain explicit authorization for any privileged write rather than embedding
  credentials or calling `sudo`;
- own partial downloads, failures, cancellation, and cleanup;
- decide whether FoldWise or Ollama owns future updates;
- support both the GUI cask and CLI formula without installing conflicting
  Homebrew packages.

Ollama's preferred macOS path is a DMG and explicit drag to `/Applications`; on
first start its app may ask permission to create `/usr/local/bin/ollama`
([Ollama macOS docs](https://docs.ollama.com/macos#filesystem-requirements)).
Homebrew exposes distinct formula and cask installations, and the formula
explicitly conflicts with the cask
([formula](https://formulae.brew.sh/formula/ollama),
[cask](https://formulae.brew.sh/cask/ollama-app),
[conflict declaration](https://github.com/Homebrew/homebrew-core/blob/07fac44cae95d2147d77797a654161e3be9e360c/Formula/o/ollama.rb#L47-L48)).

Guided setup should therefore say:

> FoldWise uses Ollama for local Polish. FoldWise can download the model after
> Ollama is running, but it does not install Ollama itself.

Offer the official macOS download page as the primary path. Copyable Homebrew
alternatives can be explicit about the two shapes:

```bash
# CLI service
brew install ollama
brew services start ollama

# Or the official GUI app through Homebrew
brew install --cask ollama-app
open -a Ollama
```

These commands match the current Homebrew formula/cask and service contract
([Homebrew formula](https://formulae.brew.sh/formula/ollama),
[Homebrew cask](https://formulae.brew.sh/cask/ollama-app),
[Homebrew services](https://docs.brew.sh/Manpage#services-subcommand)).

## 4. Reusing the existing pull path

### Reusable now

| Existing behavior | Setup reuse |
| --- | --- |
| `OLLAMA_PULL_URL` points to local `POST /api/pull`. | Use the same local-server boundary; do not run `ollama pull` as a child command when the HTTP API already provides the operation. |
| `OllamaClient.pull` requests a streamed response and parses NDJSON `status`, `completed`, and `total`. | Reuse progress text and fraction reporting. Ollama's API defines streamed status updates and `stream: true` by default. |
| `LiveLLMModelManager` adapts the client to `LLMModelManaging`. | Keep the production effect behind this test seam. |
| `SettingsWorkflow` excludes concurrent pull/delete mutations, records per-target failures, retains failed custom input, and refreshes inventory on success. | If setup remains within the existing Settings lifetime, call the same workflow operation for the seeded model. If setup has a separate lifetime, extract a small shared Polish-model lifecycle rather than duplicating HTTP logic. |
| The Models projection keeps progress and target-specific error state visible. | Reuse its presentation grammar, while giving Guided setup its own step copy and next-state transition. |

Sources:
[`Config.swift`](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift#L1-L7),
[`OllamaClient.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L117-L157),
[`OllamaTransport.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaTransport.swift#L1-L42),
[`AppMain.swift`](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift#L10-L28),
[`SettingsWorkflow.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L480-L541),
[Ollama pull API](https://docs.ollama.com/api/pull).

### Required hardening

1. **Use the current request field.** FoldWise sends
   `{"name": model, "stream": true}`. Current Ollama documents required field
   `model`; upstream still accepts `name` only as a deprecated compatibility
   alias. Change FoldWise to `{"model": model, "stream": true}` before setup
   relies on it
   ([FoldWise request](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L117-L132),
   [Ollama `PullRequest`](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/api/types.go#L777-L787),
   [server compatibility fallback](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/server/routes.go#L1101-L1112)).
2. **Require terminal success.** Ollama's documented stream ends with
   `status: "success"`. The current client returns success whenever a 2xx line
   sequence ends without throwing, even if every line is malformed or the
   stream ends before success. Track terminal status; return a typed incomplete
   response error unless success was observed
   ([Ollama upstream API description](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/docs/api.md#L1561-L1629),
   [current FoldWise loop](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L133-L157)).
3. **Retain a cancelable operation.** `SettingsWorkflow` creates an unretained
   `Task` and exposes no Polish cancellation method. Retain a task/operation
   token, cancel the URLSession byte stream, make late progress inert, and
   distinguish user cancellation from failure. The transport already cancels
   its producer when the line stream terminates, but this behavior needs an
   end-to-end cancellation test
   ([workflow task](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift#L500-L541),
   [stream transport](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaTransport.swift#L18-L38)).
4. **Make retry explicit.** The existing target action can be invoked again
   after failure and Ollama says canceled pulls resume from downloaded data.
   Label the post-failure action **Retry**, preserve the server's safe error
   message, and re-probe readiness if the failure was connectivity-related
   ([Ollama resume contract](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/docs/api.md#L1561-L1568),
   [upstream completed-blob reuse](https://github.com/ollama/ollama/blob/64ee2f9847ccaedd8f05a139c30f086e9e0abe73/x/transfer/download.go#L96-L120),
   [`ModelsWorkspaceProjection.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/ModelsWorkspaceProjection.swift#L1127-L1149)).
5. **Separate server readiness from installation evidence.** A model pull is
   enabled only after typed version/tags success. If Ollama dies during setup,
   return to the start/retry state without losing the known installation
   evidence.
6. **Treat disk checks as advisory.** Ollama stores models at
   `~/.ollama/models` by default but can use `OLLAMA_MODELS`, and the HTTP API
   does not report the server's model directory. FoldWise cannot reliably check
   the correct volume for every local configuration. Show the 1.9 GB artifact
   size and recommend additional free headroom; let Ollama report an actual
   write failure. A local capacity preflight is useful only when FoldWise can
   identify the storage volume, and it must not hard-block on an estimate.

Apple provides `volumeAvailableCapacityForImportantUsage` for an advisory
capacity check
([capacity API](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacityforimportantusage)).
Apple marks the API as a potential fingerprinting surface and identifies
`E174.1` as the approved reason for observable sufficient-space behavior where
a distribution is required to declare API reasons; FoldWise should keep that
policy constraint with any future distribution work
([required reason](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)).
The model-location uncertainty still means capacity is informative rather than
authoritative.

## 5. Opening Ollama web pages

Opening an official HTTPS page after a direct click is appropriate and requires
no new FoldWise entitlement under the current non-sandboxed profile.
`NSWorkspace.open(_:)` opens a URL with its registered handler and returns
whether the open request was accepted
([Apple `open(_:)`](https://developer.apple.com/documentation/appkit/nsworkspace/open%28_%3A%29)).
FoldWise already uses `NSWorkspace` to open System Settings, so the platform
dependency is present; it has no current web-link action in `Sources/`
([`Permissions.swift`](../../Sources/FoldWiseVoiceKit/SystemIntegrations/Permissions/Permissions.swift#L34-L48)).

Use specific destinations:

- **Download Ollama** →
  [`https://ollama.com/download/mac`](https://ollama.com/download/mac)
- **macOS installation help** →
  [`https://docs.ollama.com/macos`](https://docs.ollama.com/macos)
- **Model details** →
  [`https://ollama.com/library/qwen2.5:3b`](https://ollama.com/library/qwen2.5:3b)

The generic `https://ollama.com` is safe but less useful than the task-specific
download page. Do not auto-open a browser on failed detection. If
`NSWorkspace.open` returns false, keep the URL visible/copyable and show a local
error; acceptance of the open request does not prove that the page loaded.

## 6. The first model to offer

### Recommendation

Keep `qwen2.5:3b` as the single Guided setup offer until a FoldWise-specific
comparison justifies a migration.

The concrete evidence for it is:

- all seeded editable Modes reference `qwen2.5:3b`, and the curated catalog
  calls it the default for multilingual Modes
  ([`Config.swift`](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift),
  [`ModelCatalog.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/ModelCatalog.swift#L18-L70));
- Ollama's current artifact is `qwen2.5:3b`, digest prefix `357c53fb659c`, 3.09B
  parameters, Q4_K_M, and **1.9 GB**
  ([Ollama catalog](https://ollama.com/library/qwen2.5:3b));
- the first-party Qwen/Ollama description emphasizes instruction following,
  resilience to system prompts, and multilingual support. Those properties
  align with FoldWise's short transformation prompts, although the catalog
  does not publish a Polish dictation-cleanup benchmark
  ([Ollama catalog readme](https://ollama.com/library/qwen2.5:3b)).

The download copy should say **“1.9 GB download”**, not imply 1.9 GB is the
maximum temporary or final disk impact. Manifests, shared layers, partial
download data, filesystem allocation, and future catalog retagging can change
the observed space. After installation, `/api/tags` supplies the actual local
size and FoldWise already formats that value
([tags response](https://docs.ollama.com/api/tags),
[`InstalledModel`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Polish/OllamaClient.swift#L82-L98)).

`qwen2.5:3b` is no longer the newest Qwen option. Ollama currently offers
`qwen3:4b` at 2.5 GB with a `thinking` capability and 100+ advertised languages,
and `qwen3.5:4b` at 3.4 GB with `thinking`, vision, and 201 advertised languages
([Qwen 3 catalog](https://ollama.com/library/qwen3:4b),
[Qwen 3.5 catalog](https://ollama.com/library/qwen3.5:4b)).
Those general catalog claims do not establish better FoldWise behavior. They
also add download and behavioral surface that the current OpenAI-compatible
request does not explicitly control. Promote a successor only after testing
Polish text, strict output-only compliance, off-task fallback, latency, memory,
and cancellation on FoldWise's supported Macs. Until then, changing the setup
model would make fresh installs diverge from the persisted default and the
repository's existing behavior without task-specific evidence.

## Resulting Guided setup boundary

The supported path is:

1. Probe `/api/version` and `/api/tags` into typed states.
2. If HTTP is unavailable, gather positive app/formula evidence; otherwise say
   “couldn't find,” not “not installed.”
3. Explain that FoldWise does not install Ollama. Offer the official download
   page and copyable app/formula commands.
4. For a discovered GUI app, offer an explicit background launch; for Homebrew,
   keep the service command copyable initially. Poll HTTP after either route.
5. When Ollama responds with an empty inventory, offer one in-app
   `qwen2.5:3b` pull with 1.9 GB copy, progress, cancellation, retry, and
   terminal-success validation.
6. Refresh `/api/tags` and complete setup only when the exact model is present.

This boundary is honest about ownership: FoldWise detects its HTTP dependency,
can start a user-installed GUI app with consent, and manages the model through
Ollama's API. The person or their package manager continues to own installation
and background-service policy.
