"""Combined audio-analysis endpoint used by the analyzed-song page."""

import os
import time
import traceback
import logging
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor

import requests
from flask import Blueprint, current_app, jsonify, request

from extensions import limiter
from config import get_config
from services.audio.tempfiles import temporary_file
from services.youtube.youtube_search_service import YouTubeSearchService
from utils.logging import log_error, log_info


analysis_bp = Blueprint("analysis", __name__)
config = get_config()
logger = logging.getLogger(__name__)
youtube_service = YouTubeSearchService()


@analysis_bp.post("/api/analyze-audio")
@limiter.limit(config.get_rate_limit("heavy_processing"))
def analyze_audio():
    """Run beat detection and chord recognition against one uploaded file.

    The service responses are normalized into the small timeline contract used
    by the client. Model-internal fields stay inside the backend.
    """
    started_at = time.perf_counter()
    uploaded_file = request.files.get("file")
    youtube_url = (request.form.get("youtube_url") or "").strip()
    if request.is_json:
        youtube_url = (request.get_json(silent=True) or {}).get("youtube_url", "").strip()
    if not youtube_url and (not uploaded_file or not uploaded_file.filename):
        return jsonify({"success": False, "error": "No audio file or YouTube URL provided."}), 400

    beat_detector = request.form.get("beat_detector", "auto").lower()
    chord_detector = request.form.get("chord_detector", "auto").lower()
    chord_dict = request.form.get("chord_dict") or None
    force = request.form.get("force", "false").lower() == "true"

    youtube_audio_path = None
    youtube_audio_url = ""
    youtube_metadata = {}
    try:
        if youtube_url:
            log_info(f"Downloading YouTube audio for analysis: {youtube_url}")
            youtube_audio_path, youtube_audio_url, youtube_metadata = (
                youtube_service.download_audio(youtube_url)
            )
            input_filename = os.path.basename(youtube_audio_path)
            input_mimetype = "audio/mp4" if input_filename.endswith(".m4a") else "audio/mpeg"
        else:
            input_filename = uploaded_file.filename or "audio.bin"
            input_mimetype = uploaded_file.mimetype or "application/octet-stream"

        has_external_services = any(
            current_app.config.get(key)
            for key in ("AUDIO_SERVICE_URL", "BEAT_SERVICE_URL", "CHORD_SERVICE_URL")
        )
        if has_external_services:
            # The gateway owns the upload, then sends the same bytes to both
            # independent services concurrently. Each service gets its own
            # request body, so neither request can consume the other's stream.
            if youtube_audio_path:
                with open(youtube_audio_path, "rb") as audio_file:
                    audio_bytes = audio_file.read()
            else:
                audio_bytes = uploaded_file.read()
            filename = input_filename
            mimetype = input_mimetype
            beat_url = (
                current_app.config.get("BEAT_SERVICE_URL")
                or current_app.config.get("AUDIO_SERVICE_URL")
            )
            chord_url = (
                current_app.config.get("CHORD_SERVICE_URL")
                or current_app.config.get("AUDIO_SERVICE_URL")
            )
            log_info(
                f"Running parallel audio services: beat={beat_url} chord={chord_url}"
            )
            with ThreadPoolExecutor(max_workers=2) as executor:
                beat_future = executor.submit(
                    _call_external_service,
                    beat_url,
                    "/api/detect-beats",
                    audio_bytes,
                    filename,
                    mimetype,
                    {"detector": beat_detector, "force": str(force).lower()},
                )
                chord_future = executor.submit(
                    _call_external_service,
                    chord_url,
                    "/api/recognize-chords",
                    audio_bytes,
                    filename,
                    mimetype,
                    {
                        "detector": chord_detector,
                        "chord_dict": chord_dict or "",
                        "force": str(force).lower(),
                        "use_spleeter": "false",
                    },
                )
                beat_result = beat_future.result()
                chord_result = chord_future.result()
        else:
            services = current_app.extensions["services"]
            if youtube_audio_path:
                file_context = _existing_file(youtube_audio_path)
            else:
                file_context = temporary_file(
                    suffix=os.path.splitext(input_filename)[1] or ".wav"
                )
            with file_context as file_path:
                if not youtube_audio_path:
                    uploaded_file.save(file_path)
                log_info(
                    f"Running combined audio analysis in-process: "
                    f"beat_detector={beat_detector} chord_detector={chord_detector}"
                )
                beat_result = services["beat_detection"].detect_beats(
                    file_path=file_path,
                    detector=beat_detector,
                    force=force,
                )
                chord_result = services["chord_recognition"].recognize_chords(
                    file_path=file_path,
                    detector=chord_detector,
                    chord_dict=chord_dict,
                    force=force,
                    use_spleeter=False,
                )

        success = bool(beat_result.get("success") and chord_result.get("success"))
        chords_by_beat = _build_chords_by_beat(
            beat_result.get("beats", []),
            chord_result.get("chords", []),
        )
        response = {
            "success": success,
            "beats": beat_result.get("beats", []),
            "downbeats": beat_result.get("downbeats", []),
            "bpm": beat_result.get("bpm", 0),
            "time_signature": beat_result.get("time_signature", "—"),
            "duration": max(
                float(beat_result.get("duration", 0) or 0),
                float(chord_result.get("duration", 0) or 0),
            ),
            "beat_model": beat_result.get("model_name") or beat_result.get("model_used"),
            "chord_model": chord_result.get("model_name") or chord_result.get("model_used"),
            "analysis_time": round(time.perf_counter() - started_at, 3),
            # Index N is the chord at beat N. Empty strings represent N/no chord.
            "chords_by_beat": chords_by_beat,
        }
        if youtube_url:
            response.update(
                {
                    "title": youtube_metadata.get("title"),
                    "artist": youtube_metadata.get("channel"),
                    "artwork_url": youtube_metadata.get("thumbnail"),
                    "youtube_url": youtube_metadata.get("url") or youtube_url,
                    "audio_url": youtube_audio_url,
                }
            )
        if not success:
            response["error"] = (
                beat_result.get("error")
                or chord_result.get("error")
                or "Audio analysis failed."
            )
        return jsonify(response), 200 if success else 500
    except Exception as exc:
        log_error(f"Combined audio analysis failed: {exc}")
        log_error(traceback.format_exc())
        return jsonify({"success": False, "error": str(exc)}), 500
    finally:
        if youtube_audio_path:
            youtube_service.cleanup(os.path.dirname(youtube_audio_path))


