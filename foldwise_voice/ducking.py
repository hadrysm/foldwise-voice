"""Silence other apps while dictating.

On duck: pause Spotify / Apple Music if they are playing (remembered), then
mute system output so browsers etc. go quiet too. On restore: unmute and
resume only the players we paused.

osascript calls take ~100ms each, so duck()/restore() spawn a worker thread
— safe to call from the hotkey listener thread. A generation counter makes
a quick duck→restore→duck sequence settle on the latest call.
"""

from __future__ import annotations

import logging
import subprocess
import threading

log = logging.getLogger(__name__)

_PLAYERS = ("Spotify", "Music")


def _osascript(script: str) -> str:
    try:
        out = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return out.stdout.strip()
    except Exception:
        log.exception("osascript failed: %s", script)
        return ""


class AudioDucker:
    def __init__(self):
        self._lock = threading.Lock()
        self._gen = 0
        self._ducked = False
        self._paused_players: list[str] = []
        self._was_muted = False

    def duck(self) -> None:
        self._spawn(self._duck)

    def restore(self) -> None:
        self._spawn(self._restore)

    def _spawn(self, target) -> None:
        with self._lock:
            self._gen += 1
            gen = self._gen
        threading.Thread(target=target, args=(gen,), daemon=True, name="ducker").start()

    def _duck(self, gen: int) -> None:
        with self._lock:
            if gen != self._gen or self._ducked:
                return
            self._ducked = True
            self._paused_players = []
            for app in _PLAYERS:
                state = _osascript(
                    f'if application "{app}" is running then '
                    f'tell application "{app}" to get player state as text'
                )
                if state == "playing":
                    _osascript(f'tell application "{app}" to pause')
                    self._paused_players.append(app)
            self._was_muted = (
                _osascript("output muted of (get volume settings)") == "true"
            )
            if not self._was_muted:
                _osascript("set volume with output muted")

    def _restore(self, gen: int) -> None:
        with self._lock:
            if gen != self._gen or not self._ducked:
                return
            self._ducked = False
            if not self._was_muted:
                _osascript("set volume without output muted")
            for app in self._paused_players:
                _osascript(f'tell application "{app}" to play')
            self._paused_players = []
