"""Load and validate modes.json."""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

DEFAULT_ASR_MODEL = "mlx-community/whisper-large-v3-turbo"
OLLAMA_URL = "http://localhost:11434/v1/chat/completions"
# Skip LLM cleanup for very short utterances to keep latency low.
MIN_CHARS_FOR_LLM = 40

DEFAULT_CONFIG = {
    "active_mode": "Clean",
    "hotkey": "alt_r",
    "toggle_hotkey": None,
    "modes": {
        "Voice to Text": {
            "asr_model": DEFAULT_ASR_MODEL,
            "llm_model": None,
            "system_prompt": None,
            "vocab": [],
        },
        "Clean": {
            "asr_model": DEFAULT_ASR_MODEL,
            "llm_model": "llama3.2:3b",
            "system_prompt": (
                "You clean up dictated speech. Fix punctuation, capitalization, "
                "and obvious transcription errors. Remove filler words (um, uh, "
                "like, you know). Do NOT change meaning, add content, or answer "
                "questions. Output ONLY the cleaned text."
            ),
            "vocab": ["FoldWise", "Ollama", "Anthropic"],
        },
        "Email": {
            "asr_model": DEFAULT_ASR_MODEL,
            "llm_model": "llama3.2:3b",
            "system_prompt": (
                "Rewrite this dictation as a clear, concise, professional email "
                "body. Output only the email text."
            ),
            "vocab": [],
        },
        "Bullets": {
            "asr_model": DEFAULT_ASR_MODEL,
            "llm_model": "llama3.2:3b",
            "system_prompt": (
                "Convert this dictation into a tight bulleted list, one idea per "
                "bullet. Output only the list."
            ),
            "vocab": [],
        },
    },
}


@dataclass
class Mode:
    name: str
    asr_model: str = DEFAULT_ASR_MODEL
    llm_model: str | None = None
    system_prompt: str | None = None
    vocab: list[str] = field(default_factory=list)

    @property
    def uses_llm(self) -> bool:
        return bool(self.llm_model)


@dataclass
class Config:
    active_mode: str
    hotkey: str
    toggle_hotkey: str | None
    modes: dict[str, Mode]
    path: Path
    # Pause music / mute other audio while dictating.
    pause_audio: bool = True
    # Saved HUD anchor as [center_x, bottom_y] in screen points; None = default.
    hud_position: list[float] | None = None

    @property
    def mode(self) -> Mode:
        return self.modes[self.active_mode]

    def set_active_mode(self, name: str) -> None:
        if name not in self.modes:
            raise KeyError(f"Unknown mode: {name!r}. Available: {list(self.modes)}")
        self.active_mode = name

    @property
    def llm_model(self) -> str | None:
        """The Ollama model used by LLM modes (they share one by convention)."""
        for m in self.modes.values():
            if m.llm_model:
                return m.llm_model
        return None

    def set_llm_model(self, model: str) -> None:
        """Point every LLM-enabled mode at `model`."""
        for m in self.modes.values():
            if m.llm_model:
                m.llm_model = model

    def save(self) -> None:
        data = {
            "active_mode": self.active_mode,
            "hotkey": self.hotkey,
            "toggle_hotkey": self.toggle_hotkey,
            "pause_audio": self.pause_audio,
            "hud_position": self.hud_position,
            "modes": {
                m.name: {
                    "asr_model": m.asr_model,
                    "llm_model": m.llm_model,
                    "system_prompt": m.system_prompt,
                    "vocab": m.vocab,
                }
                for m in self.modes.values()
            },
        }
        self.path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def load_config(path: str | Path = "modes.json") -> Config:
    path = Path(path)
    if path.exists():
        raw = json.loads(path.read_text())
    else:
        log.info("No %s found — writing default config.", path)
        raw = DEFAULT_CONFIG
        path.write_text(json.dumps(raw, indent=2) + "\n")

    modes_raw = raw.get("modes") or {}
    if not modes_raw:
        raise ValueError(f"{path}: 'modes' must contain at least one mode")

    modes: dict[str, Mode] = {}
    for name, m in modes_raw.items():
        if not isinstance(m, dict):
            raise ValueError(f"{path}: mode {name!r} must be an object")
        modes[name] = Mode(
            name=name,
            asr_model=m.get("asr_model") or DEFAULT_ASR_MODEL,
            llm_model=m.get("llm_model"),
            system_prompt=m.get("system_prompt"),
            vocab=list(m.get("vocab") or []),
        )

    active = raw.get("active_mode")
    if active not in modes:
        fallback = next(iter(modes))
        if active is not None:
            log.warning("active_mode %r not found; using %r.", active, fallback)
        active = fallback

    pos = raw.get("hud_position")
    if not (
        isinstance(pos, (list, tuple))
        and len(pos) == 2
        and all(isinstance(v, (int, float)) for v in pos)
    ):
        pos = None

    return Config(
        active_mode=active,
        hotkey=raw.get("hotkey") or "alt_r",
        toggle_hotkey=raw.get("toggle_hotkey"),
        modes=modes,
        path=path,
        pause_audio=bool(raw.get("pause_audio", True)),
        hud_position=list(pos) if pos else None,
    )
