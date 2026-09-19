import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track_result.dart';

/// Sends audio files to the Python backend for recognition / analysis.
///
class RecognitionService {
  Future<TrackResult> findTabsFromAudio(
    String audioFilePath, {
    Map<String, List<String>> preferences = const {},
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.findTabsEndpoint}'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', audioFilePath));
    request.fields['preferences'] = jsonEncode(preferences);
    return _sendFindTabs(request);
  }

  Future<TrackResult> findTabsBySong({
    required String title,
    required String artist,
    Map<String, List<String>> preferences = const {},
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.findTabsEndpoint}'),
    );
    request.fields['title'] = title;
    request.fields['artist'] = artist;
    request.fields['preferences'] = jsonEncode(preferences);
    return _sendFindTabs(request);
  }

  Future<TrackResult> _sendFindTabs(http.MultipartRequest request) async {
    final streamed = await request.send().timeout(ApiConfig.requestTimeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw RecognitionException(_serverError(response));
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        throw RecognitionException(json['error'] as String? ?? 'No tabs found.');
      }
      return TrackResult.fromFindTabsJson(json);
    } catch (e) {
      if (e is RecognitionException) rethrow;
      throw RecognitionException('Failed to parse tab response: $e');
    }
  }
  // ── Song fingerprint recognition ─────────────────────────────────

  Future<TrackResult> recognizeSong(String audioFilePath) async {
    if (ApiConfig.useMockResponses) {
      await Future.delayed(const Duration(milliseconds: 800));
      return MockResponses.recognize();
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.recognizeEndpoint}');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audioFilePath,
        filename: 'recording.wav',
      ),
    );

    final streamed = await request.send().timeout(ApiConfig.requestTimeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw RecognitionException(
        'Server error ${response.statusCode}: ${response.body}',
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        throw RecognitionException(
          json['error'] as String? ??
              'The backend could not recognize the recording.',
        );
      }
      return TrackResult.fromChordRecognitionJson(json);
    } catch (e) {
      if (e is RecognitionException) rethrow;
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

    if (audioFilePath.isEmpty) {
      throw const RecognitionException(
        'No recording was created. Please try again.',
      );
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyzeEndpoint}');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        audioFilePath,
        filename: 'recording.wav',
      ),
    );

    final streamed = await request.send().timeout(ApiConfig.requestTimeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw RecognitionException(_serverError(response));
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        throw RecognitionException(
          json['error'] as String? ??
              'The backend could not analyze the recording.',
        );
      }
      return TrackResult.fromChordRecognitionJson(json);
    } catch (e) {
      if (e is RecognitionException) rethrow;
      throw RecognitionException('Failed to parse server response: $e');
    }
  }

  String _serverError(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['error'] as String? ??
          'Server error ${response.statusCode}. Please try again.';
    } catch (_) {
      return 'Server error ${response.statusCode}. Please try again.';
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
