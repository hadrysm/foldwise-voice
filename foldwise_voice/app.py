"""Orchestration: headless loop, or a rumps menu-bar app with --menubar."""

from __future__ import annotations

import logging
import time

from .config import Config
from .hotkey import HotkeyListener
from .pipeline import Pipeline

log = logging.getLogger(__name__)


def _build(config: Config) -> tuple[Pipeline, HotkeyListener]:
    pipeline = Pipeline(config)
    listener = HotkeyListener(
        ptt_key=config.hotkey,
        on_press=pipeline.start_recording,
        on_release=pipeline.stop_recording,
        toggle_key=config.toggle_hotkey,
        on_toggle=pipeline.toggle_recording,
    )
    return pipeline, listener


def run_headless(config: Config) -> None:
    mode = config.mode
    print(
        f"foldwise-voice ready.\n"
        f"  active mode : {config.active_mode}"
        f" ({'ASR + ' + mode.llm_model if mode.uses_llm else 'ASR only'})\n"
        f"  push-to-talk: hold '{config.hotkey}'"
        + (f"\n  toggle      : tap '{config.toggle_hotkey}'" if config.toggle_hotkey else "")
        + "\n  Ctrl+C to quit."
    )
    pipeline, listener = _build(config)
    listener.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nbye.")
    finally:
        listener.stop()
        pipeline.shutdown()


def run_ui(config: Config) -> None:
    """Menu-bar app with the listening HUD and settings window."""
    from .ui.menubar import run_app

    run_app(config)
