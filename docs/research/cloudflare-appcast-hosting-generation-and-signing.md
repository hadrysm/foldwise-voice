# Cloudflare appcast hosting, generation, and signing

Research for
[Decide the appcast's hosting, generation, and signing](https://github.com/hadrysm/foldwise-voice/issues/283),
audited on 2026-07-25 against primary Sparkle, Cloudflare, GitHub, and local
repository sources.

## Decision

Use a Cloudflare R2 Standard bucket behind the project-owned custom domain
`updates.foldwise.app`. Host both the mutable `appcast.xml` and immutable,
versioned DMGs there. Keep uploading the exact same final DMG to GitHub Releases
for release bookkeeping, but do not make an installed app depend on the
repository's name, owner, visibility, or continued existence.

R2 is a better boundary than Pages for this job. Pages would be adequate for
the XML feed alone, but its 25 MiB per-file limit makes it a brittle home for
update archives; Cloudflare explicitly points larger files to R2
([Pages limits](https://developers.cloudflare.com/pages/platform/limits/)).
R2 supports objects far larger than FoldWise's current ~6.4 MB DMG and does not
charge Internet egress
([R2 upload limits](https://developers.cloudflare.com/r2/objects/upload-objects/),
[R2 pricing](https://developers.cloudflare.com/r2/pricing/)).

The recommendation also resolves a present distribution problem: the
repository is private, and an unauthenticated request for the current
`v0.16.0` GitHub Release DMG returns HTTP 404. A public feed that points to
private GitHub assets is not usable by Sparkle clients.

## Permanent public URLs

- Embed `https://updates.foldwise.app/appcast.xml` as `SUFeedURL`.
- Publish archives at immutable versioned paths such as
  `https://updates.foldwise.app/releases/FoldWise-Voice-0.17.0.dmg`.
- Never overwrite or delete a published versioned archive while an appcast
  item can reference it.
- Use the custom domain in production and disable the `r2.dev` development URL.
  Cloudflare describes `r2.dev` as a non-production surface and requires a
  custom domain for caching, WAF, and related controls
  ([R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)).

A project-owned hostname is the durable contract. The R2 bucket and even
Cloudflare itself remain replaceable behind DNS. GitHub redirects most web and
Git traffic after a repository rename, but a repository URL is still the wrong
permanent identity for an updater
([GitHub repository renames](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository)).

## Generation and publication order

Use Sparkle 2.9.4's `generate_appcast`; do not hand-author the feed. Sparkle's
documented flow is to archive the app, run `generate_appcast` over the archive
directory, and publish the resulting feed and archives
([Sparkle setup](https://sparkle-project.org/documentation/)).

For every release:

1. Sign the nested Sparkle components and outer app with Developer ID.
2. Create, notarize, and staple the final DMG.
3. Generate the version-scoped release-notes fragment beside the DMG.
4. Run `generate_appcast` with:
   - the existing appcast history present;
   - `--download-url-prefix https://updates.foldwise.app/releases/`;
   - an explicit output path for `appcast.xml`;
   - the private EdDSA key supplied on standard input via `--ed-key-file -`.
5. Upload the versioned DMG first with immutable caching.
6. Verify the public DMG URL and byte identity.
7. Upload `appcast.xml` last with revalidation caching, then verify the feed
   and enclosure URL from the public hostname.
8. Upload the identical DMG bytes to the GitHub Release.

Publishing the feed last prevents clients from seeing an enclosure that is not
yet available. Sparkle signs the final archive bytes and records their length,
so the DMG must not be mutated after appcast generation.

## Sparkle EdDSA key lifecycle

Generate one Ed25519 keypair with Sparkle's `generate_keys`. Embed only the
printed public key as `SUPublicEDKey`; the private key signs update archives.
Sparkle documents that `generate_keys` stores the private key in the login
Keychain and supports exporting and importing it for transfer or recovery
([Sparkle setup](https://sparkle-project.org/documentation/)).

For CI:

- Export the private key once and store its base64 text as a GitHub Actions
  secret, for example `SPARKLE_ED_PRIVATE_KEY`.
- Pipe that secret to `generate_appcast --ed-key-file -`. Sparkle 2.9.4's CLI
  explicitly documents standard input as the safe automation path; passing the
  secret as a command-line argument is deprecated
  ([Sparkle 2.9.4 `SigningOptions`](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/main.swift#L80-L97)).
- Keep an independent recovery copy in the maintainer's existing protected,
  backed-up secret store. Loss of the key prevents publishing updates trusted
  by already-installed versions. Suspected compromise requires shipping a
  manual recovery release with a new embedded public key; the leaked key must
  never be silently replaced in CI.
- Record the public key and a fingerprint/checksum in repository configuration
  so CI can fail if the supplied private key does not derive the expected
  public key.

Sparkle checks archive EdDSA signatures and also validates the incoming app's
Apple code-signing identity. The EdDSA key authenticates the archive bytes; it
does not replace Developer ID signing
([Sparkle security](https://sparkle-project.org/documentation/publishing/#security)).

Enable `SURequireSignedFeed` and its prerequisite
`SUVerifyUpdateBeforeExtraction`. This makes Sparkle validate the appcast and
embedded release information, verify the archive before extraction, and still
validate the incoming app's Developer ID identity before installation
([Sparkle signed feeds](https://sparkle-project.org/documentation/#signing-feeds-optional)).

Keep Sparkle's default `SUSignedFeedFailureExpirationInterval` of 1,728,000
seconds (20 days). It is a deliberate availability escape hatch: after a
continuous signed-feed validation failure, Sparkle may recover through a
Developer ID-authenticated key rotation while stripping untrusted release
notes, links, and unsupported informational-update data. Setting the interval
to `0` would disable this recovery and turn loss of the EdDSA key into a manual
reinstall for every user
([Sparkle customization](https://sparkle-project.org/documentation/customization/)).

## Cloudflare metadata and credentials

Store these HTTP metadata values on R2 objects:

- `appcast.xml`: `Content-Type: application/xml` and
  `Cache-Control: no-cache` (or `public, max-age=0, must-revalidate`), plus an
  explicit Cloudflare cache bypass for the path.
- Versioned DMGs: `Content-Type: application/x-apple-diskimage`,
  `Content-Disposition: attachment`, and
  `Cache-Control: public, max-age=31536000, immutable`.

R2 supports `Content-Type`, `Content-Disposition`, and `Cache-Control` object
metadata
([R2 S3 extensions](https://developers.cloudflare.com/r2/api/s3/extensions/)).
Avoid caching the mutable feed because Cloudflare warns that overwrites and
cached 404s may remain visible until expiry or purge
([R2 consistency](https://developers.cloudflare.com/r2/reference/consistency/)).

Use R2's S3-compatible API from GitHub Actions with an Object Read & Write token
scoped to the single update bucket. Store the access-key ID, secret access key,
account ID, and bucket name as Actions secrets or variables as appropriate.
Cloudflare documents bucket-scoped S3 credentials and recommends scoping them
to specific buckets
([R2 S3 credentials](https://developers.cloudflare.com/r2/get-started/s3/)).

## Rejected alternatives

- **GitHub Release asset as `SUFeedURL`:** tied to repository visibility and
  identity; currently inaccessible without authentication.
- **GitHub Pages:** cannot serve a private repository's release asset, retains a
  GitHub-owned hostname unless fronted by a custom domain, and has a 25 MiB
  file-size ceiling if it later hosts archives.
- **Cloudflare Pages for the feed plus R2 for archives:** workable, but creates
  two deploy targets and credential surfaces without adding useful separation.
- **Hand-authored appcast:** duplicates archive metadata and signing work that
  Sparkle's official generator already performs.
