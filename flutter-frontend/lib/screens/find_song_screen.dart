import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/song_play_bar.dart';
import '../models/track_result.dart';
import '../models/ai_chat_message.dart';
import '../services/audio_recorder_service.dart';
import '../services/recognition_service.dart';
import '../services/music_search_service.dart';
import '../models/song_search_result.dart';
import '../providers/app_state.dart';
import 'home_screen.dart';
import 'ai_analyzer_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'key_details_screen.dart';
import '../services/storage_service.dart';
import '../services/music_ai_service.dart';

// ─────────────────────────────────────────────────────────────
// Screen states
// ─────────────────────────────────────────────────────────────
enum _ScanState { idle, search, recording, analyzing, result, error }

class FindSongScreen extends StatefulWidget {
  final TrackResult? initialResult;

  const FindSongScreen({super.key, this.initialResult});

  @override
  State<FindSongScreen> createState() => _FindSongScreenState();
}

class _FindSongScreenState extends State<FindSongScreen>
    with TickerProviderStateMixin {
  _ScanState _scanState = _ScanState.idle;
  TrackResult? _result;
  String? _errorMessage;
  bool _isPlaying = false;
  StreamSubscription? _amplitudeSubscription;
  double _amplitudeLevel = 0.05;
  int _recordingGeneration = 0;
  Timer? _searchDebounce;
  final _searchController = TextEditingController();
  List<SongSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _autoListening = false;
  bool _autoButtonPressed = false;
  TrackResult? _pendingAutoResult;
  List<AiChatMessage> _aiConversation = [];
  Completer<void>? _recognitionCancel;
  Map<String, List<String>> _tabPreferences = {
    'en': ['ultimate_guitar'],
    'he': ['tab4u'],
  };

  final _recorder = AudioRecorderService();
  final _recognizer = RecognitionService();
  final _musicSearch = MusicSearchService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Outer pulse ring
  late AnimationController _outerPulse;
  late Animation<double> _outerScale;
  late Animation<double> _outerOpacity;

  // Inner pulse ring
  late AnimationController _innerPulse;
  late Animation<double> _innerScale;
  late Animation<double> _innerOpacity;

  // Mic bounce bars
  late List<AnimationController> _barCtrls;
  late List<Animation<double>> _barAnims;

  @override
  void initState() {
    super.initState();
    if (widget.initialResult != null) {
      _result = widget.initialResult;
      _scanState = _ScanState.result;
      unawaited(_preparePlayback(widget.initialResult!));
      unawaited(_loadAiConversation(widget.initialResult!));
    }
    final storage = StorageService();
    storage.loadTabPreferences().then((preferences) {
      if (mounted && preferences.values.any((sources) => sources.isNotEmpty)) {
        setState(() => _tabPreferences = preferences);
      }
    });
    storage.loadAutoShazam().then((enabled) {
      if (!mounted || widget.initialResult != null) return;
      if (enabled && _scanState == _ScanState.idle) {
        unawaited(_startAutoListening());
      }
    });

    _outerPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _outerScale = Tween<double>(
      begin: 0.85,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _outerPulse, curve: Curves.easeInOut));
    _outerOpacity = Tween<double>(
      begin: 0.4,
      end: 0.08,
    ).animate(CurvedAnimation(parent: _outerPulse, curve: Curves.easeInOut));

    _innerPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _innerScale = Tween<double>(
      begin: 0.92,
      end: 1.16,
    ).animate(CurvedAnimation(parent: _innerPulse, curve: Curves.easeInOut));
    _innerOpacity = Tween<double>(
      begin: 0.8,
      end: 0.25,
    ).animate(CurvedAnimation(parent: _innerPulse, curve: Curves.easeInOut));

    final barDurations = [300, 250, 400, 350];
    final barDelays = [0, 150, 75, 300];
    _barCtrls = List.generate(4, (i) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: barDurations[i]),
      );
      Future.delayed(
        Duration(milliseconds: barDelays[i]),
        () => mounted ? c.repeat(reverse: true) : null,
      );
      return c;
    });
    _barAnims = _barCtrls.map((c) {
      return Tween<double>(
        begin: 0.3,
        end: 1.0,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    _outerPulse.dispose();
    _innerPulse.dispose();
    for (final c in _barCtrls) c.dispose();
    _amplitudeSubscription?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _recognitionCancel?.complete();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        if (_audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.seek(Duration.zero);
        }
        if (_audioPlayer.audioSource == null && _result != null) {
          await _preparePlayback(_result!);
        }
        if (_audioPlayer.audioSource == null) return;
        await _audioPlayer.play();
        if (mounted) setState(() => _isPlaying = true);
      }
    } catch (e) {
      _showError('Could not play the song preview.');
    }
  }

  Future<void> _preparePlayback(TrackResult result) async {
    try {
      final localPath = result.localAudioPath;
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
          await _audioPlayer.setFilePath(localPath);
          return;
        }
      }

      var audioUrl = result.audioUrl;
      final youtubeUrl =
          result.youtubeUrl ?? result.analysisData['youtube_url']?.toString();
      if ((audioUrl == null || audioUrl.isEmpty) &&
          youtubeUrl != null &&
          youtubeUrl.isNotEmpty) {
        audioUrl = await _recognizer.refreshYouTubeAudioUrl(youtubeUrl);
      }
      if (audioUrl != null && audioUrl.isNotEmpty && mounted) {
        await _audioPlayer.setUrl(audioUrl);
        return;
      }
    } catch (_) {
      // Preview lookup below can still recover from an expired source URL.
    }

    try {
      final matches = await _musicSearch.search(
        '${result.title} ${result.artist}',
      );
      final preview = matches
          .map((match) => match.previewUrl)
          .whereType<String>()
          .firstWhere((url) => url.isNotEmpty, orElse: () => '');
      if (preview.isNotEmpty && mounted) {
        await _audioPlayer.setUrl(preview);
      }
    } catch (_) {
      // Playback remains disabled when no preview is available.
    }
  }

  // ── Flow ─────────────────────────────────────────────────────────

  Future<void> _startScan() async {
    if (_pendingAutoResult != null) {
      final result = _pendingAutoResult!;
      _pendingAutoResult = null;
      await _showResult(result);
      return;
    }

    // Auto Shazam may already be listening in the background. Show the
    // listening animation, but never create a second socket session.
    if (_autoListening) {
      _autoButtonPressed = true;
      if (_scanState == _ScanState.idle && mounted) {
        setState(() => _scanState = _ScanState.recording);
      }
      return;
    }

    if (_scanState == _ScanState.recording ||
        _scanState == _ScanState.analyzing) {
      return;
    }

    await _beginRecognition(background: false);
  }

  Future<void> _startAutoListening() async {
    if (_autoListening || _pendingAutoResult != null || !mounted) return;
    await _beginRecognition(background: true);
  }

  Future<void> _beginRecognition({required bool background}) async {
    final generation = ++_recordingGeneration;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _amplitudeLevel = 0.05;
    _outerPulse
      ..reset()
      ..repeat();
    _innerPulse
      ..reset()
      ..repeat();
    _autoListening = true;
    _autoButtonPressed = !background;
    _recognitionCancel = Completer<void>();

    if (!background && mounted) {
      setState(() {
        _scanState = _ScanState.recording;
        _errorMessage = null;
      });
    }

    _amplitudeSubscription = _recorder.amplitudeStream.listen((amplitude) {
      if (!mounted || generation != _recordingGeneration || !_autoListening) {
        return;
      }
      final db = amplitude.current;
      final level = db.isFinite && db > -55
          ? ((db + 55) / 35).clamp(0.0, 1.0).toDouble()
          : 0.0;
      setState(() => _amplitudeLevel = level);
    });

    try {
      final audioStream = await _recorder.startStream();
      if (!mounted || generation != _recordingGeneration || !_autoListening) {
        await _recorder.cancelRecording();
        return;
      }
      final result = await _recognizer.findTabsFromStream(
        audioStream,
        preferences: _tabPreferences,
        cancelSignal: _recognitionCancel!.future,
      );
      final wasRequested = _autoButtonPressed;
      await _stopRecognitionSession();

      if (background &&
          !wasRequested &&
          mounted &&
          _scanState == _ScanState.idle) {
        _pendingAutoResult = result;
        return;
      }
      await _showResult(result);
    } catch (error) {
      await _stopRecognitionSession();
      if (!mounted) return;
      if (_scanState == _ScanState.idle) return;
      // Auto listening stays visually quiet until the user asks to see it;
      // a manual WebSocket failure is shown normally.
      if (!background || _autoButtonPressed) {
        _showError(
          'Streaming recognition failed: ${error.toString().replaceAll('RecognitionException: ', '')}',
        );
      }
    }
  }

  void _openSearch() {
    unawaited(_stopRecognitionSession());
    setState(() {
      _scanState = _ScanState.search;
      _searchError = null;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() {
        _isSearching = true;
        _searchError = null;
      });
      try {
        final results = await _musicSearch.search(value);
        if (!mounted || value != _searchController.text) return;
        setState(() => _searchResults = results);
      } catch (_) {
        if (!mounted || value != _searchController.text) return;
        setState(() => _searchError = 'Could not search the music catalogue.');
      } finally {
        if (mounted && value == _searchController.text) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  Future<void> _selectSong(SongSearchResult song) async {
    setState(() {
      _scanState = _ScanState.analyzing;
      _errorMessage = null;
    });
    try {
      final result = await _recognizer.findTabsBySong(
        title: song.title,
        artist: song.artist,
        artistId: song.artistId,
        preferences: _tabPreferences,
      );
      if (!mounted) return;
      final resultWithArtwork = result.copyWith(artworkUrl: song.artworkUrl);
      await context.read<AppState>().addIdentification(resultWithArtwork);
      if (!mounted) return;
      setState(() {
        _result = resultWithArtwork;
        _aiConversation = [];
        _scanState = _ScanState.result;
      });
      unawaited(_loadAiConversation(resultWithArtwork));
      unawaited(_preparePlayback(resultWithArtwork));
    } catch (e) {
      _showError(
        'Song analysis failed: ${e.toString().replaceAll('RecognitionException: ', '')}',
      );
    }
  }

  Future<void> _stopRecognitionSession() async {
    _recordingGeneration++;
    _autoListening = false;
    if (_recognitionCancel != null && !_recognitionCancel!.isCompleted) {
      _recognitionCancel!.complete();
    }
    _recognitionCancel = null;
    await _recorder.cancelRecording();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
  }

  Future<void> _showResult(TrackResult result) async {
    await _stopRecognitionSession();
    if (!mounted) return;
    await context.read<AppState>().addIdentification(result);

    if (!mounted) return;
    setState(() {
      _result = result;
      _aiConversation = [];
      _scanState = _ScanState.result;
    });
    unawaited(_loadAiConversation(result));
    unawaited(_preparePlayback(result));
  }

  Future<void> _loadAiConversation(TrackResult song) async {
    final conversation = await StorageService().loadMusicAiConversation(song);
    if (mounted && identical(_result, song)) {
      setState(() => _aiConversation = conversation);
    }
  }

  Future<void> _openAiChat() async {
    final result = _result;
    if (result == null || !mounted) return;
    final conversation = await showModalBottomSheet<List<AiChatMessage>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _SongAiChatSheet(song: result, initialConversation: _aiConversation),
    );
    if (conversation != null && mounted) {
      setState(() => _aiConversation = conversation);
      unawaited(StorageService().saveMusicAiConversation(result, conversation));
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _scanState = _ScanState.error;
    });
  }

  Future<void> _resetToIdle() async {
    await _stopRecognitionSession();
    _amplitudeLevel = 0.05;
    _pendingAutoResult = null;
    _autoButtonPressed = false;
    setState(() {
      _scanState = _ScanState.idle;
      _result = null;
      _aiConversation = [];
      _errorMessage = null;
      _isPlaying = false;
      _searchController.clear();
      _searchResults = [];
      _searchError = null;
    });
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: _buildAppBar(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _buildBody(),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_result != null)
            SongPlayBar(
              player: _audioPlayer,
              title: _result!.title,
              artworkUrl: _result!.artworkUrl,
            ),
          AppBottomNavBar(
            currentIndex: 1,
            onTap: (i) {
              if (i == 0) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (_) => false,
                );
              } else if (i == 2) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AiAnalyzerScreen()),
                );
              } else if (i == 3) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LibraryScreen()),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_scanState) {
      case _ScanState.result:
        return _ResultView(
          key: const ValueKey('result'),
          result: _result!,
          player: _audioPlayer,
          isPlaying: _isPlaying,
          onPlayPause: () => _togglePlayback(),
          onReset: () => unawaited(_resetToIdle()),
          onToggleSave: () => context.read<AppState>().toggleSave(_result!),
          onAskAi: _openAiChat,
        );
      case _ScanState.recording:
        return _RecordingView(
          key: const ValueKey('recording'),
          outerScale: _outerScale,
          outerOpacity: _outerOpacity,
          innerScale: _innerScale,
          innerOpacity: _innerOpacity,
          barAnims: _barAnims,
          amplitudeLevel: _amplitudeLevel,
          onCancel: () => unawaited(_resetToIdle()),
        );
      case _ScanState.analyzing:
        return _AnalyzingView(key: const ValueKey('analyzing'));
      case _ScanState.search:
        return _SongSearchView(
          key: const ValueKey('search'),
          controller: _searchController,
          results: _searchResults,
          isSearching: _isSearching,
          errorMessage: _searchError,
          onChanged: _onSearchChanged,
          onSelect: _selectSong,
          onBack: () => unawaited(_resetToIdle()),
          onShazam: _startScan,
        );
      case _ScanState.error:
        return _ErrorView(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Unknown error',
          onRetry: () => unawaited(_resetToIdle()),
        );
      case _ScanState.idle:
        return _ListeningView(
          key: const ValueKey('listening'),
          outerScale: _outerScale,
          outerOpacity: _outerOpacity,
          innerScale: _innerScale,
          innerOpacity: _innerOpacity,
          barAnims: _barAnims,
          onShazam: _startScan,
          onSearch: _openSearch,
        );
    }
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface.withOpacity(0.85),
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceContainer,
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.onSurfaceVariant,
            size: 18,
          ),
        ),
      ),
      title: Text(
        'Find Song',
        style: GoogleFonts.sora(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Icon(
              Icons.settings_rounded,
              color: AppColors.onSurfaceVariant,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Idle / Listening view
// ─────────────────────────────────────────────────────────────

class _ListeningView extends StatelessWidget {
  final Animation<double> outerScale;
  final Animation<double> outerOpacity;
  final Animation<double> innerScale;
  final Animation<double> innerOpacity;
  final List<Animation<double>> barAnims;
  final VoidCallback onShazam;
  final VoidCallback onSearch;

  const _ListeningView({
    super.key,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerOpacity,
    required this.barAnims,
    required this.onShazam,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 18),
                Text(
                  'Find an existing song',
                  style: GoogleFonts.sora(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Listen to what is playing or search for a song yourself',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: onSearch,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: AppColors.surfaceContainer,
                      border: Border.all(
                        color: AppColors.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Search by song or artist',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                GestureDetector(
                  onTap: onShazam,
                  child: SizedBox(
                    width: 280,
                    height: 280,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: outerScale,
                          builder: (_, __) => Transform.scale(
                            scale: outerScale.value,
                            child: Container(
                              width: 280,
                              height: 280,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.secondary.withOpacity(
                                    outerOpacity.value,
                                  ),
                                  width: 1,
                                ),
                                color: AppColors.secondary.withOpacity(
                                  outerOpacity.value * 0.15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: innerScale,
                          builder: (_, __) => Transform.scale(
                            scale: innerScale.value,
                            child: Container(
                              width: 210,
                              height: 210,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(
                                    innerOpacity.value * 0.6,
                                  ),
                                  width: 1,
                                ),
                                color: AppColors.primary.withOpacity(
                                  innerOpacity.value * 0.12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(150, 150),
                          painter: _DashedCirclePainter(
                            color: AppColors.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2F7BFF), Color(0xFF1468F5)],
                            ),
                            border: Border.all(
                              color: Color(0xFF74A8FF),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF1468F5),
                                blurRadius: 34,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Color(0xFF74A8FF),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const CustomPaint(
                            painter: _ShazamLogoPainter(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'TAP TO SHAZAM',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Listens until a match is found • Sends short audio clips',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Public catalogue search
// ─────────────────────────────────────────────────────────────

class _SongSearchView extends StatelessWidget {
  const _SongSearchView({
    super.key,
    required this.controller,
    required this.results,
    required this.isSearching,
    required this.errorMessage,
    required this.onChanged,
    required this.onSelect,
    required this.onBack,
    required this.onShazam,
  });

  final TextEditingController controller;
  final List<SongSearchResult> results;
  final bool isSearching;
  final String? errorMessage;
  final ValueChanged<String> onChanged;
  final ValueChanged<SongSearchResult> onSelect;
  final VoidCallback onBack;
  final VoidCallback onShazam;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.plusJakartaSans(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'Song or artist',
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: AppColors.onSurfaceVariant,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                ),
                suffixIcon: isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : controller.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                        icon: const Icon(Icons.clear_rounded),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: AppColors.outlineVariant.withOpacity(0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: AppColors.outlineVariant.withOpacity(0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onShazam,
                icon: const Icon(Icons.mic_rounded, size: 18),
                label: const Text('Use Shazam instead'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (errorMessage != null)
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              )
            else if (controller.text.isEmpty)
              Expanded(child: _SearchEmptyState(onBack: onBack))
            else if (!isSearching && results.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No songs found. Try another search.'),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final song = results[index];
                    return _SongSearchTile(
                      song: song,
                      onTap: () => onSelect(song),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.library_music_rounded,
          size: 48,
          color: AppColors.secondary,
        ),
        const SizedBox(height: 12),
        Text(
          'Search by song or artist',
          style: GoogleFonts.plusJakartaSans(color: AppColors.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _SongSearchTile extends StatelessWidget {
  const _SongSearchTile({required this.song, required this.onTap});
  final SongSearchResult song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceContainer,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 52,
                height: 52,
                child: song.artworkUrl == null
                    ? const ColoredBox(
                        color: AppColors.surfaceContainerHigh,
                        child: Icon(Icons.album_rounded),
                      )
                    : Image.network(
                        song.artworkUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: AppColors.surfaceContainerHigh,
                          child: Icon(Icons.album_rounded),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                  if (song.album.isNotEmpty)
                    Text(
                      song.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Recording view (mic active, countdown)
// ─────────────────────────────────────────────────────────────

class _RecordingView extends StatelessWidget {
  final Animation<double> outerScale;
  final Animation<double> outerOpacity;
  final Animation<double> innerScale;
  final Animation<double> innerOpacity;
  final List<Animation<double>> barAnims;
  final double amplitudeLevel;
  final VoidCallback onCancel;

  const _RecordingView({
    super.key,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerOpacity,
    required this.barAnims,
    required this.amplitudeLevel,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            _PingBadge(label: 'RECORDING NOW'),
            const SizedBox(height: 14),
            Text(
              'Listening…',
              style: GoogleFonts.sora(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Keep the sound playing near your phone',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            // Sphere with red recording ring
            SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0.82,
                      end: 0.82 + amplitudeLevel * 0.38,
                    ),
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    builder: (_, scale, __) => Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(0.85),
                            width: 2,
                          ),
                          color: Colors.redAccent.withOpacity(0.06),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [
                          AppColors.surfaceContainerHigh,
                          AppColors.surfaceContainer,
                          AppColors.surfaceVariant,
                        ],
                      ),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.35),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.mic_rounded,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'LISTENING FOR A MATCH',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AppColors.surfaceContainerHigh,
                  border: Border.all(
                    color: AppColors.outlineVariant.withOpacity(0.4),
                  ),
                ),
                child: Text(
                  'CANCEL',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceVariant,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Analyzing view (spinner while waiting for API)
// ─────────────────────────────────────────────────────────────

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ANALYZING',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.secondary,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Matching acoustic fingerprint…',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Error view
// ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withOpacity(0.1),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Recognition Failed',
              style: GoogleFonts.sora(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AppColors.surfaceContainerHigh,
                  border: Border.all(
                    color: AppColors.outlineVariant.withOpacity(0.4),
                  ),
                ),
                child: Text(
                  'TRY AGAIN',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Result view (real data)
// ─────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final TrackResult result;
  final AudioPlayer player;
  final VoidCallback onReset;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleSave;
  final VoidCallback onAskAi;

  const _ResultView({
    super.key,
    required this.result,
    required this.player,
    required this.onReset,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onToggleSave,
    required this.onAskAi,
  });

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(result);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Match Found',
              style: GoogleFonts.sora(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Main result card
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surfaceContainer.withOpacity(0.82),
              border: Border.all(
                color: AppColors.primaryFixedDim.withOpacity(0.12),
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.secondary.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SongArtwork(url: result.artworkUrl, size: 96),
                          const SizedBox(width: 16),
                          // Track details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.title,
                                  style: GoogleFonts.sora(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  result.artist,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  result.album,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (result.key != '—') ...[
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => KeyDetailsScreen(
                                          keyName: result.key,
                                          songTitle: result.title,
                                          artworkUrl: result.artworkUrl,
                                          player: player,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.music_note_rounded,
                                          color: AppColors.secondary,
                                          size: 15,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'KEY ${result.key}',
                                          style: GoogleFonts.spaceGrotesk(
                                            color: AppColors.secondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Bookmark button
                          GestureDetector(
                            onTap: onToggleSave,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: saved
                                    ? AppColors.primary.withOpacity(0.2)
                                    : AppColors.surfaceContainerHigh,
                                border: Border.all(
                                  color: saved
                                      ? AppColors.primary.withOpacity(0.5)
                                      : AppColors.outlineVariant.withOpacity(
                                          0.3,
                                        ),
                                ),
                              ),
                              child: Icon(
                                saved
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_outline_rounded,
                                color: saved
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Context-aware music theory assistant
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAskAi,
              icon: const Icon(Icons.auto_awesome_rounded, size: 19),
              label: Text(
                'ASK AI ABOUT THIS SONG',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondary,
                side: BorderSide(color: AppColors.secondary.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (result.tabSource != null ||
              result.tabUrl?.isNotEmpty == true) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surfaceContainerLow,
                border: Border.all(
                  color: AppColors.outlineVariant.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.library_music_rounded,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'TABS${result.tabSource == null ? '' : ' · ${result.tabSource}'}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.outline,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _TabContentSwitcher(
                    result: result,
                    onOpenFullScreen: (browser) =>
                        _openFullScreenTabs(context, result, browser: browser),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Mood tags
          if (result.mood.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surfaceContainerLow,
                border: Border.all(
                  color: AppColors.outlineVariant.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MOOD',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.outline,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: result.mood.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: AppColors.secondaryContainer.withOpacity(0.15),
                          border: Border.all(
                            color: AppColors.secondary.withOpacity(0.25),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Quick action buttons
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.podcasts_rounded,
                  label: 'Spotify',
                  color: AppColors.secondary,
                  onTap: () => _openMusicSearch(
                    context,
                    'https://open.spotify.com/search/${Uri.encodeComponent('${result.title} ${result.artist}')}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.music_note_rounded,
                  label: 'Apple',
                  color: AppColors.primary,
                  onTap: () => _openMusicSearch(
                    context,
                    Uri.https('music.apple.com', '/us/search', {
                      'term': '${result.title} ${result.artist}',
                    }).toString(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: AppColors.secondary,
                  onTap: () => _shareSong(context, result),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Scan another
          GestureDetector(
            onTap: onReset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: AppColors.surfaceContainerHigh,
                border: Border.all(
                  color: AppColors.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.autorenew_rounded,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SCAN ANOTHER SONG',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMusicSearch(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the music service.')),
      );
    }
  }

  Future<void> _shareSong(BuildContext context, TrackResult result) async {
    final text = '${result.title} — ${result.artist}';
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await AndroidIntent(
          action: 'android.intent.action.SEND',
          type: 'text/plain',
          arguments: {
            'android.intent.extra.SUBJECT': text,
            'android.intent.extra.TEXT': text,
          },
        ).launch();
        return;
      }
      final opened = await launchUrl(
        Uri.parse('sms:?body=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open sharing.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open sharing.')),
        );
      }
    }
  }

  void _openFullScreenTabs(
    BuildContext context,
    TrackResult result, {
    required bool browser,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: AppColors.background,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenChordSheet(
            title: result.title,
            source: result.tabSource,
            url: result.tabUrl!,
            content: result.tabChordContent,
            sourceId: result.tabSourceId,
            browser: browser,
            player: player,
            artworkUrl: result.artworkUrl,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class _SongAiChatSheet extends StatefulWidget {
  final TrackResult song;
  final List<AiChatMessage> initialConversation;

  const _SongAiChatSheet({
    required this.song,
    required this.initialConversation,
  });

  @override
  State<_SongAiChatSheet> createState() => _SongAiChatSheetState();
}

Future<List<AiChatMessage>?> showSongCoach(
  BuildContext context,
  TrackResult song, {
  List<AiChatMessage> initialConversation = const [],
}) {
  return showModalBottomSheet<List<AiChatMessage>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _SongAiChatSheet(song: song, initialConversation: initialConversation),
  );
}

class _SongAiChatSheetState extends State<_SongAiChatSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _ai = MusicAiService();
  late List<AiChatMessage> _messages;
  bool _isSending = false;
  String? _error;

  static const _suggestions = [
    'Explain this chord progression',
    'What scales can I use to solo?',
    'How can I make this easier on guitar?',
  ];

  @override
  void initState() {
    super.initState();
    _messages = [...widget.initialConversation];
    unawaited(_loadModel());
    unawaited(_restoreConversation());
  }

  String _model = MusicAiService.defaultModel;

  Future<void> _loadModel() async {
    final saved = await StorageService().loadMusicAiModel();
    if (!mounted ||
        saved == null ||
        !MusicAiService.supportedModels.contains(saved)) {
      return;
    }
    setState(() => _model = saved);
  }

  Future<void> _restoreConversation() async {
    final stored = await StorageService().loadMusicAiConversation(widget.song);
    if (!mounted || stored.isEmpty || _messages.isNotEmpty) return;
    setState(() => _messages = stored);
    _scrollToBottom();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    final question = (suggestedQuestion ?? _inputController.text).trim();
    if (question.isEmpty || _isSending) return;
    _inputController.clear();
    setState(() {
      _error = null;
      _isSending = true;
      _messages.add(AiChatMessage(role: 'user', content: question));
    });
    _scrollToBottom();

    try {
      final answer = await _ai.ask(
        song: widget.song,
        question: question,
        conversation: _messages.sublist(0, _messages.length - 1),
        model: _model,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(AiChatMessage(role: 'assistant', content: answer));
        _isSending = false;
      });
      unawaited(
        StorageService().saveMusicAiConversation(widget.song, _messages),
      );
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _isSending = false;
        _error = error.toString().replaceFirst('MusicAiException: ', '');
      });
    }
  }

  Future<void> _clearConversation() async {
    if (_isSending) return;
    setState(() {
      _messages = [];
      _error = null;
    });
    await StorageService().saveMusicAiConversation(widget.song, const []);
  }

  Future<void> _closeCoach() async {
    await StorageService().saveMusicAiConversation(widget.song, _messages);
    if (mounted) Navigator.pop(context, _messages);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.82,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.secondary.withOpacity(0.15),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Song Coach',
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        '${widget.song.title} · ${widget.song.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _model,
                          isDense: true,
                          dropdownColor: AppColors.surfaceContainerHigh,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                          icon: const Icon(
                            Icons.expand_more_rounded,
                            size: 15,
                            color: AppColors.secondary,
                          ),
                          items: MusicAiService.supportedModels
                              .map(
                                (model) => DropdownMenuItem(
                                  value: model,
                                  child: Text(model),
                                ),
                              )
                              .toList(),
                          onChanged: (model) {
                            if (model == null) return;
                            setState(() => _model = model);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear conversation',
                  onPressed: _messages.isEmpty ? null : _clearConversation,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  color: AppColors.onSurfaceVariant,
                ),
                IconButton(
                  onPressed: _closeCoach,
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? _Suggestions(suggestions: _suggestions, onSelected: _send)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _AiTypingBubble();
                      }
                      final message = _messages[index];
                      return _AiMessageBubble(message: message);
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: AppColors.onSurface),
                    decoration: InputDecoration(
                      hintText:
                          'Ask about the harmony, rhythm, or guitar part…',
                      hintStyle: TextStyle(
                        color: AppColors.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: AppColors.background,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  const _Suggestions({required this.suggestions, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      children: [
        Text(
          'Ask anything about this song',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        ...suggestions.map(
          (suggestion) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: ActionChip(
              label: Text(suggestion),
              onPressed: () => onSelected(suggestion),
              labelStyle: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 12,
              ),
              side: BorderSide(
                color: AppColors.outlineVariant.withOpacity(0.35),
              ),
              backgroundColor: AppColors.surfaceContainerLow,
            ),
          ),
        ),
      ],
    );
  }
}

class _AiMessageBubble extends StatelessWidget {
  final AiChatMessage message;

  const _AiMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.secondary.withOpacity(0.18)
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUser
                ? AppColors.secondary.withOpacity(0.25)
                : AppColors.outlineVariant.withOpacity(0.18),
          ),
        ),
        child: _AiFormattedText(message.content),
      ),
    );
  }
}

class _AiFormattedText extends StatelessWidget {
  final String text;

  const _AiFormattedText(this.text);

  @override
  Widget build(BuildContext context) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i].trimRight();
      if (raw.trim().startsWith('```')) {
        if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
        continue;
      }
      final heading = RegExp(r'^#{1,6}\s+').firstMatch(raw);
      final bullet = RegExp(r'^\s*[-*+]\s+').firstMatch(raw);
      final numbered = RegExp(r'^\s*\d+[.)]\s+').firstMatch(raw);
      var line = raw;
      TextStyle? lineStyle;
      if (heading != null) {
        line = raw.substring(heading.end);
        lineStyle = const TextStyle(fontWeight: FontWeight.w700, fontSize: 14);
      } else if (bullet != null) {
        line = '• ${raw.substring(bullet.end)}';
      } else if (numbered != null) {
        line = raw;
      }
      spans.addAll(_inlineMarkdown(line, lineStyle));
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 13,
          height: 1.45,
        ),
        children: spans,
      ),
    );
  }

  List<TextSpan> _inlineMarkdown(String value, TextStyle? lineStyle) {
    final spans = <TextSpan>[];
    final pattern = RegExp(
      r'\*\*\*(.+?)\*\*\*|(\*\*|__)(.+?)\2|(?<!\*)\*([^*]+)\*(?!\*)|`([^`]+)`|\$([^$]+)\$',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: value.substring(cursor, match.start),
            style: lineStyle,
          ),
        );
      }
      final boldItalic = match.group(1);
      final bold = match.group(3);
      final italic = match.group(4);
      final code = match.group(5);
      final math = match.group(6);
      spans.add(
        TextSpan(
          text: boldItalic ?? bold ?? italic ?? code ?? math,
          style:
              lineStyle?.copyWith(
                fontWeight: boldItalic != null || bold != null
                    ? FontWeight.w700
                    : lineStyle.fontWeight,
                fontStyle: boldItalic != null || italic != null
                    ? FontStyle.italic
                    : lineStyle.fontStyle,
              ) ??
              (boldItalic != null
                  ? const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                    )
                  : bold != null
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : italic != null
                  ? const TextStyle(fontStyle: FontStyle.italic)
                  : const TextStyle(
                      color: AppColors.secondary,
                      fontFamily: 'monospace',
                    )),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor), style: lineStyle));
    }
    return spans;
  }
}

class _AiTypingBubble extends StatelessWidget {
  const _AiTypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 12, left: 4),
        child: Text(
          'Thinking…',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────

class _SongArtwork extends StatelessWidget {
  final String? url;
  final double size;

  const _SongArtwork({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.13),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.3),
            AppColors.secondary.withOpacity(0.2),
            AppColors.surfaceContainerHighest,
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: url?.isNotEmpty == true
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultArtwork(),
            )
          : _defaultArtwork(),
    );
  }

  Widget _defaultArtwork() {
    return Center(
      child: Icon(
        Icons.album_rounded,
        color: AppColors.primary,
        size: size * 0.5,
      ),
    );
  }
}

class _TabMiniPlayer extends StatelessWidget {
  final TrackResult result;
  final AudioPlayer player;
  final bool isPlaying;
  final VoidCallback onPlayPause;

  const _TabMiniPlayer({
    required this.result,
    required this.player,
    required this.isPlaying,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: AppColors.primary.withOpacity(0.35)),
        ),
      ),
      child: Row(
        children: [
          _SongArtwork(url: result.artworkUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  result.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  initialData: player.position,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration?>(
                      stream: player.durationStream,
                      initialData: player.duration,
                      builder: (context, durationSnapshot) {
                        final duration = durationSnapshot.data ?? Duration.zero;
                        final progress = duration.inMilliseconds == 0
                            ? 0.0
                            : (position.inMilliseconds /
                                      duration.inMilliseconds)
                                  .clamp(0.0, 1.0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LinearProgressIndicator(
                              minHeight: 2,
                              value: progress,
                              backgroundColor: AppColors.outlineVariant
                                  .withOpacity(0.25),
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_formatDuration(position)} / ${_formatDuration(duration)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlayPause,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChordSheet extends StatelessWidget {
  final String content;
  final String? sourceId;

  const _ChordSheet({required this.content, this.sourceId});

  bool get _isUltimateGuitar => sourceId == 'ultimate_guitar';

  TextStyle _sheetStyle({required double fontSize, required Color color}) {
    if (_isUltimateGuitar) {
      // Ultimate Guitar's tab body uses Roboto Mono, 14px text with a 32px
      // line rhythm. Keeping the same family for measurement and rendering
      // is important because the chord columns are encoded as spaces.
      return GoogleFonts.robotoMono(
        fontSize: fontSize,
        height: 1.4,
        color: color,
      );
    }
    return TextStyle(fontFamily: 'Tab4uFont', fontSize: fontSize, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        // Leading and trailing whitespace are meaningful source coordinates.
        .map((line) => line)
        .where(_hasVisibleCharacters)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          var widestLine = 0.0;
          for (final line in lines) {
            final measureStyle = _sheetStyle(
              fontSize: 14,
              color: AppColors.onSurface,
            );
            final measure = TextPainter(
              text: _isChordLine(line)
                  ? TextSpan(style: measureStyle, children: _chordSpans(line))
                  : TextSpan(text: line, style: measureStyle),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout();
            if (measure.width > widestLine) widestLine = measure.width;
          }
          // Leave a few pixels for font overhang and the chord highlight
          // background, which are not fully reflected by plain-text width.
          final measuredWidth = widestLine + 8;
          final scale = (constraints.maxWidth / measuredWidth)
              .clamp(_isUltimateGuitar ? 0.55 : 0.8, 1.25)
              .toDouble();
          final fontSize = (14 * scale).clamp(8.0, 17.5).toDouble();

          return Align(
            alignment: _isUltimateGuitar
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: _isUltimateGuitar
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: _isUltimateGuitar
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  for (final line in lines)
                    _isChordLine(line)
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text.rich(
                              TextSpan(children: _chordSpans(line)),
                              textDirection: TextDirection.ltr,
                              textAlign: _isUltimateGuitar
                                  ? TextAlign.left
                                  : TextAlign.right,
                              softWrap: false,
                              maxLines: 1,
                              style: _sheetStyle(
                                fontSize: fontSize,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : Padding(
                            padding: EdgeInsets.zero,
                            child: Text(
                              _displayLine(
                                line,
                                preserveLeadingWhitespace: _isUltimateGuitar,
                              ),
                              textDirection: TextDirection.ltr,
                              textAlign: _isUltimateGuitar
                                  ? TextAlign.left
                                  : TextAlign.right,
                              softWrap: false,
                              maxLines: 1,
                              style: _sheetStyle(
                                fontSize: fontSize,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static final _chordPattern = RegExp(
    r'^(?:♫̸|x\d+|N(?:\.?C\.?)?|[A-G](?:#|b)?(?:maj|min|m|dim|aug|sus|add)?\d*(?:/[A-G](?:#|b)?)?)$',
    caseSensitive: false,
  );

  static bool _isChordLine(String line) {
    // Tab4U mixes regular spaces, tabs, and NBSPs. Normalize only for
    // classification; the original line is still rendered unchanged so its
    // spacing remains exact.
    final normalized = line.replaceAll('\u00a0', ' ').trim();
    final tokens = normalized.split(RegExp(r'\s+'));
    return tokens.isNotEmpty && tokens.every(_chordPattern.hasMatch);
  }

  static bool _hasVisibleCharacters(String line) =>
      line.replaceAll(RegExp(r'[\s\u00a0]'), '').isNotEmpty;

  static List<InlineSpan> _chordSpans(String line) {
    final spans = <InlineSpan>[];
    final chordPattern = RegExp(
      r'♫̸|x\d+|N(?:\.?C\.?)?|[A-G](?:#|b)?(?:maj|min|m|dim|aug|sus|add)?\d*(?:/[A-G](?:#|b)?)?',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in chordPattern.allMatches(line)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            backgroundColor: AppColors.primary.withOpacity(0.14),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor)));
    }
    return spans;
  }

  static String _displayLine(
    String line, {
    bool preserveLeadingWhitespace = false,
  }) {
    // Chord rows keep their source whitespace for accurate chord placement.
    // Lyric rows are right-aligned, so their indentation is only visual noise.
    final lyric = preserveLeadingWhitespace
        ? line
        : line.replaceFirst(RegExp(r'^[\t \u00a0]+'), '');
    // Keep Hebrew section labels such as "פתיחה:" resolving the neutral
    // colon on the visual right.
    return lyric.replaceAllMapped(
      RegExp(r'(?<=[\u0590-\u05ff]):'),
      (_) => '\u200F:\u200F',
    );
  }
}

class _TabContentSwitcher extends StatefulWidget {
  final TrackResult result;
  final ValueChanged<bool> onOpenFullScreen;

  const _TabContentSwitcher({
    required this.result,
    required this.onOpenFullScreen,
  });

  @override
  State<_TabContentSwitcher> createState() => _TabContentSwitcherState();
}

class _TabContentSwitcherState extends State<_TabContentSwitcher> {
  bool _browser = false;
  Offset? _pointerDownPosition;

  @override
  void initState() {
    super.initState();
    _browser = widget.result.tabChordContent?.isNotEmpty != true;
  }

  @override
  Widget build(BuildContext context) {
    final hasBrowser = widget.result.tabUrl?.isNotEmpty == true;
    final hasChords = widget.result.tabChordContent?.isNotEmpty == true;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _modeButton('CHORDS', false, hasChords)),
            const SizedBox(width: 8),
            Expanded(child: _modeButton('WEBSITE', true, hasBrowser)),
            if (widget.result.tabSourceId == 'ultimate_guitar')
              TextButton.icon(
                onPressed: hasBrowser ? _openInApp : null,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('APP'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            IconButton(
              tooltip: 'Maximize current view',
              onPressed: (_browser ? hasBrowser : hasChords)
                  ? () => widget.onOpenFullScreen(_browser)
                  : null,
              icon: const Icon(Icons.open_in_full_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildTabContent(hasBrowser, hasChords),
      ],
    );
  }

  Widget _buildTabContent(bool hasBrowser, bool hasChords) {
    final content = SizedBox(
      height: 420,
      child: _browser && hasBrowser
          ? _TabWebView(url: widget.result.tabUrl!)
          : hasChords
          ? SingleChildScrollView(
              child: _ChordSheet(
                content: widget.result.tabChordContent!,
                sourceId: widget.result.tabSourceId,
              ),
            )
          : const Center(child: Text('No tab view available.')),
    );

    // A tap can maximize the chord sheet without interfering with its scroll.
    // The website keeps all taps and drags for normal WebView interaction;
    // its expand button is the deliberate maximize action.
    if (_browser) {
      return Listener(
        onPointerDown: (event) => _pointerDownPosition = event.position,
        onPointerUp: (event) {
          final start = _pointerDownPosition;
          _pointerDownPosition = null;
          if (start != null && (event.position - start).distance < 10) {
            widget.onOpenFullScreen(true);
          }
        },
        onPointerCancel: (_) => _pointerDownPosition = null,
        child: content,
      );
    }
    return Listener(
      onPointerDown: (event) => _pointerDownPosition = event.position,
      onPointerUp: (event) {
        final start = _pointerDownPosition;
        _pointerDownPosition = null;
        if (start != null && (event.position - start).distance < 10) {
          widget.onOpenFullScreen(false);
        }
      },
      child: content,
    );
  }

  Widget _modeButton(String label, bool browser, bool enabled) {
    final selected = _browser == browser;
    return OutlinedButton(
      onPressed: enabled ? () => setState(() => _browser = browser) : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? AppColors.primary.withOpacity(0.15)
            : Colors.transparent,
        foregroundColor: selected
            ? AppColors.primary
            : AppColors.onSurfaceVariant,
        side: BorderSide(
          color: selected
              ? AppColors.primary.withOpacity(0.5)
              : AppColors.outlineVariant.withOpacity(0.35),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<void> _openInApp() async {
    final value = widget.result.tabUrl;
    if (value == null || value.isEmpty) return;
    final uri = Uri.parse(value);
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: value,
          package: 'com.ultimateguitar.tabs',
        ).launch();
        return;
      } catch (_) {
        // The app may not be installed or may not accept this tab URL.
      }
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ultimate Guitar could not be opened.')),
      );
    }
  }
}

class _TabWebView extends StatefulWidget {
  final String url;

  const _TabWebView({required this.url});

  @override
  State<_TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends State<_TabWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onWebResourceError: (_) {}))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: WebViewWidget(
        controller: _controller,
        gestureRecognizers: {
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }
}

class _FullScreenChordSheet extends StatelessWidget {
  final String title;
  final String? source;
  final String url;
  final String? content;
  final String? sourceId;
  final bool browser;
  final AudioPlayer player;
  final String? artworkUrl;

  const _FullScreenChordSheet({
    required this.title,
    required this.source,
    required this.url,
    required this.content,
    required this.sourceId,
    required this.browser,
    required this.player,
    this.artworkUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            if (source != null)
              Text(
                source!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Close tabs',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: browser || content?.isNotEmpty != true
            ? _TabWebView(url: url)
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 92),
                child: _ExpandedChordSheet(
                  content: content!,
                  sourceId: sourceId,
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 84,
          child: SongPlayBar(
            player: player,
            title: title,
            artworkUrl: artworkUrl,
            compact: true,
          ),
        ),
      ),
    );
  }
}

class _ExpandedChordSheet extends StatelessWidget {
  final String content;
  final String? sourceId;

  const _ExpandedChordSheet({required this.content, this.sourceId});

  bool get _isUltimateGuitar => sourceId == 'ultimate_guitar';

  TextStyle _sheetStyle({required double fontSize, required Color color}) {
    if (_isUltimateGuitar) {
      return GoogleFonts.robotoMono(
        fontSize: fontSize,
        height: 1.4,
        color: color,
      );
    }
    return TextStyle(fontFamily: 'Tab4uFont', fontSize: fontSize, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .where(_ChordSheet._hasVisibleCharacters)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        var widestLine = 0.0;
        for (final line in lines) {
          final measureStyle = _sheetStyle(
            fontSize: 14,
            color: AppColors.onSurface,
          );
          final painter = TextPainter(
            text: _ChordSheet._isChordLine(line)
                ? TextSpan(
                    style: measureStyle,
                    children: _ChordSheet._chordSpans(line),
                  )
                : TextSpan(text: line, style: measureStyle),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          if (painter.width > widestLine) widestLine = painter.width;
        }
        final fontSize = (14 * ((constraints.maxWidth - 8) / (widestLine + 2)))
            .clamp(_isUltimateGuitar ? 7.5 : 10.0, 28.0)
            .toDouble();

        return Align(
          alignment: _isUltimateGuitar ? Alignment.topLeft : Alignment.topRight,
          child: Column(
            crossAxisAlignment: _isUltimateGuitar
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              for (final line in lines)
                _ChordSheet._isChordLine(line)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text.rich(
                          TextSpan(children: _ChordSheet._chordSpans(line)),
                          textDirection: TextDirection.ltr,
                          textAlign: _isUltimateGuitar
                              ? TextAlign.left
                              : TextAlign.right,
                          softWrap: false,
                          maxLines: 1,
                          style: _sheetStyle(
                            fontSize: fontSize,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Text(
                        _ChordSheet._displayLine(
                          line,
                          preserveLeadingWhitespace: _isUltimateGuitar,
                        ),
                        textDirection: TextDirection.ltr,
                        textAlign: _isUltimateGuitar
                            ? TextAlign.left
                            : TextAlign.right,
                        softWrap: false,
                        maxLines: 1,
                        style: _sheetStyle(
                          fontSize: fontSize,
                          color: AppColors.onSurface,
                        ),
                      ),
            ],
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(1, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.surfaceContainer,
          border: Border.all(color: AppColors.outlineVariant.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  final double height;
  const _MiniBar({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashCount = 24;
    const sweepAngle = 2 * 3.14159 / dashCount;
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * sweepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * 0.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

/// The Shazam mark, rendered from the official Simple Icons geometry.
class _ShazamLogoPainter extends CustomPainter {
  const _ShazamLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.29;
    final white = Paint()..color = Colors.white;
    final blue = Paint()..color = const Color(0xFF1D6DF2);

    // Shazam's mark is a white disc with the characteristic blue, angular S
    // cut through its center.
    canvas.drawCircle(center, radius, white);
    final path = Path()
      ..moveTo(size.width * 0.42, size.height * 0.35)
      ..cubicTo(
        size.width * 0.50,
        size.height * 0.28,
        size.width * 0.61,
        size.height * 0.29,
        size.width * 0.68,
        size.height * 0.36,
      )
      ..lineTo(size.width * 0.61, size.height * 0.43)
      ..cubicTo(
        size.width * 0.56,
        size.height * 0.38,
        size.width * 0.49,
        size.height * 0.38,
        size.width * 0.45,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.40,
        size.height * 0.47,
        size.width * 0.42,
        size.height * 0.51,
        size.width * 0.48,
        size.height * 0.54,
      )
      ..lineTo(size.width * 0.59, size.height * 0.60)
      ..cubicTo(
        size.width * 0.67,
        size.height * 0.65,
        size.width * 0.68,
        size.height * 0.73,
        size.width * 0.61,
        size.height * 0.79,
      )
      ..cubicTo(
        size.width * 0.53,
        size.height * 0.86,
        size.width * 0.42,
        size.height * 0.85,
        size.width * 0.34,
        size.height * 0.78,
      )
      ..lineTo(size.width * 0.41, size.height * 0.71)
      ..cubicTo(
        size.width * 0.47,
        size.height * 0.76,
        size.width * 0.54,
        size.height * 0.76,
        size.width * 0.58,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.62,
        size.height * 0.68,
        size.width * 0.60,
        size.height * 0.64,
        size.width * 0.54,
        size.height * 0.61,
      )
      ..lineTo(size.width * 0.43, size.height * 0.55)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.50,
        size.width * 0.35,
        size.height * 0.41,
        size.width * 0.42,
        size.height * 0.35,
      )
      ..close();
    canvas.drawPath(path, blue);
  }

  @override
  bool shouldRepaint(_ShazamLogoPainter oldDelegate) => false;
}

class _PingBadge extends StatefulWidget {
  final String label;
  const _PingBadge({required this.label});

  @override
  State<_PingBadge> createState() => _PingBadgeState();
}

class _PingBadgeState extends State<_PingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(
      begin: 1.0,
      end: 2.2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.surfaceContainerHigh,
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => Transform.scale(
                    scale: _anim.value,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.secondary.withOpacity(
                          1.2 - _anim.value * 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
