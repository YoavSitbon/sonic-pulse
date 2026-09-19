import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_pulse/models/track_result.dart';

void main() {
  group('TrackResult Model Tests', () {
    final sampleJson = {
      'title': 'Midnight City',
      'artist': 'M83',
      'album': "Hurry Up, We're Dreaming",
      'key': 'B Minor',
      'bpm': 105,
      'confidence': 0.998,
      'chords': ['Bm', 'G', 'D', 'A'],
      'mood': ['Nostalgic', 'Atmospheric', 'Dreamy'],
      'camelot': '10A',
      'time_sig': '4/4',
      'timestamp': '2026-09-17T20:00:00.000Z',
      'is_saved': false,
    };

    test('fromJson creates valid instance with all fields', () {
      final track = TrackResult.fromJson(sampleJson);

      expect(track.title, 'Midnight City');
      expect(track.artist, 'M83');
      expect(track.album, "Hurry Up, We're Dreaming");
      expect(track.key, 'B Minor');
      expect(track.bpm, 105);
      expect(track.confidence, 0.998);
      expect(track.chords, ['Bm', 'G', 'D', 'A']);
      expect(track.mood, ['Nostalgic', 'Atmospheric', 'Dreamy']);
      expect(track.camelot, '10A');
      expect(track.timeSig, '4/4');
      expect(track.isSaved, false);
    });

    test('toJson and fromJson roundtrip preserves all values', () {
      final track = TrackResult.fromJson(sampleJson);
      final json = track.toJson();

      expect(json['title'], 'Midnight City');
      expect(json['bpm'], 105);
      expect(json['chords'], ['Bm', 'G', 'D', 'A']);

      final roundtrip = TrackResult.fromJson(json);
      expect(roundtrip.title, track.title);
      expect(roundtrip.artist, track.artist);
      expect(roundtrip.bpm, track.bpm);
      expect(roundtrip.key, track.key);
    });

    test('toJsonString and fromJsonString helpers work seamlessly', () {
      final track = TrackResult.fromJson(sampleJson);
      final serialized = track.toJsonString();
      final deserialized = TrackResult.fromJsonString(serialized);

      expect(deserialized.title, track.title);
      expect(deserialized.bpm, track.bpm);
      expect(deserialized.chords, track.chords);
    });

    test('confidencePercent formats properly', () {
      final track = TrackResult.fromJson(sampleJson);
      expect(track.confidencePercent, '99.8%');
    });

    test('copyWith updates isSaved cleanly', () {
      final track = TrackResult.fromJson(sampleJson);
      final savedTrack = track.copyWith(isSaved: true);

      expect(savedTrack.isSaved, true);
      expect(savedTrack.title, track.title);
      expect(track.isSaved, false); // Original remains unchanged
    });

    test('MockResponses generates valid mock data', () {
      final mock = MockResponses.recognize();
      expect(mock.title.isNotEmpty, true);
      expect(mock.bpm, greaterThan(0));
      expect(mock.chords.isNotEmpty, true);
    });

    test('maps chord recognition response segments to display chords', () {
      final result = TrackResult.fromChordRecognitionJson({
        'success': true,
        'model_name': 'Chord-CNN-LSTM',
        'chords': [
          {'start': 0.0, 'end': 1.0, 'chord': 'C:maj', 'confidence': 0.9},
          {'start': 1.0, 'end': 2.0, 'chord': 'C:maj', 'confidence': 0.8},
          {'start': 2.0, 'end': 3.0, 'chord': 'A:min', 'confidence': 1.0},
        ],
      });

      expect(result.chords, ['C', 'Am']);
      expect(result.confidence, closeTo(0.9, 0.001));
      expect(result.title, 'Recorded analysis');
    });
  });
}
