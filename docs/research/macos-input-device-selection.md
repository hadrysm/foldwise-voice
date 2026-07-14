# Reliable macOS Input-device selection and lifecycle

## Question

Which supported macOS audio APIs and lifecycle can implement FoldWise's global
Input-device behavior while preserving the existing `AudioRecorder` /
`AudioRecording` seam?

## Answer

Use Core Audio's Hardware Abstraction Layer (HAL) as the source of truth for
device discovery, stable identity, the live default input, and topology-change
notifications. Persist a device's UID, never its process-local `AudioDeviceID`.
Resolve the preferred UID to a current `AudioDeviceID` whenever the topology
changes, and bind that ID to the `AVAudioEngine` input node's AUHAL audio unit
through `kAudioOutputUnitProperty_CurrentDevice`.

FoldWise should deepen `AudioRecorder` into the module that owns device policy,
HAL observation, and engine reconfiguration. `Config` continues to own the
persisted preference and change propagation. The Pipeline keeps a small
`AudioRecording` seam and should not learn about UIDs, device lists, fallback,
or reconnects. A fakeable internal HAL adapter makes the policy deterministic
in tests without requiring a microphone.

An effective-device change must never reconfigure the engine in the middle of a
healthy Dictation session. Record the new preference immediately, mark the
effective change pending, and apply it after `stop()` has frozen that session's
samples. A physical disconnect is different: hardware has already invalidated
the route. Fail that session explicitly, select the fallback for the next
session, and do not splice samples from two microphones into one Dictation
session.

## Supported platform primitives

| Need | Supported primitive | How FoldWise should use it |
| --- | --- | --- |
| Enumerate current devices | [`kAudioHardwarePropertyDevices`](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydevices) on `kAudioObjectSystemObject` | Read current `AudioObjectID`s, then keep only devices with at least one input stream/channel by querying [`kAudioDevicePropertyStreams`](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertystreams) or [`kAudioDevicePropertyStreamConfiguration`](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertystreamconfiguration) in input scope. |
| Persist identity | [`kAudioDevicePropertyDeviceUID`](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertydeviceuid) | Persist the returned `CFString`. Apple's SDK header defines it as persistent across boots and opaque to the app. Do not persist `AudioDeviceID`; IDs belong only to the current HAL topology. |
| Display name | [`kAudioObjectPropertyName`](https://developer.apple.com/documentation/coreaudio/kaudioobjectpropertyname) | Read the localized `CFString` for each current device. Treat names as presentation only; duplicate and changing names must not affect identity. |
| Find a reconnected preferred device | [`kAudioHardwarePropertyTranslateUIDToDevice`](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertytranslateuidtodevice) | Translate the persisted UID each time the topology changes. A missing UID resolves to an unknown object, which is availability state rather than a reason to overwrite the preference. |
| Follow System Default | [`kAudioHardwarePropertyDefaultInputDevice`](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultinputdevice) | Read the current default and register a property listener on the system object. Re-resolve it on every notification rather than trusting a cached ID. |
| Detect connect/disconnect and default changes | [`AudioObjectAddPropertyListenerBlock`](https://developer.apple.com/documentation/coreaudio/audioobjectaddpropertylistenerblock(_:_:_:_:)) | Observe the system object's device list and default-input properties on one serial queue. Remove matching blocks at shutdown; Apple documents that HAL retains both the queue and block until removal. |
| Detect HAL restart | [`kAudioHardwarePropertyServiceRestarted`](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyservicerestarted) | Drop cached IDs/state, recreate the snapshot, and re-establish listeners and the engine route. Apple's SDK header says cached HAL state and listeners must be re-established after a service reset. |
| Bind an explicit device | [`kAudioOutputUnitProperty_CurrentDevice`](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice) | Set the resolved `AudioDeviceID` on `engine.inputNode.audioUnit` with `AudioUnitSetProperty`, global scope, element 0, while the engine is stopped. Check every `OSStatus`. |
| Recover from hardware format changes | [`AVAudioEngineConfigurationChange`](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification) | The engine stops when its I/O unit sees a channel-count or sample-rate change. Schedule recovery off the notification callback, refresh the hardware format, rebuild the converter/tap, and restart only when capture should be active. Never deallocate the engine inside the callback; Apple warns this can deadlock. |
| Check capture permission | [`AVCaptureDevice.authorizationStatus(for:)`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)) and [`requestAccess`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)) | Keep the current launch-time permission flow. Enumeration and selection do not replace TCC permission. Apple documents that denied or unanswered permission produces silent audio, and `NSMicrophoneUsageDescription` is mandatory. |

`AVCaptureDevice` also exposes audio devices and connection notifications, but
using it as the catalog while using Core Audio IDs to bind AUHAL creates an
unnecessary identity-mapping seam. Core Audio already supplies the complete set
of primitives needed by the recorder, so it should own discovery and routing;
AVFoundation remains the permission and engine layer.