@contextmanager
def _existing_file(path):
    """Present an already-downloaded file through the temporary-file API."""
    yield path


def _build_chords_by_beat(beats, chord_segments):
    """Assign every chord change to its closest detected beat."""
    beat_times = [float(value) for value in beats if isinstance(value, (int, float))]
    segments = [
        segment for segment in chord_segments or []
        if isinstance(segment, dict)
        and isinstance(segment.get("start"), (int, float))
    ]
    if not beat_times or not segments:
        return [""] * len(beat_times)

    def nearest_beat_index(time):
        return min(
            range(len(beat_times)),
            key=lambda index: abs(beat_times[index] - time),
        )

    changes = [None] * len(beat_times)
    for segment in segments:
        beat_index = nearest_beat_index(float(segment["start"]))
        chord = str(segment.get("chord") or "")
        changes[beat_index] = "" if chord == "N" else chord

    aligned = []
    current_chord = ""
    for change in changes:
        if change is not None:
            current_chord = change
        aligned.append(current_chord)

    return aligned


def _call_external_service(
    base_url,
    path,
    audio_bytes,
    filename,
    mimetype,
    form_data,
):
    """Call one audio microservice and normalize transport-level failures."""
    if not base_url:
        return {"success": False, "error": f"Service is not configured for {path}."}
    try:
        response = requests.post(
            f"{base_url.rstrip('/')}{path}",
            data=form_data,
            files={"file": (filename, audio_bytes, mimetype)},
            timeout=int(os.environ.get("AUDIO_SERVICE_TIMEOUT", "600")),
        )
        try:
            payload = response.json()
        except ValueError:
            payload = {"success": False, "error": response.text[:500]}
        if not isinstance(payload, dict):
            payload = {"success": False, "error": "Invalid service response."}
        if response.status_code >= 400:
            payload["success"] = False
        return payload
    except requests.RequestException as exc:
        logger.exception("Audio microservice request failed: %s", path)
        return {"success": False, "error": f"{path} unavailable: {exc}"}
