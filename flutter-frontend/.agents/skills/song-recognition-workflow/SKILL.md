---
name: song-recognition-workflow
description: >-
  Use this skill when modifying, debugging, or verifying the end-to-end song recognition flow, including microphone recording, backend communication, and result presentation.
---

# Song Recognition Workflow Runbook

This runbook guides agents through the lifecycle of song recognition in Sonic Pulse.

## End-to-End Sequence

1. **User Interaction**:
   - In `FindSongScreen`, the user taps the pulse recognition button (`_buildScanButton`).
   - Calls `AppState.startScanAndRecognize()`.

2. **Microphone Permission & Capture**:
   - `AudioRecorderService.hasPermission()` checks microphone access.
   - `AudioRecorderService.startRecording()` initializes recording into a temporary `.m4a` file.
   - Recording runs for 5 seconds (or until `stopRecording()` is called).

3. **Backend Recognition / Mock**:
   - `RecognitionService.recognizeTrack(audioFilePath)` is called.
   - If `ApiConfig.useMockResponses` is `true`: returns realistic `TrackResult` after 2.5s simulation.
   - If `ApiConfig.useMockResponses` is `false`: sends `POST /api/recognize` multipart request to `ApiConfig.baseUrl`.

4. **State Transition & Persistence**:
   - `AppState` updates `currentTrack` with the resulting `TrackResult`.
   - Adds the track to `_history` (deduplicating by ID).
   - Calls `StorageService.saveHistory()` to write to `SharedPreferences`.
   - `AppState.scanState` changes from `listening` -> `analyzing` -> `result`.

5. **UI Display**:
   - `FindSongScreen` switches view to display track details, chords, BPM, Camelot wheel, and Save button.

## Verification & Testing Steps

To verify without a physical device:
1. Run `flutter test test/services/recognition_service_test.dart` to verify JSON parsing.
2. Verify `ApiConfig.useMockResponses == true` allows full UI flow execution without backend network dependencies.
