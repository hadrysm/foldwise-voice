# Config owns change propagation via a hand-rolled changed-key notification

Persistence and change-propagation are unified behind Config: mutating a tracked
property records a changed-key set, and `saveAndNotify()` persists to disk and
then delivers that set to observers registered once at startup via `onChange`.
The manual fan-out in `AppDelegate.settingsSaved()` (rebind hotkey, refresh
menu-bar checks, re-fit HUD) is deleted; each reactor subscribes to the change
it cares about instead. We deliver the event through a hand-rolled `@MainActor`
closure list carrying a typed `ChangeSet` (an `OptionSet`), not Combine,
NotificationCenter, or the Observation framework.

## Considered Options

- **Combine `PassthroughSubject<ChangeSet, Never>`** — pulls Combine into the
  model layer (today only the SwiftUI *view models* use it) and adds
  `AnyCancellable` bookkeeping for a lifecycle we don't have: every subscriber
  is an app-lifetime singleton, so subscriptions are never torn down.
- **NotificationCenter** — `userInfo` is `[AnyHashable: Any]`, which throws away
  the typed changed-key payload and reintroduces the `removeObserver`-in-`deinit`
  dance already seen elsewhere in the app.
- **Observation (`@Observable`, macOS 14+)** — built for SwiftUI view tracking,
  not for an imperative "here is exactly what changed" callback with a payload.

## Consequences

- The payload is granular at the level subscribers **act**, not per-property:
  `.activeMode`, `.hudStyle`, `.hotkeys` (the last covers both push-to-talk and
  toggle keys, because the hotkey listener can only rebind both at once).
- Properties nobody re-reads — `hudPosition`, `pauseAudio` — get **no** key.
  `pauseAudio` is read live by the pipeline; `hudPosition` by nobody. So an HUD
  drag persists with an empty changed-key set and notifies no one. That is what
  keeps the TCC-sensitive hotkey event tap from being rebuilt on every drag or
  menu mode-switch: `startListener()` runs only when `.hotkeys` is in the set,
  where before the refactor a naive "every save notifies everyone" would have
  torn the tap down and recreated it on unrelated changes.
- `save()` stays a non-isolated persistence primitive (used by `defaultConfig`,
  `loadOrCreate`, and the `--print-config` diagnostic, none of which have
  observers). `saveAndNotify()` is the `@MainActor` transaction the live UI
  calls. Config's reads stay non-isolated so the pipeline can read it off the
  main actor during dictation.
