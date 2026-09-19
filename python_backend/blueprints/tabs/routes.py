import json
import os
import tempfile

from flask import Blueprint, current_app, jsonify, request

from extensions import limiter
from services.tabs import TAB_SOURCES, TabFinderService

tabs_bp = Blueprint("tabs", __name__)


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
