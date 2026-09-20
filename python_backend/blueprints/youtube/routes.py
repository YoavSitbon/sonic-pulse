"""Backend proxy for YouTube Data API searches."""

import requests
from flask import Blueprint, current_app, jsonify, request

from extensions import limiter


youtube_bp = Blueprint("youtube", __name__)


@youtube_bp.get("/api/search-youtube")
@limiter.limit("20 per minute")
def search_youtube():
    query = (request.args.get("query") or "").strip()
    category = (request.args.get("type") or "videos").lower()
    if not query:
        return jsonify({"success": False, "error": "A search query is required."}), 400
    if category not in {"videos", "shorts"}:
        return jsonify({"success": False, "error": "Invalid YouTube search type."}), 400

    api_key = current_app.config.get("YOUTUBE_API_KEY", "")
    if not api_key:
        return jsonify({"success": False, "error": "YOUTUBE_API_KEY is not configured."}), 503

    params = {
        "part": "snippet",
        "type": "video",
        "maxResults": 10,
        "q": f"{query} #shorts" if category == "shorts" else query,
        "key": api_key,
    }
    if category == "shorts":
        params["videoDuration"] = "short"

    try:
        response = requests.get(
            "https://www.googleapis.com/youtube/v3/search",
            params=params,
            timeout=current_app.config.get("YOUTUBE_API_TIMEOUT", 15),
        )
        payload = response.json()
    except (requests.RequestException, ValueError) as exc:
        current_app.logger.exception("YouTube API search failed")
        return jsonify({"success": False, "error": f"YouTube search failed: {exc}"}), 502

    if response.status_code >= 400:
        error = payload.get("error", {}).get("message", "YouTube search failed.")
        return jsonify({"success": False, "error": error}), response.status_code

    results = []
    for item in payload.get("items", []):
        video_id = (item.get("id") or {}).get("videoId")
        snippet = item.get("snippet") or {}
        if not video_id:
            continue
        thumbnails = snippet.get("thumbnails") or {}
        thumbnail = (
            (thumbnails.get("high") or {}).get("url")
            or (thumbnails.get("medium") or {}).get("url")
            or (thumbnails.get("default") or {}).get("url")
            or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
        )
        results.append(
            {
                "video_id": video_id,
                "title": snippet.get("title") or "Unknown video",
                "channel": snippet.get("channelTitle") or "",
                "thumbnail": thumbnail,
                "url": (
                    f"https://www.youtube.com/shorts/{video_id}"
                    if category == "shorts"
                    else f"https://www.youtube.com/watch?v={video_id}"
                ),
            }
        )

    return jsonify({"success": True, "results": results})
