import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/song_search_result.dart';

/// Public, credential-free music catalogue search.
///
/// Spotify and YouTube require an application token/API key; iTunes Search is
/// a public HTTPS endpoint, so it can be queried safely from the mobile app.
class MusicSearchService {
  Future<List<SongSearchResult>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return [];

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'limit': '30',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Music search failed (${response.statusCode})');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SongSearchResult.fromItunesJson)
        .toList();
  }
}
