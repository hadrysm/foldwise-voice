"""Entrypoint: python -m foldwise_voice [--menubar] [--config PATH] [--mode NAME]"""

from __future__ import annotations

import argparse
import logging


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="foldwise_voice",
        description="Local, private dictation for macOS (mlx-whisper + optional Ollama).",
    )
    parser.add_argument("--config", default="modes.json", help="path to modes.json")
    parser.add_argument("--mode", help="override the active mode for this run")
    parser.add_argument(
        "--ui", "--menubar", dest="ui", action="store_true",
        help="run the menu-bar UI (status icon, listening HUD, settings window)",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    from .app import run_headless, run_ui
    from .config import load_config

    config = load_config(args.config)
    if args.mode:
        config.set_active_mode(args.mode)

    if args.ui:
        run_ui(config)
    else:
        run_headless(config)


if __name__ == "__main__":
    main()
