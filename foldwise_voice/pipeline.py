"""Wires the stages: record -> ASR -> (optional LLM) -> insert.

Transcription and the LLM call run on a single worker thread so the audio
callback and the keyboard listener stay responsive.
"""

from __future__ import annotations

import logging
import queue
import threading

import numpy as np

from . import asr, insert, llm
from .audio import AudioRecorder
from .config import MIN_CHARS_FOR_LLM, Config, Mode
from .ducking import AudioDucker

log = logging.getLogger(__name__)


class Pipeline:
    """States emitted via on_state(state, detail):
    listening, transcribing, polishing, inserted, clipboard, idle, error.
    Callbacks may fire from the hotkey or worker thread — UIs must hop to
    their main thread themselves.
    """

    def __init__(self, config: Config, on_state=None):
        self.config = config
        self.recorder = AudioRecorder()
        self.ducker = AudioDucker()
        self.on_state = on_state
        self._jobs: queue.Queue[tuple[np.ndarray, Mode] | None] = queue.Queue()
        self._worker = threading.Thread(target=self._run, daemon=True, name="pipeline")
        self._worker.start()

    def _emit(self, state: str, detail: str = "") -> None:
        if self.on_state is not None:
            try:
                self.on_state(state, detail)
            except Exception:
                log.exception("on_state callback failed")

    # --- called from the hotkey listener thread (must be fast) ---

    def start_recording(self) -> None:
        if self.recorder.is_recording:
            return
        print(f"● recording…  [mode: {self.config.active_mode}]")
        if self.config.pause_audio:
            self.ducker.duck()
        self.recorder.start()
        self._emit("listening", self.config.active_mode)

    def stop_recording(self) -> None:
        if not self.recorder.is_recording:
            return
        audio = self.recorder.stop()
        self.ducker.restore()
        print(f"○ stopped ({audio.size / 16000:.1f}s) — transcribing…")
        self._emit("transcribing")
        # Capture the mode now: a mode switch while this job waits in the
        # queue must not change how an already-spoken dictation is handled.
        self._jobs.put((audio, self.config.mode))

    def toggle_recording(self) -> None:
        if self.recorder.is_recording:
            self.stop_recording()
        else:
            self.start_recording()

    def shutdown(self) -> None:
        self._jobs.put(None)
        self.ducker.restore()
        self.recorder.close()

    # --- worker thread ---

    def _run(self) -> None:
        while True:
            job = self._jobs.get()
            if job is None:
                return
            try:
                self._process(*job)
            except Exception as e:
                log.exception("pipeline job failed")
                self._emit("error", str(e))

    def _process(self, audio: np.ndarray, mode: Mode) -> None:
        if audio.size < 1600:  # < 0.1 s — no real audio captured
            log.info("No audio captured — skipping.")
            self._emit("idle")
            return

        # Near-silence makes Whisper hallucinate ("Thank you." etc.) — skip it.
        if float(np.abs(audio).max()) < 0.005:
            log.info("Only silence captured — skipping.")
            self._emit("idle")
            return

        text = asr.transcribe(audio, model=mode.asr_model, vocab=mode.vocab)
        if not text:
            log.info("Empty transcript — nothing to insert.")
            self._emit("idle")
            return
        print(f"  raw: {text}")

        if mode.uses_llm and len(text) > MIN_CHARS_FOR_LLM:
            self._emit("polishing", mode.llm_model or "")
            text = llm.polish(
                text,
                model=mode.llm_model,
                system_prompt=mode.system_prompt,
                vocab=mode.vocab,
            )
            print(f"  llm: {text}")

        pasted = insert.insert_text(text)
        print("✓ inserted" if pasted else "✓ on clipboard")
        self._emit("inserted" if pasted else "clipboard", text)
