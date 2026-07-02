"""Build the native Swift app as 'FoldWise Voice Native.app' and install it.

The bundle contains a real compiled binary — no launcher script. The local
install shares the repo's modes.json via the LSEnvironment FOLDWISE_CONFIG
hook, so repo edits to modes take effect without a rebuild.

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
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP_NAME = "FoldWise Voice Native"
BUNDLE_ID = "com.foldwise.voice.native"
DIST = REPO / "dist"
SWIFT_DIR = REPO / "swift"
VERSION = (REPO / "version.txt").read_text().strip()


def render_assets() -> tuple[Path, Path]:
    """Render icon.icns and the DMG background with scripts/render_assets.swift."""
    out = DIST / "assets"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    subprocess.run(
        ["swift", str(REPO / "scripts" / "render_assets.swift"), str(out)],
        check=True,
    )
    subprocess.run(
        ["iconutil", "-c", "icns", str(out / "icon.iconset"),
         "-o", str(out / "icon.icns")],
        check=True,
    )
    return out / "icon.icns", out / "dmg-background.png"


def build_binary() -> Path:
    subprocess.run(
        ["swift", "build", "-c", "release", "--package-path", str(SWIFT_DIR)],
        check=True,
    )
    binary = SWIFT_DIR / ".build" / "release" / "FoldWiseVoice"
    if not binary.exists():
        sys.exit("Release binary not found — did the build fail?")
    return binary


def build_bundle(binary: Path, dest: Path, name: str, icon: Path,
                 share_repo_config: bool) -> Path:
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
        # Point the local install at the repo's modes.json. Never set for the
        # .dmg build: the repo path doesn't exist on other machines, and the
        # app falls back to ~/Library/Application Support/FoldWise Voice/.
        plist["LSEnvironment"] = {"FOLDWISE_CONFIG": str(REPO / "modes.json")}
    shutil.copy2(icon, resources / "icon.icns")
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
    # Empty (e.g. an unset CI secret) means ad-hoc, same as unset.
    identity = os.environ.get("CODESIGN_IDENTITY") or "-"
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


DMG_LAYOUT_SCRIPT = """
tell application "Finder"
    tell disk "{volume}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {{200, 120, 860, 548}}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 12
        set background picture of opts to file ".background:background.png"
        set position of item "{app}" of container window to {{180, 190}}
        set position of item "Applications" of container window to {{480, 190}}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
"""


def style_dmg_volume(mount_point: Path, app_name: str, icon: Path) -> None:
    script = DMG_LAYOUT_SCRIPT.format(volume=mount_point.name, app=app_name)
    for attempt in range(3):  # Finder scripting is flaky on CI runners
        result = subprocess.run(["osascript", "-e", script])
        if result.returncode == 0:
            break
        time.sleep(2 * (attempt + 1))
    else:
        sys.exit("Could not lay out the DMG window via Finder.")

    # Volume icon, after the layout pass so Finder can't overwrite it:
    # `hdiutil create -srcfolder` drops .VolumeIcon.icns, so copy it onto the
    # mounted volume, then set kHasCustomIcon (byte 8 of root FinderInfo).
    shutil.copy2(icon, mount_point / ".VolumeIcon.icns")
    subprocess.run(
        ["xattr", "-wx", "com.apple.FinderInfo",
         "0000000000000000040000000000000000000000000000000000000000000000",
         str(mount_point)],
        check=True,
    )


def build_dmg(app: Path, background: Path, icon: Path) -> Path:
    staging = app.parent
    (staging / "Applications").symlink_to("/Applications")
    bg_dir = staging / ".background"
    bg_dir.mkdir()
    shutil.copy2(background, bg_dir / "background.png")

    # Build read-write first, style the mounted volume with Finder (window
    # size, icon positions, background), then compress to the final image.
    rw_dmg = DIST / "FoldWise-Voice-rw.dmg"
    rw_dmg.unlink(missing_ok=True)
    subprocess.run(
        ["hdiutil", "create", "-volname", "FoldWise Voice", "-srcfolder",
         str(staging), "-fs", "HFS+", "-format", "UDRW", str(rw_dmg)],
        check=True,
    )
    attach = subprocess.run(
        ["hdiutil", "attach", "-readwrite", "-noverify", "-noautoopen",
         "-plist", str(rw_dmg)],
        check=True, capture_output=True,
    )
    entities = plistlib.loads(attach.stdout)["system-entities"]
    mount_point = Path(next(e["mount-point"] for e in entities
                            if "mount-point" in e))
    try:
        style_dmg_volume(mount_point, app.name, icon)
        subprocess.run(["sync"])
    finally:
        for attempt in range(5):  # Finder may briefly hold the volume busy
            if subprocess.run(["hdiutil", "detach", str(mount_point)]
                              ).returncode == 0:
                break
            time.sleep(2)
        else:
            subprocess.run(["hdiutil", "detach", str(mount_point), "-force"],
                           check=True)

    dmg = DIST / f"FoldWise-Voice-{VERSION}.dmg"
    dmg.unlink(missing_ok=True)
    subprocess.run(
        ["hdiutil", "convert", str(rw_dmg), "-format", "UDZO", "-o", str(dmg)],
        check=True,
    )
    rw_dmg.unlink()
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
    icon, background = render_assets()

    if args.dmg:
        staging = DIST / "dmg"
        shutil.rmtree(staging, ignore_errors=True)
        staging.mkdir(parents=True)
        app = build_bundle(binary, staging, "FoldWise Voice", icon,
                           share_repo_config=False)
        dmg = build_dmg(app, background, icon)
        print(f"Built: {dmg}")
        if os.environ.get("CODESIGN_IDENTITY"):
            print("Signed with your Developer ID. To pass Gatekeeper on download,")
            print("notarize it:  xcrun notarytool submit <dmg> --keychain-profile <p> --wait")
            print("then:         xcrun stapler staple <dmg>")
        else:
            print("Ad-hoc signed (no Developer ID). macOS blocks the first launch:")
            print('recipients click "Done" (not "Move to Bin"), then System Settings')
            print('→ Privacy & Security → "Open Anyway". Or clear quarantine:')
            print('  xattr -dr com.apple.quarantine "/Applications/FoldWise Voice.app"')
        return

    app = build_bundle(binary, DIST, APP_NAME, icon, share_repo_config=True)
    installed = install(app)
    print(f"Built and installed: {installed}")
    print("First launch: grant Microphone when prompted; add the app under")
    print("System Settings → Privacy & Security → Accessibility for auto-paste")
    print("(and Input Monitoring if the hotkey doesn't fire).")
    print("First dictation downloads the Parakeet model (~600 MB) once.")


if __name__ == "__main__":
    main()
