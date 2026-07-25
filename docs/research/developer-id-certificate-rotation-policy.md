# Developer ID certificate rotation policy

Research for [Establish the Developer ID certificate rotation
policy](https://github.com/hadrysm/foldwise-voice/issues/289), current as of
2026-07-25. External claims below come from Apple or Sparkle primary sources.

## Decision

Rotate FoldWise's Developer ID Application certificate through an overlapping,
same-team cutover:

1. Keep the bundle identifier `com.foldwise.voice.native`, Team ID
   `6849P798YW`, and Sparkle Ed25519 key unchanged.
2. Create a second Developer ID Application identity after Apple makes a
   successor to the current G2 intermediate available. Confirm the new leaf's
   issuer and actual `notAfter` before treating it as the replacement.
3. Export the complete new identity as a protected `.p12`, install it in a
   staging release job, and prove the old-certificate app can update through
   Sparkle to the new-certificate app without losing effective TCC grants.
4. Prove code signing, notarization, stapling, Gatekeeper assessment, and the
   expected designated requirement before replacing the production signing
   secrets.
5. Keep the old identity archived and let it expire. Do **not** revoke it merely
   because rotation is complete.

Apple permits up to five concurrent Developer ID Application certificates, so
the overlap does not require destroying the current identity
([Create Developer ID
certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)).
Apple distinguishes expiration from revocation: properly signed apps without a
Developer ID provisioning profile remain installable and runnable after the
leaf expires, while revocation can prevent both installation and launch
([Developer ID support](https://developer.apple.com/support/developer-id/)).

## Verified FoldWise identity

The installed identity was inspected locally on 2026-07-25:

- Common name: `Developer ID Application: Mateusz Hadry (6849P798YW)`
- Team ID: `6849P798YW`
- Issuer: `Developer ID Certification Authority` / `G2`
- Valid from: `2026-07-25 13:21:43 UTC`
- Valid until: `2031-07-26 13:21:42 UTC`
- SHA-256 fingerprint:
  `D4:E9:78:96:97:A5:85:04:4B:15:D0:FB:D5:5C:C9:AB:7F:E3:3D:5F:80:86:7C:34:6A:89:FC:1B:C7:BC:33:A2`

A temporary Mach-O signed with this identity, the production identifier,
Hardened Runtime, and a secure timestamp produced this designated requirement:

```text
identifier "com.foldwise.voice.native"
and anchor apple generic
and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */
and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
and certificate leaf[subject.OU] = "6849P798YW"
```

It contains the code-signing identifier, Developer ID issuer/application
markers, and Team ID. It does **not** contain the leaf fingerprint, serial
number, validity dates, or common name. This matches Apple's documented default
Developer ID requirement
([TN3127: Inside Code Signing:
Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).

## What survives rotation

| Property | Same-team rotation result | Condition and proof |
| --- | --- | --- |
| Designated requirement | **Survives.** A replacement Developer ID Application leaf from Apple for Team `6849P798YW` satisfies the current default requirement. | Preserve `com.foldwise.voice.native`, the Developer ID Application certificate class, and Team ID. Before cutover, run Apple's bidirectional `codesign --test-requirement` checks between old- and new-signed bundles; do not add a custom requirement that pins the leaf. TN3127 explains both the requirement and the compatibility test. |
| TCC grants | **Survive under the standard requirement.** Microphone, Accessibility, and Input Monitoring see the new build as the same responsible code when it satisfies the requirement stored with the grant. | Team ID alone is not the contract; the full designated requirement is. Preserve the identifier and Team ID, then manually verify all three effective grants after an actual old-to-new update. TN3127 documents that macOS records a DR with privacy grants and tests later code against it. |
| Sparkle validation | **Survives, with the Ed25519 key held constant.** | Sparkle 2.9.4 copies the running app's DR and asks Security.framework whether the update satisfies it. Sparkle accepts a valid old Ed25519 signature or matching Apple code-signing identity, but its documented rotation protocol changes either the Developer ID certificate or the Ed25519 key in one update, not both ([Sparkle security setup](https://sparkle-project.org/documentation/), [`SUCodeSigningVerifier.m`](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUCodeSigningVerifier.m), [`SUUpdateValidator.m`](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUUpdateValidator.m)). |
| Notarization and Gatekeeper | **Survive.** A valid replacement Developer ID certificate can sign artifacts submitted to the same team's notary service. Existing securely timestamped releases do not need re-signing when the old leaf expires. | Continue Hardened Runtime, secure timestamps, notarization, and stapling. Apple says intermediate-certificate renewal does not change notarization and new Developer ID certificates may be submitted normally ([Developer ID intermediate update](https://developer.apple.com/support/developer-id-intermediate-certificate/), [TN3161: Inside Code Signing: Certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)). |
| CI | **The pipeline survives; the signing secret does not.** | Replace `MACOS_CERTIFICATE` with the new `.p12` and replace `MACOS_CERTIFICATE_PASSWORD`. `CODESIGN_IDENTITY` may retain the same human-readable common name, but CI must resolve exactly one imported identity and verify its Team ID and fingerprint. The Team App Store Connect API key used by `notarytool` is separate and need not rotate just because the signing leaf changes. Apple documents moving the complete certificate/private-key identity as a protected `.p12` ([Sharing signing certificates](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates)). |

These conclusions apply to routine expiry rotation inside Team `6849P798YW`.
Changing the Team ID, changing `com.foldwise.voice.native`, switching away from
a Developer ID Application identity, or embedding a leaf-pinned custom
requirement is a different identity migration and must not use this playbook.

## The G2 intermediate constraint

Apple's current Developer ID G2 intermediate expires on **2031-09-16**. Apple
also states that a leaf certificate cannot be valid beyond its issuer. The
current FoldWise leaf expires on **2031-07-26**, only about 52 days earlier
([Developer ID intermediate
update](https://developer.apple.com/support/developer-id-intermediate-certificate/)).

Consequently, creating another certificate under G2 well before July 2031 does
not produce a fresh five-year runway; its validity would still stop no later
than 16 September 2031. Rotation is ready only when the portal issues the
replacement under Apple's successor intermediate and the downloaded leaf's
actual `notAfter` extends materially beyond 26 July 2031. If Apple has not
published that path by the escalation dates below, contact Apple Developer
Support rather than cycling G2 leaves and assuming the problem is solved.

## Calendar safeguards

The Account Holder owns four durable calendar reminders, all carrying a link to
this policy and the protected `.p12` storage record:

- **2029-07-26 (T-24 months):** open the rotation tracking issue; verify
  membership renewal, backup access, Apple's current intermediate guidance, and
  available certificate slots.
- **2030-07-26 (T-12 months):** confirm successor-intermediate issuance is
  available. If it is, create the replacement identity and record issuer,
  fingerprint, and `notAfter`. If it is not, open an Apple Developer Support
  case.
- **2031-01-26 (T-6 months):** cutover deadline. Complete the production-like
  rehearsal and rotate the GitHub signing secrets. One ordinary release should
  ship with the replacement by this date.
- **2031-04-27 (T-90 days):** emergency boundary. No routine release may use
  fingerprint `D4:E9:…:33:A2`; only an explicitly approved hotfix may use the
  old identity while it remains valid.

Annual Apple Developer Program renewal remains a separate recurring safeguard:
an active membership is required to obtain the replacement certificate even
though already signed apps continue to run after membership lapse
([Developer ID support](https://developer.apple.com/support/developer-id/)).

## Release safeguards

Every production release should inspect the public leaf immediately after CI
imports the `.p12` and before any signing:

1. Fail if the certificate is not currently valid.
2. Fail if the subject OU / signing information is not Team `6849P798YW`.
3. Emit a GitHub Actions warning at 365 days remaining.
4. Fail routine releases at 90 days remaining unless an explicit,
   time-bounded emergency override is present.
5. Log the public fingerprint, issuer, and `notAfter`; never log the `.p12`,
   its password, or private-key material.

After signing, CI must also fail unless:

- the outer app's identifier and Team ID are the production values;
- its DR has the expected identifier + Developer ID + Team ID shape and does
  not pin the leaf;
- all nested code and the outer app have valid Developer ID signatures,
  Hardened Runtime, and secure timestamps;
- notarization succeeds, the ticket staples, and `spctl` accepts both app and
  DMG.

The rotation rehearsal adds two manual checks that a single-build CI job cannot
prove:

1. Start from the last production-like build signed by the old leaf, grant
   Microphone and Accessibility (and exercise Input Monitoring where used), then
   update through Sparkle to the new-leaf candidate. Confirm the update installs
   and all previously effective grants remain effective without prompts.
2. Confirm the candidate keeps the existing `SUPublicEDKey` and that its
   archive is signed by the corresponding existing Ed25519 private key. Rotate
   that key only in a later release if ever required.

Keep at least the last old-leaf release artifact and the new-leaf rehearsal
artifact until the cutover has shipped. They make the continuity test
reproducible. Routine rotation does not require changing the notary API key,
re-signing old releases, resetting TCC, changing the appcast URL, or revoking
the old certificate.
