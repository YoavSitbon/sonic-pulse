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
  final String? artworkUrl;
  final String? audioUrl;
  final String? youtubeUrl;
  final String? tabSource;
  final String? tabSourceId;
  final String? tabUrl;
  final String? tabChordContent;
  final String? tabLyrics;
  final String? language;
  final List<ChordSegment> chordSegments;
  final List<double> beats;
  final List<double> downbeats;
  final List<String> chordsByBeat;
  final double duration;
  final String beatModel;
  final String chordModel;
  final Map<String, dynamic> analysisData;
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
    this.artworkUrl,
    this.audioUrl,
    this.youtubeUrl,
    this.tabSource,
    this.tabSourceId,
    this.tabUrl,
    this.tabChordContent,
    this.tabLyrics,
    this.language,
    this.chordSegments = const [],
    this.beats = const [],
    this.downbeats = const [],
    this.chordsByBeat = const [],
    this.duration = 0,
    this.beatModel = '—',
    this.chordModel = '—',
    this.analysisData = const {},
    this.isSaved = false,
  });

  // ── JSON ─────────────────────────────────────────────────────────

  factory TrackResult.fromJson(Map<String, dynamic> json) {
    return TrackResult(
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? '',
      key: json['key'] as String? ?? '—',
      bpm: (json['bpm'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      chords: List<String>.from(json['chords'] as List? ?? []),
      mood: List<String>.from(json['mood'] as List? ?? []),
      camelot: json['camelot'] as String? ?? '—',
      timeSig: json['time_sig'] as String? ?? '4/4',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      artworkUrl: json['artwork_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      youtubeUrl: json['youtube_url'] as String?,
      tabSource: json['tab_source'] as String?,
      tabSourceId: json['tab_source_id'] as String?,
      tabUrl: json['tab_url'] as String?,
      tabChordContent: json['tab_chord_content'] as String?,
      tabLyrics: json['tab_lyrics'] as String?,
      language: json['language'] as String?,
      chordSegments: (json['chord_segments'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ChordSegment(
              start: (item['start'] as num?)?.toDouble() ?? 0,
              end: (item['end'] as num?)?.toDouble() ?? 0,
              chord: item['chord']?.toString() ?? 'N',
              confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(),
      beats: _parseNumbers(json['beats']),
      downbeats: _parseNumbers(json['downbeats']),
      chordsByBeat: _parseChordNames(json['chords_by_beat']),
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      beatModel: json['beat_model'] as String? ?? '—',
      chordModel: json['chord_model'] as String? ?? '—',
      analysisData:
          (json['analysis_data'] as Map?)?.cast<String, dynamic>() ?? const {},
      isSaved: json['is_saved'] as bool? ?? false,
    );
  }

  /// Maps the response from POST /api/recognize-chords to the fields used by
  /// the current results UI. The backend returns timed chord segments rather
  /// than the catalogue metadata used by the rest of the app.
  factory TrackResult.fromChordRecognitionJson(Map<String, dynamic> json) {
    final rawChords = json['chords'] as List? ?? const [];
    final chordNames = <String>[];
    var confidenceTotal = 0.0;
    var confidenceCount = 0;

    for (final rawChord in rawChords) {
      if (rawChord is! Map) continue;
      final chord = rawChord['chord']?.toString();
      if (chord != null && chord.isNotEmpty) {
        final formattedChord = _formatChordName(chord);
        if (chordNames.isEmpty || chordNames.last != formattedChord) {
          chordNames.add(formattedChord);
        }
      }
      final confidence = rawChord['confidence'];
      if (confidence is num) {
        confidenceTotal += confidence.toDouble();
        confidenceCount++;
      }
    }

    return TrackResult(
      title: 'Recorded analysis',
      artist: 'SonicPulse AI',
      album: json['model_name'] as String? ?? 'Chord recognition',
      key: json['key'] as String? ?? '—',
      bpm: 0,
      confidence: confidenceCount == 0
          ? 0.0
          : confidenceTotal / confidenceCount,
      chords: chordNames,
      mood: const [],
      camelot: '—',
      timeSig: '—',
      timestamp: DateTime.now(),
      chordSegments: _parseChordSegments(rawChords),
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      chordModel: json['model_name'] as String? ?? '—',
      analysisData: Map<String, dynamic>.from(json),
    );
  }

  factory TrackResult.fromAudioAnalysisJson(Map<String, dynamic> json) {
    final chordPayload =
        (json['chord_recognition'] as Map?)?.cast<String, dynamic>() ?? json;
    final beatPayload =
        (json['beat_detection'] as Map?)?.cast<String, dynamic>() ?? json;
    final rawChords = (chordPayload['chords'] as List?) ?? const [];
    final segments = _parseChordSegments(rawChords);
    final chordNames = <String>[];
    for (final segment in segments) {
      if (chordNames.isEmpty || chordNames.last != segment.chord) {
        chordNames.add(segment.chord);
      }
    }
    final rawAnalysis = Map<String, dynamic>.from(json);
    return TrackResult(
      title: 'Recorded analysis',
      artist: 'SonicPulse AI',
      album: chordPayload['model_name'] as String? ?? 'Chord recognition',
      key:
          json['key'] as String? ??
          chordPayload['key'] as String? ??
          '—',
      bpm:
          (json['bpm'] as num?)?.round() ??
          (beatPayload['bpm'] as num?)?.round() ??
          0,
      confidence: _averageConfidence(segments),
      chords: chordNames,
      mood: const [],
      camelot: '—',
      timeSig:
          json['time_signature'] as String? ??
          beatPayload['time_signature'] as String? ??
          '—',
      timestamp: DateTime.now(),
      youtubeUrl: json['youtube_url'] as String?,
      chordSegments: segments,
      beats: _parseNumbers(json['beats'] ?? beatPayload['beats']),
      downbeats: _parseNumbers(json['downbeats'] ?? beatPayload['downbeats']),
      chordsByBeat: _parseChordNames(json['chords_by_beat']),
      duration:
          (json['duration'] as num?)?.toDouble() ??
          _maxDuration(beatPayload, chordPayload),
      beatModel:
          json['beat_model'] as String? ??
          beatPayload['model_name'] as String? ??
          beatPayload['model_used'] as String? ??
          '—',
      chordModel:
          json['chord_model'] as String? ??
          chordPayload['model_name'] as String? ??
          chordPayload['model_used'] as String? ??
          '—',
      analysisData: rawAnalysis,
    );
  }

  static double _maxDuration(
    Map<String, dynamic> beatPayload,
    Map<String, dynamic> chordPayload,
  ) {
    final beatDuration = (beatPayload['duration'] as num?)?.toDouble() ?? 0;
    final chordDuration = (chordPayload['duration'] as num?)?.toDouble() ?? 0;
    return beatDuration > chordDuration ? beatDuration : chordDuration;
  }

  static List<ChordSegment> _parseChordSegments(List? rawChords) {
    return (rawChords ?? const <dynamic>[]).whereType<Map>().map((raw) {
      final value = Map<String, dynamic>.from(raw);
      return ChordSegment(
        start: (value['start'] as num?)?.toDouble() ?? 0,
        end: (value['end'] as num?)?.toDouble() ?? 0,
        chord: _formatChordName(value['chord']?.toString() ?? 'N'),
        confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  static List<double> _parseNumbers(dynamic values) {
    if (values is! List) return const [];
    return values.whereType<num>().map((value) => value.toDouble()).toList();
  }

  static List<String> _parseStrings(dynamic values) {
    if (values is! List) return const [];
    return values.map((value) => value?.toString() ?? '').toList();
  }

  static List<String> _parseChordNames(dynamic values) {
    return _parseStrings(values).map((value) {
      if (value == 'N') return '';
      return _formatChordName(value);
    }).toList();
  }

  static double _averageConfidence(List<ChordSegment> segments) {
    if (segments.isEmpty) return 0;
    return segments.fold<double>(
          0,
          (sum, segment) => sum + segment.confidence,
        ) /
        segments.length;
  }

  factory TrackResult.fromFindTabsJson(Map<String, dynamic> json) {
    final tabs = (json['tabs'] as List? ?? const [])
        .whereType<Map>()
        .map((tab) => Map<String, dynamic>.from(tab))
        .toList();
    final selected = tabs.isEmpty ? <String, dynamic>{} : tabs.first;
    final rawChords = selected['chords'] as List? ?? const [];
    return TrackResult(
      title: json['title'] as String? ?? 'Unknown song',
      artist: json['artist'] as String? ?? 'Unknown artist',
      album: selected['source'] as String? ?? 'Guitar tabs',
      key: '—',
      bpm: 0,
      confidence: 1,
      chords: rawChords.map((chord) => chord.toString()).toList(),
      mood: const [],
      camelot: '—',
      timeSig: '—',
      timestamp: DateTime.now(),
      artworkUrl: json['artwork_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      tabSource: selected['source'] as String?,
      tabSourceId: selected['source_id'] as String?,
      tabUrl: selected['url'] as String?,
      tabChordContent: selected['chord_content'] as String?,
      tabLyrics: selected['lyrics'] as String?,
      language: json['language'] as String?,
    );
  }

  static String _formatChordName(String chord) {
    return chord
        .replaceAll(':maj', '')
        .replaceAll(':min', 'm')
        .replaceAll(':dim', 'dim')
        .replaceAll(':aug', 'aug');
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'key': key,
      'bpm': bpm,
      'confidence': confidence,
      'chords': chords,
      'mood': mood,
      'camelot': camelot,
      'time_sig': timeSig,
      'timestamp': timestamp.toIso8601String(),
      'artwork_url': artworkUrl,
      'audio_url': audioUrl,
      'youtube_url': youtubeUrl,
      'tab_source': tabSource,
      'tab_source_id': tabSourceId,
      'tab_url': tabUrl,
      'tab_chord_content': tabChordContent,
      'tab_lyrics': tabLyrics,
      'language': language,
      'is_saved': isSaved,
      'chord_segments': chordSegments
          .map((segment) => segment.toJson())
          .toList(),
      'beats': beats,
      'downbeats': downbeats,
      'chords_by_beat': chordsByBeat,
      'duration': duration,
      'beat_model': beatModel,
      'chord_model': chordModel,
      'analysis_data': analysisData,
    };
  }

  // ── SharedPreferences helpers ────────────────────────────────────

  String toJsonString() => jsonEncode(toJson());

  factory TrackResult.fromJsonString(String s) =>
      TrackResult.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ── Display helpers ──────────────────────────────────────────────

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get timeIdentified {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return 'Identified at $hour:$minute';
  }

  TrackResult copyWith({
    String? title,
    String? artist,
    bool? isSaved,
    String? artworkUrl,
    String? audioUrl,
    String? youtubeUrl,
    String? tabSource,
    String? tabSourceId,
    String? tabUrl,
    String? tabChordContent,
    String? tabLyrics,
    String? language,
  }) {
    return TrackResult(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album,
      key: key,
      bpm: bpm,
      confidence: confidence,
      chords: chords,
      mood: mood,
      camelot: camelot,
      timeSig: timeSig,
      timestamp: timestamp,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      tabSource: tabSource ?? this.tabSource,
      tabSourceId: tabSourceId ?? this.tabSourceId,
      tabUrl: tabUrl ?? this.tabUrl,
      tabChordContent: tabChordContent ?? this.tabChordContent,
      tabLyrics: tabLyrics ?? this.tabLyrics,
      language: language ?? this.language,
      chordSegments: chordSegments,
      beats: beats,
      downbeats: downbeats,
      chordsByBeat: chordsByBeat,
      duration: duration,
      beatModel: beatModel,
      chordModel: chordModel,
      analysisData: analysisData,
      isSaved: isSaved ?? this.isSaved,
    );
  }
}

class ChordSegment {
  const ChordSegment({
    required this.start,
    required this.end,
    required this.chord,
    required this.confidence,
  });

  final double start;
  final double end;
  final String chord;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'chord': chord,
    'confidence': confidence,
  };
}

// ── Mock data ────────────────────────────────────────────────────────────────

class MockResponses {
  static TrackResult recognize() => TrackResult(
    title: 'Midnight City',
    artist: 'M83',
    album: 'Hurry Up, We\'re Dreaming',
    key: 'B Minor',
    bpm: 105,
    confidence: 0.998,
    chords: ['Bm', 'G', 'D', 'A'],
    mood: ['Nostalgic', 'Atmospheric', 'Dreamy'],
    camelot: '10A',
    timeSig: '4/4',
    timestamp: DateTime.now(),
  );

  static TrackResult analyze() => TrackResult(
    title: 'After Dark',
    artist: 'Mr. Kitty',
    album: 'After Dark',
    key: 'D Minor',
    bpm: 140,
    confidence: 0.994,
    chords: ['Dm', 'Bb', 'F', 'C'],
    mood: ['Darkwave', 'Nostalgic', 'Atmospheric', 'Reverb-Heavy'],
    camelot: '7A',
    timeSig: '4/4',
    timestamp: DateTime.now(),
  );
}
