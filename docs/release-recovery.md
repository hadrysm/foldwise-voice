# Bad-release withdrawal and Forward repair

Use this runbook only after declaring an advertised Sparkle release bad. It
contains the release without attempting a downgrade.

## What withdrawal can and cannot do

Withdrawal protects clients that have not prepared the bad release. An update
already prepared for install-on-Quit cannot be recalled by changing the feed or
removing its archive.

For a prepared **non-critical** update, tell the user:

> Keep FoldWise open. Open **Check for Updates…**, choose
> **Skip This Version**, wait for the update window to close, and only then
> quit.

Do not offer that guidance for a prepared critical update: Sparkle's standard
UI has no supported Skip or Later action in that state. Routine publication is
therefore always phased and non-critical. Only the explicit Forward-repair
path can create an unphased critical item.

## Withdraw the bad release

1. Stop other release work and identify the last-known-good release tag. Its
   durable GitHub Release assets include the notarized DMG,
   checksum-bearing `publication.json`, source commit/run,
   `appcast-before.xml`, `appcast-published.xml`, and actionable references to
   both signing recovery paths. The finalizer also creates a 90-day
   `release-record-<run-id>-<attempt>` workflow artifact as a convenience copy;
   recovery does not depend on that expiring artifact.
2. Run the **release-recovery** workflow with `execute` off. Review its complete
   plan. A dry run requires no production authorization and cannot call R2 or
   Cloudflare mutation APIs. The command verifies the signed snapshot against
   the SHA-256 stored in that release's `publication.json`.
3. Re-run it with `execute` on and enter `WITHDRAW <bad-version>` exactly. The
   workflow requires the scoped R2 credentials plus
   `UPDATE_CF_API_TOKEN`/`UPDATE_CF_ZONE_ID`.
4. Preserve the private `release-incident-*` artifact outside the mutable
   publication directory according to the project's incident-retention policy.

Execution validates the last-known-good signed snapshot before mutation, then:

1. publishes and publicly verifies the routine-publication freeze;
2. captures the current bad feed and DMG with SHA-256 evidence;
3. deletes the bad immutable archive without replacing its URL;
4. purges and verifies that archive URL;
5. restores the last-known-good appcast byte-for-byte;
6. purges and verifies the public feed.

Every routine publication checks the public freeze before generating or
uploading anything, so an incident cannot race a later routine release.

## Publish a Forward repair

1. Cut a release whose release version, build version, filename, and appcast
   version are equal and strictly greater than the bad version. Never rebuild,
   overwrite, or republish the bad version.
2. Keep the bundle identifier, Team ID, Developer ID identity, and Sparkle
   Ed25519 key continuous. Complete signing, notarization, stapling, and the
   normal strict artifact checks.
3. Validate an installed bad build updating to this exact repair artifact.
   Record the acceptance run or evidence URL.
4. Run the credential-free plan before authorizing publication:
   `python3 scripts/release_recovery.py plan-forward-repair --bad-version
   <bad-version> --repair-version <repair-version> --validation-reference
   <evidence>`. This validates the repair constraints without making network
   requests or mutations.
5. Explicitly dispatch **release-please** for the preserved source run with:
   `publication_mode=forward-repair`, the bad version, the validation
   reference, and `PUBLISH FORWARD REPAIR <repair-version>` exactly.

The finalizer rejects an equal/lower repair, missing validation evidence,
partial recovery arguments, and an inexact confirmation. The Forward-repair
policy is the only path that bypasses the incident freeze. It publishes the
immutable archive first and the signed appcast last, with
`sparkle:criticalUpdate` and no phased-rollout interval.

Keep routine publication frozen until the public repair and representative
client states are verified. Remove
`controls/publication-frozen.json` only through a separately reviewed operator
action, purge that exact URL, and verify it returns no bytes before resuming
routine releases.
