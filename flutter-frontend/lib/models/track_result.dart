import 'dart:convert';

/// Represents the result of a song recognition or AI analysis.
///
/// Backend JSON contract (POST /api/recognize-chords or /api/analyze):
/// ```json
/// {
///   "title":      "Midnight City",
///   "artist":     "M83",
///   "album":      "Hurry Up, We're Dreaming",
///   "key":        "B Minor",
///   "bpm":        105,
///   "confidence": 0.998,
///   "chords":     ["Bm", "G", "D", "A"],
///   "mood":       ["Nostalgic", "Atmospheric", "Dreamy"],
///   "camelot":    "10A",
///   "time_sig":   "4/4"
/// }
/// ```
class TrackResult {
  final String title;
  final String artist;
  final String album;
  final String key;
  final int bpm;
  final double confidence;
  final List<String> chords;
  final List<String> mood;
  final String camelot;
  final String timeSig;
  final DateTime timestamp;
  bool isSaved;

  TrackResult({
    required this.title,
    required this.artist,
    required this.album,
    required this.key,
    required this.bpm,
    required this.confidence,
    required this.chords,
    required this.mood,
    required this.camelot,
    required this.timeSig,
    required this.timestamp,
    this.isSaved = false,
  });

  // ── JSON ─────────────────────────────────────────────────────────

  factory TrackResult.fromJson(Map<String, dynamic> json) {
    return TrackResult(
      title:      json['title'] as String? ?? 'Unknown Title',
      artist:     json['artist'] as String? ?? 'Unknown Artist',
      album:      json['album'] as String? ?? '',
      key:        json['key'] as String? ?? '—',
      bpm:        (json['bpm'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      chords:     List<String>.from(json['chords'] as List? ?? []),
      mood:       List<String>.from(json['mood'] as List? ?? []),
      camelot:    json['camelot'] as String? ?? '—',
      timeSig:    json['time_sig'] as String? ?? '4/4',
      timestamp:  json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isSaved:    json['is_saved'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title':      title,
      'artist':     artist,
      'album':      album,
      'key':        key,
      'bpm':        bpm,
      'confidence': confidence,
      'chords':     chords,
      'mood':       mood,
      'camelot':    camelot,
      'time_sig':   timeSig,
      'timestamp':  timestamp.toIso8601String(),
      'is_saved':   isSaved,
    };
  }

  // ── SharedPreferences helpers ────────────────────────────────────

  String toJsonString() => jsonEncode(toJson());

  factory TrackResult.fromJsonString(String s) =>
      TrackResult.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ── Display helpers ──────────────────────────────────────────────

  String get confidencePercent =>
      '${(confidence * 100).toStringAsFixed(1)}%';

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  TrackResult copyWith({bool? isSaved}) {
    return TrackResult(
      title:      title,
      artist:     artist,
      album:      album,
      key:        key,
      bpm:        bpm,
      confidence: confidence,
      chords:     chords,
      mood:       mood,
      camelot:    camelot,
      timeSig:    timeSig,
      timestamp:  timestamp,
      isSaved:    isSaved ?? this.isSaved,
    );
  }
}

// ── Mock data ────────────────────────────────────────────────────────────────

class MockResponses {
  static TrackResult recognize() => TrackResult(
        title:      'Midnight City',
        artist:     'M83',
        album:      'Hurry Up, We\'re Dreaming',
        key:        'B Minor',
        bpm:        105,
        confidence: 0.998,
        chords:     ['Bm', 'G', 'D', 'A'],
        mood:       ['Nostalgic', 'Atmospheric', 'Dreamy'],
        camelot:    '10A',
        timeSig:    '4/4',
        timestamp:  DateTime.now(),
      );

  static TrackResult analyze() => TrackResult(
        title:      'After Dark',
        artist:     'Mr. Kitty',
        album:      'After Dark',
        key:        'D Minor',
        bpm:        140,
        confidence: 0.994,
        chords:     ['Dm', 'Bb', 'F', 'C'],
        mood:       ['Darkwave', 'Nostalgic', 'Atmospheric', 'Reverb-Heavy'],
        camelot:    '7A',
        timeSig:    '4/4',
        timestamp:  DateTime.now(),
      );
}
