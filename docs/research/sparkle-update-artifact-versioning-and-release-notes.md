# Sparkle update artifact, versioning, and release notes

Research answer for
[Decide the update artifact and version scheme Sparkle consumes](https://github.com/hadrysm/foldwise-voice/issues/281),
audited on 2026-07-25. External claims below use only Sparkle's official
documentation and Sparkle 2.9.4 source, plus Apple's bundle and notarization
documentation where relevant.

## Executive decision

Use the **same final DMG** as both the manual GitHub Release download and
Sparkle's full-update enclosure. Do not add a ZIP merely for Sparkle.
Sparkle explicitly says that DMG, ZIP, tar, and Apple Archive distributions can
generally be reused for website distribution and Sparkle updates, and recommends
a notarized, Developer ID-signed DMG for website distribution
([Sparkle setup and distribution](https://sparkle-project.org/documentation/)).

Keep `CFBundleVersion` and `CFBundleShortVersionString` equal to the
release-please version while every distributed release increments that version.
That is a valid and low-complexity scheme. Split them only if FoldWise needs to
publish two installable builds under the same human-visible release version; in
that case use a monotonically increasing numeric `CFBundleVersion` /
`sparkle:version` and retain the release version in
`CFBundleShortVersionString` / `sparkle:shortVersionString`.

Generate a release-specific HTML fragment from that version's `CHANGELOG.md`
section, give it the same basename as the DMG, and let `generate_appcast` embed
it in the appcast. Set the full-version-history link to the repository's rendered
`CHANGELOG.md`. Advertise macOS **14.0.0** as
`sparkle:minimumSystemVersion`, preferably by normalizing the bundle's
`LSMinimumSystemVersion` from `14.0` to `14.0.0` so the generator infers the
three-part value.

The release order must be:

```text
sign app and nested code
create DMG
submit DMG for notarization and staple it
generate CHANGELOG-derived release-notes HTML
run generate_appcast on the final DMG
publish that exact DMG, appcast, and any non-embedded notes/deltas
```

Any mutation of the DMG after `generate_appcast` invalidates its Sparkle EdDSA
signature and enclosure length.

## 1. DMG versus ZIP

### Recommendation and requirements

Sparkle accepts a regular `.app` in either a DMG or ZIP. The app should have the
same filename as the installed app it replaces, and the archive must preserve
framework symlinks or the app's code signature will be broken. Sparkle recommends
APFS plus LZFSE for DMGs for decompression speed; for ZIPs it gives a `ditto`
command that preserves the bundle and resource metadata
([publishing guide: archive formats](https://sparkle-project.org/documentation/publishing/#archive-your-app)).

The current FoldWise DMG already contains `FoldWise Voice.app` and an
`Applications` symlink. That manual-install layout is also valid input to
Sparkle:

- For a DMG, Sparkle mounts the image privately with `hdiutil`, ignores hidden
  top-level files, aliases, and symbolic links, copies the remaining readable
  content into its extraction directory, and detaches the image. It therefore
  ignores the drag-install `/Applications` link rather than following it
  ([DMG extractor](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUDiskImageUnarchiver.m#L123-L137),
  [filter and copy](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUDiskImageUnarchiver.m#L207-L287)).
- For a ZIP, Sparkle extracts with `/usr/bin/ditto -x -k`; it does not mount a
  volume
  ([ZIP extractor](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUPipedUnarchiver.m#L23-L42)).
- After either extraction path, the common installer finds the incoming app by
  installed bundle filename/display name, with matching bundle identifier as a
  fallback, and replaces the installed bundle. Sparkle does not show the
  manual drag-to-Applications DMG UI during an update
  ([incoming-app selection](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Autoupdate/SUInstaller.m#L24-L112)).

Thus the difference is extraction mechanics and performance, not the resulting
application installation. A ZIP may be smaller or faster for a particular app,
but Sparkle does not prescribe it as the preferred update format. Reusing the
already-required DMG removes a second artifact, second URL, and second set of
release validation without losing Sparkle functionality.

The current DMG is HFS+/UDZO
([build_swift_app.py](../../scripts/build_swift_app.py#L185-L219)). That remains
a supported DMG; APFS/LZFSE is a separate performance improvement suggested by
Sparkle, not a prerequisite for adopting the single-DMG decision.

## 2. Exactly what makes a build newer

Sparkle's normal decision is based on build versions, not GitHub tags, release
dates, filenames, or the human-facing version:

1. `SUHost.version` reads the installed app's required `CFBundleVersion`.
   `SUHost.displayVersion` separately reads `CFBundleShortVersionString`, falling
   back to the build version only for display
   ([host version source](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUHost.m#L138-L172)).
2. An appcast item's comparison version is `sparkle:version`; this corresponds
   to the update bundle's `CFBundleVersion`. Its optional display version is
   `sparkle:shortVersionString`, corresponding to
   `CFBundleShortVersionString`
   ([`SUAppcastItem` contract](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUAppcastItem.h#L41-L63)).
3. After filtering appcast items for such rules as system/hardware
   compatibility, channels, phased rollout, major upgrades, and skipped
   updates, Sparkle selects the greatest remaining `sparkle:version`. It reports
   an update only when comparing installed `CFBundleVersion` to that value
   returns strictly ascending; equality is not an update
   ([selection and newer test](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUAppcastDriver.m#L497-L577)).
4. Unless an app supplies a custom comparator, Sparkle uses its standard
   comparator. Sparkle documents the intended form as `x`, `x.y`, or `x.y.z`
   with numeric components; it compares numeric segments numerically and treats
   omitted trailing numeric components as zero
   ([comparator contract](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUStandardVersionComparator.h#L28-L58),
   [comparator implementation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SUStandardVersionComparator.m#L169-L273)).

Apple defines `CFBundleVersion` as a machine-readable string of one to three
period-separated integers, containing only digits and periods, and says macOS
apps must increment it before distributing a build
([Apple `CFBundleVersion`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)).
Apple defines `CFBundleShortVersionString` as the user-visible
`Major.Minor.Patch` release version
([Apple version-number glossary](https://developer.apple.com/help/glossary/version-number/)).
Sparkle likewise warns that the internal build number should be machine-readable,
not formatted prose or a Git changeset ID
([Sparkle internal build numbers](https://sparkle-project.org/documentation/publishing/#internal-build-numbers)).

`generate_appcast` removes manual synchronization risk: it extracts
`CFBundleVersion`, `CFBundleShortVersionString`, and `LSMinimumSystemVersion`
from the archived app, then writes them as the top-level `sparkle:version`,
`sparkle:shortVersionString`, and `sparkle:minimumSystemVersion` elements
([archive inspection](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/ArchiveItem.swift#L233-L267),
[appcast emission](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/FeedXML.swift#L467-L493)).
Sparkle now recommends these version values as top-level item elements, although
the older enclosure-attribute placement remains supported
([publishing guide](https://sparkle-project.org/documentation/publishing/#update-your-appcast)).

For FoldWise, equal values such as `0.17.0` are correctly ordered and satisfy
both roles. The only functional limitation is that a rebuilt `0.17.0` cannot
update an installed `0.17.0`; that use case is the trigger to introduce an
independent monotonic build number.

## 3. Release-notes mechanisms

Sparkle supports all of these mechanisms:

- External, version-specific HTML at `sparkle:releaseNotesLink`, which Sparkle
  downloads and renders.
- Embedded HTML in an item's `<description><![CDATA[...]]></description>`.
- Embedded plain text via `<description sparkle:format="plain-text">`.
- In Sparkle 2.9 on macOS 12+, embedded Markdown via
  `<description sparkle:format="markdown">`.
- `sparkle:fullReleaseNotesLink` for the full version history, normally opened
  in a browser when no newer update is available; it falls back to the
  version-specific release-notes link when absent
  ([embedded and full release notes](https://sparkle-project.org/documentation/publishing/#embedded-release-notes)).

`generate_appcast` looks for `.html`, `.txt`, `.md`, or `.markdown` beside the
archive with the same basename. By default an HTML fragment without
`<!DOCTYPE>` or `<body>` is embedded; a full HTML document is linked. The
`--embed-release-notes` flag forces embedding, and
`--release-notes-url-prefix` supplies the base URL for linked files
([generator CLI behavior](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/main.swift#L81-L113),
[file discovery and embedding](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/ArchiveItem.swift#L430-L519)).

The cleanest use of release-please's `CHANGELOG.md` is therefore:

1. Extract the section for the released version and render it to an HTML
   fragment such as `dist/FoldWise-Voice-0.17.0.html`.
2. Place it beside `dist/FoldWise-Voice-0.17.0.dmg`.
3. Run `generate_appcast`; it embeds the fragment automatically, so no
   independently hosted release-notes asset or signature is required.
4. Pass `--full-release-notes-url` pointing at the rendered repository
   `CHANGELOG.md` page to retain a browser-accessible full history
   ([generator full-notes option](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/main.swift#L102-L110)).

Using the raw whole `CHANGELOG.md` as each update's release notes would show
unrelated old releases. A derived per-version fragment preserves the existing
single source of truth while giving Sparkle the version-scoped content its UI
expects.

## 4. Minimum system version

The appcast representation is a child of the item:

```xml
<sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
```

Sparkle's publishing guide calls for a three-part `major.minor.patch` value
([minimum system requirements](https://sparkle-project.org/documentation/publishing/#minimum-system-version-requirements)).
Apple likewise defines `LSMinimumSystemVersion` as the minimum macOS release
that may run the app, and its detailed key reference specifies `n.n.n`
([Apple `LSMinimumSystemVersion`](https://developer.apple.com/documentation/bundleresources/information-property-list/lsminimumsystemversion),
[Apple Launch Services key reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html#//apple_ref/doc/uid/20001431-113253)).

At runtime Sparkle compares the item's minimum version to the current system
using the standard version comparator and excludes the item when the minimum is
greater. A manual update check can tell the user the latest update exists but
requires a newer macOS version
([state resolver](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUAppcastItemStateResolver.m#L53-L61),
[incompatible-update message](https://github.com/sparkle-project/Sparkle/blob/2.9.4/Sparkle/SPUNoUpdateFoundInfo.m#L55-L70)).

`generate_appcast` infers the feed value from the archived app's
`LSMinimumSystemVersion`; if the key is absent, Sparkle 2.9.4's generator falls
back to `10.13`
([archive-item default](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/ArchiveItem.swift#L178-L198)).
FoldWise already sets `LSMinimumSystemVersion` to `14.0`, so generation will not
silently use that fallback. Normalize it to `14.0.0` when implementing the feed
so the app and generated appcast share the documented three-part form
([current bundle plist](../../scripts/build_swift_app.py#L76-L85)).

## 5. Artifact signing and appcast generation

Apple signing/notarization and Sparkle archive signing are separate layers:

- The app and nested code must carry their Developer ID signatures, and the
  distributed artifact should complete notarization and stapling before it is
  published
  ([Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
- The final DMG bytes also receive Sparkle's EdDSA signature. Sparkle recommends
  generating it automatically with `generate_appcast`; the enclosure records
  both `sparkle:edSignature` and the exact byte `length`
  ([Sparkle update security](https://sparkle-project.org/documentation/publishing/#secure-your-update)).
- `generate_appcast` extracts the archive, validates an existing app code
  signature and nested code, reads bundle metadata, calculates the archive
  signature, and emits the enclosure URL, length, MIME type, and EdDSA signature
  ([bundle validation and metadata](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/ArchiveItem.swift#L220-L267),
  [archive signing](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/Appcast.swift#L178-L217),
  [enclosure generation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/FeedXML.swift#L581-L603)).

Consequently, notarizing or stapling after appcast generation changes the DMG
covered by Sparkle's signature and length. The currently stapled DMG
([release workflow](../../.github/workflows/release-please.yml#L67-L85)) must be
the exact input to `generate_appcast` and the exact file uploaded to the GitHub
Release.

If FoldWise enables `SURequireSignedFeed`, `generate_appcast` additionally signs
the appcast and any external release-note files. Any later manual edit to those
files requires rerunning the generator. Embedded release notes avoid a separate
release-note-file signature, but the signed appcast still must remain byte-for-
byte as generated
([Sparkle setup: signed feeds](https://sparkle-project.org/documentation/),
[signed appcast generation](https://github.com/sparkle-project/Sparkle/blob/2.9.4/generate_appcast/FeedXML.swift#L642-L656)).

The implementation should supply `--download-url-prefix` for the GitHub Release
asset base URL and preserve the generated filename. A second ZIP would require
a second immutable signed artifact but would not improve the trust model.
