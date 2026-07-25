# ADR-0008: Sparkle updates require a stable Developer ID identity

## Status

Accepted (2026-07-25).

## Context

FoldWise's original updater only checked GitHub Releases, announced a newer
version, and opened its DMG in the browser. It did not authenticate, install, or
recover an update. Releases through v0.16.0 were self-signed under a designated
requirement that pinned one certificate leaf, had no Apple Team ID, and were
rejected by Gatekeeper.

Replacing an installed macOS app safely depends on a durable code-signing
identity. Sparkle verifies the incoming app's signing identity before
installation, while macOS keys Microphone, Accessibility, and Input Monitoring
decisions to the app's identity. Changing that identity is therefore both an
update-acceptance boundary and a one-time permission reset, not release polish.

## Decision

FoldWise uses Sparkle 2 as its single in-app update system. Release artifacts
are signed with the Developer ID Application identity for Team `6849P798YW`,
secure-timestamped, notarized, stapled, and Gatekeeper-verified before
publication. The bundle identifier and Team ID remain stable across releases.

Sparkle reads its signed appcast and immutable release archives from the
project-controlled **Update origin**. It authenticates the feed and archive
with the dedicated Ed25519 key and validates the incoming app's Developer ID
identity. The hand-rolled checker and its parallel update state are removed;
FoldWise keeps only its user-facing **Check for Updates…** entry points, which
invoke Sparkle's standard flow.

Automatic updates mean automatic checks and background preparation, followed
by silent installation when the user chooses to Quit. Reaching an idle pipeline
state never causes FoldWise to terminate or relaunch. If Quit or an
update-related relaunch is requested during an active **Dictation session**,
FoldWise postpones both Sparkle's relaunch and AppKit termination until the
complete press-to-insert cycle finishes.

Bad automatic releases use withdrawal plus **Forward repair**, never automatic
rollback. Operators remove the bad item and archive from the live Update
origin to contain further exposure, knowing that an already prepared
install-on-Quit cannot be recalled. Users who already installed the release
recover through a newly versioned, signed, notarized release whose build
version is greater than the bad one. Routine releases phase over seven days;
the repair is published unphased and critical after the bad-to-repair path is
verified. A true downgrade remains an exceptional manual support operation.

## The release sequence cannot be collapsed

At least two distinct releases under the final Developer ID identity are
required before automatic updating is proven:

1. Existing v0.16.x users manually install the Developer ID-signed and
   notarized transition release, v0.17.0. macOS treats the new designated
   requirement as a new app identity, so users refresh permissions once.
2. A later release with the same bundle identifier and Team ID is the first
   target that Sparkle can accept without another identity or permission
   transition.

The old build cannot install that transition through Sparkle: it has no Sparkle
runtime, and its self-signed identity does not match the incoming Developer ID
identity. Nor can one artifact prove an update from itself; an updater-capable
source must already be installed before it can accept a later target. Because
v0.17.0 shipped before the Sparkle integration, the updater-enabling release
also requires a manual install in the actual rollout, and the release after it
is the first one deliverable automatically.

## Rejected alternatives

- **Extend the hand-rolled updater.** Secure archive verification, staged
  replacement, authorization, relaunch, recovery, and macOS signing checks
  would duplicate Sparkle's security-sensitive machinery while retaining a
  second source of update truth.
- **Use a Homebrew cask as the primary channel.** A cask requires Homebrew and
  a user-driven package-manager workflow, so it cannot update the existing
  direct-download population in place. A cask may be evaluated later as a
  secondary distribution channel, but it does not replace the Update origin or
  Sparkle.
- **Relaunch whenever Dictation becomes idle.** Pipeline idleness is not user
  intent to interrupt the always-running app. Installation remains tied to
  explicit Quit, with active Dictation postponing termination.
- **Roll back to an older release automatically.** Sparkle selects only a
  strictly newer version, and prepared installs cannot be remotely recalled.
  Forward repair preserves version ordering and the signed-update trust chain.
