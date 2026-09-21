import 'dart:io';
import 'package:flutter/material.dart';
import '../models/track_result.dart';
import '../services/storage_service.dart';

/// Global app state: identified tracks, saved tracks, scan count.
///
/// Screens use [context.watch<AppState>()] or [context.read<AppState>()]
/// to subscribe or trigger mutations.
class AppState extends ChangeNotifier {
  AppState() {
    _init();
  }

  final StorageService _storage = StorageService();

  List<TrackResult> _identifiedTracks = [];
  List<TrackResult> _savedTracks = [];
  int _scanCount = 0;
  bool _isLoaded = false;

  // ── Getters ──────────────────────────────────────────────────────

  List<TrackResult> get identifiedTracks =>
      List.unmodifiable(_identifiedTracks);

  List<TrackResult> get savedTracks => List.unmodifiable(_savedTracks);

  int get scanCount => _scanCount;

  bool get isLoaded => _isLoaded;

  // ── Init ─────────────────────────────────────────────────────────

  Future<void> _init() async {
    _identifiedTracks = await _storage.loadIdentifiedTracks();
    _savedTracks = await _storage.loadSavedTracks();
    for (final track in _identifiedTracks) {
      track.isSaved = _savedTracks.any(
        (saved) => saved.title == track.title && saved.artist == track.artist,
      );
    }
    _scanCount = await _storage.loadScanCount();
    _isLoaded = true;
    notifyListeners();
  }

  // ── Mutations ────────────────────────────────────────────────────

  /// Called after a successful recognition. Persists and notifies.
  Future<void> addIdentification(TrackResult track) async {
    _identifiedTracks.insert(0, track);
    if (_identifiedTracks.length > 50) {
      _identifiedTracks = _identifiedTracks.sublist(0, 50);
    }
    _scanCount++;
    await _storage.addIdentifiedTrack(track);
    await _storage.incrementScanCount();
    notifyListeners();
  }

  /// Toggles the saved/bookmark state for a track.
  Future<void> toggleSave(TrackResult track) async {
    final isCurrentlySaved = _savedTracks.any(
      (t) => t.title == track.title && t.artist == track.artist,
    );

    if (isCurrentlySaved) {
      _savedTracks.removeWhere(
        (t) => t.title == track.title && t.artist == track.artist,
      );
      await _storage.removeSavedTrack(track);

      // also update identified list flag
      for (final t in _identifiedTracks) {
        if (t.title == track.title && t.artist == track.artist) {
          t.isSaved = false;
        }
      }
    } else {
      final saved = track.copyWith(isSaved: true);
      _savedTracks.insert(0, saved);
      await _storage.saveTrack(saved);

      // also update identified list flag
      for (final t in _identifiedTracks) {
        if (t.title == track.title && t.artist == track.artist) {
          t.isSaved = true;
        }
      }
    }
    await _storage.replaceIdentifiedTracks(_identifiedTracks);
    notifyListeners();
  }

  Future<void> removeIdentification(TrackResult track) async {
    _identifiedTracks.removeWhere(
      (item) => item.title == track.title && item.artist == track.artist,
    );
    await _storage.removeIdentifiedTrack(track);
    await _deleteUnreferencedRecording(track);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final history = List<TrackResult>.from(_identifiedTracks);
    _identifiedTracks.clear();
    await _storage.replaceIdentifiedTracks(const []);
    for (final track in history) {
      await _deleteUnreferencedRecording(track);
    }
    notifyListeners();
  }

  Future<void> _deleteUnreferencedRecording(TrackResult track) async {
    final path = track.localAudioPath;
    if (path == null || path.isEmpty) return;
    final isSaved = _savedTracks.any(
      (saved) => saved.title == track.title && saved.artist == track.artist,
    );
    final isStillInHistory = _identifiedTracks.any(
      (item) => item.localAudioPath == path,
    );
    if (!isSaved && !isStillInHistory) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  bool isSaved(TrackResult track) => _savedTracks.any(
    (t) => t.title == track.title && t.artist == track.artist,
  );
}
