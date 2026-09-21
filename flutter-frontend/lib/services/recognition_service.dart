import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../models/track_result.dart';
import '../models/youtube_video.dart';

/// Sends audio files to the Python backend for recognition / analysis.
///
class RecognitionService {
  Future<YouTubeSearchResults> searchYouTube(
    String query, {
    bool shorts = false,
  }) async {
    final uri =
        Uri.parse(
          '${ApiConfig.baseUrl}${ApiConfig.youtubeSearchEndpoint}',
        ).replace(
          queryParameters: {
            'query': query,
            'type': shorts ? 'shorts' : 'videos',
          },
        );
    final response = await http.get(uri).timeout(ApiConfig.requestTimeout);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw RecognitionException(
        json['error']?.toString() ??
            'YouTube search failed (${response.statusCode}).',
      );
    }

    final results = (json['results'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => YouTubeVideo.fromJson(item.cast<String, dynamic>()))
        .where((video) => video.videoId.isNotEmpty)
        .toList();
    return YouTubeSearchResults(
      videos: shorts ? const [] : results,
      shorts: shorts ? results : const [],
    );
  }

  Future<TrackResult> analyzeYouTubeVideo(YouTubeVideo video) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.analyzeAudioEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'youtube_url': video.url}),
        )
        .timeout(ApiConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw RecognitionException(_serverError(response));
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        throw RecognitionException(
          json['error'] as String? ??
              'The backend could not analyze the video.',
        );
      }
      return TrackResult.fromAudioAnalysisJson(json).copyWith(
        title: json['title'] as String? ?? video.title,
        artist: json['artist'] as String? ?? video.channel,
        artworkUrl: json['artwork_url'] as String? ?? video.thumbnail,
        audioUrl: json['audio_url'] as String?,
      );
    } catch (e) {
      if (e is RecognitionException) rethrow;
      throw RecognitionException('Failed to parse YouTube analysis: $e');
    }
  }

  Future<TrackResult> findTabsFromStream(
    Stream<Uint8List> audioStream, {
    Map<String, List<String>> preferences = const {},
    Future<void>? cancelSignal,
  }) async {
    final httpUri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.streamFindTabsEndpoint}',
    );
    final uri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    );
    final channel = WebSocketChannel.connect(uri);
    StreamSubscription<Uint8List>? audioSubscription;

    try {
      await channel.ready;
      channel.sink.add(
        jsonEncode({'type': 'start', 'preferences': preferences}),
      );
      audioSubscription = audioStream.listen(channel.sink.add);

      Future<TrackResult> readMessages() async {
        await for (final message in channel.stream) {
          if (message is! String) continue;
          final payload = jsonDecode(message) as Map<String, dynamic>;
          if (payload['type'] == 'progress') continue;
          if (payload['type'] == 'error' || payload['success'] != true) {
            throw RecognitionException(
              payload['error'] as String? ?? 'Streaming recognition failed.',
            );
          }
          return TrackResult.fromFindTabsJson(payload);
        }
        throw RecognitionException('The recognition stream closed early.');
      }

      if (cancelSignal == null) return await readMessages();
      return await Future.any<TrackResult>([
        readMessages(),
        cancelSignal.then<TrackResult>(
          (_) => throw RecognitionException('Recognition cancelled.'),
        ),
      ]);
    } catch (error) {
      if (error is RecognitionException) rethrow;
      throw RecognitionException('Streaming recognition unavailable: $error');
    } finally {
      await audioSubscription?.cancel();
      await channel.sink.close();
    }
  }

  Future<TrackResult> findTabsBySong({
    required String title,
    required String artist,
    int? artistId,
    Map<String, List<String>> preferences = const {},
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.findTabsEndpoint}'),
    );
    request.fields['title'] = title;
    request.fields['artist'] = artist;
    if (artistId != null) request.fields['artist_id'] = artistId.toString();
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
        throw RecognitionException(
          json['error'] as String? ?? 'No tabs found.',
        );
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

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.analyzeAudioEndpoint}',
    );
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
      return TrackResult.fromAudioAnalysisJson(json);
    } catch (e) {
      if (e is RecognitionException) rethrow;
      throw RecognitionException('Failed to parse server response: $e');
    }
  }

  Future<String> refreshYouTubeAudioUrl(String youtubeUrl) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.youtubeAudioEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'youtube_url': youtubeUrl}),
        )
        .timeout(ApiConfig.requestTimeout);
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || json['success'] != true) {
        throw RecognitionException(
          json['error']?.toString() ?? 'Could not refresh YouTube audio.',
        );
      }
      final audioUrl = json['audio_url']?.toString() ?? '';
      if (audioUrl.isEmpty) {
        throw const RecognitionException('No playable YouTube audio found.');
      }
      return audioUrl;
    } catch (e) {
      if (e is RecognitionException) rethrow;
      throw RecognitionException('Could not refresh YouTube audio: $e');
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