## Preference and effective-device policy

Persist exactly one global preference:

```swift
enum InputDevicePreference: Equatable, Codable {
    case systemDefault
    case device(uid: String)
}
```

Maintain a runtime snapshot that distinguishes intent from current execution:

```swift
struct InputDeviceState: Equatable {
    var available: [InputDevice]       // UID + display name
    var systemDefaultUID: String?
    var preferred: InputDevicePreference
    var effectiveUID: String?
    var pendingEffectiveUID: String?
    var status: Status
}

enum Status: Equatable {
    case ready
    case usingFallback(preferredUID: String)
    case switchDeferred
    case unavailable
    case failed(message: String)
}
```

The selection reducer is:

1. `.systemDefault` resolves to the current default input.
2. `.device(uid)` resolves to that device while it is connected.
3. If the preferred UID is absent, preserve it and resolve temporarily to the
   current default input.
4. While fallback is active, a default-input change changes the fallback target.
5. When the preferred UID reappears, it becomes the target again automatically.
6. If neither preferred nor default resolves to an input-capable device, the
   effective device is absent and starting capture must fail visibly.
7. If a target changes while recording, preserve the active target and record a
   pending target until the current session stops. A physical loss of the active
   device instead terminates that capture as a failure because the old route no
   longer exists.

All HAL callbacks, `Config` changes, and capture start/stop transitions should be
serialized through one actor or serial queue. Listener callbacks are change
hints, not complete state: rebuild a fresh snapshot and reduce from it. This
avoids races such as disconnect followed immediately by reconnect, or a default
change delivered beside a device-list change.

## `AVAudioEngine` lifecycle

The current recorder installs one tap and keeps the engine running for the
process lifetime after first use
([`AudioRecorder.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Record/AudioRecorder.swift#L3-L76)).
That lifecycle assumes an invariant input format and never observes engine
configuration changes, so it cannot safely support explicit routing or hot
plugging.

For each effective-device application, FoldWise should perform this ordered
operation while no healthy session is recording:

1. Stop the engine and remove the existing input tap.
2. Resolve the target UID/default to a current input-capable `AudioDeviceID`.
3. Get `engine.inputNode.audioUnit` and set
   `kAudioOutputUnitProperty_CurrentDevice`; fail on a missing audio unit or
   nonzero `OSStatus`.
4. Re-read `inputNode.outputFormat(forBus: 0)`. Reject zero sample rate or zero
   channels before installing a tap. Apple's
   [`inputNode`](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)
   documentation names a nonzero input format as the availability check.
5. Recreate `AVAudioConverter` from the new hardware format to FoldWise's
   16 kHz mono Float32 format, then install the tap using the new input format.
6. Call `prepare()` if startup latency warrants it and `start()` when capture is
   required. [`AVAudioEngine.start()`](https://developer.apple.com/documentation/avfaudio/avaudioengine/start())
   throws for invalid graphs, session failures, and hardware-driver startup
   failures; propagate that result.

Apple documents that [`stop()`](https://developer.apple.com/documentation/avfaudio/avaudioengine/stop())
stops hardware and releases prepared resources, and recommends pause/stop while
audio is not needed to reduce power. FoldWise may choose between a prepared idle
engine and start-on-dictation after measuring latency, but selection changes must
use the stopped/rebuild sequence and every session must verify that the engine
is actually running.

The configuration-change notification is mandatory even with HAL listeners:
sample-rate/channel-count changes can stop the engine without a device-list
change. The handler should only enqueue recovery. If no session is active,
rebuild immediately or lazily before the next start. If a session is active,
mark it failed, freeze/discard its partial samples according to Pipeline policy,
and prepare the resolved route for the next session.

## FoldWise ownership and seams

The existing architecture already places the production recorder correctly:
`AppMain` constructs one `AudioRecorder` and shares it with the Pipeline and the
Badge level meter
([`AppMain.swift`](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift#L141-L179)).
ADR-0002 deliberately keeps the Pipeline's record Stage behind the small
`AudioRecording` seam
([`Pipeline.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L10-L16)),
and ADR-0003 makes `Config` the owner of persistence and typed change
propagation.

Preserve those decisions as follows:

- **`Config` owns intent.** Add the persisted global preference and an
  `.inputDevice` change bit. Settings mutates and saves it immediately. Unknown
  or disconnected UIDs remain on disk unchanged.
- **The shared recorder owns execution.** Deepen `AudioRecorder` (or rename that
  deep module to `AudioInput`) so it owns the HAL snapshot, listener lifetime,
  fallback reducer, active/pending target, engine/tap/converter, capture state,
  level, and errors. Deleting this module would spread routing complexity across
  Settings, Pipeline, and AppMain, so it earns the seam.
- **The Pipeline owns session sequencing, not routing.** Keep UIDs and topology
  out of `Pipeline`. It still says start/stop/close and receives samples or a
  typed failure.
