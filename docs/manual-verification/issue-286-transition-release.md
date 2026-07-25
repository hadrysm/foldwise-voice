# Transition release verification

Evidence record for
[Ship the notarized transition release](https://github.com/hadrysm/foldwise-voice/issues/286).
Complete this against the exact DMG attached to the GitHub release.

## Candidate

- Version: 0.17.0
- Commit: `702a33ff99ba9641f69b0b3a60710efd45fb2b5c`
- DMG:
  [FoldWise-Voice-0.17.0.dmg](https://github.com/hadrysm/foldwise-voice/releases/download/v0.17.0/FoldWise-Voice-0.17.0.dmg)
- SHA-256: `df191d677645d93212da7d5ee23487ac4464bc7f701c322867490d62e17ba3db`
- GitHub release:
  [v0.17.0](https://github.com/hadrysm/foldwise-voice/releases/tag/v0.17.0)
- Release workflow:
  [successful run](https://github.com/hadrysm/foldwise-voice/actions/runs/30167312351)
- Artifact-check macOS and hardware: macOS 26.5 (25F71), MacBook Pro
  (MacBookPro18,1), Apple M1 Pro
- Artifact tester: Codex on Mateusz Hadry's Mac
- Date: 2026-07-25

## Artifact acceptance

- [x] `codesign --verify --strict` passes for the app and DMG.
- [x] `codesign -dvvv` shows the Developer ID authority chain, secure
      timestamp, hardened runtime, and `TeamIdentifier=6849P798YW`.
- [x] `spctl -a -vvv -t exec` accepts the app.
- [x] `spctl -a -vvv -t open --context context:primary-signature` accepts the
      DMG.
- [ ] `xcrun stapler validate` passes with networking disabled.
- [ ] Gatekeeper is silent on first launch; **Open Anyway** is not needed.

The release workflow successfully notarized, stapled, and validated the DMG.
Independent validation of the downloaded asset also passed. When networking was
denied with `sandbox-exec`, however, `stapler validate` attempted to query
`api.apple-cloudkit.com` and exited 68. In the same network-denied sandbox,
Gatekeeper accepted both the quarantined DMG and mounted app as **Notarized
Developer ID**. The literal offline-`stapler` box remains unchecked pending the
clean-account test; `stapler`'s own CloudKit dependency must not be reported as
an absent embedded ticket. Apple documents that the trusted execution system
can use an embedded ticket for a first launch while offline in
[The Pros and Cons of Stapling](https://developer.apple.com/forums/thread/720093).

## Clean macOS account

- [ ] The account has never run FoldWise Voice.
- [ ] The Permission recovery guide opens in the main window without stacked
      alerts.
- [ ] The normal Microphone and Accessibility actions grant successfully.
- [ ] Status updates live and the guide closes after both grants.
- [ ] Global shortcuts and synthetic paste work without Input Monitoring.
- [ ] One real Voice to Text Dictation session completes in TextEdit.

## Existing v0.16.x account

- [ ] Start with v0.16.x installed and Microphone, Accessibility, and Input
      Monitoring enabled.
- [ ] Replace it from the transition DMG without resetting privacy data.
- [ ] The guide appears because live checks fail, without an upgrade marker.
- [ ] **Not now** dismisses it, it reappears after relaunch, and Home and
      Settings can reopen it.
- [ ] Granting Microphone and Accessibility updates live, restores recording,
      global shortcuts, and paste, and closes the guide without another
      relaunch.
- [ ] An enabled-looking stale Accessibility row is recovered by the guide's
      remove-and-re-add instructions.
- [ ] With Accessibility declined, Input Monitoring restores global shortcuts
      while completed text remains on the clipboard.
- [ ] No ordinary step uses `tccutil`.

## Release note

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

## Results and surprises

- Clean-account result: Pending on the exact public DMG above.
- Existing-user result: Pending on the exact public DMG above.
- Behavior not predicted by the TCC decision: `stapler validate` itself requires
  CloudKit connectivity on this macOS version even when the ticket is embedded.
  Offline Gatekeeper assessment succeeds, but the literal validation command
  does not.
