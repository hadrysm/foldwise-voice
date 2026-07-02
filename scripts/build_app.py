"""Build 'FoldWise Voice.app' and install it to /Applications.

The bundle is a thin launcher: it runs this repo's venv Python with
`-m foldwise_voice --ui`, so the app and the terminal share one codebase
and one modes.json. Re-run this script if you move the repo.

Usage:  .venv/bin/python scripts/build_app.py
"""

from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP_NAME = "FoldWise Voice"
BUNDLE_ID = "com.foldwise.voice"
DIST = REPO / "dist"
VERSION = (REPO / "version.txt").read_text().strip()

# (filename, pixel size) pairs for a complete .iconset
ICONSET_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def render_icon_png(path: Path, size: int) -> None:
    """Rounded dark tile with a mic emoji, rendered offscreen via AppKit."""
    import AppKit
    import Foundation

    img = AppKit.NSImage.alloc().initWithSize_((size, size))
    img.lockFocus()

    inset = size * 0.06
    rect = ((inset, inset), (size - 2 * inset, size - 2 * inset))
    radius = size * 0.21
    path_bg = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        rect, radius, radius
    )
    gradient = AppKit.NSGradient.alloc().initWithStartingColor_endingColor_(
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.13, 0.14, 0.22, 1.0),
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(0.24, 0.16, 0.42, 1.0),
    )
    gradient.drawInBezierPath_angle_(path_bg, 90.0)

    emoji = Foundation.NSString.stringWithString_("🎤")
    attrs = {AppKit.NSFontAttributeName: AppKit.NSFont.systemFontOfSize_(size * 0.58)}
    text_size = emoji.sizeWithAttributes_(attrs)
    emoji.drawAtPoint_withAttributes_(
        ((size - text_size.width) / 2, (size - text_size.height) / 2), attrs
    )

    img.unlockFocus()

    rep = AppKit.NSBitmapImageRep.imageRepWithData_(img.TIFFRepresentation())
    rep.setSize_((size, size))
    png = rep.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, None)
    png.writeToFile_atomically_(str(path), True)


def build_icns(resources: Path) -> None:
    iconset = DIST / "icon.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    iconset.mkdir(parents=True)
    for name, px in ICONSET_SIZES:
        render_icon_png(iconset / name, px)
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "icon.icns")],
        check=True,
    )
    shutil.rmtree(iconset)


def build_bundle() -> Path:
    app = DIST / f"{APP_NAME}.app"
    shutil.rmtree(app, ignore_errors=True)
    macos = app / "Contents" / "MacOS"
    resources = app / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)

    plist = {
        "CFBundleName": APP_NAME,
        "CFBundleDisplayName": APP_NAME,
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleExecutable": "foldwise-voice",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": VERSION,
        "CFBundleIconFile": "icon",
        "LSMinimumSystemVersion": "12.0",
        "LSUIElement": True,  # menu-bar app: no Dock icon
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": (
            "FoldWise Voice records the microphone while you hold the "
            "dictation hotkey, and transcribes it entirely on this Mac."
        ),
    }
    with open(app / "Contents" / "Info.plist", "wb") as f:
        plistlib.dump(plist, f)

    launcher = macos / "foldwise-voice"
    launcher.write_text(
        "#!/bin/bash\n"
        f'cd "{REPO}"\n'
        f'exec "{REPO}/.venv/bin/python" -m foldwise_voice --ui\n'
    )
    launcher.chmod(0o755)

    build_icns(resources)

    # Ad-hoc signature gives the bundle a stable identity for TCC grants.
    subprocess.run(["codesign", "--force", "--deep", "-s", "-", str(app)], check=True)
    return app


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
    if not (REPO / ".venv" / "bin" / "python").exists():
        sys.exit("No .venv found in the repo — create it first (see README).")
    app = build_bundle()
    installed = install(app)
    print(f"Built and installed: {installed}")
    print("First launch: grant Microphone when prompted, and add the app under")
    print("System Settings → Privacy & Security → Accessibility for auto-paste.")


if __name__ == "__main__":
    main()
