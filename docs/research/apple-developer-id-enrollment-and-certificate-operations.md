# Apple Developer enrollment and Developer ID identity

Research for **Enroll in the Apple Developer Program and obtain the Developer ID
identity**, current as of 2026-07-25. Every external source below is published by
Apple. This note contains no real Team ID, certificate identity, credential,
backup location, or private-key material.

## Operational answer

An individual enrollee needs an Apple Account with two-factor authentication,
must be the age of majority in their region, and must use their legal identity.
Apple may request government identification. Enrollment costs 99 USD per
membership year, with regional pricing where available. When enrolling on the
web as an individual and paying by credit card, Apple says to use the enrollee's
own card. Check enrollment status by signing in at
[developer.apple.com/account](https://developer.apple.com/account/) with the
same Apple Account; if membership confirmation has not arrived within 24 hours
after purchase, contact Apple Developer Support with the Enrollment ID
([Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/),
[Identity verification](https://developer.apple.com/help/account/membership/identity-verification/)).

Once active, **Membership details** shows the Team ID, role, and renewal date.
The Team ID is Apple's unique 10-character identifier for the membership
([Account landing page](https://developer.apple.com/help/account/basics/account-landing-page/),
[Team ID](https://developer.apple.com/help/glossary/team-id/)). An individual
member is the Account Holder of their one-person team, and Apple requires the
Account Holder role to create a conventional Developer ID certificate
([Certificates overview](https://developer.apple.com/help/account/certificates/certificates-overview),
[Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)).

Do not treat purchase acknowledgment alone as completion. Proceed when the
signed-in account exposes active Membership details and Certificates,
Identifiers & Profiles.

## Create the CSR on the signing Mac

Use the Mac whose keychain will hold the signing private key:

1. Open Keychain Access.
2. Choose **Keychain Access > Certificate Assistant > Request a Certificate
   from a Certificate Authority**.
3. Enter the Apple Account email address.
4. Give the key a descriptive Common Name.
5. Leave **CA Email Address** empty.
6. Choose **Saved to disk**, then save the `.certSigningRequest`.

These are Apple's published
[CSR steps](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/).
In this classic flow, Keychain Access creates the public/private key pair in the
login keychain while the CSR contains the public key. Apple never receives the
private key. After the issued `.cer` is imported on that Mac, Keychain Access
pairs it with the private key to form the digital identity shown under **login >
My Certificates**
([Certificate Signing Requests Explained](https://developer.apple.com/forums/thread/699268)).
This is why the CSR should be generated on the intended signing Mac unless the
complete identity will later be moved via a protected `.p12`.

## Create and install Developer ID Application

While signed in as the enrolled Account Holder:

1. Open **Certificates, Identifiers & Profiles > Certificates**.
2. Click **+**.
3. Under **Software**, choose **Developer ID**, continue, and select
   **Developer ID Application** (not Developer ID Installer).
4. Upload the `.certSigningRequest`, continue, and download the issued `.cer`.
5. Double-click the `.cer` to add it to the keychain.
6. In Keychain Access, select **login > My Certificates**. Confirm the
   `Developer ID Application` entry expands to show its private key.

Apple identifies Developer ID Application as the certificate for signing a Mac
app distributed outside the Mac App Store, requires the Account Holder role,
allows up to five Developer ID Application certificates, and documents the
portal/install sequence above
([Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)).
An entry visible only under **Certificates**, with no matching private key under
**My Certificates**, is not a usable signing identity
([Certificate Signing Requests Explained](https://developer.apple.com/forums/thread/699268)).

## Export and protect the `.p12`

Export the complete identity, not merely the public certificate:

1. In Keychain Access, choose **login > My Certificates**.
2. Select the `Developer ID Application` identity and confirm its private key is
   nested beneath it.
3. Choose **File > Export Items** and select **Personal Information Exchange
   (`.p12`)**.
4. Save it with a strong export password and authorize the export with the
   keychain password.
5. Store the `.p12` and its password durably, with access controls appropriate
   to a release-signing credential. Do not place either in this repository,
   issue comments, logs, or other plaintext project records.

Apple describes a `.p12` as the password-protected PKCS#12 export of the signing
identity, including its private key, and warns that anyone who obtains both the
file and password can distribute software as the developer. Apple recommends a
strong password and separate channels when sharing the identity and password
([Synchronizing code signing identities](https://developer.apple.com/documentation/Xcode/sharing-your-teams-signing-certificates)).
Keychain Access also documents **File > Export Items** and the export password
([Import and export keychain items](https://support.apple.com/guide/keychain-access/import-and-export-keychain-items-kyca35961/mac)).

Record only the durable storage-system/location labels needed by the downstream
work. Do not record the `.p12` contents or password itself.

## Verify identity and expiry

### Keychain Access

Under **login > My Certificates**, select the Developer ID Application
identity. It must expand to a private key. Double-click the certificate and
check:

- the validity indicator;
- **Expires**; or
- **Details > Not Valid Before / Not Valid After**.

Apple's code-signing troubleshooting guidance uses these fields to diagnose an
expired certificate and notes that an expired identity does not appear among
valid identities
([Code-signing certificate diagnostics](https://developer.apple.com/forums/topics/code-signing-topic)).

### Terminal

List valid code-signing identities:

```sh
security find-identity -v -p codesigning
```

Look for the exact `Developer ID Application: … (<TEAMID>)` line and copy that
whole quoted name as `CODESIGN_IDENTITY`. Apple's documentation states that
`-p codesigning` selects code-signing identities and `-v` returns valid
identities only
([Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)).
Apple's `security(1)` source documents the same arguments
([security.1](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/security.1)).

To print the public certificate's subject and actual validity dates without
exporting the private key, substitute the exact identity:

```sh
security find-certificate \
  -c "Developer ID Application: EXAMPLE NAME (TEAMID)" \
  -p \
  | /usr/bin/openssl x509 -noout -subject -dates -fingerprint -sha256
```

`notAfter` is the expiry date to record. The pipeline uses `security
find-certificate` only to emit the matching public certificate in PEM form; the
private key is neither requested nor printed. Apple's `security(1)` source
documents `-c` name matching and `-p` PEM output, and Apple's certificate
technote demonstrates inspecting certificate data with `openssl x509`
([security.1](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/security.1),
[TN3161: Inside Code Signing: Certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates)).
If the common-name match could select more than one certificate, use Keychain
Access to confirm the leaf certificate and its **Not Valid After** field rather
than trusting the first match.

## Expiry facts

Developer ID certificates are normally valid for five years from creation.
Apple also states that a leaf certificate cannot extend beyond its issuing
intermediate certificate, so the certificate's actual **Not Valid After** value
is authoritative
([Developer ID support](https://developer.apple.com/support/developer-id/),
[Developer ID intermediate updates](https://developer.apple.com/support/developer-id-intermediate-certificate/)).

For an app that does not use a Developer ID provisioning profile, expiration
does not stop users from downloading and running a version signed while the
certificate was valid, but a new certificate is required for updates and new
apps. Revocation is materially different: Apple says a Developer ID app signed
with a revoked certificate can no longer be installed or launched. If program
membership lapses, already signed apps can still run, but active membership is
required to obtain a replacement after the certificate expires
([Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates),
[Developer ID support](https://developer.apple.com/support/developer-id/)).

## Facts to record after the manual work

- Team ID from **Membership details**.
- Exact quoted Developer ID Application identity from
  `security find-identity -v -p codesigning`.
- Actual `notAfter` / **Not Valid After** date.
- Durable storage location labels for the `.p12` and its password, without
  exposing either secret.
