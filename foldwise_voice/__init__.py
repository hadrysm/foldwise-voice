"""foldwise_voice — local, private dictation for macOS.

Two-stage pipeline:
  audio -> [Stage 1: mlx-whisper ASR] -> raw text -> [Stage 2: Ollama LLM, optional] -> insert
"""

__version__ = "0.5.0"  # x-release-please-version
