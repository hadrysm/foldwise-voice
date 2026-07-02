"""Insert text into the focused app: clipboard + synthetic Cmd+V.

The synthetic keystroke needs macOS Accessibility permission. Without it we
fall back to clipboard-only and tell the user once.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import logging
import time

import pyperclip

log = logging.getLogger(__name__)

_notified_no_ax = False

# Virtual keycode for the ANSI "V" key (kVK_ANSI_V). We post Cmd+V by keycode
# rather than by character so macOS never has to resolve the current keyboard
# layout via the Text Input Source APIs — those must run on the main thread on
# recent macOS and abort (SIGTRAP) when called from the pipeline worker thread.
_KVK_ANSI_V = 0x09


def _post_cmd_v() -> None:
    """Synthesize a Cmd+V keystroke via Quartz, safe to call off-main-thread."""
    import Quartz

    src = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    for down in (True, False):
        ev = Quartz.CGEventCreateKeyboardEvent(src, _KVK_ANSI_V, down)
        Quartz.CGEventSetFlags(ev, Quartz.kCGEventFlagMaskCommand)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)


def accessibility_trusted() -> bool:
    """Call AXIsProcessTrusted() from the ApplicationServices framework."""
    try:
        path = ctypes.util.find_library("ApplicationServices")
        if not path:
            return True  # can't detect — assume OK and let paste try
        appserv = ctypes.cdll.LoadLibrary(path)
        appserv.AXIsProcessTrusted.restype = ctypes.c_bool
        return bool(appserv.AXIsProcessTrusted())
    except Exception as e:
        log.debug("AXIsProcessTrusted check failed (%s); attempting paste anyway", e)
        return True


def insert_text(text: str, restore_clipboard: bool = True) -> bool:
    """Copy `text` and paste it into the focused app.

    Returns True if a synthetic Cmd+V was posted, False if we fell back to
    clipboard-only.
    """
    global _notified_no_ax
    if not text:
        return False

    previous = None
    if restore_clipboard:
        try:
            previous = pyperclip.paste()
        except Exception:
            previous = None

    pyperclip.copy(text)

    if not accessibility_trusted():
        if not _notified_no_ax:
            _notified_no_ax = True
            print(
                "\n⚠️  Transcript copied to clipboard — paste manually (Cmd+V).\n"
                "   To auto-insert, grant Accessibility to your terminal app:\n"
                "   System Settings → Privacy & Security → Accessibility.\n"
            )
        else:
            log.info("Accessibility not granted — transcript left on clipboard.")
        return False

    time.sleep(0.05)  # let the clipboard settle before pasting
    _post_cmd_v()

    if restore_clipboard and previous is not None:
        # Give the focused app time to read the clipboard before restoring.
        time.sleep(0.4)
        try:
            pyperclip.copy(previous)
        except Exception:
            pass
    return True
