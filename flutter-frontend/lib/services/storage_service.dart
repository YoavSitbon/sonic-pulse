import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_result.dart';

/// Handles all on-device persistence via SharedPreferences.
class StorageService {
  static const String _identifiedKey = 'identified_tracks';
  static const String _savedKey      = 'saved_tracks';
  static const String _scanCountKey  = 'scan_count';
  static const int    _maxHistory    = 50;
  static const String _tabPreferencesKey = 'tab_source_preferences';

  Future<Map<String, List<String>>> loadTabPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_tabPreferencesKey) ?? [];
    final result = <String, List<String>>{'en': [], 'he': []};
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length == 2 && result.containsKey(parts[0])) {
        result[parts[0]]!.add(parts[1]);
      }
    }
    return result;
  }

  Future<void> saveTabPreferences(Map<String, List<String>> preferences) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = <String>[];
    preferences.forEach((language, sources) {
      for (final source in sources) {
        raw.add('$language|$source');
      }
    });
    await prefs.setStringList(_tabPreferencesKey, raw);
  }

  // ── Identified tracks (recent scan history) ──────────────────────

  Future<List<TrackResult>> loadIdentifiedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_identifiedKey) ?? [];
    return raw.map((s) {
      try {
        return TrackResult.fromJsonString(s);
      } catch (_) {
        return null;
      }
    }).whereType<TrackResult>().toList();
  }

  Future<void> addIdentifiedTrack(TrackResult track) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_identifiedKey) ?? [];
    raw.insert(0, track.toJsonString());
    // cap to max history
    final capped = raw.take(_maxHistory).toList();
    await prefs.setStringList(_identifiedKey, capped);
  }

  // ── Saved (bookmarked) tracks ────────────────────────────────────

  Future<List<TrackResult>> loadSavedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_savedKey) ?? [];
    return raw.map((s) {
      try {
        return TrackResult.fromJsonString(s);
      } catch (_) {
        return null;
      }
    }).whereType<TrackResult>().toList();
  }

  Future<void> saveTrack(TrackResult track) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_savedKey) ?? [];
    // deduplicate by title+artist
    final deduped = raw
        .where((s) {
          try {
            final t = TrackResult.fromJsonString(s);
            return !(t.title == track.title && t.artist == track.artist);
          } catch (_) {
            return true;
          }
        })
        .toList();
    deduped.insert(0, track.copyWith(isSaved: true).toJsonString());
    await prefs.setStringList(_savedKey, deduped);
  }

  Future<void> removeSavedTrack(TrackResult track) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_savedKey) ?? [];
    final filtered = raw.where((s) {
      try {
        final t = TrackResult.fromJsonString(s);
        return !(t.title == track.title && t.artist == track.artist);
      } catch (_) {
        return true;
      }
    }).toList();
    await prefs.setStringList(_savedKey, filtered);
  }

  // ── Scan count ───────────────────────────────────────────────────

  Future<int> loadScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_scanCountKey) ?? 0;
  }

  Future<void> incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_scanCountKey) ?? 0;
    await prefs.setInt(_scanCountKey, current + 1);
  }

  /// Clear all data (for testing / reset).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_identifiedKey);
    await prefs.remove(_savedKey);
    await prefs.remove(_scanCountKey);
    await prefs.remove(_tabPreferencesKey);
  }
}
