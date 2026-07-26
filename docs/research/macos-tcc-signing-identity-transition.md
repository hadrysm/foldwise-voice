# macOS TCC behavior across a signing-identity transition

Research for [issue #280](https://github.com/hadrysm/foldwise-voice/issues/280),
current as of 2026-07-25. External sources are Apple documentation, Apple
Support, Apple engineering presentations, or Apple staff responses.

## Conclusions

1. **The first Developer ID build is new code to TCC.** macOS records the
   designated requirement (DR) of an app when granting access to a
   privacy-protected resource, and a later build must satisfy that original DR.
   Apple explicitly says an ad-hoc signature has a DR tied to that specific
   version of the code, so it cannot carry authorization reliably across
   versions. An ad-hoc `v0.16.x` build and the first Developer ID build therefore
   do not share the old grants; the Developer ID build needs fresh user consent
   ([TN3127, “Designated requirement”](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
2. **A normal re-grant is the supported recovery; `tccutil reset` is not a
   migration prerequisite.** The new build should request Microphone permission
   and direct the user to the Accessibility/Input Monitoring panes when their
   respective checks fail. If an enabled-looking row left by the old build does
   not grant the new build access, merely switching that stale row off and on is
   not documented by Apple as rebinding it to a new DR. The deterministic UI
   recovery is to remove the stale Accessibility/Input Monitoring row, add the
   installed Developer ID app, and enable it. Apple documents adding the current
   app in both panes, while its microphone documentation says apps request
   access and users may later change the decision in settings
   ([Privacy & Security settings](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac),
   [microphone authorization](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)).
3. **Reserve `tccutil` for troubleshooting and test reset.** Apple's microphone
   authorization guide puts `tccutil reset` under “Reset Authorization from
   Terminal” and says to use it to debug privacy prompts and localizations. It
   is not presented as an end-user grant mechanism. Apple DTS likewise calls it
   a basic testing tool and warns app developers against using it to make the
   system nag users for consent. The installed macOS `tccutil(1)` manual defines
   `reset` as erasing decisions so apps can prompt again; it does not grant
   access. A per-bundle reset can recover an unusually stuck database state, but
   release guidance should not require it in the ordinary transition
   ([Requesting authorization for media capture on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos),
   [Apple DTS on TCC testing](https://developer.apple.com/forums/thread/678819),
   [Apple DTS warning about app-driven resets](https://developer.apple.com/forums/thread/696174)).
4. **The installed new app cannot reliably discover the overwritten app's old
   signing identity.** Apple's public Code Signing Services can inspect the
   caller's current code or code that still exists at a supplied filesystem
   path. The permission APIs report only the current process's effective
   authorization; they do not return a previous DR or signing identity. Once
   installation has replaced the old bundle, there is no old code left for
   those APIs to inspect. Reliable identity-specific detection therefore has to
   happen before replacement—for example, an updater inspecting the old bundle
   and persisting a marker—or be prepared by an old release persisting a
   migration marker. A first-launch check of preferences, application data, or
   denied permissions is only an “existing user” heuristic: it cannot prove
   which identity signed the overwritten app
   ([Code Signing Services](https://developer.apple.com/documentation/security/code-signing-services),
   [`SecStaticCodeCreateWithPath`](https://developer.apple.com/documentation/security/secstaticcodecreatewithpath(_:_:_:)),
   [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).

## What the user must do

For the ordinary ad-hoc-to-Developer-ID transition:

1. Install and open the Developer ID build.
2. Approve its new Microphone prompt. If permission was denied instead, enable
   the current app under **System Settings > Privacy & Security > Microphone**.
3. Grant the current app Accessibility. That broader privilege enables both
   synthetic paste and global-shortcut listening, so a separate Input
   Monitoring grant is unnecessary. If the user declines Accessibility, Input
   Monitoring remains a narrower fallback for global shortcuts while completed
   text stays on the clipboard. If either pane already contains an
   enabled-looking FoldWise Voice entry but the runtime check stays false,
   remove that stale entry and add the installed app again before enabling it.

Apple documents that microphone consent is explicit, saved after the first
decision, and changeable in System Settings
([AVCaptureDevice authorization](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)),
[Control microphone access](https://support.apple.com/guide/mac-help/control-access-to-the-microphone-on-mac-mchla1b1e1fe/mac)).
For Accessibility, Apple says an untrusted app informs the user asynchronously
and that the user grants access in Privacy & Security; Apple Support documents
turning on or adding the app
([`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions),
[Allow accessibility apps](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)).
Apple Support likewise documents enabling or adding the app for Input
Monitoring
([Privacy & Security settings](https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac)).

One nuance is useful for FoldWise's UX: Accessibility is the broader privilege.
Apple's security engineers describe Accessibility as authorizing event posting
and listening, whereas Input Monitoring authorizes listening only. An app that
already has effective Accessibility access does not separately need Input
Monitoring for a listen-only event tap
([WWDC19 “Advances in macOS Security”](https://developer.apple.com/videos/play/wwdc2019/701/),
[Apple DTS clarification](https://developer.apple.com/forums/thread/828052)).

## Supported runtime APIs

| Permission | Inspect | Request or guide |
| --- | --- | --- |
| Microphone | `AVCaptureDevice.authorizationStatus(for: .audio)` returns `.notDetermined`, `.restricted`, `.denied`, or `.authorized`. | When the status is `.notDetermined`, call `AVCaptureDevice.requestAccess(for: .audio)`. After denial, the saved decision must be changed in System Settings. Apple requires `NSMicrophoneUsageDescription` ([authorization status](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)), [request access](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:))). |
| Accessibility | `AXIsProcessTrusted()` or `AXIsProcessTrustedWithOptions(nil)` returns whether the current process is a trusted Accessibility client. | `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` asynchronously informs an untrusted user; it does not itself grant the privilege or change the returned value. The user completes the grant in System Settings ([API documentation](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)). |
| Input Monitoring / listen events | `CGPreflightListenEventAccess()` returns effective listen-event access. `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` is the lower-level status API and distinguishes granted, denied, and unknown. | `CGRequestListenEventAccess()` potentially prompts. The equivalent lower-level request is `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`. Apple introduced the inspect/request pair specifically so an app can check without prompting and request approval without first creating an event tap ([Core Graphics functions](https://developer.apple.com/documentation/coregraphics/core-graphics-functions), [`IOHIDRequestAccess`](https://developer.apple.com/documentation/iokit/3181574-iohidrequestaccess), [WWDC19](https://developer.apple.com/videos/play/wwdc2019/701/)). |

These APIs answer whether **the currently running identity** has access. None is
a supported interface for enumerating TCC records, reading the DR stored with a
past decision, or resetting another identity's decision. Apple DTS states this
boundary directly: TCC has no API surface; apps interact through the
service-specific APIs above
([On File System Permissions](https://developer.apple.com/forums/thread/678819)).

## Upgrade-detection boundary

Code Signing Services offers two relevant scopes:

- `SecCodeCopySelf` obtains the calling process's current code object.
- `SecStaticCodeCreateWithPath` obtains a code object for a bundle that still
  exists at a specified absolute path.

Those scopes allow an updater to compare old and new bundles before replacement,
but they do not provide installation history
([Code Signing Services](https://developer.apple.com/documentation/security/code-signing-services)).
TN3127 also warns that code-signature structure is not API and directs products
to Code Signing Services rather than parsing implementation details
([TN3127 overview](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
Reading the private TCC database or inferring an old identity from its contents
would therefore not be a supported product strategy.

For this transition, guidance cannot be shown *only* to users reliably proven to
have upgraded from the ad-hoc identity unless the update/install path records
that fact before overwriting the old bundle. Without such a marker, use current
permission status to show guidance whenever it is actionable, or use a
first-launch/existing-data heuristic and accept that it is not identity proof.

## FoldWise-specific implication

`scripts/build_swift_app.py` currently comments that its ad-hoc signature gives
the bundle a stable identity for TCC grants. Apple's documented behavior is the
opposite: an ad-hoc DR is tied to the particular version of the code and cannot
reliably preserve authorization across rebuilds
([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
Once Developer ID signing is adopted, builds that retain the bundle identifier
and Team ID should have a stable default DR across subsequent versions; this is
the one-time identity discontinuity.
