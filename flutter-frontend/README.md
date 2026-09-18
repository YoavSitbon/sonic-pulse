# Sonic Pulse 🎵⚡

**Sonic Pulse** is a Flutter-based music and guitar chord recognition mobile app. It captures audio from the device microphone, performs chord progression and track identification via an AI model backend, and visualizes musical metrics (musical key, BPM, Camelot wheel notation, chord progressions, mood).

---

## 🚀 Features

- **Real-Time Pulse Scanner**: One-tap microphone recording with animated soundwave visualizer.
- **AI Track & Chord Recognition**: Identifies song title, artist, key, tempo (BPM), Camelot harmonic mixing key, chords, and mood.
- **Offline Mock Fallback**: Seamless offline development and UI styling mode (`ApiConfig.useMockResponses = true`).
- **Personal Library & History**: Automatically stores scan history and favorites locally via `SharedPreferences`.
- **Neo-Glassmorphic Dark UI**: High-contrast, glowing neon accents with responsive layouts.

---

## 🤖 AI Agents & Developer Context

This repository is optimized for AI coding assistants (Antigravity, Cursor, Claude Code, Copilot, Aider). Key documentation files:

- **[AGENTS.md](AGENTS.md)**: Universal agent guide, directory map, state management, commands, and gotchas.
- **[GEMINI.md](GEMINI.md)**: Antigravity/Gemini agent workspace configuration.
- **[.agents/rules/](.agents/rules/)**: Architectural boundaries, backend contracts, and Flutter conventions.
- **[.agents/skills/](.agents/skills/)**: Modular on-demand runbooks for song recognition, backend setup, and troubleshooting.
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: High-level architectural and sequence diagrams (Mermaid).

---

## 🛠️ Quickstart

### Prerequisites
- Flutter SDK 3.19+ (Dart SDK `^3.11.0`)
- Android Studio / VS Code / Antigravity IDE
- Connected Android/iOS device or emulator

### 1. Install Dependencies
```bash
flutter pub get
```

> **Note**: `pubspec.yaml` includes a dependency override for `record_linux: ^1.3.1` to ensure compatibility with Dart 3.11.x. Do not remove this override.

### 2. Run the App
```bash
flutter run
```

### 3. Run Automated Tests
```bash
flutter test
```

### 4. Code Analysis
```bash
flutter analyze --no-fatal-infos
```

---

## 🔌 Connecting to a Live Backend

By default, the app runs in **mock response mode** with simulated realistic guitar tracks.

To connect to a live Python backend:
1. Open [`lib/config/api_config.dart`](lib/config/api_config.dart).
2. Set `useMockResponses = false`.
3. Update `baseUrl` to your machine's LAN IP (or use `adb reverse tcp:5001 tcp:5001` with `http://127.0.0.1:5001`).

See [.agents/skills/backend-connection-setup/SKILL.md](.agents/skills/backend-connection-setup/SKILL.md) for full instructions and sample FastAPI code.
