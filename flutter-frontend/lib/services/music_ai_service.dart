import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/ai_chat_message.dart';
import '../models/track_result.dart';

class MusicAiException implements Exception {
  final String message;

  const MusicAiException(this.message);

  @override
  String toString() => message;
}

class MusicAiService {
  Future<String> ask({
    required TrackResult song,
    required String question,
    required List<AiChatMessage> conversation,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.songAiEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'question': question,
            'song': {
              'title': song.title,
              'artist': song.artist,
              // Older tab responses did not include a separate chords list,
              // even though the page displayed the chord sheet. Recover a
              // compact sequence for the AI without sending the full sheet.
              'chords': song.chords.isNotEmpty
                  ? song.chords
                  : _extractChords(song.tabChordContent),
              'key': song.key,
              'bpm': song.bpm == 0 ? null : song.bpm,
              'tempo': _tempoFor(song.bpm),
              'time_signature': song.timeSig == '—' ? null : song.timeSig,
              'mood': song.mood,
            },
            'conversation': conversation
                .map((message) => message.toJson())
                .toList(),
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
      for (final token in tokens) {
        if (!result.contains(token)) result.add(token);
      }
    }
    return result.take(80).toList();
  }
}
