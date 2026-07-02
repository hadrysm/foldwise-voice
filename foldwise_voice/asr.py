"""Stage 1: speech-to-text with mlx-whisper. This is Whisper, NOT Ollama."""

from __future__ import annotations

import logging

import numpy as np

log = logging.getLogger(__name__)

_first_use = True


def transcribe(audio: np.ndarray, model: str, vocab: list[str] | None = None) -> str:
    """Transcribe 16 kHz mono float32 audio. Returns trimmed text.

    `vocab` biases recognition via Whisper's initial_prompt.
    The model auto-downloads from Hugging Face on first use, then runs
    fully offline.
    """
    global _first_use
    if audio.size == 0:
        return ""

    import mlx_whisper  # deferred: heavy import, keeps startup fast

    if _first_use:
        log.info(
            "Loading ASR model %s (first run downloads it once from "
            "Hugging Face — this can take a few minutes).",
            model,
        )
        _first_use = False

    prompt = ("Terms: " + ", ".join(vocab)) if vocab else None
    result = mlx_whisper.transcribe(
        audio, path_or_hf_repo=model, initial_prompt=prompt
    )
    return result["text"].strip()
