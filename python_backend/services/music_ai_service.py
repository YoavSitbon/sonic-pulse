"""Gemini-backed music coach service."""

import os
from typing import Any, Dict, List, Optional

import requests


class MusicAiService:
    """Send the minimal song-coach prompt to Google's Gemini API."""

    DEFAULT_MODEL = "gemini-3.6-flash"

    def __init__(self, config=None):
        self.api_key = os.environ.get("GEMINI_API_KEY", "").strip()
        self.model = os.environ.get("MUSIC_AI_MODEL", self.DEFAULT_MODEL).strip()
        self.timeout = int(os.environ.get("MUSIC_AI_TIMEOUT", "60"))

    @property
    def available(self) -> bool:
        return bool(self.api_key)

    def answer(
        self,
        question: str,
        song: Dict[str, Any],
        conversation: Optional[List[Dict[str, str]]] = None,
        model: Optional[str] = None,
    ) -> str:
        if not self.available:
            raise RuntimeError(
                "Gemini is not configured. Set GEMINI_API_KEY on the backend."
            )

        selected_model = model or self.model or self.DEFAULT_MODEL
        if not selected_model.startswith("gemini-"):
            raise RuntimeError("Only Gemini models are supported.")

        chords = song.get("chords") or []
        if not isinstance(chords, list):
            chords = [str(chords)]
        prompt = (
            f"Song name: {song.get('title', 'Unknown')}\n"
            f"Artist: {song.get('artist', 'Unknown')}\n"
            "The chords in the song are: "
            f"{', '.join(str(chord) for chord in chords)}\n"
            f"User's message: {question.strip()}"
        )

        try:
            response = requests.post(
                f"https://generativelanguage.googleapis.com/v1beta/models/{selected_model}:generateContent",
                headers={
                    "Content-Type": "application/json",
                    "x-goog-api-key": self.api_key,
                },
                json={
                    "systemInstruction": {
                        "parts": [{
                            "text": "You are SonicPulse's concise music theory and guitar coach. Answer the user's message directly and clearly."
                        }]
                    },
                    "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                    "generationConfig": {"temperature": 0.3, "maxOutputTokens": 800},
                },
                timeout=self.timeout,
            )
        except requests.RequestException as exc:
            raise RuntimeError("Gemini could not be reached.") from exc

        if response.status_code != 200:
            detail = ""
            try:
                detail = response.json().get("error", {}).get("message", "")
            except ValueError:
                pass
            raise RuntimeError(detail or "Gemini returned an error.")

        try:
            parts = response.json()["candidates"][0]["content"]["parts"]
            answer = "".join(part.get("text", "") for part in parts)
        except (IndexError, KeyError, TypeError, ValueError) as exc:
            raise RuntimeError("Gemini returned an empty answer.") from exc
        if not answer.strip():
            raise RuntimeError("Gemini returned an empty answer.")
        return answer.strip()
