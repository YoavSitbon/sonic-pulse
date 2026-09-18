# Sonic Pulse — Architecture Rules & Guidelines

## 1. Architectural Layers

The Sonic Pulse codebase follows a clean layered separation of concerns:

```
UI Layer (Screens & Widgets)
       │
       ▼
State Management Layer (AppState via ChangeNotifier)
       │
   ┌───┴────────────────────────┐
   ▼                            ▼
Device Services (Audio)     API Services (Recognition)
   │                            │
   ▼                            ▼
Hardware / Native Plugin     Remote Backend (Python)
(Record, Permissions)       (or Fallback Mock Data)
```

## 2. Layer Responsibilities

### UI Layer (`lib/screens/`, `lib/widgets/`)
- Purely presentation and user interaction.
- Interacts with business logic exclusively by calling methods on `AppState` via `context.read<AppState>()`.
- Listens to state changes using `context.watch<AppState>()` or `Consumer<AppState>`.
- Must NOT instantiate services or call HTTP directly.

### State Management Layer (`lib/providers/app_state.dart`)
- Acts as the orchestrator between UI and services.
- Manages scan/recognition lifecycles (`isScanning`, `currentTrack`, `scanError`).
- Holds reactive lists: `history` and `savedTracks`.
- Notifies listeners cleanly (`notifyListeners()`) on lifecycle transitions.
- Dispatches save/load requests to `StorageService`.

### Services Layer (`lib/services/`)
- `AudioRecorderService`: Owns microphone hardware interactions via the `record` package and `permission_handler`. Handles temp file paths.
- `RecognitionService`: Owns HTTP communication with the Python backend (`multipart/form-data`). In mock mode, produces simulated responses with artificial latency to mimic real-world perception.
- `StorageService`: Owns persistence using `SharedPreferences`. Serializes and deserializes lists of `TrackResult` objects via JSON.

### Configuration Layer (`lib/config/api_config.dart`)
- Single source of truth for endpoints, mock mode toggle, timeouts, and headers.

### Models Layer (`lib/models/track_result.dart`)
- Immutable data classes with JSON serialization (`toJson()`, `fromJson()`) and convenience helpers (`keyShort`, `bpmString`, `confidencePercent`).
