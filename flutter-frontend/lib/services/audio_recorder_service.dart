import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps the `record` package to record mic audio to a temp WAV file.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  // ── Permission ───────────────────────────────────────────────────

  /// Returns true if mic permission is granted (or just granted).
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    return Permission.microphone.isGranted;
  }

  // ── Recording ────────────────────────────────────────────────────

  /// Starts recording to a temporary WAV file.
  /// Returns false if permission is denied.
  Future<bool> startRecording() async {
    if (!await requestPermission()) return false;

    final dir = await getTemporaryDirectory();
    _currentPath =
        '${dir.path}/sonic_pulse_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: _currentPath!,
    );
    return true;
  }

  /// Stops recording and returns the path to the WAV file.
  /// Returns null if no recording was in progress.
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _currentPath = null;
    return path;
  }

  Future<bool> get isRecording => _recorder.isRecording();

  /// Cancels the current recording and deletes the temp file.
  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) {
      final path = await _recorder.stop();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
    _currentPath = null;
  }

  void dispose() {
    _recorder.dispose();
  }
}
