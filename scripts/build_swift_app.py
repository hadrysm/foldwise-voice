"""Build the native Swift app as 'FoldWise Voice Native.app' and install it.

Unlike the Python launcher bundle (scripts/build_app.py), this bundle contains
a real compiled binary — no venv, no launcher script. It shares the repo's
modes.json via the LSEnvironment FOLDWISE_CONFIG hook, so both apps stay
interchangeable.

Usage:  python3 scripts/build_swift_app.py
"""

from __future__ import annotations

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


def build_bundle(binary: Path) -> Path:
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
        "CFBundleExecutable": "FoldWiseVoice",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.2.0",
        "CFBundleVersion": "0.2.0",
        "LSMinimumSystemVersion": "14.0",
        "LSUIElement": True,  # menu-bar app: no Dock icon
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": (
            "FoldWise Voice records the microphone while you hold the "
            "dictation hotkey, and transcribes it entirely on this Mac."
        ),
        # Share the repo's modes.json with the Python app.
        "LSEnvironment": {"FOLDWISE_CONFIG": str(REPO / "modes.json")},
    }
    if PYTHON_APP_ICON.exists():
        shutil.copy2(PYTHON_APP_ICON, resources / "icon.icns")
        plist["CFBundleIconFile"] = "icon"

    with open(app / "Contents" / "Info.plist", "wb") as f:
        plistlib.dump(plist, f)

    shutil.copy2(binary, macos / "FoldWiseVoice")

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
    binary = build_binary()
    app = build_bundle(binary)
    installed = install(app)
    print(f"Built and installed: {installed}")
    print("First launch: grant Microphone when prompted; add the app under")
    print("System Settings → Privacy & Security → Accessibility for auto-paste")
    print("(and Input Monitoring if the hotkey doesn't fire).")
    print("First dictation downloads the Parakeet model (~600 MB) once.")


if __name__ == "__main__":
    main()
