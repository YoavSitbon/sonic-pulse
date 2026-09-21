from flask import Blueprint, current_app, jsonify, request

from extensions import limiter

music_ai_bp = Blueprint("music_ai", __name__)


@music_ai_bp.post("/api/song-ai/chat")
@limiter.limit("10 per minute")
def song_ai_chat():
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        return jsonify({"success": False, "error": "Request body must be JSON."}), 400
    question = data.get("question")
    song = data.get("song")
    conversation = data.get("conversation", [])
    model = data.get("model")

    if not isinstance(question, str) or not question.strip():
        return jsonify({"success": False, "error": "A question is required."}), 400
    if len(question) > 2000:
        return jsonify({"success": False, "error": "Question is too long."}), 400
    if not isinstance(song, dict):
        return jsonify({"success": False, "error": "Song context is required."}), 400
    if model is not None and (
        not isinstance(model, str) or not model.startswith("gemini-")
    ):
        return jsonify({"success": False, "error": "Only Gemini models are supported."}), 400
    if not isinstance(conversation, list) or len(conversation) > 20:
        return jsonify({"success": False, "error": "Conversation is too long."}), 400

    cleaned_conversation = []
    for message in conversation:
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        content = message.get("content")
        if role in ("user", "assistant") and isinstance(content, str):
            cleaned_conversation.append({
                "role": role,
                "content": content[:4000],
            })

    service = current_app.extensions["services"].get("music_ai")
    if service is None or not service.available:
        return jsonify({
            "success": False,
            "error": "Gemini is not configured. Set GEMINI_API_KEY on the backend.",
        }), 503

    try:
        answer = service.answer(
            question=question.strip(),
            song=song,
            conversation=cleaned_conversation,
            model=model,
        )
        return jsonify({"success": True, "answer": answer})
    except Exception as exc:
        current_app.logger.exception("song AI request failed")
        return jsonify({"success": False, "error": str(exc)}), 502
