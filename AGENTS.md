# Sonic Pulse — AI Agent Context & Developer Guide

This document is optimized for AI agents (Antigravity, Cursor, Claude Code, Copilot, Aider) and developers. It provides essential context, architectural boundaries, API contracts, and command cheat sheets to minimize exploratory token waste.

---

## 1. Project Overview

- **App Name**: Sonic Pulse
- **Platform**: Flutter (Android primary target, iOS, Web, Desktop)
- **Dart SDK**: `^3.11.0` (Dart 3.11.x)
- **Purpose**: Real-time audio capture and AI music recognition (identifies track title, artist, key, BPM, chords, mood, Camelot wheel notation, time signature) and personal library curation.
- **Backend**: Python FastAPI/Flask server exposing an audio analysis model. Supports mock fallback mode when backend is offline.

---

## 2. Directory & Architecture Map

```
lib/
├── config/
│   └── api_config.dart          # Backend IP/port, endpoints, mock mode toggle (useMockResponses)
├── models/
│   └── track_result.dart        # TrackResult model, JSON serialization, copyWith, helper formatters
├── providers/
│   └── app_state.dart           # Central state: history, saved tracks, scan/recording state, persistence
├── screens/
│   ├── find_song_screen.dart    # Primary pulse scan screen (mic recording + recognition trigger)
│   ├── ai_analyzer_screen.dart  # Detailed AI track analysis view (chords, BPM, key, Camelot wheel)
│   ├── home_screen.dart         # Feed, recent discoveries, quick recognition cards
│   └── library_screen.dart      # Saved & recognized songs, playback list, search & filter
├── services/
│   ├── audio_recorder_service.dart # Microphone recording via `record` package, permission handling
│   ├── recognition_service.dart    # HTTP client sending audio to Python backend (or mock fallback)
│   └── storage_service.dart        # SharedPreferences persistence for history and saved tracks
├── theme/
│   ├── app_colors.dart          # Dark neo-glassmorphism color palette (primary, surfaces, accents)
│   └── app_theme.dart           # ThemeData, Typography, Dark mode styling
└── widgets/
    ├── bottom_nav_bar.dart      # Custom bottom navigation with glowing pulse selector
    └── wave_bars.dart           # Dynamic animated audio frequency visualizer
```

---

## 3. State Management (`AppState`)

- **Pattern**: `ChangeNotifier` provided via `MultiProvider` in `lib/main.dart`.
- **Consumer usage**: `context.watch<AppState>()` for reactive UI, `context.read<AppState>()` for actions.
- **Key Methods**:
  - `startScanAndRecognize()`: Handles mic permission -> records audio (5s) -> calls `RecognitionService` -> updates `currentTrack` -> saves to history & SharedPreferences.
  - `toggleSaveTrack(TrackResult)`: Toggles favorite/saved status and persists immediately.
  - `clearHistory()`: Purges history from memory and storage.
- **Persistence**: Managed through `StorageService` using `shared_preferences` (`sonic_pulse_history`, `sonic_pulse_saved`).

---

## 4. Audio Pipeline & Backend API Contract

### Audio Recording
- Handled by `AudioRecorderService` using `package:record`.
- Android permission required: `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`.
- Saves audio to a temporary AAC/M4A/WAV file in `getTemporaryDirectory()`.

### Backend Configuration (`lib/config/api_config.dart`)
- **`baseUrl`**: Default `http://3.3.3.3:5001`. For local USB adb testing, use `http://10.0.2.2:5001` (emulator) or your LAN IP `http://192.168.x.x:5001` (physical device), or `adb reverse tcp:5001 tcp:5001` with `http://127.0.0.1:5001`.
- **`useMockResponses`**: Set to `true` (default while backend is in development) to return instant realistic guitar/track data without network calls.

### API Contract (POST `/api/recognize`)
- **Request**: Multipart POST request with form field `file` containing the recorded audio binary (`audio/m4a` or `audio/wav`).
- **Response JSON Schema**:
  ```json
  {
    "id": "uuid-or-unique-string",
    "title": "Neon Horizons",
    "artist": "Aura Pulse",
    "album": "Synthwave Reverie",
    "cover_url": "https://...",
    "key": "B Minor",
    "bpm": 105,
    "confidence": 0.985,
    "chords": ["Bm", "G", "D", "A"],
    "mood": ["Atmospheric", "Nostalgic"],
    "camelot": "10A",
    "time_sig": "4/4"
  }
  ```

---

## 5. Critical Constraints & Gotchas

1. **`record_linux` Dependency Override**:
   - Dart SDK in this environment is `3.11.5`.
   - `record: ^5.1.2` depends on platform interfaces where `record_linux: 0.7.2` fails compilation due to missing `startStream`.
   - `record_linux >= 2.0.0` requires Dart `>= 3.12.0`.
   - **Fix**: `pubspec.yaml` contains `dependency_overrides: record_linux: ^1.3.1`. **Do not remove this override** without upgrading the Dart SDK.
2. **Android Cleartext HTTP**:
   - If connecting to an `http://` LAN IP (e.g. `http://192.168.1.50:5001`), ensure `android:usesCleartextTraffic="true"` is maintained in `android/app/src/main/AndroidManifest.xml`.
3. **Flutter Analyzer Notes**:
   - Deprecation `withOpacity` is from the original UI design template. Use `.withValues(alpha: ...)` for new code, but existing `withOpacity` calls are safe `info`-level warnings and not compilation errors.

---

## 6. Development & Verification Commands

| Action | Command |
|---|---|
| Install dependencies | `flutter pub get` |
| Check code quality | `flutter analyze --no-fatal-infos` |
| Run all tests | `flutter test` |
| Run on connected device | `flutter run` |
| Clean build cache | `flutter clean && flutter pub get` |
| Check connected devices | `flutter devices` |
| ADB reverse for localhost backend | `adb reverse tcp:5001 tcp:5001` |
