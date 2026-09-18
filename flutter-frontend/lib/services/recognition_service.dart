import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track_result.dart';

/// Sends audio files to the Python backend for recognition / analysis.
///
/// While [ApiConfig.useMockResponses] is true, all methods return
/// fake data after a short delay so the UI can be tested end-to-end.
class RecognitionService {
  // ── Song fingerprint recognition ─────────────────────────────────

  Future<TrackResult> recognizeSong(String audioFilePath) async {
    if (ApiConfig.useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 800));
      return MockResponses.recognize();
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.recognizeEndpoint}');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('file', audioFilePath,
          filename: 'recording.wav'),
    );

    final streamed = await request.send().timeout(ApiConfig.requestTimeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw RecognitionException(
        'Server error ${response.statusCode}: ${response.body}',
      );
    }

    try {
      return TrackResult.fromJsonString(response.body);
    } catch (e) {
      throw RecognitionException('Failed to parse server response: $e');
    }
  }

  /// Sends the title and artist chosen in the public music catalogue to the
  /// backend for the same analysis flow used by an identified recording.
  Future<TrackResult> analyzeSelectedSong({
    required String title,
    required String artist,
  }) async {
    if (ApiConfig.useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 700));
      final mock = MockResponses.analyze();
      return TrackResult(
        title: title,
        artist: artist,
        album: mock.album,
        key: mock.key,
        bpm: mock.bpm,
        confidence: 1,
        chords: mock.chords,
        mood: mock.mood,
        camelot: mock.camelot,
        timeSig: mock.timeSig,
        timestamp: DateTime.now(),
      );
    }

    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.selectedSongEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'title': title, 'artist': artist}),
        )
        .timeout(ApiConfig.requestTimeout);

    if (response.statusCode != 200) {
      throw RecognitionException(
        'Server error ${response.statusCode}: ${response.body}',
      );
    }
    try {
      return TrackResult.fromJsonString(response.body);
    } catch (e) {
      throw RecognitionException('Failed to parse server response: $e');
    }
  }

  // ── AI deep analysis ─────────────────────────────────────────────

  Future<TrackResult> analyzeSong(String audioFilePath) async {
    if (ApiConfig.useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 1200));
      return MockResponses.analyze();
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyzeEndpoint}');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath('audio', audioFilePath,
          filename: 'recording.wav'),
    );

    final streamed = await request.send().timeout(ApiConfig.requestTimeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw RecognitionException(
        'Server error ${response.statusCode}: ${response.body}',
      );
    }

    try {
      return TrackResult.fromJsonString(response.body);
    } catch (e) {
      throw RecognitionException('Failed to parse server response: $e');
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────

  /// Deletes the temp audio file after sending.
  Future<void> cleanupFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class RecognitionException implements Exception {
  final String message;
  const RecognitionException(this.message);

  @override
  String toString() => 'RecognitionException: $message';
}
