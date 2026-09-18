# Sonic Pulse — Gemini & Antigravity Agent Guidelines

This workspace is a Flutter mobile application for AI-powered guitar and chord recognition ("Sonic Pulse").

## Quick Navigation & Context
- Full architecture, directory map, and API specifications are defined in [AGENTS.md](file:///home/yoavs/projects/guitar/frontend/sonic_pulse/AGENTS.md).
- Custom rules and skills are located in [.agents/](file:///home/yoavs/projects/guitar/frontend/sonic_pulse/.agents/).

## Golden Rules for AI Agents
1. **Dependency Integrity**: Keep `dependency_overrides: record_linux: ^1.3.1` in `pubspec.yaml` intact. Dart SDK is 3.11.x; removing or bumping it to 2.x triggers SDK incompatibility or missing `startStream` compiler errors.
2. **Backend Mode**: `lib/config/api_config.dart` contains `useMockResponses`. Set to `false` only when a live Python backend is running and reachable.
3. **State Management**: Always use `AppState` via `provider`. Do not duplicate track history or saved lists inside individual screen states.
4. **Verification**: After modifying Dart files, run `flutter analyze --no-fatal-infos` and `flutter test` to ensure zero compilation or logical regressions.