- **Settings observes a projection.** Give `SettingsController` a read-only
  device-state projection/callback from the shared recorder. The picker never
  calls Core Audio directly.
- **The composition root wires reactions.** `AppMain` supplies `Config`'s initial
  preference to the recorder, subscribes the recorder to `.inputDevice`, and
  injects the same recorder into Pipeline, Badge, and Settings.

The current `AudioRecording.start()` returns `Void`, while `AudioRecorder.open()`
only logs failures. Pipeline then emits `.listening` even when no engine started
([`Pipeline.swift`](../../Sources/FoldWiseVoiceKit/Features/Dictation/Pipeline.swift#L176-L186)).
Change the record seam so `start()` throws or returns a typed result. Pipeline
must emit `.listening` only after successful capture startup and emit its
existing `.error` state otherwise. This is a small, justified increase in the
interface because hardware-start failure is observable session behavior, and it
lets the existing fake recorder cover the failure path.

### Internal platform seam

Hide Core Audio behind one internal interface owned by the deep recorder module,
with a production adapter and a deterministic fake:

```swift
protocol AudioInputHardware {
    func snapshot() throws -> HardwareSnapshot
    func startMonitoring(_ changed: @escaping @Sendable () -> Void) throws
    func stopMonitoring()
    func bind(_ deviceID: AudioDeviceID, to inputUnit: AudioUnit) throws
}
```

The interface returns facts and accepts one bind command; it does not expose raw
property selectors, listener blocks, or fallback policy. The production adapter
contains the unsafe Core Audio calls and `OSStatus` translation. The fake emits
snapshots and injected failures. Engine graph rebuilding can remain inside
`AudioRecorder`, with an additional private engine factory only if tests need to
exercise ordering without real hardware.

## Failure states to specify

- **Permission denied/restricted/not determined:** start fails with a permission
  error; keep the existing System Settings guidance. Do not infer permission
  from a silent buffer.
- **No input-capable default:** System Default and disconnected-device fallback
  show unavailable; start fails rather than displaying listening.
- **Preferred device absent:** nonfatal fallback status; preference is preserved.
- **Preferred device returns:** automatic restore, deferred if recording.
- **HAL property/UID/name read fails:** omit only an unreadable catalog entry
  where possible; retain the last useful UI snapshot and surface a diagnostic.
- **AUHAL bind or engine start fails:** retain the preference, report capture
  failure, refresh the HAL snapshot, and allow a later retry. Do not silently
  rewrite the preference to System Default.
- **Converter creation or zero hardware format:** treat the route as unusable and
  fail startup before installing a tap.
- **Active device disconnects or the engine stops mid-session:** fail that
  Dictation session explicitly, restore ducked audio, and prepare fallback for
  the next session. Do not transcribe a partial cross-device recording as if it
  were complete.
- **Core Audio service restarts:** invalidate all IDs, rebuild listeners/snapshot,
  then resolve preferred → fallback again.
- **App shutdown:** remove HAL listeners before releasing their queue/owner and
  stop the engine after preventing further callbacks.

## Testable acceptance boundary

Unit tests through the recorder's interface and fake HAL adapter should prove:

1. System Default follows initial and subsequent default UID changes.
2. An explicit connected UID ignores unrelated default changes.
3. Disconnect preserves the explicit UID, uses the current default, and reports
   fallback; reconnect restores the explicit UID.
4. A default change while fallback is active changes the effective fallback.
5. Preference/default changes during recording become pending and apply exactly
   once after stop.
6. Active-device loss fails the session and selects fallback for the next start.
7. No default, zero-channel formats, bind errors, converter failures, and engine
   start failures never emit listening.
8. Hardware-format/configuration changes rebuild the converter and tap from the
   fresh format, with no engine destruction in the notification callback.
9. HAL restart discards stale IDs and re-registers observation.
10. Duplicate display names remain distinct by UID.

Pipeline tests should add a fake-recorder start failure and assert `.error`
without `.listening`, while the existing session tests continue to use the same
record Stage seam
([`PipelineTestSupport.swift`](../../Tests/FoldWiseVoiceKitTests/Features/Dictation/PipelineTestSupport.swift#L9-L35)).
Manual hardware checks remain appropriate for real TCC prompts, Bluetooth/USB
hot-plugging, default-device changes in System Settings, and latency on the first
start; those are adapter integration checks, not substitutes for the policy
tests above.

## Decision

The APIs and architecture can fulfill the confirmed behavior without replacing
`AVAudioEngine` or moving device knowledge into Pipeline. The implementation
should use Core Audio HAL for catalog/identity/observation, AUHAL's current-device
property for binding, and AVFoundation for permission, capture, conversion, and
configuration-change recovery. Persist intent in `Config`; centralize runtime
policy and engine lifecycle in the shared recorder; surface typed start/runtime
failures; and test the entire selection lifecycle through a fake HAL adapter.
