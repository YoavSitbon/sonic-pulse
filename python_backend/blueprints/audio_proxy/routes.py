"""Internal proxy from the public API to the audio-analysis service."""

import os

import requests
from flask import Blueprint, Response, current_app, request
from extensions import limiter

audio_proxy_bp = Blueprint("audio_proxy", __name__)

_AUDIO_PATHS = (
    "/api/recognize-chords",
    "/api/recognize-chords-firebase",
    "/api/detect-beats",
    "/api/detect-beats-firebase",
    "/api/songformer/segment",
)


@limiter.limit("2 per minute")
def _forward(path: str):
    base_url = current_app.config.get("AUDIO_SERVICE_URL", "").rstrip("/")
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


for _path in _AUDIO_PATHS:
    audio_proxy_bp.add_url_rule(
        _path,
        endpoint=f"proxy_{_path.strip('/').replace('/', '_').replace('-', '_')}",
        view_func=lambda path=_path: _forward(path),
        methods=["POST"],
    )
