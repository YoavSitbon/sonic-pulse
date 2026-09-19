"""Qwen-backed music conversation service."""

import json
import os
from typing import Any, Dict, List

import requests

from services.music_theory_engine import MusicTheoryEngine


class MusicAiService:
    """Build deterministic music facts, then ask Qwen to explain them."""

    def __init__(self, config=None):
        self.base_url = os.environ.get(
            "MUSIC_AI_BASE_URL", "http://127.0.0.1:11434/v1"
        ).rstrip("/")
        self.api_key = os.environ.get("MUSIC_AI_API_KEY", "").strip()
        self.model = os.environ.get("MUSIC_AI_MODEL", "qwen3:8b")
        self.timeout = int(os.environ.get("MUSIC_AI_TIMEOUT", "60"))
        self.theory = MusicTheoryEngine()

    @property
    def available(self) -> bool:
        return bool(self.base_url and self.model)

    def answer(
        self,
        question: str,
        song: Dict[str, Any],
        conversation: List[Dict[str, str]],
    ) -> str:
        if not self.available:
            raise RuntimeError("Music AI is not configured on the server.")

        structured_music = self.theory.build(song)
        messages = [
            {
                "role": "system",
                "content": self._system_prompt(structured_music, question),
            }
        ]
        for message in conversation:
            role = "assistant" if message.get("role") == "assistant" else "user"
            content = str(message.get("content", "")).strip()
            if content:
                messages.append({"role": role, "content": content})
        messages.append({"role": "user", "content": question})

        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        try:
            response = requests.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json={
                    "model": self.model,
                    "messages": messages,
                    "temperature": 0.3,
                    "max_tokens": 800,
                },
                timeout=self.timeout,
            )
        except requests.RequestException as exc:
            raise RuntimeError(
                "Local music AI is unavailable. Start Ollama and run "
                f"'ollama run {self.model}'."
            ) from exc
        if response.status_code != 200:
            detail = ""
            try:
                detail = response.json().get("error", {}).get("message", "")
            except ValueError:
                pass
            raise RuntimeError(detail or "The music AI provider returned an error.")

        try:
            answer = response.json()["choices"][0]["message"]["content"]
        except (IndexError, KeyError, TypeError, ValueError) as exc:
            raise RuntimeError("The music AI provider returned an empty response.") from exc
        if not isinstance(answer, str) or not answer.strip():
            raise RuntimeError("The music AI provider returned an empty response.")
        return answer.strip()

    @staticmethod
    def _system_prompt(structured_music: Dict[str, Any], question: str) -> str:
        language = (
            "Hebrew"
            if any("\u0590" <= char <= "\u05ff" for char in question)
            else "the user's language"
        )
        return (
            "You are SonicPulse's concise music theory and guitar coach. Answer "
            "only the latest question. Do not add unrelated analysis, a general "
            "song summary, or extra suggestions unless requested. Keep the answer "
            "to 2-5 short sentences or a very small bullet list. Reply in "
            f"{language}; if the question is Hebrew, answer fully in Hebrew. "
            "Use the STRUCTURED MUSICAL REPRESENTATION as the factual source. "
            "Do not invent missing facts. Explain theory clearly and practically. "
            "Do not reproduce copyrighted lyrics or tablature.\n\n"
            "STRUCTURED MUSICAL REPRESENTATION:\n"
            f"{json.dumps(structured_music, ensure_ascii=False, indent=2)}"
        )
