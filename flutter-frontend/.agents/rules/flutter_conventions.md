# Sonic Pulse — Flutter Coding Conventions & Best Practices

## 1. UI Styling & Design System
- The app uses a dark, neo-glassmorphic aesthetic defined in `lib/theme/app_colors.dart` and `lib/theme/app_theme.dart`.
- Always reference `AppColors` constants instead of hardcoded hex values:
  - `AppColors.background`: Main scaffold background (`0xFF0D0F14`).
  - `AppColors.surface`: Cards and bottom sheets.
  - `AppColors.primary`: Electric teal/cyan accent (`0xFF00E5FF`).
  - `AppColors.secondary`: Violet glow accent (`0xFF7C4DFF`).
  - `AppColors.textPrimary` and `AppColors.textSecondary` for typography.
- For new opacity styling, prefer `.withValues(alpha: 0.8)` over `.withOpacity(0.8)`.

## 2. State & Provider Conventions
- Keep state mutations inside `AppState`.
- Never call `notifyListeners()` inside a `build()` method.
- When calling methods on `AppState` from buttons, callbacks, or `initState`, use:
  ```dart
  context.read<AppState>().startScanAndRecognize();
  ```
- When subscribing to values inside a `build` method, use:
  ```dart
  final appState = context.watch<AppState>();
  ```

## 3. Asynchronous Operations & Safety
- Always guard `BuildContext` across `await` boundaries with `if (!mounted) return;`.
- Use `try-catch` blocks inside services and return clean fallbacks or rethrow typed exceptions.

## 4. Dependencies & Pubspec Discipline
- **DO NOT REMOVE** the `dependency_overrides:` block for `record_linux: ^1.3.1` in `pubspec.yaml` unless upgrading to Dart SDK >= 3.12.0.
- When adding new native packages, always verify Android and iOS permissions requirements before publishing code changes.
