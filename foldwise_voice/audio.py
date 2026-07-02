"""Microphone capture: 16 kHz, mono, float32 (Whisper-native)."""

from __future__ import annotations

import logging
import queue
import threading

import numpy as np
import sounddevice as sd

log = logging.getLogger(__name__)

SAMPLE_RATE = 16_000


class AudioRecorder:
    """Push-to-talk recorder.

    The input stream stays open for the app's lifetime; frames are only
    buffered between start() and stop(). The sounddevice callback runs on a
    CoreAudio thread and must never block — it only copies frames into a queue.
    """

    def __init__(self, samplerate: int = SAMPLE_RATE):
        self.samplerate = samplerate
        self._q: queue.Queue[np.ndarray] = queue.Queue()
        self._recording = threading.Event()
        self._stream: sd.InputStream | None = None
        self.level = 0.0  # peak of the latest frame, for UI metering

    def open(self) -> None:
        if self._stream is not None:
            return
        self._stream = sd.InputStream(
            samplerate=self.samplerate,
            channels=1,
            dtype="float32",
            callback=self._callback,
        )
        self._stream.start()

    def close(self) -> None:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None

    def _callback(self, indata, frames, time_info, status) -> None:
        if status:
            log.debug("audio status: %s", status)
        if self._recording.is_set():
            self._q.put(indata.copy())
            self.level = float(np.abs(indata).max())

    @property
    def is_recording(self) -> bool:
        return self._recording.is_set()

    def start(self) -> None:
        self.open()
        # Drop any stale frames from a previous session.
        while not self._q.empty():
            try:
                self._q.get_nowait()
            except queue.Empty:
                break
        self._recording.set()

    def stop(self) -> np.ndarray:
        """Stop buffering and return the captured audio as 1-D float32."""
        self._recording.clear()
        self.level = 0.0
        chunks = []
        while not self._q.empty():
            try:
                chunks.append(self._q.get_nowait())
            except queue.Empty:
                break
        if not chunks:
            return np.zeros(0, dtype=np.float32)
        return np.concatenate(chunks).flatten().astype(np.float32)
