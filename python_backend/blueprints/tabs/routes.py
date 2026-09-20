import json
import os
import tempfile
import wave

from flask import Blueprint, current_app, jsonify, request

from extensions import limiter
from services.tabs import TAB_SOURCES, TabFinderService

tabs_bp = Blueprint("tabs", __name__)


def register_socket_routes(sock):
    """Register the streaming recognizer on the app-level WebSocket server."""

    @sock.route("/ws/find-existing-song")
    def find_tabs_stream(ws):
        preferences = {}
        audio_buffer = bytearray()
        sample_rate = 44100
        sample_width = 2  # PCM16
        channels = 1
        window_seconds = 5
        window_bytes = sample_rate * sample_width * channels * window_seconds
        elapsed_seconds = 0

        try:
            while True:
                message = ws.receive()
                if message is None:
                    return

                if isinstance(message, str):
                    control = json.loads(message)
                    if control.get("type") == "cancel":
                        return
                    if control.get("type") == "start":
                        preferences = control.get("preferences") or {}
                    continue

                audio_buffer.extend(message)
                while len(audio_buffer) >= window_bytes:
                    window = bytes(audio_buffer[:window_bytes])
                    del audio_buffer[:window_bytes]
                    elapsed_seconds += window_seconds

                    with tempfile.NamedTemporaryFile(
                        delete=False, suffix=".wav"
                    ) as handle:
                        window_path = handle.name
                    try:
                        with wave.open(window_path, "wb") as wav_file:
                            wav_file.setnchannels(channels)
                            wav_file.setsampwidth(sample_width)
                            wav_file.setframerate(sample_rate)
                            wav_file.writeframes(window)

                        try:
                            result = TabFinderService().find_tabs(
                                audio_path=window_path,
                                preferences=preferences,
                            )
                        except Exception:
                            # A rolling window without a match is expected.
                            result = None

                        if result and result.get("success"):
                            ws.send(json.dumps(result))
                            return

                        ws.send(json.dumps({
                            "type": "progress",
                            "seconds": elapsed_seconds,
                        }))
                    finally:
                        if os.path.exists(window_path):
                            os.unlink(window_path)
        except Exception:
            current_app.logger.exception("streaming song recognition failed")
            try:
                ws.send(json.dumps({
                    "type": "error",
                    "error": "Streaming recognition failed.",
                }))
            except Exception:
                pass


@tabs_bp.get("/api/tab-sources")
def tab_sources():
    return jsonify({
        "languages": ["en", "he"],
        "sources": [
            {
                "id": source_id,
                "name": source["name"],
                "languages": source["languages"],
            }
            for source_id, source in TAB_SOURCES.items()
        ],
    })


@tabs_bp.post("/api/find-existing-chords")
@limiter.limit("10 per minute")
def find_tabs():
    uploaded_path = None
    try:
        data = request.get_json(silent=True) or {}
        title = request.form.get("title") or data.get("title")
        artist = request.form.get("artist") or data.get("artist")
        artist_id = request.form.get("artist_id") or data.get("artist_id")
        preferences = request.form.get("preferences") or data.get("preferences") or {}
        if isinstance(preferences, str):
            preferences = json.loads(preferences)

        audio = request.files.get("file")
        if audio:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as handle:
                audio.save(handle.name)
                uploaded_path = handle.name

        result = TabFinderService().find_tabs(
            title=title,
            artist=artist,
            artist_id=artist_id,
            audio_path=uploaded_path,
            preferences=preferences,
        )
        return jsonify(result)
    except ValueError as exc:
        return jsonify({"success": False, "error": str(exc)}), 400
    except Exception as exc:
        current_app.logger.exception("find-existing-chords failed")
        return jsonify({"success": False, "error": str(exc)}), 502
    finally:
        if uploaded_path and os.path.exists(uploaded_path):
            os.unlink(uploaded_path)
