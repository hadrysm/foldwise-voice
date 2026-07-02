"""Build the native Swift app as 'FoldWise Voice Native.app' and install it.

Unlike the Python launcher bundle (scripts/build_app.py), this bundle contains
a real compiled binary — no venv, no launcher script. It shares the repo's
modes.json via the LSEnvironment FOLDWISE_CONFIG hook, so both apps stay
interchangeable.

With --dmg it instead builds a distributable disk image: a self-contained
'FoldWise Voice.app' (no repo paths baked in — the app creates its own
modes.json in ~/Library/Application Support/FoldWise Voice/ on first launch)
inside a drag-to-Applications .dmg.

By default the bundle is ad-hoc signed. To sign the .dmg build with a real
Developer ID (required for notarization), set CODESIGN_IDENTITY, e.g.
CODESIGN_IDENTITY="Developer ID Application: Jane Doe (TEAMID)".

Usage:  python3 scripts/build_swift_app.py         # build + install locally
        python3 scripts/build_swift_app.py --dmg   # build dist/FoldWise-Voice-<version>.dmg
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP_NAME = "FoldWise Voice Native"
BUNDLE_ID = "com.foldwise.voice.native"
DIST = REPO / "dist"
SWIFT_DIR = REPO / "swift"
VERSION = (REPO / "version.txt").read_text().strip()
PYTHON_APP_ICON = DIST / "FoldWise Voice.app" / "Contents" / "Resources" / "icon.icns"


def build_binary() -> Path:
    subprocess.run(
        ["swift", "build", "-c", "release", "--package-path", str(SWIFT_DIR)],
        check=True,
    )
    binary = SWIFT_DIR / ".build" / "release" / "FoldWiseVoice"
    if not binary.exists():
        sys.exit("Release binary not found — did the build fail?")
    return binary


def build_bundle(binary: Path, dest: Path, name: str, share_repo_config: bool) -> Path:
    app = dest / f"{name}.app"
    shutil.rmtree(app, ignore_errors=True)
    macos = app / "Contents" / "MacOS"
    resources = app / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)

    plist = {
        "CFBundleName": name,
        "CFBundleDisplayName": name,
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": "FoldWiseVoice",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": VERSION,
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,  # menu-bar app: no Dock icon
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": (
            "FoldWise Voice records the microphone while you hold the "
            "dictation hotkey, and transcribes it entirely on this Mac."
        ),
    }
    if share_repo_config:
        # Share the repo's modes.json with the Python app. Never set for the
        # .dmg build: the repo path doesn't exist on other machines, and the
        # app falls back to ~/Library/Application Support/FoldWise Voice/.
        plist["LSEnvironment"] = {"FOLDWISE_CONFIG": str(REPO / "modes.json")}
    if PYTHON_APP_ICON.exists():
        shutil.copy2(PYTHON_APP_ICON, resources / "icon.icns")
        plist["CFBundleIconFile"] = "icon"

    with open(app / "Contents" / "Info.plist", "wb") as f:
        plistlib.dump(plist, f)

    shutil.copy2(binary, macos / "FoldWiseVoice")
    sign(app)
    return app


def sign(app: Path) -> None:
    # Ad-hoc signature gives the bundle a stable identity for TCC grants.
    # A real Developer ID (CODESIGN_IDENTITY) additionally enables the
    # hardened runtime, which notarization requires.
    identity = os.environ.get("CODESIGN_IDENTITY", "-")
    cmd = ["codesign", "--force", "--deep", "-s", identity]
    entitlements = DIST / "entitlements.plist"
    if identity != "-":
        with open(entitlements, "wb") as f:
            plistlib.dump({"com.apple.security.device.audio-input": True}, f)
        cmd += ["--options", "runtime", "--entitlements", str(entitlements)]
    try:
        subprocess.run(cmd + [str(app)], check=True)
    finally:
        entitlements.unlink(missing_ok=True)


def build_dmg(app: Path) -> Path:
    staging = app.parent
    (staging / "Applications").symlink_to("/Applications")
    dmg = DIST / f"FoldWise-Voice-{VERSION}.dmg"
    dmg.unlink(missing_ok=True)
    subprocess.run(
        ["hdiutil", "create", "-volname", "FoldWise Voice", "-srcfolder",
         str(staging), "-format", "UDZO", str(dmg)],
        check=True,
    )
    return dmg


def install(app: Path) -> Path:
    for target_dir in (Path("/Applications"), Path.home() / "Applications"):
        target = target_dir / app.name
        try:
            target_dir.mkdir(parents=True, exist_ok=True)
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(app, target, symlinks=True)
            return target
        except PermissionError:
            continue
    print("Could not write to /Applications or ~/Applications; app left in dist/")
    return app


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dmg", action="store_true",
        help="build a distributable .dmg instead of installing locally",
    )
    args = parser.parse_args()

    binary = build_binary()

    if args.dmg:
        staging = DIST / "dmg"
        shutil.rmtree(staging, ignore_errors=True)
        staging.mkdir(parents=True)
        app = build_bundle(binary, staging, "FoldWise Voice", share_repo_config=False)
        dmg = build_dmg(app)
        print(f"Built: {dmg}")
        if os.environ.get("CODESIGN_IDENTITY"):
            print("Signed with your Developer ID. To pass Gatekeeper on download,")
            print("notarize it:  xcrun notarytool submit <dmg> --keychain-profile <p> --wait")
            print("then:         xcrun stapler staple <dmg>")
        else:
            print("Ad-hoc signed (no Developer ID). Recipients must bypass Gatekeeper")
            print("once: right-click the app → Open, or run")
            print('  xattr -dr com.apple.quarantine "/Applications/FoldWise Voice.app"')
        return

    app = build_bundle(binary, DIST, APP_NAME, share_repo_config=True)
    installed = install(app)
    print(f"Built and installed: {installed}")
    print("First launch: grant Microphone when prompted; add the app under")
    print("System Settings → Privacy & Security → Accessibility for auto-paste")
    print("(and Input Monitoring if the hotkey doesn't fire).")
    print("First dictation downloads the Parakeet model (~600 MB) once.")


if __name__ == "__main__":
    main()
