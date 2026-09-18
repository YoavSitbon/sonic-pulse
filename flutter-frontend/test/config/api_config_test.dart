import 'package:flutter_test/flutter_test.dart';
import 'package:sonic_pulse/config/api_config.dart';

void main() {
  group('ApiConfig Tests', () {
    test('endpoints are defined with expected paths', () {
      expect(ApiConfig.recognizeEndpoint, '/api/recognize-chords');
      expect(ApiConfig.analyzeEndpoint, '/api/analyze');
    });

    test('mock response mode is configured as boolean', () {
      expect(ApiConfig.useMockResponses, isA<bool>());
    });

    test('timeout duration is reasonable for audio processing', () {
      expect(ApiConfig.requestTimeout.inSeconds, greaterThanOrEqualTo(10));
    });

    test('recording seconds is within expected bounds', () {
      expect(ApiConfig.recordingSeconds, inInclusiveRange(3, 15));
    });
  });
}
