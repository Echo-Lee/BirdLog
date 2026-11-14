"""Minimal client for the local Bonsai server (mlx_vlm.server, OpenAI-compatible)."""
from __future__ import annotations

import os

import requests

BONSAI_URL = os.environ.get("BONSAI_URL", "http://localhost:8080")

# Sampling presets from the Bonsai 2 model cards. The servers do not read
# presence_penalty / min_p from model metadata, so send them on every request.
CHAT_PARAMS = {
    "temperature": 0.2,          # low: we want deterministic structured output
    "top_p": 0.8,
    "top_k": 20,
    "min_p": 0,
    "presence_penalty": 1.5,
    "repetition_penalty": 1.0,
    "max_tokens": 512,
}


class BonsaiUnavailable(Exception):
    pass


class BonsaiClient:
    def __init__(self, base_url: str = BONSAI_URL, timeout: float = 90.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self._model_id: str | None = None

    def available(self) -> bool:
        try:
            self._get_model_id()
            return True
        except (requests.RequestException, ValueError, KeyError):
            return False

    def _get_model_id(self) -> str:
        if self._model_id:
            return self._model_id
        r = requests.get(f"{self.base_url}/v1/models", timeout=5)
        r.raise_for_status()
        data = r.json()["data"]
        if not data:
            raise ValueError("no models served")
        # mlx_vlm.server also lists cached models; prefer the one actually loaded.
        model = next((m for m in data if m.get("loaded")), data[0])
        self._model_id = model["id"]
        return self._model_id

    def chat(self, system: str, user: str) -> str:
        payload = {
            "model": self._get_model_id(),
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            **CHAT_PARAMS,
            "chat_template_kwargs": {"enable_thinking": False},
        }
        try:
            r = requests.post(f"{self.base_url}/v1/chat/completions",
                              json=payload, timeout=self.timeout)
            r.raise_for_status()
        except requests.RequestException as e:
            raise BonsaiUnavailable(str(e)) from e
        content = r.json()["choices"][0]["message"]["content"]
        # Some servers leave <think>...</think> inline; strip it.
        if "</think>" in content:
            content = content.split("</think>")[-1]
        return content.strip()