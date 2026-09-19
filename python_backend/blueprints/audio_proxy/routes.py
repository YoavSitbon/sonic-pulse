"""Internal proxy from the public API to the audio-analysis service."""

import os

import requests
from flask import Blueprint, Response, current_app, request
from extensions import limiter

audio_proxy_bp = Blueprint("audio_proxy", __name__)

_SERVICE_PATHS = {
    "/api/recognize-chords": "CHORD_SERVICE_URL",
    "/api/recognize-chords-firebase": "CHORD_SERVICE_URL",
    "/api/detect-beats": "BEAT_SERVICE_URL",
    "/api/detect-beats-firebase": "BEAT_SERVICE_URL",
    "/api/songformer/segment": "AUDIO_SERVICE_URL",
}


@limiter.limit("2 per minute")
def _forward(path: str):
    service_key = _SERVICE_PATHS.get(path, "AUDIO_SERVICE_URL")
    base_url = (
        current_app.config.get(service_key, "")
        or current_app.config.get("AUDIO_SERVICE_URL", "")
    ).rstrip("/")
    if not base_url:
        return {"success": False, "error": "Audio service is not configured."}, 503

    files = {}
    for field, uploaded in request.files.items():
        files[field] = (
            uploaded.filename or "audio.bin",
            uploaded.stream,
            uploaded.mimetype or "application/octet-stream",
        )

    try:
        response = requests.post(
            f"{base_url}{path}",
            params=request.args,
            data=request.form.to_dict(flat=True) if not request.is_json else None,
            json=request.get_json(silent=True) if request.is_json else None,
            files=files or None,
            timeout=int(os.environ.get("AUDIO_SERVICE_TIMEOUT", "600")),
        )
    except requests.RequestException as exc:
        current_app.logger.exception("audio service proxy failed")
        return {
            "success": False,
            "error": f"Audio analysis service unavailable: {exc}",
        }, 502

    return Response(
        response.content,
        status=response.status_code,
        content_type=response.headers.get("Content-Type", "application/json"),
    )


for _path in tuple(_SERVICE_PATHS):
    audio_proxy_bp.add_url_rule(
        _path,
        endpoint=f"proxy_{_path.strip('/').replace('/', '_').replace('-', '_')}",
        view_func=lambda path=_path: _forward(path),
        methods=["POST"],
    )
