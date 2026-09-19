/// API configuration for SonicPulse backend.
///
/// Set [useMockResponses] to false when the Python backend is ready.
/// Update [baseUrl] to your machine's LAN IP before running on a physical device.
class ApiConfig {
  ApiConfig._();

  // ── Connection ──────────────────────────────────────────────────
  /// Your machine's local IP. Android physical devices cannot use localhost.
  // Use 10.0.2.2 for the Android emulator, or replace this with the host
  // machine's LAN IP when running on a physical device. For Flutter web and
  // iOS simulator, localhost/127.0.0.1 points at the host machine.
  static const String baseUrl = String.fromEnvironment(
    'SONIC_PULSE_API_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );

  /// Toggle to false when the backend is live.
  static const bool useMockResponses = false;

  /// How long to simulate "recording" before showing a result (mock mode).
  static const Duration mockRecordingDuration = Duration(seconds: 3);

  // ── Endpoints ────────────────────────────────────────────────────
  static const String recognizeEndpoint = '/api/recognize-chords';
  static const String analyzeEndpoint = '/api/recognize-chords';

  /// Receives a user-selected catalogue song as JSON: `{title, artist}`.
  static const String selectedSongEndpoint = '/api/analyze-song';
  static const String findTabsEndpoint = '/api/find-existing-chords';
  static const String tabSourcesEndpoint = '/api/tab-sources';

  // ── Timeouts ─────────────────────────────────────────────────────
  // Model inference can take longer than a normal API request.
  static const Duration requestTimeout = Duration(minutes: 5);

  // ── Recording ────────────────────────────────────────────────────
  /// Seconds of audio to capture before sending to backend.
  static const int recordingSeconds = 10;
}
