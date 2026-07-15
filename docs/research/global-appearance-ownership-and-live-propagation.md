# Global Appearance ownership and live propagation

Research answer for **Research global Appearance ownership and live
propagation**. The product term is **Appearance preference**: System, Light, or
Dark, globally applied to FoldWise surfaces ([domain glossary](../../CONTEXT.md)).

## Recommendation

Make AppKit's application appearance the single rendering authority:

| Appearance preference | Value assigned to `NSApp.appearance` | Result |
| --- | --- | --- |
| System | `nil` | Inherit the current macOS appearance, including changes while FoldWise is running. |
| Light | `NSAppearance(named: .aqua)` | Force the standard light appearance. |
| Dark | `NSAppearance(named: .darkAqua)` | Force the standard dark appearance. |

Apple documents `NSApplication.appearance` as the appearance associated with
the app's windows. A `nil` value applies the current system appearance to the
app's windows, views, panels, and popovers; assigning an `NSAppearance` makes
those interface elements adopt it. Apple also documents the inheritance chain:
the app normally inherits the system, windows and panels inherit the app, and
views inherit their nearest window or view ancestor. That is exactly the
required ownership shape, including future surfaces that do not exist yet.
([`NSApplication.appearance`](https://developer.apple.com/documentation/appkit/nsapplication/appearance),
[`NSAppearance`](https://developer.apple.com/documentation/appkit/nsappearance),
[*Choosing a Specific Appearance for Your macOS App*](https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app))

Do **not** distribute the preference across `NSWindow.appearance`,
`NSPanel.appearance`, and SwiftUI `.preferredColorScheme(_:)` calls. Per-window
assignment would make every surface controller part of the interface and make
new windows opt-in accidentally. `.preferredColorScheme(_:)` only overrides
the nearest SwiftUI presentation; it is not the authority for AppKit window
chrome, native controls, menus, panels, or popovers. Apple explicitly describes
it as a presentation-scoped override, including `nil` meaning no preference.
([`preferredColorScheme(_:)`](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)))

The existing main window and Badge already fit application-level inheritance:

- `SettingsController` constructs an `NSWindow` around an `NSHostingController`
  and does not set a local appearance
  ([`SettingsController.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsController.swift)).
- `BadgeController` constructs a borderless `NSPanel` around an `NSHostingView`
  and does not set a local appearance
  ([`BadgeController.swift`](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeController.swift)).
- `NSHostingView` is an AppKit view, conforms to `NSAppearanceCustomization`,
  and receives effective-appearance changes. SwiftUI in turn updates its
  `colorScheme` environment and redraws dependent views whenever the appearance
  changes. Therefore the AppKit effective appearance is sufficient for both
  hosted SwiftUI trees; adding root `.preferredColorScheme` modifiers would be
  a second authority. This is an inference from the two documented bridges,
  rather than a separate FoldWise-specific contract.
  ([`NSHostingView`](https://developer.apple.com/documentation/swiftui/nshostingview),
  [`ColorScheme`](https://developer.apple.com/documentation/swiftui/colorscheme))

## Ownership and propagation

### Persisted domain value

Add an `AppearancePreference: String` with exactly `.system`, `.light`, and
`.dark`, and store it as one top-level `"appearance"` string in `modes.json`.
An absent or unrecognized value should read as `.system`; this makes every
preference created before the field existed follow macOS, which is the current
behavior. An unrecognized value is not preserved: the next successful save
rewrites it as `"system"`. Appearance is a closed local preference, and passive
preservation would leave the persisted value disagreeing with the value FoldWise
actually applies.

`Config` should own this value alongside its other global preferences. Its
`didSet` records a new `Config.ChangeSet.appearance` member only when the value
actually changes. `saveAndNotify()` remains the only live mutation transaction:
persist first, then deliver the changed-key set. This follows the accepted
decision that Config owns typed, granular, app-lifetime change propagation and
ensures a failed save never invokes the appearance reactor
([`Config.swift`](../../Sources/FoldWiseVoiceKit/Configuration/Config.swift),
[`ADR-0003`](../adr/0003-config-owns-change-propagation.md)). No Combine,
NotificationCenter, Swift Observation, or separate appearance event bus is
needed.

The mechanical Config touchpoints are:

- constructor/default value and `defaultConfig`;
- `load` with missing/invalid-to-System fallback;
- top-level `save` field;
- the `--print-config` echo construction in the composition root;
- `.appearance` in `ChangeSet`.

### One app-lifetime reactor

Add a small `@MainActor` application module, `AppearanceReactor`, constructed
and retained by `AppDelegate`. Its narrow
interface is Config plus an injectable apply closure; its implementation does
both jobs callers should not need to repeat:

1. map System/Light/Dark to `nil`/Aqua/Dark Aqua and apply the loaded preference
   immediately; and
2. register once with `config.onChange`, reapplying only when the set contains
   `.appearance`.

The production adapter for the internal seam is simply
`{ NSApp.appearance = $0 }`; a test supplies a spy closure. A protocol hierarchy
would add interface without adding useful variation. This module earns the seam
by owning the initial application, enum-to-AppKit mapping, app-lifetime
subscription, and changed-key filtering behind one initializer. Deleting it
would push those lifecycle rules into the coverage-exempt composition root and
leave no focused test surface.

Construct this reactor immediately after Config is loaded and before the
settings window, Badge panel, menu bar, alerts, or future surfaces are built.
That gives launch the correct appearance without a light/dark flash. This is
consistent with the repository's existing composition-root decision and its
current app-lifetime Config reactors
([`AppMain.swift`](../../Sources/FoldWiseVoiceKit/Application/AppMain.swift),
[`ADR-0002`](../adr/0002-pipeline-hybrid-seams.md)). The surface controllers
must not each subscribe to `.appearance`.

The live sequences are then:

- **Preference change:** Settings model changes → Settings workflow mutates
  Config → `saveAndNotify()` succeeds → the reactor assigns
  `NSApp.appearance` → AppKit updates visible and subsequently-created surfaces.
- **macOS changes while System is selected:** Config does not change and no
  FoldWise callback runs. Because `NSApp.appearance` remains `nil`, AppKit's
  `effectiveAppearance` follows macOS and redraws its view trees; SwiftUI updates
  the hosted color-scheme environments. Apple recommends observing
  `effectiveAppearance` only for appearance-sensitive work outside a view;
  FoldWise's rendering should not need that extra observer.
  ([`NSApplication.effectiveAppearance`](https://developer.apple.com/documentation/appkit/nsapplication/effectiveappearance),
  [*Supporting Dark Mode in your interface*](https://developer.apple.com/documentation/appkit/supporting-dark-mode-in-your-interface))
- **macOS changes while Light or Dark is selected:** the assigned application
  appearance remains authoritative, so FoldWise does not change.

### Settings mediation

Add an `@Published` Appearance preference to `SettingsModel`; seed it in
`SettingsWorkflow.populatePreferences()` and copy it into Config in `commit()`.
The existing `onCommit` → workflow → `saveAndNotify()` path already provides the
right persist-before-react ordering and status/error behavior
([`SettingsModel.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsModel.swift),
[`SettingsWorkflow.swift`](../../Sources/FoldWiseVoiceKit/Features/Settings/SettingsWorkflow.swift)).
The exact control, labels, and layout belong to the separate Settings prototype;
they do not change appearance ownership.

## Palette behavior

### Preserve the dynamic window palette

The window side of `Theme` is already correctly shaped. Each token wraps an
`NSColor(name:dynamicProvider:)`, and the provider selects Aqua or Dark Aqua
from the appearance passed at draw-time. Apple documents that the provider is
called with the current drawing appearance when components are required.
SwiftUI's `Color(nsColor:)` preserves the source `NSColor`'s adaptability rather
than snapshotting it. The static `Theme` values therefore do **not** need to be
rebuilt when the preference changes
([`Theme.swift`](../../Sources/FoldWiseVoiceKit/DesignSystem/Theme.swift),
[`NSColor.init(name:dynamicProvider:)`](https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)),
[`Color.init(nsColor:)`](https://developer.apple.com/documentation/swiftui/color/init(nscolor:))).

Keep the existing `bestMatch(from: [.darkAqua, .aqua])` resolution pattern.
Do not replace adaptable colors with cached RGB components or `CGColor` values;
Apple notes that fixed component colors and `CGColor` do not update during an
appearance transition. Assigning the standard Aqua/Dark Aqua appearance also
preserves the system's Increase Contrast variants; Apple says to assign the
standard appearance and let AppKit return the corresponding high-contrast
appearance when that accessibility setting is enabled.
([*Supporting Dark Mode in your interface*](https://developer.apple.com/documentation/appkit/supporting-dark-mode-in-your-interface),
[`accessibilityHighContrastDarkAqua`](https://developer.apple.com/documentation/appkit/nsappearance/name-swift.struct/accessibilityhighcontrastdarkaqua))

### `Theme.Badge` is a real implementation gap

The Badge palette is currently explicitly fixed: every `Theme.Badge` token is a
component `Color`, and the source comments say the pill keeps one near-black
palette because it floats over arbitrary wallpaper
([`Theme.swift`](../../Sources/FoldWiseVoiceKit/DesignSystem/Theme.swift),
[`BadgeView.swift`](../../Sources/FoldWiseVoiceKit/Features/Badge/BadgeView.swift)).
Changing `NSApp.appearance` will update the hosting environment and any adaptive
system UI, but it cannot make those fixed colors change. Apple documents fixed
component colors as non-adaptive.

Consequently, the confirmed requirement that Light and Dark override the Badge
requires the Badge tokens that visibly differ by appearance to become dynamic
colors too. Reuse the same dynamic-`NSColor` mechanism as the window palette;
do not add appearance branches throughout `BadgeView` or publish the preference
into `BadgeModel`. The Settings appearance prototype must supply the actual
light Badge palette and decide which ribbon/accent tokens remain constant. If
the prototype instead keeps the entire near-black pill fixed, that is a product
exception to “Appearance applies across the Badge,” not something the AppKit
propagation layer can solve.

## Preserve the menu-bar icon

Keep `MenuBarController` out of appearance propagation. It currently installs
SF Symbols on the system `NSStatusBarButton`, gives the idle state a `nil`
`contentTintColor`, and uses adaptable system red/orange only for its existing
listening/working states
([`MenuBarController.swift`](../../Sources/FoldWiseVoiceKit/Application/MenuBarController.swift)).

That is the right separation:

- Apple defines `NSStatusBarButton` as the appearance and behavior of an item in
  the **systemwide menu bar**.
- Symbol images have no intrinsic color by default; the system applies the tint
  appropriate to their context.
- For template image content, `nil` content tint requests the standard,
  theme-appropriate effects.

([`NSStatusBarButton`](https://developer.apple.com/documentation/appkit/nsstatusbarbutton),
[*Configuring and displaying symbol images in your UI*](https://developer.apple.com/documentation/appkit/configuring-and-displaying-symbol-images-in-your-ui),
[`NSImage.isTemplate`](https://developer.apple.com/documentation/appkit/nsimage/istemplate),
[`NSButton.contentTintColor`](https://developer.apple.com/documentation/appkit/nsbutton/contenttintcolor))

Do not assign an appearance to `statusItem.button`, do not tint its idle icon
with a `Theme` token, and do not subscribe it to `.appearance`. If a custom
bitmap ever replaces the SF Symbol, mark the black-and-transparent source as a
template image; with the current system symbols, preserve their symbol/template
rendering information and configuration. `NSApp.appearance` remains the right
authority for FoldWise surfaces while the status-bar host remains responsible
for making its button legible against the actual macOS menu bar.

## Test seams and acceptance checks

Automated tests should cover decisions through the same interfaces production
uses:

1. **Config round trip:** absent → System; System, Light, and Dark each survive
   save/load; invalid raw value degrades to System.
2. **Config propagation:** a genuine change delivers exactly `.appearance`;
   assigning the same value delivers nothing; appearance combines with other
   changed keys; failed persistence does not invoke the appearance reactor and a
   later successful retry does. Extend the existing Config suites rather than
   create a second event-path test harness
   ([`ConfigRoundTripTests.swift`](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigRoundTripTests.swift),
   [`ConfigChangePropagationTests.swift`](../../Tests/FoldWiseVoiceKitTests/Configuration/ConfigChangePropagationTests.swift)).
3. **Appearance module:** against an injected spy apply closure, initialization
   maps System/Light/Dark to `nil`/Aqua/Dark Aqua, an appearance notification
   reapplies once, and unrelated Config notifications do nothing. This seam
   avoids mutating global `NSApp` state in the unit suite.
4. **Settings mediation:** population reads Config and commit writes it through
   the existing persist closure. Add this to `SettingsWorkflowTests`; controller
   wiring needs a test only if the final control introduces a new callback
   rather than reusing `onCommit`.
5. **Dynamic palette:** resolve representative window and new Badge dynamic
   tokens under Aqua and Dark Aqua using
   `performAsCurrentDrawingAppearance`; assert expected variants. This guards
   against accidentally replacing a dynamic token with a fixed color.
   ([`performAsCurrentDrawingAppearance(_:)`](https://developer.apple.com/documentation/appkit/nsappearance/performascurrentdrawingappearance(_:)))

Some guarantees are visual platform integration and deserve a macOS smoke
matrix rather than brittle global-state tests:

- with System selected, toggle macOS Light ↔ Dark while both the settings
  window and Badge are visible and confirm both update without reopening;
- with Light and Dark selected, toggle macOS and confirm FoldWise stays forced;
- switch all three choices while a sheet, menu, tooltip, or alert is visible or
  subsequently opened, confirming inherited native chrome is coherent;
- in each combination, confirm the idle menu-bar symbol remains system-rendered
  and legible, and the listening/working state tints retain their current
  behavior.

## Resulting implementation boundary

The implementation slice should touch Config, the application composition
root/new appearance module, Settings model/workflow/view, Theme's Badge tokens,
and tests. It should **not** add appearance state to `SettingsView` or
`BadgeModel`, per-surface appearance subscriptions, root
`.preferredColorScheme` modifiers, manual macOS appearance notifications, or an
appearance dependency in `MenuBarController`.
