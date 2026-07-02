"""Query the local Ollama server for installed models (for the settings UI)."""

from __future__ import annotations

import logging

import requests

log = logging.getLogger(__name__)

TAGS_URL = "http://localhost:11434/api/tags"


def list_models(timeout: float = 2.0) -> list[str]:
    """Names of locally installed Ollama models; [] if Ollama is unreachable."""
    try:
        resp = requests.get(TAGS_URL, timeout=timeout)
        resp.raise_for_status()
        return sorted(m["name"] for m in resp.json().get("models", []))
    except Exception as e:
        log.debug("Ollama not reachable for model list: %s", e)
        return []
