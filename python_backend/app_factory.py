"""
Flask application factory for ChordMini.

This module implements the application factory pattern, creating and configuring
Flask applications with proper separation of concerns.
"""

from flask import Flask
from typing import Optional

# Import configuration
from config import get_config

# Import extensions
from extensions import init_extensions, sock

# Import error handlers
from error_handlers import register_error_handlers, register_custom_error_handlers

# Import utilities
from utils.logging import log_info, log_debug, is_debug_enabled


def create_app(config_name: Optional[str] = None) -> Flask:
    """
    Create and configure Flask application using the application factory pattern.

    Args:
        config_name: Configuration name ('development', 'production', 'testing')
                    If None, auto-detect from environment

    Returns:
        Configured Flask application instance
    """
    # Create Flask application
    app = Flask(__name__, template_folder='templates')

    # Load configuration
    config = get_config(config_name)
    app.config.from_object(config)

    if config.SERVICE_ROLE in ('audio', 'chord', 'beat', 'monolith'):
        import compat
        compat.apply_all()

    log_info(f"Creating Flask app with config: {config.__class__.__name__}")

    # Initialize extensions
    init_extensions(app, config)

    # Register error handlers
    register_error_handlers(app)
    register_custom_error_handlers(app)

    # Register blueprints
    register_blueprints(app, config)

    # Initialize service container
    init_services(app, config)

    log_info("Flask application created successfully")

    return app


def register_blueprints(app: Flask, config) -> None:
    """
    Register all blueprints with the Flask application.

    Args:
        app: Flask application instance
        config: Configuration object
    """
    # Import blueprints
    from blueprints.health import health_bp
    from blueprints.docs import docs_bp
    from blueprints.beats import beats_bp
    from blueprints.chords import chords_bp
    from blueprints.lyrics import lyrics_bp
    from blueprints.songformer import songformer_bp
    from blueprints.debug import debug_bp
    from blueprints.tabs import tabs_bp
    from blueprints.tabs.routes import register_socket_routes
    from blueprints.music_ai import music_ai_bp
    from blueprints.audio_proxy import audio_proxy_bp

    # Register blueprints
    app.register_blueprint(health_bp)
    app.register_blueprint(docs_bp)
    if config.SERVICE_ROLE in ('audio', 'chord', 'beat'):
        if config.SERVICE_ROLE in ('audio', 'beat'):
            app.register_blueprint(beats_bp)
        if config.SERVICE_ROLE in ('audio', 'chord'):
            app.register_blueprint(chords_bp)
        if config.SERVICE_ROLE == 'audio':
            app.register_blueprint(songformer_bp)
    else:
        app.register_blueprint(lyrics_bp)
        app.register_blueprint(tabs_bp)
        app.register_blueprint(music_ai_bp)
        if config.AUDIO_SERVICE_URL or config.CHORD_SERVICE_URL or config.BEAT_SERVICE_URL:
            app.register_blueprint(audio_proxy_bp)
        else:
            app.register_blueprint(beats_bp)
            app.register_blueprint(chords_bp)
            app.register_blueprint(songformer_bp)
        register_socket_routes(sock)

    # Register debug blueprint only in non-production mode
    if not config.PRODUCTION_MODE:
        app.register_blueprint(debug_bp)
        log_info("Debug blueprint registered (non-production mode)")
    else:
        log_info("Debug blueprint skipped (production mode)")

    log_info("Blueprints registered successfully")


def init_services(app: Flask, config) -> None:
    """
    Initialize service container with dependency injection.

    Args:
        app: Flask application instance
        config: Configuration object
    """
    # Setup model paths for imports
    from utils.paths import setup_model_paths
    setup_model_paths()

    # Create a simple service container
    services = {}

    if config.SERVICE_ROLE in ('audio', 'chord', 'beat') or not (
        config.AUDIO_SERVICE_URL or config.CHORD_SERVICE_URL or config.BEAT_SERVICE_URL
    ):
        _init_audio_services(services, config.SERVICE_ROLE)
    else:
        services['beat_detection'] = None
        services['chord_recognition'] = None
        services['songformer'] = None

    if config.SERVICE_ROLE in ('audio', 'chord', 'beat'):
        services['lyrics'] = None
        services['music_ai'] = None
    else:
        try:
            from services.lyrics.orchestrator import LyricsOrchestrator
            services['lyrics'] = LyricsOrchestrator(config)
            log_info("Lyrics service initialized")
        except Exception as e:
            log_info(f"Failed to initialize lyrics service: {e}")
            services['lyrics'] = None

        try:
            from services.music_ai_service import MusicAiService
            services['music_ai'] = MusicAiService(config)
            log_info("Music AI service initialized")
        except Exception as e:
            log_info(f"Failed to initialize music AI service: {e}")
            services['music_ai'] = None

    # Store services in app extensions
    app.extensions['services'] = services

    log_info("Service container initialized")


def _init_audio_services(services: dict, role: str) -> None:
    """Initialize only the model family owned by this service role."""
    if role in ('audio', 'beat', 'monolith'):
        try:
            from services.audio.beat_detection_service import BeatDetectionService
            services['beat_detection'] = BeatDetectionService()
            log_info("Beat detection service initialized")
        except Exception as e:
            log_info(f"Failed to initialize beat detection service: {e}")
            services['beat_detection'] = None
    else:
        services['beat_detection'] = None

    if role in ('audio', 'chord', 'monolith'):
        try:
            from services.audio.chord_recognition_service import ChordRecognitionService
            services['chord_recognition'] = ChordRecognitionService()
            log_info("Chord recognition service initialized")
        except Exception as e:
            log_info(f"Failed to initialize chord recognition service: {e}")
            services['chord_recognition'] = None
    else:
        services['chord_recognition'] = None

    if role in ('audio', 'monolith'):
        try:
            from services.audio.songformer_service import SongFormerService
            services['songformer'] = SongFormerService()
            log_info("SongFormer service initialized")
        except Exception as e:
            log_info(f"Failed to initialize SongFormer service: {e}")
            services['songformer'] = None
    else:
        services['songformer'] = None
