"""Silence other apps while dictating.

On duck: pause Spotify / Apple Music if they are playing (remembered), then
mute system output so browsers etc. go quiet too. On restore: unmute and
resume only the players we paused.

osascript calls take ~100ms each, so duck()/restore() only enqueue work for
a single serial worker thread — they never block, safe to call from the
hotkey listener thread. A generation counter makes a quick duck→restore→duck
sequence settle on the latest call.
"""

from __future__ import annotations

import logging
import queue
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
        # The lock only guards the generation counter; ducking state is
        # owned by the worker thread. Holding a lock across the slow
        # osascript calls would make duck() block the hotkey thread (and
        # delay recorder.start(), losing the start of the dictation).
        self._lock = threading.Lock()
        self._gen = 0
        self._ops: queue.Queue[tuple[str, int]] = queue.Queue()
        self._ducked = False
        self._paused_players: list[str] = []
        self._was_muted = False
        threading.Thread(target=self._run, daemon=True, name="ducker").start()

    def duck(self) -> None:
        self._submit("duck")

    def restore(self) -> None:
        self._submit("restore")

    def _submit(self, op: str) -> None:
        with self._lock:
            self._gen += 1
            self._ops.put((op, self._gen))

    def _is_current(self, gen: int) -> bool:
        with self._lock:
            return gen == self._gen

    def _run(self) -> None:
        while True:
            op, gen = self._ops.get()
            if not self._is_current(gen):
                continue  # superseded by a newer duck/restore
            if op == "duck":
                self._duck()
            else:
                self._restore()

    def _duck(self) -> None:
        if self._ducked:
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

    def _restore(self) -> None:
        if not self._ducked:
            return
        self._ducked = False
        if not self._was_muted:
            _osascript("set volume without output muted")
        for app in self._paused_players:
            _osascript(f'tell application "{app}" to play')
        self._paused_players = []
