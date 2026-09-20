"""YouTube search and audio extraction backed by yt-dlp."""

import os
import tempfile
from pathlib import Path

import yt_dlp


class YouTubeSearchService:
    """Use yt-dlp so the API does not require a YouTube API key."""

    _CLIENT_FALLBACKS = (
        None,
        {"youtube": {"player_client": ["default", "web_embedded"]}},
        {"youtube": {"player_client": ["web_safari", "android_vr"]}},
    )

    @classmethod
    def _extract(cls, url: str, options: dict, *, download: bool):
        last_error = None
        for client_args in cls._CLIENT_FALLBACKS:
            attempt = dict(options)
            if client_args:
                attempt["extractor_args"] = client_args
            try:
                with yt_dlp.YoutubeDL(attempt) as ydl:
                    return ydl.extract_info(url, download=download)
            except Exception as exc:
                last_error = exc
        raise last_error

    def download_audio(self, url: str) -> tuple[str, str, dict]:
        """Download one video audio stream and return path, playable URL, metadata."""
        directory = tempfile.mkdtemp(prefix="sonic_pulse_youtube_")
        options = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "format": "bestaudio[ext=m4a]/bestaudio/best",
            "outtmpl": os.path.join(directory, "audio.%(ext)s"),
        }
        try:
            info = self._extract(url, options, download=True)
            path = Path(options["outtmpl"].replace("%(ext)s", info.get("ext", "m4a")))
            if not path.exists():
                candidates = list(Path(directory).glob("audio.*"))
                if not candidates:
                    raise RuntimeError("YouTube audio download produced no file.")
                path = candidates[0]
            playable_url = info.get("url") or ""
            metadata = {
                "video_id": info.get("id"),
                "title": info.get("title") or "YouTube analysis",
                "channel": info.get("channel") or info.get("uploader") or "",
                "thumbnail": info.get("thumbnail"),
                "duration": info.get("duration") or 0,
                "url": info.get("webpage_url") or url,
            }
            return str(path), playable_url, metadata
        except Exception:
            self.cleanup(directory)
            raise

    @staticmethod
    def cleanup(path: str) -> None:
        import shutil

        shutil.rmtree(path, ignore_errors=True)
