# CI authentication for Apple's notary service

## Question

Should FoldWise's release workflow authenticate `notarytool` with an Apple
Account and app-specific password, or with an App Store Connect API key?

## Recommendation

Use a dedicated **Team App Store Connect API key** for CI, assign it the
**Developer** role, and validate it against the notary service before switching
the workflow from its current Apple Account-shaped credential contract.

This is a machine-owned credential with an independent revocation boundary. It
does not make a release depend on one person's Apple Account password and 2FA
lifecycle. The Developer role is the narrowest role to which Apple's roles page
grants full “Notarize software” access; Account Holder, Admin, and App Manager
also have that permission
([Apple Developer Program roles](https://developer.apple.com/help/account/access/roles/)).
Apple does not publish a separate `notarytool` API-key role matrix, so validating
the Developer-role key with `notarytool history` and then one real submission is
a rollout requirement, not an optional confidence check.

This recommendation has an important scope caveat: an App Store Connect Team key
is **not notarization-only**. Apple says the selected role determines its
permissions, but a Team key applies across all apps and cannot be limited to one
app. It is nevertheless better bounded than a person's Apple Account credential:
use a dedicated key with the Developer role, never an Admin key
([Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api),
[App Store Connect API setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)).

Use a **Team** key, not an Individual key. Apple's current API documentation
explicitly says Individual keys cannot use `notaryTool`
([Creating API Keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)).
There is a first-party documentation conflict: the locally installed Xcode 26.2
`notarytool` 1.1.0 (39) manual says Individual keys are supported when
`--issuer` is omitted. The Team-key route avoids that ambiguity, and both the
manual and Apple's technote agree on its invocation.

## Comparison

| Concern | Apple Account + app-specific password | Team App Store Connect API key |
| --- | --- | --- |
| Authentication identity | Uses a developer's Apple Account, app-specific password, and Team ID. Apple requires the account to have 2FA before it can generate or use app-specific passwords ([Apple Support](https://support.apple.com/en-us/102654), [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)). | At runtime, `notarytool` uses a Team key's private `.p8`, key ID, and issuer ID; no person's Apple Account is passed to CI ([TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)). An Account Holder or Admin still administers Team keys in App Store Connect ([App Store Connect API setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)). |
| Scope | The notary service authorizes the Apple Account for a developer team. Apple documents no way to issue a notarization-only app-specific password. | Role-scoped, so the key can use the Developer role instead of Admin. It is still team-wide across all apps and not notarization-only ([Creating API Keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)). |
| Revocation | Up to 25 app-specific passwords can be active; one password or all passwords can be revoked. Changing or resetting the Apple Account's primary password automatically revokes **all** app-specific passwords, including the CI credential ([Apple Support](https://support.apple.com/en-us/102654)). | A Team key can be revoked independently without changing a person's sign-in credentials. Revocation is irreversible, and Apple says to revoke immediately when a key is unused, lost, or compromised ([Revoking API Keys](https://developer.apple.com/documentation/appstoreconnectapi/revoking-api-keys)). |
| Rotation and leak response | A dedicated password can be replaced and individually revoked, but an unrelated primary-password reset also breaks CI. The credential remains coupled to that person's continued team access and accepted agreements (`man notarytool`, Xcode 26.2). | Multiple Team keys may coexist, enabling generate → install → validate → revoke rotation. A key's role cannot be edited; changing access requires a replacement key. The private key is downloadable only once, Apple keeps no copy, and Apple says never to put it in a source repository ([Creating API Keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api), [App Store Connect API setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)). |
| GitHub Actions values | Three values: Apple Account email, app-specific password, and Team ID. No temporary file is needed. | Three values: private key material, key ID, and issuer ID. `notarytool` requires the private key as a filesystem path, so the workflow must create and remove a temporary file ([TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool), `man notarytool`). |
| Failure blast radius | An app-specific password can be revoked alone, but primary-password recovery revokes every app-specific password for that personal account ([Apple Support](https://support.apple.com/en-us/102654)). | A dedicated release key can be revoked alone. Its remaining blast radius is the Developer role across all apps, because Apple provides no per-app or notarization-only restriction for Team keys ([Creating API Keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)). |

The API key does not reduce the number of configured GitHub values, and its
temporary file is a small implementation cost. Its advantages are ownership,
role selection, isolated revocation, and rotation that does not disturb a
person's Apple Account.

## Exact GitHub Actions secret contract

Configure these three repository or release-environment secrets:

- `NOTARY_API_PRIVATE_KEY_BASE64` — Base64 of the complete, one-time-downloaded
  `.p8` private-key file.
- `NOTARY_API_KEY_ID` — the App Store Connect Team key ID.
- `NOTARY_API_ISSUER_ID` — the Team key's issuer UUID.

Only the `.p8` is private cryptographic material; the other two values are
identifiers. Keeping all three as separate Actions secrets matches the existing
workflow's secret-only configuration surface and avoids wrapping credentials in
structured data. GitHub warns that log redaction is not a security boundary
([GitHub Actions secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use)).

Base64 makes a file-shaped secret a reliable single-line Actions value; it does
not encrypt it. GitHub explicitly supports Base64-encoding a small file into a
secret and decoding it on the runner, and warns that Base64 is not a substitute
for encryption
([Using secrets in GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)).
The value remains protected by GitHub's secret storage, while the decoded file
exists only for the notarization step.

Materialize and use the key in the same step:

```yaml
env:
  NOTARY_API_PRIVATE_KEY_BASE64: ${{ secrets.NOTARY_API_PRIVATE_KEY_BASE64 }}
  NOTARY_API_KEY_ID: ${{ secrets.NOTARY_API_KEY_ID }}
  NOTARY_API_ISSUER_ID: ${{ secrets.NOTARY_API_ISSUER_ID }}
run: |
  set -euo pipefail
  umask 077
  NOTARY_KEY_PATH="${RUNNER_TEMP:?}/notary-api-key.p8"
  trap 'rm -f "$NOTARY_KEY_PATH"' EXIT

  printf '%s' "$NOTARY_API_PRIVATE_KEY_BASE64" |
    base64 --decode > "$NOTARY_KEY_PATH"
  test -s "$NOTARY_KEY_PATH"

  xcrun notarytool submit dist/FoldWise-Voice-*.dmg \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_API_KEY_ID" \
    --issuer "$NOTARY_API_ISSUER_ID" \
    --wait
  xcrun stapler staple dist/FoldWise-Voice-*.dmg
```

`umask 077` restricts the newly created file to the runner user, the guarded
`${RUNNER_TEMP:?}` expansion refuses an unset temp directory, `printf` avoids
shell reinterpretation of the value, and the `EXIT` trap removes the file on
success or ordinary failure. Do not enable shell tracing, print the environment,
or inspect the private key in logs. These are CI hardening choices inferred from
Apple's requirements that `--key` receive a file path and that the private key
remain secret; GitHub notes that a compromised runner can read any secret the
job uses, regardless of masking
([Apple TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool),
[GitHub on compromised runners](https://docs.github.com/en/actions/concepts/security/compromised-runners)).

The installed `notarytool` manual and TN3147 define the Team-key flags:
`--key` is the private-key path, `--key-id` is the App Store Connect key ID, and
`--issuer` is the issuer UUID and is required for Team keys
([TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)).
No `--apple-id`, `--password`, or `--team-id` is used on this route.

## Provisioning, validation, and rotation

1. Have an Account Holder or Admin create a named Team key such as
   `FoldWise GitHub Actions notarization`, assign the Developer role, and
   download the `.p8` once. Apple says it does not retain a copy
   ([Creating API Keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)).
2. Base64-encode the complete file locally and set the three secrets above.
   Never commit the raw key, encoded key, or a generated credential file.
3. Validate the same direct credential form before cutover:

   ```bash
   xcrun notarytool history \
     --key /path/to/AuthKey_KEYID.p8 \
     --key-id KEYID \
     --issuer ISSUER_UUID
   ```

   `history` accepts the same authentication options as `submit`
   (`man notarytool`, Xcode 26.2). Run a real signed-artifact submission before
   marking credential provisioning complete because it verifies the complete
   release path.
4. For planned rotation, generate a second Developer-role Team key, replace all
   three GitHub secrets, validate the new credential, then revoke the old key.
   Apple permits multiple Team keys and requires replacement rather than editing
   a key's access level
   ([App Store Connect API setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)).
5. For a suspected leak, revoke the key in App Store Connect immediately, then
   replace the GitHub secrets and validate a newly generated key. Revocation
   cannot be undone
   ([Revoking API Keys](https://developer.apple.com/documentation/appstoreconnectapi/revoking-api-keys)).
   If the value reached an Actions log, delete the affected log and rotate the
   key; GitHub explicitly recommends deletion and rotation for exposed secrets
   ([GitHub Actions secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use)).

## Decision

Adopt a dedicated Developer-role **Team App Store Connect API key** using
`NOTARY_API_PRIVATE_KEY_BASE64`, `NOTARY_API_KEY_ID`, and
`NOTARY_API_ISSUER_ID`. Materialize the `.p8` under `RUNNER_TEMP` with
owner-only creation permissions and an `EXIT` cleanup trap, then call
`notarytool submit` with `--key`, `--key-id`, `--issuer`, and `--wait`.

The choice does not achieve notarization-only authorization—Apple offers no such
Team-key scope—but it is the cleaner CI identity: independently revocable,
role-bounded, and not coupled to a person's Apple Account password or 2FA
lifecycle.
