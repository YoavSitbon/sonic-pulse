import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/ai_chat_message.dart';
import '../models/track_result.dart';
import 'storage_service.dart';

class MusicAiException implements Exception {
  final String message;

  const MusicAiException(this.message);

  @override
  String toString() => message;
}

class MusicAiService {
  static const supportedModels = [
    'gemini-3.5-flash-lite',
    'gemini-3.6-flash',
    'gemini-3.1-pro',
  ];
  static const defaultModel = 'gemini-3.6-flash';

  final StorageService _storage = StorageService();

  Future<String> ask({
    required TrackResult song,
    required String question,
    required List<AiChatMessage> conversation,
    String? model,
  }) async {
    final selectedModel =
        model ?? await _storage.loadMusicAiModel() ?? defaultModel;
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.songAiEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'question': question,
            'song': {
              'title': song.title,
              'artist': song.artist,
              'chords': _chordsInOrder(song),
            },
            'model': selectedModel,
          }),
        )
        .timeout(ApiConfig.requestTimeout);

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw MusicAiException('The AI service returned an invalid response.');
    }
    if (response.statusCode != 200 || body['success'] != true) {
      throw MusicAiException(
        body['error'] as String? ??
            'The AI service could not answer right now.',
      );
    }
    final answer = body['answer'] as String?;
    if (answer == null || answer.trim().isEmpty) {
      throw const MusicAiException('The AI returned an empty answer.');
    }
    return answer;
  }

  List<String> _chordsInOrder(TrackResult song) {
    if (song.chordsByBeat.isNotEmpty) return song.chordsByBeat;
    if (song.chordSegments.isNotEmpty) {
      return song.chordSegments.map((segment) => segment.chord).toList();
    }
    return song.chords.isNotEmpty
        ? song.chords
        : _extractChords(song.tabChordContent);
  }

  String? _tempoFor(int bpm) {
    if (bpm <= 0) return null;
    if (bpm < 60) return 'Largo';
    if (bpm < 76) return 'Adagio';
    if (bpm < 108) return 'Andante';
    if (bpm < 120) return 'Moderato';
    if (bpm < 168) return 'Allegro';
    if (bpm < 200) return 'Presto';
    return 'Prestissimo';
  }

  List<String> _extractChords(String? content) {
    if (content == null || content.trim().isEmpty) return const [];
    final chord = RegExp(
      r'^(?:N\.?C\.?|[A-G](?:#|b)?(?:maj|min|m|dim|aug|sus|add)?[0-9]*(?:/[A-G](?:#|b)?)?)$',
      caseSensitive: false,
    );
    final result = <String>[];
    for (final line in content.split('\n')) {
      final tokens = line.trim().split(RegExp(r'\s+'));
      if (tokens.isEmpty || tokens.any((token) => !chord.hasMatch(token))) {
        continue;
      }
      result.addAll(tokens);
    }
    return result.take(80).toList();
  }
}
