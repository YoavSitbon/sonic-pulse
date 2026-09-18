import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav_bar.dart';
import '../models/track_result.dart';
import '../services/audio_recorder_service.dart';
import '../services/recognition_service.dart';
import '../services/music_search_service.dart';
import '../models/song_search_result.dart';
import '../providers/app_state.dart';
import '../config/api_config.dart';
import 'home_screen.dart';
import 'ai_analyzer_screen.dart';
import 'library_screen.dart';

// ─────────────────────────────────────────────────────────────
// Screen states
// ─────────────────────────────────────────────────────────────
enum _ScanState { idle, search, recording, analyzing, result, error }

class FindSongScreen extends StatefulWidget {
  const FindSongScreen({super.key});

  @override
  State<FindSongScreen> createState() => _FindSongScreenState();
}

class _FindSongScreenState extends State<FindSongScreen>
    with TickerProviderStateMixin {
  _ScanState _scanState = _ScanState.idle;
  TrackResult? _result;
  String? _errorMessage;
  bool _isPlaying = false;
  int _recordingSecondsLeft = ApiConfig.recordingSeconds;
  Timer? _recordingTimer;
  Timer? _searchDebounce;
  final _searchController = TextEditingController();
  List<SongSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  final _recorder = AudioRecorderService();
  final _recognizer = RecognitionService();
  final _musicSearch = MusicSearchService();

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

    _outerPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
    _outerScale = Tween<double>(begin: 0.85, end: 1.3).animate(
      CurvedAnimation(parent: _outerPulse, curve: Curves.easeInOut),
    );
    _outerOpacity = Tween<double>(begin: 0.4, end: 0.08).animate(
      CurvedAnimation(parent: _outerPulse, curve: Curves.easeInOut),
    );

    _innerPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _innerScale = Tween<double>(begin: 0.92, end: 1.16).animate(
      CurvedAnimation(parent: _innerPulse, curve: Curves.easeInOut),
    );
    _innerOpacity = Tween<double>(begin: 0.8, end: 0.25).animate(
      CurvedAnimation(parent: _innerPulse, curve: Curves.easeInOut),
    );

    final barDurations = [300, 250, 400, 350];
    final barDelays = [0, 150, 75, 300];
    _barCtrls = List.generate(4, (i) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: barDurations[i]),
      );
      Future.delayed(
          Duration(milliseconds: barDelays[i]),
          () => mounted ? c.repeat(reverse: true) : null);
      return c;
    });
    _barAnims = _barCtrls.map((c) {
      return Tween<double>(begin: 0.3, end: 1.0)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    _outerPulse.dispose();
    _innerPulse.dispose();
    for (final c in _barCtrls) c.dispose();
    _recordingTimer?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Flow ─────────────────────────────────────────────────────────

  Future<void> _startScan() async {
    // Check permission first
    final hasPermission = await _recorder.requestPermission();
    if (!hasPermission) {
      _showError('Microphone permission denied. Please enable it in Settings.');
      return;
    }

    setState(() {
      _scanState = _ScanState.recording;
      _recordingSecondsLeft = ApiConfig.recordingSeconds;
      _errorMessage = null;
    });

    final started = await _recorder.startRecording();
    if (!started) {
      _showError('Could not start recording. Please try again.');
      return;
    }

    // Countdown timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _recordingSecondsLeft--);
      if (_recordingSecondsLeft <= 0) {
        t.cancel();
        _finishRecordingAndSend();
      }
    });
  }

  void _openSearch() {
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
      final result = await _recognizer.analyzeSelectedSong(
        title: song.title,
        artist: song.artist,
      );
      if (!mounted) return;
      final resultWithArtwork = result.copyWith(artworkUrl: song.artworkUrl);
      await context.read<AppState>().addIdentification(resultWithArtwork);
      if (!mounted) return;
      setState(() {
        _result = resultWithArtwork;
        _scanState = _ScanState.result;
      });
    } catch (e) {
      _showError('Song analysis failed: ${e.toString().replaceAll('RecognitionException: ', '')}');
    }
  }

  Future<void> _finishRecordingAndSend() async {
    _recordingTimer?.cancel();
    final audioPath = await _recorder.stopRecording();

    setState(() => _scanState = _ScanState.analyzing);

    try {
      final result = await _recognizer.recognizeSong(audioPath ?? '');
      await _recognizer.cleanupFile(audioPath);

      if (!mounted) return;
      // Add to global state
      await context.read<AppState>().addIdentification(result);

      setState(() {
        _result = result;
        _scanState = _ScanState.result;
      });
    } catch (e) {
      await _recognizer.cleanupFile(audioPath);
      _showError('Recognition failed: ${e.toString().replaceAll('RecognitionException: ', '')}');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _scanState = _ScanState.error;
    });
  }

  void _resetToIdle() {
    _recordingTimer?.cancel();
    _recorder.cancelRecording();
    setState(() {
      _scanState = _ScanState.idle;
      _result = null;
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
      bottomNavigationBar: AppBottomNavBar(
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
    );
  }

  Widget _buildBody() {
    switch (_scanState) {
      case _ScanState.result:
        return _ResultView(
          key: const ValueKey('result'),
          result: _result!,
          isPlaying: _isPlaying,
          onPlayPause: () => setState(() => _isPlaying = !_isPlaying),
          onReset: _resetToIdle,
          onToggleSave: () => context.read<AppState>().toggleSave(_result!),
        );
      case _ScanState.recording:
        return _RecordingView(
          key: const ValueKey('recording'),
          secondsLeft: _recordingSecondsLeft,
          outerScale: _outerScale,
          outerOpacity: _outerOpacity,
          innerScale: _innerScale,
          innerOpacity: _innerOpacity,
          barAnims: _barAnims,
          onCancel: _resetToIdle,
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
          onBack: _resetToIdle,
          onShazam: _startScan,
        );
      case _ScanState.error:
        return _ErrorView(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Unknown error',
          onRetry: _resetToIdle,
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
          child: const Icon(Icons.arrow_back_rounded,
              color: AppColors.onSurfaceVariant, size: 18),
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
          child: Icon(Icons.settings_rounded,
              color: AppColors.onSurfaceVariant, size: 22),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          const SizedBox(height: 20),
          _PingBadge(label: 'ACOUSTIC ENGINE READY'),
          const SizedBox(height: 14),
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
                            color: AppColors.secondary
                                .withOpacity(outerOpacity.value),
                            width: 1,
                          ),
                          color: AppColors.secondary
                              .withOpacity(outerOpacity.value * 0.15),
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
                            color: AppColors.primary
                                .withOpacity(innerOpacity.value * 0.6),
                            width: 1,
                          ),
                          color: AppColors.primary
                              .withOpacity(innerOpacity.value * 0.12),
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
                      gradient: const RadialGradient(
                        colors: [
                          AppColors.surfaceContainerHigh,
                          AppColors.surfaceContainer,
                          AppColors.surfaceVariant,
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.secondary.withOpacity(0.8),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondary.withOpacity(0.45),
                          blurRadius: 45,
                        ),
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.6),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.mic_rounded,
                            color: AppColors.secondary, size: 44),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(4, (i) {
                              final colors = [
                                AppColors.secondary,
                                AppColors.primary,
                                AppColors.secondary,
                                AppColors.primary,
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: AnimatedBuilder(
                                  animation: barAnims[i],
                                  builder: (_, __) => Container(
                                    width: 3,
                                    height: 14 * barAnims[i].value,
                                    decoration: BoxDecoration(
                                      color: colors[i],
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'SHAZAM IT',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.secondary,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Records ${ApiConfig.recordingSeconds}s • Sends audio to the fingerprint engine',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Container(height: 1, color: AppColors.outlineVariant.withOpacity(0.4)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: AppColors.outlineVariant.withOpacity(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
              label: const Text('SEARCH FOR A SONG'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                textStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ],
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
                hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.onSurfaceVariant),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
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
                  borderSide: BorderSide(color: AppColors.outlineVariant.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.outlineVariant.withOpacity(0.5)),
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
              Text(errorMessage!, style: const TextStyle(color: Colors.redAccent))
            else if (controller.text.isEmpty)
              Expanded(child: _SearchEmptyState(onBack: onBack))
            else if (!isSearching && results.isEmpty)
              const Expanded(child: Center(child: Text('No songs found. Try another search.')))
            else
              Expanded(
                child: ListView.separated(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final song = results[index];
                    return _SongSearchTile(song: song, onTap: () => onSelect(song));
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
            const Icon(Icons.library_music_rounded, size: 48, color: AppColors.secondary),
            const SizedBox(height: 12),
            Text('Search by song or artist',
                style: GoogleFonts.plusJakartaSans(color: AppColors.onSurfaceVariant)),
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
                        ? const ColoredBox(color: AppColors.surfaceContainerHigh, child: Icon(Icons.album_rounded))
                        : Image.network(song.artworkUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surfaceContainerHigh, child: Icon(Icons.album_rounded))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                    const SizedBox(height: 3),
                    Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.primary)),
                    if (song.album.isNotEmpty) Text(song.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
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
  final int secondsLeft;
  final Animation<double> outerScale;
  final Animation<double> outerOpacity;
  final Animation<double> innerScale;
  final Animation<double> innerOpacity;
  final List<Animation<double>> barAnims;
  final VoidCallback onCancel;

  const _RecordingView({
    super.key,
    required this.secondsLeft,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerOpacity,
    required this.barAnims,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
                          color: Colors.redAccent
                              .withOpacity(outerOpacity.value * 1.2),
                          width: 1.5,
                        ),
                        color: Colors.redAccent
                            .withOpacity(outerOpacity.value * 0.1),
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
                          color: Colors.redAccent
                              .withOpacity(innerOpacity.value * 0.5),
                          width: 1,
                        ),
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
                      const Icon(Icons.mic_rounded,
                          color: Colors.redAccent, size: 40),
                      const SizedBox(height: 4),
                      Text(
                        '$secondsLeft',
                        style: GoogleFonts.sora(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.redAccent,
                        ),
                      ),
                      Text(
                        'SEC',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'RECORDING AUDIO',
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: AppColors.surfaceContainerHigh,
                border: Border.all(
                    color: AppColors.outlineVariant.withOpacity(0.4)),
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
              child: const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 36),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AppColors.surfaceContainerHigh,
                  border: Border.all(
                      color: AppColors.outlineVariant.withOpacity(0.4)),
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
  final VoidCallback onReset;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleSave;

  const _ResultView({
    super.key,
    required this.result,
    required this.onReset,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(result);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _PingBadge(label: 'FINGERPRINT MATCHED')),
          const SizedBox(height: 14),
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
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Standard acoustic fingerprint verified',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
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
                          // Album art placeholder
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.outlineVariant
                                      .withOpacity(0.4)),
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
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.album_rounded,
                                    color: AppColors.primary, size: 48),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: AppColors.surfaceContainerLowest
                                          .withOpacity(0.9),
                                      border: Border.all(
                                          color: AppColors.secondary
                                              .withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      'WAV',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Track details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'FINGERPRINT MATCHED',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.secondary,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified_rounded,
                                        color: AppColors.secondary, size: 12),
                                  ],
                                ),
                                const SizedBox(height: 4),
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
                                      : AppColors.outlineVariant
                                          .withOpacity(0.3),
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
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.only(top: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: AppColors.outlineVariant.withOpacity(0.2),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                child: _MetricChip(
                                    label: 'KEY', value: result.key)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _MetricChip(
                                    label: 'TEMPO',
                                    value: '${result.bpm} BPM',
                                    valueColor: AppColors.secondary)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: _MetricChip(
                                    label: 'CONFIDENCE',
                                    value: result.confidencePercent,
                                    valueColor: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Chords card
          if (result.chords.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surfaceContainerLow,
                border: Border.all(
                    color: AppColors.outlineVariant.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CHORD PROGRESSION',
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
                    children: result.chords.map((chord) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.surfaceContainerHigh,
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Text(
                          chord,
                          style: GoogleFonts.sora(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
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

          // Mood tags
          if (result.mood.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surfaceContainerLow,
                border: Border.all(
                    color: AppColors.outlineVariant.withOpacity(0.2)),
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
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color:
                              AppColors.secondaryContainer.withOpacity(0.15),
                          border: Border.all(
                              color: AppColors.secondary.withOpacity(0.25)),
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
                      color: AppColors.secondary)),
              const SizedBox(width: 8),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.music_note_rounded,
                      label: 'Apple',
                      color: AppColors.primary)),
              const SizedBox(width: 8),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.share_rounded,
                      label: 'Share',
                      color: AppColors.secondary)),
              const SizedBox(width: 8),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.lyrics_rounded,
                      label: 'Lyrics',
                      color: AppColors.primary)),
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
                    color: AppColors.outlineVariant.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.autorenew_rounded,
                      color: AppColors.secondary, size: 20),
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
}

// ─────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricChip(
      {required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.surfaceContainerLow.withOpacity(0.7),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickAction(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    _anim = Tween<double>(begin: 1.0, end: 2.2)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
                        color: AppColors.secondary
                            .withOpacity(1.2 - _anim.value * 0.5),
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
