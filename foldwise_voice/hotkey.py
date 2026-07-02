"""Global hotkey listener (pynput): push-to-talk and optional toggle.

Callbacks fire on pynput's listener thread — they must return fast. The
pipeline hands the heavy work (ASR/LLM) to a worker thread.
"""

from __future__ import annotations

import logging
from typing import Callable

from pynput import keyboard

log = logging.getLogger(__name__)


def parse_key(name: str):
    """Map a config string like 'alt_r', 'f19', or 'a' to a pynput key."""
    name = name.strip()
    special = getattr(keyboard.Key, name.lower(), None)
    if special is not None:
        return special
    if len(name) == 1:
        return keyboard.KeyCode.from_char(name)
    raise ValueError(
        f"Unknown hotkey {name!r}. Use a pynput key name (e.g. 'alt_r', "
        f"'cmd_r', 'f19') or a single character."
    )


class HotkeyListener:
    """Push-to-talk on `ptt_key` (hold = record); optional tap-to-toggle key."""

    def __init__(
        self,
        ptt_key: str,
        on_press: Callable[[], None],
        on_release: Callable[[], None],
        toggle_key: str | None = None,
        on_toggle: Callable[[], None] | None = None,
    ):
        self._ptt = parse_key(ptt_key)
        self._toggle = parse_key(toggle_key) if toggle_key else None
        self._on_press = on_press
        self._on_release = on_release
        self._on_toggle = on_toggle
        self._ptt_down = False
        self._listener: keyboard.Listener | None = None

    @staticmethod
    def _same(a, b) -> bool:
        # Compare, normalizing KeyCode char comparisons.
        if a == b:
            return True
        av, bv = getattr(a, "char", None), getattr(b, "char", None)
        return av is not None and av == bv

    def _handle_press(self, key) -> None:
        try:
            if self._same(key, self._ptt) and not self._ptt_down:
                self._ptt_down = True
                self._on_press()
            elif self._toggle is not None and self._same(key, self._toggle):
                if self._on_toggle:
                    self._on_toggle()
        except Exception:
            log.exception("hotkey press handler failed")

    def _handle_release(self, key) -> None:
        try:
            if self._same(key, self._ptt) and self._ptt_down:
                self._ptt_down = False
                self._on_release()
        except Exception:
            log.exception("hotkey release handler failed")

    def start(self) -> None:
        self._listener = keyboard.Listener(
            on_press=self._handle_press, on_release=self._handle_release
        )
        self._listener.start()

    def stop(self) -> None:
        if self._listener is not None:
            self._listener.stop()
            self._listener = None

    def join(self) -> None:
        if self._listener is not None:
            self._listener.join()
