# Sparkle bad-release withdrawal and recovery policy

Research for [Choose the rollback policy for an automatically distributed bad
release](https://github.com/hadrysm/foldwise-voice/issues/297), audited on
2026-07-25 against Sparkle 2.9.4 at exact commit
[`b6496a74a087257ef5e6da1c5b29a447a60f5bd7`](https://github.com/sparkle-project/Sparkle/tree/b6496a74a087257ef5e6da1c5b29a447a60f5bd7).
External claims use only Sparkle's official documentation and that exact source.
Repository-specific constraints come from the already-resolved child tickets of
[Ship FoldWise under a real Apple Team ID with in-app
auto-update](https://github.com/hadrysm/foldwise-voice/issues/277).

## Decision

FoldWise has two recovery operations with different reach:

1. **Withdraw the appcast item** to stop clients that have not selected and
   prepared the bad release. Preserve private incident evidence, make the bad
   archive URL fail closed, restore the last-known-good signed appcast, purge
   both cache paths, and verify both public states. A transient enclosure
   download failure is safer than leaving bad bytes available to a client with
   a cached feed. This is a feed rollback, not an installed-app downgrade.
2. **Publish a higher-version forward repair** for every client that already
   installed the bad release. The repair may restore the last-known-good source
   code, but it must have a new, greater `CFBundleVersion` and release version.
   Sign it with the established Sparkle Ed25519 key and compatible Developer ID
   identity, publish its immutable DMG first, then publish it in the signed feed
   as an unphased critical update.

There is no operator-side recall for an update already in Sparkle's prepared
install-on-Quit state. For a **non-critical** prepared update, a user can open
**Check for Updates…** before quitting and choose **Skip This Version**; Sparkle
then cancels the installer and records the minor-version skip. Dismiss,
**Install on Quit**, closing the update window, or simply quitting does not
cancel it. A prepared non-major **critical** update has no Skip or Later action
in Sparkle's standard UI, so FoldWise has no supported in-app cancellation path
for that case. This is an additional reason to reserve critical marking for
tested incident-recovery releases, not routine releases.

Routine releases should use a 24-hour phased-rollout interval. Sparkle has seven
groups, so automatic exposure expands one group per day; manual checks still
bypass phasing. The live appcast must retain prior known-good items, and release
storage must retain the matching immutable DMGs and a signed appcast snapshot
from before every publication. Configure `generate_appcast` with
`--maximum-versions 0` so it does not prune good appcast history, and never use
`--auto-prune-update-files` as the release archive retention policy.

## Why changing the appcast cannot recall a prepared update

With automatic downloads enabled, Sparkle does more than cache an archive. It
downloads, extracts, validates, starts the installer, completes installation
stage 1, gives the installer the selected appcast item, and leaves that separate
process waiting for the target app to terminate. The automatic driver can then
abort its own cycle while explicitly leaving the installer alive
([automatic-driver handoff](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUAutomaticUpdateDriver.m#L104-L127),
[installation design](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Documentation/Installation.md#L67-L95)).
The public delegate contract is unambiguous: whether or not the app takes
control of immediate installation, Sparkle always attempts installation when
the app terminates
([install-on-Quit contract](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUUpdaterDelegate.h#L421-L440)).

On a later manual or scheduled check, Sparkle probes for the live installer,
retrieves the appcast item cached by that installer, and resumes it instead of
fetching the feed
([updater branch](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUUpdater.m#L904-L923),
[cached-item resume](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUBasicUpdateDriver.m#L87-L114)).
The installer has moved the archive into its own update directory to prevent
the updater or another process from accidentally removing it, and it retains
the appcast data needed for resumption
([installer-owned archive](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Documentation/Installation.md#L39-L47),
[persisted appcast item](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Autoupdate/AppInstaller.m#L600-L615)).

Consequences:

- Removing the item protects clients that perform a later feed check; it does
  not affect a prepared local installer.
- Removing the public DMG may stop a not-yet-complete download, but cannot be
  assumed to stop an in-flight response and cannot affect a completed local
  copy.
- Overwriting the enclosure URL with different bytes is neither a recall nor a
  repair. Prepared clients already have the old bytes, while later clients
  validate the archive against the appcast's exact Ed25519 signature and byte
  length and reject a mismatch
  ([archive signing](https://sparkle-project.org/documentation/publishing/#secure-your-update),
  [signature and metadata mismatch checks](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUSignatureVerifier.m#L173-L226)).

## The one supported cancellation path

Sparkle's standard user-driver state distinguishes an update that is merely
downloaded from one that is already installing. For an Installing-stage update,
**Dismiss** preserves the installer and leaves installation scheduled for app
termination, while **Skip** cancels the installer
([user-driver choices](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUUserDriver.h#L63-L100)).
The exact 2.9.4 implementation persists the skipped version and sends the
installer a cancellation message; the installer removes its update directory
and exits
([Skip implementation](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUUIBasedUpdateDriver.m#L267-L319),
[cancel IPC](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUInstallerDriver.m#L614-L633),
[installer cleanup](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Autoupdate/AppInstaller.m#L643-L646)).

FoldWise's chosen Sparkle standard UI and retained **Check for Updates…** entry
points make this cancellation reachable
([update UX resolution](https://github.com/hadrysm/foldwise-voice/issues/284#issuecomment-5078876616)).
Incident communication for a prepared ordinary release can therefore say:

> Do not quit FoldWise. Open Check for Updates…, choose Skip This Version, and
> wait for confirmation that the update window has closed before quitting.

This is a user action, not a remote control. It must not be promised for an
update marked critical: Sparkle 2.9.4's standard non-major critical alert hides
both Skip and Later
([critical alert controls](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUUpdateAlert.m#L472-L483)).

## Feed rollback versus application downgrade

Sparkle chooses the greatest eligible `sparkle:version`; XML order and
`pubDate` are not release precedence. Equal versions use the first matching
item only as a tie-breaker, and an update is offered only when its version is
strictly greater than the installed `CFBundleVersion`
([best-item selection](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUAppcastDriver.m#L525-L578)).
FoldWise has already chosen to keep `CFBundleVersion`,
`CFBundleShortVersionString`, `sparkle:version`, and the release version equal,
with every distributed rebuild receiving a new version
([artifact/version resolution](https://github.com/hadrysm/foldwise-voice/issues/281#issuecomment-5078776778)).

Restoring a feed whose highest item is the prior good version therefore has two
useful effects:

- clients older than that good version can still update to it; and
- clients already on that good version see no update.

It cannot help a client already on the higher bad version. The regular
application installer independently rejects an incoming bundle whose
`CFBundleVersion` is lower than the installed bundle, using Sparkle's standard
comparator as an anti-downgrade security rule
([downgrade rejection](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Autoupdate/SUPlainInstaller.m#L323-L343),
[comparator warning](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUUpdaterDelegate.h#L376-L389)).

Accordingly, "roll back the code" means build the known-good source plus the
minimal repair as a **newer release**. Republishing the old version, putting an
old item first, changing its date, or relabeling the old archive cannot recover
an installed bad version. A manual old-DMG reinstall is outside Sparkle's
supported update path and should not be the standard incident plan.

### When a manual downgrade is allowed

A true downgrade means support instructs the user to replace the app manually
with a retained older DMG; Sparkle does not perform or validate that transition.
Treat it as an exceptional support procedure, and offer it only when all of
these are true:

- the bad release cannot launch or cannot run a trustworthy update check;
- producing a higher-version manual repair quickly is not possible;
- the older app is proven able to read every configuration and persisted-data
  shape the bad release may have written;
- the retained DMG is the original Developer ID-signed, notarized,
  checksum-verified artifact with the same bundle identifier and Team ID; and
- the full replace-and-relaunch path has been tested on a copy of affected user
  data.

If the bad release migrated or damaged persisted data, changed an external
protocol, or still has a working Sparkle path, a higher-version forward repair
is mandatory. When speed matters, that repair can be the last-known-good source
rebuilt under a new version plus only the compatibility or data-repair code
needed to consume the bad release's state.

## Appcast controls during an incident

### Removing the bad item

The live feed must not retain a known-bad item. If a later repair is
incompatible with some OS or branch, leaving the bad item below it can make the
bad item the greatest eligible fallback. First preserve private evidence, then
move or deny the bad DMG outside the public R2 namespace without overwriting its
URL. Restore the last-known-good, byte-for-byte signed feed snapshot
immediately afterward. Purge the bad-object and feed paths and verify from an
unauthenticated client that:

- the feed signature validates and contains no bad item or enclosure URL;
- the previous known-good items and URLs remain valid; and
- the bad archive URL no longer returns installable bytes.

The chosen origin already requires a revalidating, cache-bypassed
`appcast.xml`, immutable versioned R2 DMGs, archive-first/feed-last publication,
and public byte verification
([hosting and signing resolution](https://github.com/hadrysm/foldwise-voice/issues/283#issuecomment-5078878034)).
Restoring the exact previous signed feed is the fastest safe withdrawal because
its signature remains valid. Any newly edited emergency feed must be signed
again; with `SURequireSignedFeed`, Sparkle rejects modified unsigned bytes
([signed-feed verification](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUAppcastDriver.m#L91-L182)).

### Informational recovery notice

If the bad app can check the feed but cannot safely accept an automatic repair,
Sparkle 2 supports making a newer item informational only for that exact bad
version. Its **Learn More…** link can lead to a status page and a manually
installed higher-version repair. Other source versions may still treat the same
item as installable. This is a supported way to surface recovery instructions,
not a recall and not a downgrade
([official informational-update format](https://sparkle-project.org/documentation/publishing/#downloading-from-a-web-site)).

Do not use an informational item when the automatic forward repair is safe:
every extra manual step reduces recovery. It also cannot reach a build that
does not launch or run Sparkle, so external communication remains mandatory for
that failure.

### Critical recovery release

A critical item is presented more promptly and cannot normally be skipped; it
is not a recall flag and it does not bypass the strictly-newer requirement
([official critical-update behavior](https://sparkle-project.org/documentation/publishing/#critical-updates)).
Critical items do bypass phased-rollout eligibility
([phased filter](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUAppcastDriver.m#L603-L629)).

Publish the forward repair without `sparkle:phasedRolloutInterval` and mark it
critical for every earlier version by emitting `<sparkle:criticalUpdate/>`
without a version bound. This reaches users on the bad version and all older
eligible versions. It still must pass channel, OS/hardware, minimum-version,
version-order, feed-signature, archive-signature, and code-signing checks.

### Skipped updates

For an ordinary minor release, Sparkle persists the skipped
`sparkle:version` and filters out items at or below that version during
background checks. A greater forward-repair version escapes that skip.
User-initiated checks ignore/clear stored skip state
([skip storage](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUSkippedUpdate.m#L36-L69),
[skip filtering](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUAppcastDriver.m#L580-L600),
[manual-check clearing](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUUIBasedUpdateDriver.m#L186-L216)).
Republishing a correction at the same skipped version is therefore wrong even
before considering immutable URLs and signature mismatch.

Major-upgrade skips have broader train semantics, but FoldWise's map explicitly
rules out a beta/prerelease channel and has not chosen paid major upgrades. If
that changes, `sparkle:ignoreSkippedUpgradesBelowVersion` needs a separate
policy; Sparkle documents the distinction in its
[major-upgrade rules](https://sparkle-project.org/documentation/publishing/#major-upgrades).

### Phased groups

Sparkle uses seven groups derived from a random identifier in app user defaults.
For background checks, group `n` becomes eligible at
`pubDate + n × phasedRolloutInterval`. The identifier is regenerated after a
phased update downloads and is never sent to the server. Manual checks and
critical updates bypass the filter
([official phased-rollout behavior](https://sparkle-project.org/documentation/publishing/#phased-group-rollouts),
[group implementation](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUPhasedUpdateGroupInfo.m#L18-L44),
[post-download regeneration](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SPUCoreBasedUpdateDriver.m#L166-L183)).

There is no server-visible group list and no group-targeted recall. Phasing only
limits how many automatic clients become eligible before an operator withdraws
the item. Use `--phased-rollout-interval 86400` for routine releases; omit it
for a critical forward repair.

## Trust and signing constraints on the repair

The repair DMG must be a new immutable artifact generated through FoldWise's
already-chosen order: sign nested code and app, create the DMG, notarize and
staple it, generate release notes, run `generate_appcast`, upload and verify the
DMG, then publish the signed feed
([artifact order](sparkle-update-artifact-versioning-and-release-notes.md),
[release signing pipeline](https://github.com/hadrysm/foldwise-voice/issues/285)).

For application-bundle updates, Sparkle accepts archive trust through the old
embedded Ed25519 key or a matching valid Apple code-signing identity, while
also refusing to remove an existing EdDSA key or code signature
([update trust policy](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUUpdateValidator.m#L272-L306),
[validation against the old app](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/Sparkle/SUUpdateValidator.m#L335-L376)).
FoldWise should take the uncomplicated path: keep `SUPublicEDKey`, the matching
private key, bundle identifier `com.foldwise.voice.native`, Team ID
`6849P798YW`, and Developer ID Application identity continuity unchanged. The
separate certificate-rotation policy permits a same-Team leaf rotation only
while the Ed25519 key is held constant
([certificate-rotation decision](developer-id-certificate-rotation-policy.md)).

Losing the Ed25519 private key, losing/revoking the usable Developer ID
identity, changing both trust anchors in one release, publishing an improperly
signed feed, or shipping a bad build that cannot launch its updater can make
normal forward recovery unavailable or delayed. Those cases require the
documented key-rotation escape path where applicable, or a manually downloaded
Developer ID-signed and notarized repair. They do not make a true Sparkle
downgrade supported.

## Operator runbook

### Preparedness before every release

1. Use a 24-hour phased interval for ordinary updates; do not mark them
   critical.
2. Preserve all good items in the live appcast with
   `generate_appcast --maximum-versions 0`. Sparkle 2.9.4 otherwise defaults to
   three versions per branch, moves pruned inputs to `old_updates/`, and can
   delete them after two weeks when `--auto-prune-update-files` is used
   ([generator retention options](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/generate_appcast/main.swift#L120-L163),
   [pruning behavior](https://github.com/sparkle-project/Sparkle/blob/b6496a74a087257ef5e6da1c5b29a447a60f5bd7/generate_appcast/main.swift#L177-L196)).
3. Retain, outside the mutable publication working directory:
   - every final notarized/stapled DMG and its checksum;
   - every published signed `appcast.xml` snapshot;
   - the release/version manifest and version-scoped release notes;
   - the source commit and reproducible build inputs for the last-known-good
     release;
   - the Sparkle Ed25519 private-key recovery copy and public-key fingerprint;
   - the Developer ID `.p12`, password reference, notary credentials, and
     identity metadata required by the existing certificate policy; and
   - R2 credentials capable of uploading/restoring the feed, purging cache, and
     quarantining a bad archive.
4. Test three incident paths in a production-like environment: withdraw before
   download, cancel a non-critical prepared update via Check for Updates…, and
   update from an installed bad build to a higher critical repair.

### Response after declaring a release bad

1. Freeze the release publisher and preserve the current bad feed and DMG in
   private incident evidence.
2. Move or deny the bad DMG outside the public namespace without putting
   different bytes at its immutable URL. Purge that path and verify it is
   unavailable.
3. Restore the last-known-good signed appcast snapshot to R2. Purge the feed
   cache and verify its signature and contents from the public hostname.
4. Communicate that anyone who sees the non-critical update already prepared
   must keep FoldWise open, use **Check for Updates… → Skip This Version**, and
   only then quit. Do not claim this works for a critical prepared update.
5. Cut a new release version greater than the bad version. Base it on the
   last-known-good source plus the minimal fix, preserve both trust anchors,
   notarize/staple it, and validate an actual bad-to-repair Sparkle update.
6. Upload and byte-verify the repair DMG first. Generate and publish the signed
   appcast last, with the repair marked critical and no phased interval.
7. Verify these client states: last-known-good, prepared bad, installed bad,
   skipped bad, and a clean older install. Keep the bad item out of every
   subsequently generated live appcast.

## Recovery boundary

| Client state when withdrawal lands | Supported response |
| --- | --- |
| Has not fetched/selected the bad item | Restored feed prevents selection; an older client may still receive the retained known-good item. |
| Is downloading the bad DMG | Quarantining the public object may fail the download, but an already-open response may complete; treat the client as potentially exposed. |
| Has the bad update prepared for install-on-Quit | Feed changes do nothing. For a non-critical item, use Check for Updates… and Skip before quitting. A critical prepared item has no supported standard-UI cancel. |
| Installed bad version and updater still runs | Publish and install a higher-version, signed, notarized, unphased critical forward repair. |
| Installed bad version can check the feed but must recover manually | Publish a newer informational item targeted at the bad version, linking to the recovery page and a higher-version manual repair. |
| Installed bad version cannot launch or cannot run Sparkle | Provide a manually downloaded Developer ID-signed and notarized repair with a higher version; support instructions may need to replace the app outside Sparkle. |
| Installed bad version but only an older good DMG is available | No supported Sparkle recovery. Prefer building a new higher-version repair; allow manual downgrade only after proving persisted-data compatibility and the retained artifact's trust. |
