/// API configuration for SonicPulse backend.
///
/// Set [useMockResponses] to false when the Python backend is ready.
/// Update [baseUrl] to your machine's LAN IP before running on a physical device.
class ApiConfig {
  ApiConfig._();

  // ── Connection ──────────────────────────────────────────────────
  /// Your machine's local IP. Android physical devices cannot use localhost.
  static const String baseUrl = 'http://3.3.3.3:5001';

  /// Toggle to false when the backend is live.
  static const bool useMockResponses = true;

  /// How long to simulate "recording" before showing a result (mock mode).
  static const Duration mockRecordingDuration = Duration(seconds: 3);

  // ── Endpoints ────────────────────────────────────────────────────
  static const String recognizeEndpoint = '/api/recognize-chords';
  static const String analyzeEndpoint = '/api/analyze';
  /// Receives a user-selected catalogue song as JSON: `{title, artist}`.
  static const String selectedSongEndpoint = '/api/analyze-song';

  // ── Timeouts ─────────────────────────────────────────────────────
  static const Duration requestTimeout = Duration(seconds: 30);

  // ── Recording ────────────────────────────────────────────────────
  /// Seconds of audio to capture before sending to backend.
  static const int recordingSeconds = 10;
}
