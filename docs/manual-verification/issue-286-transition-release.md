# Transition release verification

Evidence record for
[Ship the notarized transition release](https://github.com/hadrysm/foldwise-voice/issues/286).
Complete this against the exact DMG attached to the GitHub release.

## Candidate

- Version:
- Commit:
- DMG:
- GitHub release:
- macOS and hardware:
- Tester:
- Date:

## Artifact acceptance

- [ ] `codesign --verify --strict` passes for the app and DMG.
- [ ] `codesign -dvvv` shows the Developer ID authority chain, secure
      timestamp, hardened runtime, and `TeamIdentifier=6849P798YW`.
- [ ] `spctl -a -vvv -t exec` accepts the app.
- [ ] `spctl -a -vvv -t open --context context:primary-signature` accepts the
      DMG.
- [ ] `xcrun stapler validate` passes with networking disabled.
- [ ] Gatekeeper is silent on first launch; **Open Anyway** is not needed.

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

- Clean-account result:
- Existing-user result:
- Behavior not predicted by the TCC decision:
