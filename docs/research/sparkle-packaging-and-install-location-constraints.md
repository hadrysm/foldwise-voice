# Sparkle packaging and install-location constraints

Research answer for
[Establish Sparkle's packaging and install-location constraints](https://github.com/hadrysm/foldwise-voice/issues/282),
audited at repository commit `b1f8502db2a4691aeab361f4eceb64778829d116`
on 2026-07-25. External claims below use only Sparkle's official
documentation, the Sparkle 2.9.4 release and source, and Apple's documentation.

## Executive answer

FoldWise should target and pin **Sparkle 2.9.4**. It is the current stable
release, published 2026-07-03, and its one change is directly relevant: a fix
for user-initiated Sparkle windows not reliably taking focus in backgrounded /
dockless applications
([2.9.4 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4),
[2.9.4 changelog](https://github.com/sparkle-project/Sparkle/blob/2.9.4/CHANGELOG#L1-L4)).

The distributable app must embed the complete `Sparkle.framework` at
`FoldWise Voice.app/Contents/Frameworks/Sparkle.framework`, preserving its
symlinks and executable permissions. In Sparkle 2.9.4 the framework contains
the Sparkle dynamic library, the **`Autoupdate` executable** (not
`Autoupdate.app`), **`Updater.app`**, resources, and two optional XPC services.
Sparkle's migration documentation confirms the helper names and locations, and
its publishing guide warns that following framework symlinks instead of
preserving them breaks the code signature
([Sparkle 2 helper paths](https://sparkle-project.org/documentation/upgrading/),
[archive requirements](https://sparkle-project.org/documentation/publishing/),
[official 2.9.4 SwiftPM artifact](https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-for-Swift-Package-Manager.zip)).

FoldWise is currently a non-sandboxed application, so it must **not** enable
`SUEnableInstallerLauncherService` or `SUEnableDownloaderService`. It may strip
the entire `XPCServices` directory and symlink from its copied framework before
signing. `Autoupdate` and `Updater.app` are not optional: the former extracts,
validates, and installs, while the latter shows installation progress and
relaunches the updated app
([sandboxing guide](https://sparkle-project.org/documentation/sandboxing/),
[installation design](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Documentation/Installation.md#L3-L18)).

The required manual signing direction is inside-out:

1. If retained, sign `Installer.xpc`, then `Downloader.xpc` while preserving
   its entitlements.
2. Sign `Versions/B/Autoupdate`.
3. Sign `Versions/B/Updater.app`.
4. Sign `Sparkle.framework`.
5. Sign the outer `FoldWise Voice.app` last, applying FoldWise's entitlements
   only to that app signature.

Every Developer ID signature in that sequence must use Hardened Runtime and a
secure timestamp. Sparkle publishes the exact helper order and explicitly says
not to use `--deep`; Apple likewise requires nested code to be signed from the
deepest component outward, with the top-level app last, and requires secure
timestamps for notarization
([Sparkle manual-signing instructions](https://sparkle-project.org/documentation/sandboxing/#code-signing),
[Apple: Creating distribution-signed code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
[Apple: Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Apple: Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html#//apple_ref/doc/uid/TP40005929-CH4-SW6)).

Sparkle is location-agnostic on a writable volume. A user-owned app in
`~/Applications` can update in place without elevation. Sparkle asks for
administrator authorization when it cannot write both the bundle and its parent
directory or cannot preserve the bundle's owner/group; an app on a read-only
volume or under App Translocation is rejected rather than elevated
([authorization test](https://github.com/sparkle-project/Sparkle/blob/2.9.4/InstallerLauncher/SUInstallerLauncher.m#L348-L405),
[read-only/translocation rejection](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUBasicUpdateDriver.m#L69-L84),
[installation design](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Documentation/Installation.md#L13-L27)).

`LSUIElement = true` is compatible with Sparkle's standard UI and relaunch.
Sparkle treats such an app as backgrounded, activates it for a user-initiated
check, and relaunches the installed bundle by path through `NSWorkspace`.
Scheduled alerts deliberately remain behind other apps except around launch, so
a menu-bar app should implement Sparkle's gentle-reminder hooks and expose a
notice in its own menu-bar UI
([Apple `LSUIElement`](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement),
[Sparkle focus behavior](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUStandardUserDriver.m#L129-L208),
[Sparkle relaunch](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/InstallerProgress/InstallerProgressAppController.m#L406-L438),
[gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/)).

## What must be embedded

The Sparkle 2.9.4 Swift package is a binary target that resolves to the official
`Sparkle-for-Swift-Package-Manager.zip` XCFramework. Its macOS slice contains
this runtime shape
([Sparkle 2.9.4 `Package.swift`](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Package.swift#L3-L25),
[official release assets](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4)):

```text
FoldWise Voice.app/
└── Contents/
    └── Frameworks/
        └── Sparkle.framework/
            ├── Sparkle -> Versions/Current/Sparkle
            ├── Autoupdate -> Versions/Current/Autoupdate
            ├── Updater.app -> Versions/Current/Updater.app
            ├── Resources -> Versions/Current/Resources
            ├── XPCServices -> Versions/Current/XPCServices  # optional here
            └── Versions/
                ├── Current -> B
                └── B/
                    ├── Sparkle
                    ├── Autoupdate
                    ├── Updater.app/
                    ├── Resources/
                    └── XPCServices/                         # optional here
                        ├── Installer.xpc/
                        └── Downloader.xpc/
```

`Sparkle.framework` is one nested framework. Do not copy only its `Sparkle`
Mach-O file, and do not copy the top-level symlink targets as ordinary
directories. Sparkle locates `Autoupdate` and `Updater.app` as auxiliary
executables relative to the framework, and its own build creates those
top-level helper symlinks for that lookup
([helper symlink creation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Configurations/link-tools.sh#L10-L16),
[helper lookup and launch](https://github.com/sparkle-project/Sparkle/blob/2.9.4/InstallerLauncher/SUInstallerLauncher.m#L486-L500)).

### XPC decision

The Installer XPC service exists to let a **sandboxed** host install outside its
sandbox. Sparkle says it is required for sandboxed apps and says
non-sandboxed apps should not enable it; the Downloader service is only for a
sandboxed host that lacks the outgoing-network entitlement. Sparkle also
documents removing all XPC services for a non-sandboxed app
([sandbox integration](https://sparkle-project.org/documentation/sandboxing/#integration),
[Sparkle settings](https://sparkle-project.org/documentation/customization/#sandboxing-settings),
[removing XPC services](https://sparkle-project.org/documentation/sandboxing/#removing-xpc-services)).

For FoldWise, the smallest valid framework therefore retains `Autoupdate`,
`Updater.app`, the framework binary/resources/symlinks, and removes both
`Versions/B/XPCServices` and the top-level `XPCServices` symlink. Removal must
happen **after copying but before signing** because removing nested content after
signing invalidates the framework's resource seal. Sparkle's own strip script
removes the versioned directory and the top-level symlink together
([Sparkle strip script](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Configurations/strip-framework.sh#L3-L32),
[Apple nested-code sealing](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html#//apple_ref/doc/uid/TP40005929-CH4-SW6)).

The repository's ADR-0001 is **not evidence about App Sandbox**. It decides
whether the Sandcastle agent runner uses Docker
([ADR-0001](../adr/0001-sandcastle-in-place-not-sandboxed.md)).
The application is non-sandboxed for a different, direct reason: its release
entitlements contain only `com.apple.security.device.audio-input` and never set
`com.apple.security.app-sandbox`
([build_swift_app.py:113-128](../../scripts/build_swift_app.py#L113-L128)).

## Signing sequence for this build system

Sparkle's prebuilt distribution is ad-hoc signed with Hardened Runtime for
development, but Sparkle says an alternative distribution workflow must
re-sign the framework and helpers with the application's certificate. Its
published order is XPC services, `Autoupdate`, `Updater.app`, then the framework;
the outer application follows because it seals the already-signed framework
([Sparkle code-signing guide](https://sparkle-project.org/documentation/sandboxing/#code-signing),
[Apple inside-out rule](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)).

For FoldWise's chosen no-XPC shape, the concrete release sequence is:

```text
copy complete Sparkle.framework, preserving symlinks and modes
remove Versions/B/XPCServices and the top-level XPCServices symlink
codesign ... --options runtime --timestamp Sparkle.framework/Versions/B/Autoupdate
codesign ... --options runtime --timestamp Sparkle.framework/Versions/B/Updater.app
codesign ... --options runtime --timestamp Sparkle.framework
codesign ... --options runtime --timestamp --entitlements FoldWise.entitlements \
    "FoldWise Voice.app"
codesign --verify --deep --strict --verbose=2 "FoldWise Voice.app"
```

`--deep` belongs on recursive **verification**, not signing. Signing with it can
apply the same options and entitlements to helpers with different requirements;
Apple calls it unsuitable for normal signing, and Sparkle identifies it as a
common source of integration errors
([Apple guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
[Sparkle guidance](https://sparkle-project.org/documentation/sandboxing/#code-signing)).

If FoldWise elects not to strip the XPC services, both must be explicitly signed
before the other helpers. Sparkle 2.6 and later requires preserving metadata /
entitlements while signing `Downloader.xpc`; no FoldWise app entitlements should
be applied to the framework or helpers
([Sparkle helper commands](https://sparkle-project.org/documentation/sandboxing/#code-signing),
[Apple entitlement placement](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/#Configure-your-entitlements)).

## Install location, write access, and authorization

Sparkle does not require `/Applications` by name. For a regular app update, its
authorization preflight tests:

- whether the current bundle is writable;
- whether the bundle's parent directory is writable; and
- whether it can preserve the bundle's owner and group.

If those checks fail, the installer uses the system domain and, for an
interactive update, presents the administrator authorization prompt. If an
automatic/silent driver cannot interact, Sparkle retains the downloaded update
and defers authorization until a UI-driven attempt
([authorization source](https://github.com/sparkle-project/Sparkle/blob/2.9.4/InstallerLauncher/SUInstallerLauncher.m#L348-L405),
[interactive deferral](https://github.com/sparkle-project/Sparkle/blob/2.9.4/InstallerLauncher/SUInstallerLauncher.m#L462-L480),
[installer design](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Documentation/Installation.md#L13-L27)).

Consequently:

- A normally copied, user-owned `~/Applications/FoldWise Voice.app` and its
  user-owned parent are writable and update without an admin prompt.
- `/Applications/FoldWise Voice.app` also works. Whether it prompts depends on
  the installing user's access and the bundle's ownership, not on the literal
  `/Applications` path.
- A root-owned or other-user-owned app can update, but Sparkle may request admin
  authorization.
- A read-only disk image, read-only volume, temporary location, or translocated
  launch cannot be repaired by authorization; Sparkle aborts and directs the
  user to copy the app into Applications and relaunch it.

These conclusions follow from Sparkle's permission tests and read-only-volume
guard rather than from assumptions about conventional install paths
([permission test](https://github.com/sparkle-project/Sparkle/blob/2.9.4/InstallerLauncher/SUInstallerLauncher.m#L348-L382),
[read-only guard](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUBasicUpdateDriver.m#L69-L84)).

The existing fallback from `/Applications` to `~/Applications` is therefore
compatible with Sparkle, and the use of `copytree(..., symlinks=True)` when
installing the completed app is the correct behavior once it contains
`Sparkle.framework`
([build_swift_app.py:225-237](../../scripts/build_swift_app.py#L225-L237),
[Sparkle symlink requirement](https://sparkle-project.org/documentation/publishing/)).

## `LSUIElement`, UI, termination, and relaunch

Apple defines `LSUIElement` as making the app an agent that runs without a Dock
icon. The corresponding `.accessory` activation policy still permits windows
and programmatic activation
([Apple `LSUIElement`](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement),
[Apple accessory activation policy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)).

Sparkle detects that accessory policy as a background application. In 2.9.4 it
uses explicit activation for permission prompts and user-initiated checks, so
its standard windows work in an `LSUIElement` app. This is the reason not to
target 2.9.3 or older for FoldWise: 2.9.4 fixes unreliable focus specifically
for backgrounded user-initiated actions
([background-app detection](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUApplicationInfo.m#L15-L20),
[user-initiated activation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUStandardUserDriver.m#L129-L155),
[2.9.4 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4)).

Scheduled checks behave differently by design. Except just after launch,
Sparkle shows a dockless app's scheduled alert behind other apps rather than
stealing focus, logs a warning when a background app has not declared gentle
reminder support, and may still need to surface UI when installation needs
authorization. FoldWise should use `SPUStandardUserDriverDelegate` gentle
reminders to light its existing menu-bar update affordance while leaving
Sparkle's standard install UI available
([scheduled alert source](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUStandardUserDriver.m#L160-L208),
[gentle-reminder guide](https://sparkle-project.org/documentation/gentle-reminders/)).

For installation, `Updater.app` sends the running app a normal terminate
request, waits for termination, and opens the installed bundle path through
`NSWorkspace` when relaunch was requested. `LSUIElement` does not change that
path-based relaunch, and the new process again becomes an accessory app from its
Info.plist. FoldWise may delay or veto relaunch through Sparkle's updater
delegate if dictation or another critical operation is active
([terminate and relaunch source](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/InstallerProgress/InstallerProgressAppController.m#L394-L438),
[`SPUUpdaterDelegate` relaunch hooks](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUUpdaterDelegate.h#L343-L374)).

## Development and release bundle names

Sparkle recommends that the update archive contain an `.app` with the same
filename as the version it replaces. FoldWise's release-to-release path obeys
that rule: the installed and incoming production bundles are both
`FoldWise Voice.app`
([Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/),
[build_swift_app.py:251-257](../../scripts/build_swift_app.py#L251-L257)).

The `FoldWise Voice Native.app` development name does **not** by itself block an
update. Sparkle first searches the archive for the running bundle filename or
display name, then falls back to an incoming bundle with the same bundle
identifier. With default name normalization disabled, it replaces the host at
the host's existing path rather than renaming it to the incoming filename
([incoming-bundle matching](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUInstaller.m#L35-L112),
[installation-path selection](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUInstaller.m#L274-L290),
[normalization default](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Configurations/ConfigCommon.xcconfig#L88-L94)).

That means a development app pointed at the production appcast could replace
`FoldWise Voice Native.app` with production bundle contents and then relaunch
that same `...Native.app` path. The shared bundle identifier also gives both
copies the same application preferences domain and the same bundle-ID-derived
Sparkle installer/status service names
([Sparkle defaults selection](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUHost.m#L41-L69),
[service-name derivation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SPUMessageTypes.m#L14-L18),
[service-name implementation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SPUMessageTypes.m#L63-L84)).

Therefore the name mismatch is not a Sparkle validation failure, but two live
copies with the same identifier are an avoidable operational hazard. Choose one
of these boundaries:

1. Preferred: keep the release identifier for release builds and give local
   development bundles a development-only bundle identifier.
2. If TCC continuity requires keeping the identifier, compile or configure the
   development bundle not to instantiate/start Sparkle and do not point it at
   the production appcast.

Production archives should continue to contain exactly `FoldWise Voice.app`.

## Pure SwiftPM integration

Sparkle 2.9.4's manifest exposes a `Sparkle` library product backed by the
official binary XCFramework. FoldWise's manifest should pin that release and
add the product to the target that imports Sparkle—currently
`FoldWiseVoiceKit`, where `AppMain` and update integration live
([Sparkle manifest](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Package.swift#L3-L25),
[FoldWise manifest](../../Package.swift),
[AppMain.swift:218-221](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift#L218-L221)).

```swift
dependencies: [
    // existing packages...
    .package(
        url: "https://github.com/sparkle-project/Sparkle.git",
        exact: "2.9.4"
    ),
],
targets: [
    .target(
        name: "FoldWiseVoiceKit",
        dependencies: [
            // existing products...
            .product(name: "Sparkle", package: "Sparkle"),
        ]
    ),
    .executableTarget(
        name: "FoldWiseVoice",
        dependencies: ["FoldWiseVoiceKit"],
        linkerSettings: [
            .unsafeFlags([
                "-Xlinker", "-rpath",
                "-Xlinker", "@loader_path/../Frameworks",
            ]),
        ]
    ),
    // ...
]
```

Pinning exactly `2.9.4` makes the audited helper layout and signing sequence
reproducible. A dependency-bump change can intentionally re-audit future
Sparkle releases instead of allowing a packaging dependency to drift
implicitly.

`swift build` links the binary target, but FoldWise—not Xcode—constructs the
`.app`. The Python bundler must therefore locate the resolved XCFramework's
macOS `Sparkle.framework`, copy the whole framework to `Contents/Frameworks`
with symlinks and modes preserved, optionally strip the XPC services, and
perform the inside-out signing sequence. The executable must also carry a
runpath to `@loader_path/../Frameworks`; without Xcode, Sparkle explicitly
requires the equivalent linker flags. Sparkle's setup guide says custom
copying/packaging must preserve symlinks and permissions, and its own package
manifest shows that SwiftPM supplies an XCFramework binary artifact rather than
source that can be flattened into FoldWise's executable
([Sparkle basic setup](https://sparkle-project.org/documentation/),
[Sparkle package binary target](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Package.swift#L15-L24)).

Because FoldWise has no MainMenu nib, it must create and retain
`SPUStandardUpdaterController` programmatically on the main actor and route its
existing “Check for Updates” actions to that controller/updater. Sparkle
provides this exact pure-code path; the controller targets the main bundle,
uses the standard user interface, and must be retained
([programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[`SPUStandardUpdaterController` reference](https://sparkle-project.org/documentation/api-reference/Classes/SPUStandardUpdaterController.html)).

The generated Info.plist must also gain an HTTPS `SUFeedURL` and the Ed25519
public key as `SUPublicEDKey`; Sparkle compares increasing `CFBundleVersion`
values. FoldWise already emits a version into `CFBundleVersion`, but has neither
Sparkle key today
([Sparkle basic configuration and publishing](https://sparkle-project.org/documentation/),
[build_swift_app.py:76-91](../../scripts/build_swift_app.py#L76-L91)).

## Current-repository comparison

| Constraint | Current state | Verdict |
| --- | --- | --- |
| Sparkle dependency and product | `Package.swift` contains FluidAudio and WhisperKit only; `Package.resolved` has no Sparkle pin ([Package.swift:7-20](../../Package.swift#L7-L20), [Package.resolved](../../Package.resolved)). | **Violation / absent.** Add exact 2.9.4 dependency and product. |
| Framework embedding | The bundler creates only `Contents/MacOS` and `Contents/Resources`, then copies one executable ([build_swift_app.py:67-74](../../scripts/build_swift_app.py#L67-L74), [build_swift_app.py:102-109](../../scripts/build_swift_app.py#L102-L109)). | **Violation.** No `Contents/Frameworks/Sparkle.framework` or required helpers can exist. |
| Framework runpath | The executable target declares no linker settings ([Package.swift:22-25](../../Package.swift#L22-L25)). | **Violation / absent.** Add `@loader_path/../Frameworks` to the executable's runpaths. |
| Preserve framework symlinks | No framework copy step exists. Final local app installation does preserve symlinks ([build_swift_app.py:225-233](../../scripts/build_swift_app.py#L225-L233)). | **Violation at bundle construction; compatible at final install.** The framework copy must also preserve symlinks and modes. |
| XPC services | The release app's only generated entitlement is audio input; it is not App Sandbox enabled ([build_swift_app.py:113-128](../../scripts/build_swift_app.py#L113-L128)). | **Compatible with no-XPC route.** Strip both services and do not add `SUEnable*Service` keys. ADR-0001 is unrelated to this determination. |
| Nested signing | The script signs only the outer app, passes `--deep`, and omits `--timestamp`, with the app entitlements on that operation ([build_swift_app.py:113-128](../../scripts/build_swift_app.py#L113-L128)). | **Violation.** Replace with timestamped helpers → framework → app signing; reserve `--deep` for verification. |
| Install location | Local install tries `/Applications`, then `~/Applications`, and preserves symlinks ([build_swift_app.py:225-237](../../scripts/build_swift_app.py#L225-L237)). | **Compatible.** `~/Applications` is a good no-elevation fallback when user-owned. |
| Read-only launch | The DMG includes an `/Applications` alias to encourage copying out ([build_swift_app.py:131-150](../../scripts/build_swift_app.py#L131-L150)). | **Compatible.** Sparkle will refuse to update a copy launched on the mounted DMG, as designed. |
| Dockless UI | `LSUIElement` is true ([build_swift_app.py:76-86](../../scripts/build_swift_app.py#L76-L86)); the current custom manual alert explicitly activates the app ([AppMain.swift:242-275](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift#L242-L275)). | **Compatible with Sparkle 2.9.4.** Add a gentle-reminder delegate/menu-bar notice for scheduled Sparkle updates. |
| Bundle names and identifier | Local app is `FoldWise Voice Native.app`, release app is `FoldWise Voice.app`, both `com.foldwise.voice.native` ([build_swift_app.py:1-10](../../scripts/build_swift_app.py#L1-L10), [build_swift_app.py:31-34](../../scripts/build_swift_app.py#L31-L34)). | **Not a matching failure, but unsafe if dev Sparkle runs.** Use a dev bundle ID or disable Sparkle in dev. |
| Updater runtime | `UpdateChecker` only polls GitHub Releases and opens a browser/DMG; it never installs ([UpdateChecker.swift:1-14](../../Sources/FoldWiseVoiceKit/SystemIntegrations/Updates/UpdateChecker.swift#L1-L14)). | **Violation / not Sparkle.** Replace or wrap with a retained `SPUStandardUpdaterController`. |
| Sparkle Info.plist keys | Info.plist has versions and app metadata but no `SUFeedURL` or `SUPublicEDKey` ([build_swift_app.py:76-91](../../scripts/build_swift_app.py#L76-L91)). | **Violation / absent.** Both are needed for the intended signed appcast flow. |

## Implementation boundary established by this research

An implementation ticket can treat the following as fixed:

- Target exact Sparkle 2.9.4.
- Use the SwiftPM `Sparkle` product from the official repository.
- Embed the complete framework in `Contents/Frameworks`, preserving symlinks and
  executable modes.
- Link the executable with a runpath to `@loader_path/../Frameworks`.
- For the current non-App-Sandbox release, remove both XPC services and do not
  enable their Info.plist switches.
- Retain `Autoupdate` and `Updater.app`.
- Sign `Autoupdate` → `Updater.app` → `Sparkle.framework` → FoldWise app with
  Hardened Runtime and secure timestamps; never sign with `--deep`.
- Keep `~/Applications` fallback; expect no admin prompt for a user-owned copy.
- Use Sparkle 2.9.4 standard UI with a gentle-reminder/menu-bar bridge for the
  dockless app.
- Prevent the production updater from running in the same-bundle-ID development
  copy, or assign that copy a development bundle identifier.
- Add `SUFeedURL`, `SUPublicEDKey`, a retained programmatic updater controller,
  and route existing manual checks through it.
