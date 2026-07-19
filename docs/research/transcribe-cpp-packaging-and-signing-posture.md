# transcribe.cpp packaging and signing posture

Research answer for
[**Choose the transcribe.cpp packaging and signing posture**](https://github.com/hadrysm/foldwise-voice/issues/201),
audited on 2026-07-19. This note covers acquisition, pinning, Swift exposure,
embedding, loading, signing, notarization, attribution, and upgrade gates for
transcribe.cpp v0.1.3. It does not decide model-download licensing, which is
covered separately by the
[Handy baseline license and immutable-artifact audit](handy-baseline-license-and-artifact-access.md).

## Executive answer

Adopt a **FoldWise-curated, checksum-pinned v0.1.3 binary package**, not the
published upstream ZIP directly and not an unpinned source build during an app
release:

1. Start from upstream tag `v0.1.3`, commit
   [`a94e021ef658dc7c788837341a13f6acea3baf3c`](https://github.com/handy-computer/transcribe.cpp/commit/a94e021ef658dc7c788837341a13f6acea3baf3c),
   and the published `TranscribeCpp.xcframework.zip` whose upstream SHA-256 is
   `b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd`
   ([v0.1.3 release metadata](https://api.github.com/repos/handy-computer/transcribe.cpp/releases/tags/v0.1.3)).
2. Check in a deterministic curator script that verifies the upstream digest,
   repairs only the archive's macOS framework topology by restoring the five
   symlinks that upstream created before packaging, validates the result, and
   repacks it without dereferencing links. Publish those audited bytes as a
   FoldWise-owned immutable release asset with a new SwiftPM checksum. The
   published upstream ZIP is not directly signable after normal extraction;
   the defect and proof are below.
3. Vendor the version-matched Swift wrapper sources from the same commit in
   FoldWise. The advertised standalone SwiftPM mirror does not exist publicly
   yet, the wrapper labels itself “in development (0.0.1),” and the direct
   binary target exposes only `CTranscribe`, not the idiomatic
   `TranscribeCpp` product
   ([Swift README](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/README.md),
   [Swift package](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Package.swift)).
4. At build time select and embed only the universal macOS
   `CTranscribe.framework` in `FoldWise Voice.app/Contents/Frameworks`, link the
   executable with `@executable_path/../Frameworks` in its run-path search
   paths, and copy runtime notices to `Contents/Resources`. An XCFramework is a
   build-time container of platform variants; the macOS app embeds its selected
   dynamic framework, not the whole XCFramework
   ([Apple XCFramework documentation](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle),
   [Apple bundle placement](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle)).
5. Sign explicitly inside out—framework, app, then DMG—with one Developer ID
   Application identity, a secure timestamp, and hardened runtime. Do not use
   `--deep` to sign. Submit the final signed DMG with `notarytool`, inspect its
   log, staple that exact DMG, and test it under Gatekeeper on both arm64 and
   x86_64
   ([Apple distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac),
   [Apple packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution),
   [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).

This should produce **one universal app and one universal DMG** unless another
device-support decision deliberately chooses architecture-specific products.
The transcribe framework already contains both architectures. A single artifact
avoids two identities, URLs, update paths, and opportunities to pair the wrong
app and framework slices. Either way, the current host-only `swift build`
command is not evidence that both architectures were produced; release CI must
assert the architecture set of the app executable and every embedded native
binary.

## What upstream v0.1.3 actually publishes

The annotated `v0.1.3` tag points to commit
`a94e021ef658dc7c788837341a13f6acea3baf3c`; the tag object itself is unsigned.
GitHub reports the peeled commit's signature as verified, but that does not
authenticate the separate release-asset bytes, so both commit and digest remain
part of the pin.
The release was published on 2026-07-12 and gives the XCFramework ZIP a
GitHub-computed SHA-256 digest and byte size of 13,089,928. Pinning the commit
and archive digest therefore matters even when the human-readable tag is also
recorded
([tag object](https://api.github.com/repos/handy-computer/transcribe.cpp/git/tags/d503d6a239e2a290a03ab72dbd3b40460d87acb0),
[peeled commit](https://github.com/handy-computer/transcribe.cpp/commit/a94e021ef658dc7c788837341a13f6acea3baf3c),
[release metadata](https://api.github.com/repos/handy-computer/transcribe.cpp/releases/tags/v0.1.3)).

The XCFramework manifest declares three variants: macOS arm64+x86_64, iOS
arm64, and iOS Simulator arm64+x86_64. Direct inspection of the published
macOS binary reports a universal Mach-O dynamically linked shared library with
`x86_64` and `arm64` slices, deployment target macOS 13, and install name
`@rpath/CTranscribe.framework/Versions/Current/CTranscribe`. The upstream build
script intentionally builds arm64 with Metal+CPU and x86_64 CPU-only, then
combines the two dylibs into a versioned macOS framework
([XCFramework build script](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/scripts/ci/build_xcframework.sh),
[Swift backend table](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/README.md#backends)).

Its only non-system dynamic identity is itself. The inspected macOS image links
Apple Foundation, Metal, MetalKit, Accelerate, `libc++`, `libSystem`, and (on
arm64) CoreFoundation and Objective-C runtime libraries. ggml and miniz are
already merged into `CTranscribe`; FoldWise does not need to locate or embed
additional third-party dylibs. The upstream script explains why this is a
dynamic framework rather than a static archive and force-loads the native
archives into that image
([XCFramework build script](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/scripts/ci/build_xcframework.sh)).

### Published-ZIP topology defect

The source build creates the conventional versioned-framework symlinks:

```text
CTranscribe                 -> Versions/Current/CTranscribe
Headers                     -> Versions/Current/Headers
Modules                     -> Versions/Current/Modules
Resources                   -> Versions/Current/Resources
Versions/Current            -> A
```

The v0.1.3 packaging script then calls `/usr/bin/zip -qr -X` without the
symlink-preservation option. In the published ZIP all five links have become
duplicate files or directories. After extraction with `ditto`, the framework
contains both a top-level executable/resources tree and the versioned tree;
`codesign --verify --strict --verbose=4 CTranscribe.framework` exits 1 with
`bundle format is ambiguous (could be app or framework)`. The release's binary
is ad-hoc signed, but the malformed outer framework cannot be validated or
re-signed as a framework bundle
([assembly source](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/scripts/ci/build_xcframework.sh),
[packaging source](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/scripts/ci/package_xcframework.sh),
[published asset](https://github.com/handy-computer/transcribe.cpp/releases/download/v0.1.3/TranscribeCpp.xcframework.zip)).

This is a packaging-only defect. Replacing the five duplicated paths with the
intended symlinks, without changing `Versions/A`, makes the original embedded
signature pass `codesign --verify --strict`. The release workflow tests the
unarchived build-tree XCFramework; it packages and checksums the ZIP but does
not extract that ZIP and validate its macOS framework topology or signature.
That explains how the defect can coexist with upstream Swift test success
([publish workflow](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/.github/workflows/publish.yml),
[Swift CI workflow](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/.github/workflows/swift-ci.yml)).

The audit is repeatable against the published digest with `shasum -a 256`,
`ditto -x -k`, `find`/`ls -l`, `file`, `lipo -archs`, `otool -L`, `plutil`, and
`codesign --verify --strict --verbose=4`. A FoldWise-curated artifact must add
an extracted-archive topology/signature test so this exact regression cannot
recur.

## Swift acquisition and update boundary

The upstream monorepo is not directly consumable as a normal remote Swift
package: its Swift `Package.swift` is under `bindings/swift`, expects a local
XCFramework path by default, and says a standalone mirror is only planned. A
direct remote binary target supports `import CTranscribe` only. Therefore the
smallest truthful initial boundary is:

- a FoldWise-owned remote `binaryTarget(url:checksum:)` pointing to the
  corrected immutable ZIP;
- version-matched wrapper sources vendored into a narrow FoldWise target; and
- the app's transcribe.cpp adapter depending on that wrapper target, while no
  other feature imports `CTranscribe` directly.

These facts come directly from the upstream
[package manifest](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Package.swift)
and
[publication-status README](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/README.md).
If the standalone upstream mirror is later published, FoldWise may replace its
curated source target only after the mirror passes the same binary identity,
ABI, packaging, signing, and runtime tests; publication alone is not an upgrade
signal.

This boundary is intentionally version-locked. The native header says its 0.x
on-disk ABI may break between minor releases and consumers must rebuild against
matching headers. The v0.1.3 wrapper pins `compiledVersion = "0.1.3"`, checks
the loaded library version at runtime, and pins public-header ABI digest
`86b16dd97ad1cb58`; upstream CI compares that value with
`include/transcribe.abihash`
([C ABI contract](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/include/transcribe.h#L50-L53),
[Swift version gate](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Sources/TranscribeCpp/TranscribeCpp.swift),
[Swift ABI pin](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/bindings/swift/Sources/TranscribeCpp/ABIHash.swift),
[upstream drift check](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/scripts/ci/swift_abihash_check.py)).

Record the following as one reviewable vendor manifest and never update them
independently:

| Pin | v0.1.3 value / rule |
| --- | --- |
| Upstream tag | `v0.1.3` |
| Source commit | `a94e021ef658dc7c788837341a13f6acea3baf3c` |
| Upstream ZIP URL | Exact v0.1.3 release-asset URL |
| Upstream ZIP SHA-256 | `b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd` |
| Topology transformation | Restore exactly the five source-declared macOS symlinks; make no Mach-O change |
| Corrected ZIP | FoldWise immutable URL + `swift package compute-checksum` result |
| Wrapper | Exact source files from the same source commit |
| Native/wrapper version | Both `0.1.3`; runtime gate must pass |
| Public ABI digest | `86b16dd97ad1cb58` |
| Notices | Exact transcribe.cpp, ggml, and miniz texts from the same commit |
| Toolchain | Pin the Xcode/Swift release used to build the universal app; record it in release evidence |

`Package.resolved` is useful for remote source-control dependency resolution,
but it is not a substitute for the binary URL checksum, source snapshot,
topology recipe, or notice pins. SwiftPM records resolved source-control
versions in `Package.resolved`, while a remote binary target's manifest
checksum authenticates its archive bytes
([SwiftPM dependency resolution](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/resolvingpackageversions/),
[Apple binary-framework distribution](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)).

## Embedding and runtime loading

Apple's canonical macOS location for frameworks and dylibs is
`Contents/Frameworks`. Apple also says apps using a dynamic framework must
embed it, and its troubleshooting guidance treats an `@rpath` dependency that
is absent from the app's embedded frameworks or has the wrong architecture as
an invalid bundle
([bundle placement](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle),
[TN2435](https://developer.apple.com/library/archive/technotes/tn2435/_index.html#//apple_ref/doc/uid/DTS40017543-CH1-EMBEDDING_A_FRAMEWORK_IN_IOS__MACOS__WATCHOS__AND_TVOS_APPS)).

For FoldWise's command-line SwiftPM/custom-bundler flow, the release build must:

1. build a universal executable deliberately and assert `lipo -archs` reports
   exactly `arm64 x86_64` (order is immaterial);
2. assert the linked dependency is the expected `@rpath/CTranscribe.framework/Versions/Current/CTranscribe`;
3. assert an `LC_RPATH` resolves that identity at
   `@executable_path/../Frameworks`;
4. copy the corrected framework with a symlink-preserving operation into
   `Contents/Frameworks/CTranscribe.framework`;
5. assert the embedded image is dynamic, has both architectures, contains no
   unexpected non-system dependencies, and passes strict signature validation
   after signing; and
6. launch the staged app from the actual DMG on each architecture, rather than
   treating link success or `otool` output as a launch test.

The framework's `@rpath` install name and the executable's run-path list work
together: dyld traverses the executable's run paths to resolve an `@rpath`
install name. Apple documents `otool -L` as the inspection tool and recommends
`@rpath` for relocatable dependent libraries
([run-path libraries](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/100-Articles/RunpathDependentLibraries.html),
[TN2435 linkage inspection](https://developer.apple.com/library/archive/technotes/tn2435/_index.html#//apple_ref/doc/uid/DTS40017543-CH1-TROUBLESHOOTING)).

Do not rely on SwiftPM to stage the dynamic framework for this custom app
bundle. Upstream's own Swift CI notes that command-line `swift test`/`swift run`
do not reliably stage or resolve it across toolchains and supplies an explicit
run path for those commands
([upstream Swift CI](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/.github/workflows/swift-ci.yml#L89-L110)).

## Signing, hardened runtime, and notarization

Apple's nested-code model seals the signature of embedded code into the outer
bundle. Nested code must therefore be in a standard code location and signed
before its container. `Contents/Frameworks` is the standard location for
frameworks/dylibs. Apple explicitly discourages using `--deep` for signing and
recommends signing inside out in individual stages; `--deep` remains useful for
recursive verification
([TN2206 nested code](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS40007919-CH1-TNTAG201),
[TN2206 `--deep`](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS40007919-CH1-TNTAG205)).

The production order should be:

1. finish all framework/app content and run-path changes;
2. sign `Contents/Frameworks/CTranscribe.framework` with the release's
   Developer ID Application identity, secure timestamp, and runtime option;
3. sign the app last with the same identity, timestamp, hardened runtime, and
   only its required microphone entitlement;
4. verify the app recursively and strictly;
5. create the read-only UDZO DMG using symlink-preserving copy operations;
6. sign the DMG with the Developer ID Application identity, timestamp, and a
   distinct identifier;
7. submit that exact DMG with `xcrun notarytool submit ... --wait`, require
   `Accepted`, download and retain the log even on success, and fail on errors
   or warnings FoldWise has not explicitly accepted;
8. staple and validate that same DMG, then assess and launch the quarantined
   distribution on clean arm64 and x86_64 systems.

Apple requires Developer ID signing, hardened runtime, secure timestamps, and
valid signatures for notarization. It accepts UDIF disk images, says to
notarize only the outermost distributed container, and says to staple the item
actually distributed. Its disk-image guidance separately requires signing the
DMG before notarization
([notarization prerequisites](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[packaging a DMG](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)).

No hardened-runtime exception is evidenced for CTranscribe. Because FoldWise
controls and re-signs the embedded framework with its own Developer ID identity,
it should keep library validation enabled and must not add
`com.apple.security.cs.disable-library-validation`, JIT, unsigned executable
memory, or dyld-environment exceptions preemptively. Hardened runtime is meant
to prevent code injection, dylib hijacking, and process-memory tampering; add an
exception only after a specific tested requirement earns it
([Apple hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime)).

## Current FoldWise gaps

FoldWise's
[`Package.swift`](../../Package.swift)
has only remote source dependencies; it declares no transcribe.cpp binary or
wrapper target. Its checked-in
[`Package.resolved`](../../Package.resolved)
pins those source dependencies but naturally contains no transcribe.cpp binary
identity.

The current
[`build_swift_app.py`](../../scripts/build_swift_app.py)
runs a host-default `swift build -c release`, copies only the resulting
`FoldWiseVoice` executable into `Contents/MacOS`, creates no
`Contents/Frameworks`, and provides no explicit app run path. It then signs the
outer app with `codesign --force --deep`; when a real identity is present it
adds hardened runtime but does not request an explicit secure timestamp.
Those behaviors are insufficient for a universal dynamic framework and the
signing method conflicts with Apple's inside-out guidance.

The current
[`release-please.yml`](../../.github/workflows/release-please.yml)
uses one `macos-latest` build, does not assert either architecture, and gates
certificate import and notarization independently. It may therefore publish an
ad-hoc-signed DMG when secrets are absent, or attempt notarization when notary
credentials exist but signing credentials do not. It staples the DMG but does
not sign the DMG first, retain/check the notarization log, validate the staple,
or run Gatekeeper/launch tests. Production publishing should require the full
signing-and-notarization credential set as one atomic gate; ad-hoc output may
remain a clearly named local/development artifact but should not be the normal
release asset.

These are release-pipeline gaps, not reasons to reject the runtime. They should
be acceptance criteria of the transcribe.cpp integration slice.

## Attribution posture

transcribe.cpp, its vendored ggml, and its vendored miniz are all MIT-licensed.
Each license requires preservation of its copyright and permission notice in
copies or substantial portions. The v0.1.3 XCFramework ZIP carries three texts
at its XCFramework root, and upstream's third-party notice identifies the
statically linked components
([transcribe.cpp license](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/LICENSE),
[third-party licenses](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/THIRD-PARTY-LICENSES.md),
[XCFramework packaging source](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/scripts/ci/package_xcframework.sh)).

Those root files are build-artifact metadata; selecting the macOS framework
does not automatically place them in FoldWise's distributable app. FoldWise
must deliberately reproduce all three exact texts in a readable consolidated
third-party-notices resource under `Contents/Resources` (and expose it from the
app's legal/about surface when that surface exists). Do not place license data
beside the framework in `Contents/Frameworks`, which Apple reserves for code
([Apple bundle placement](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle),
[TN2206 code locations](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS40007919-CH1-TNTAG201)).

This runtime notice is independent of per-model licenses and access terms. It
does not authorize FoldWise to redistribute or facilitate every GGUF in the
Handy catalog.

For provenance within the runtime itself, v0.1.3 records vendored ggml commit
`707321c4cf6d21cb4bc831aa8b687dbf01a521ce` and miniz 3.1.1 commit
`d10b03cc73475af673df40f06e5cefd1d5f940d9`; these pins should be re-audited
with every runtime bump
([ggml pin](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/ggml/UPSTREAM),
[miniz pin](https://github.com/handy-computer/transcribe.cpp/blob/v0.1.3/src/third_party/miniz/UPSTREAM)).

## Upgrade and release gates

Treat every transcribe.cpp bump as a reviewed vendor update, never a floating
dependency update. A candidate is releasable only when all of these pass:

1. **Provenance:** tag, commit, upstream URL and SHA-256, corrected-artifact
   URL and SwiftPM checksum, wrapper snapshot, ABI hash, and license texts all
   agree in the vendor manifest.
2. **Archive:** clean download; checksum; clean extraction; exact macOS
   symlinks; standard framework layout; no unexpected executable files; strict
   signature validation after re-signing.
3. **Binary:** expected minimum OS, universal `arm64`+`x86_64` slices,
   `@rpath` install name, no unexpected dynamic dependencies, and required
   CPU/Metal backend inventory per architecture.
4. **Wrapper/ABI:** upstream Swift tests plus FoldWise adapter tests; native
   version equals wrapper version; header ABI digest matches; every ABI change
   receives human review because 0.x permits breaks.
5. **App bundle:** universal main executable and framework, expected
   `LC_RPATH`, framework present only in `Contents/Frameworks`, notices in
   Resources, and explicit inside-out signatures with the same team identity.
6. **Distribution:** signed app and signed DMG; hardened runtime and timestamp;
   strict recursive verification; accepted notarization log; successful staple
   validation; Gatekeeper assessment and actual cold launch/transcription from
   a quarantined DMG on clean Apple Silicon and Intel Macs.
7. **Regression:** exercise offline and streaming model smoke fixtures,
   cancellation, model unload/reload, CPU-only Intel behavior, Metal Apple
   Silicon behavior, and upgrade from the previous shipped FoldWise version.

The final two-machine distribution test is not optional. Apple recommends
testing the exact distributed product on a different Mac, including fresh,
upgrade, duplicate, run-from-image/translocated, and move-then-launch scenarios
([Apple packaging tests](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)).

## Decision

Choose a FoldWise-owned corrected v0.1.3 XCFramework archive plus vendored
same-commit Swift wrapper, embedded as one universal private framework and
released in one universal, Developer-ID-signed, hardened, notarized, and
stapled DMG. Do not consume the current upstream ZIP directly, do not float any
0.x component independently, and do not let the existing executable-only
bundler or `codesign --deep` path ship it.

This posture is reproducible because every external byte and transformation is
explicitly pinned; launchable because the framework topology, embed location,
run path, architectures, and inside-out signatures are tested; attributable
because all linked MIT notices enter the app resources; and safely upgradeable
because binary, wrapper, ABI, license, and distribution evidence move through
one gated vendor update.
