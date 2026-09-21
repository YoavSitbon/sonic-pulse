import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/wave_bars.dart';
import '../models/track_result.dart';
import '../models/youtube_video.dart';
import '../services/audio_recorder_service.dart';
import '../services/recognition_service.dart';
import '../providers/app_state.dart';
import 'home_screen.dart';
import 'find_song_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'youtube_search_screen.dart';
import 'key_details_screen.dart';

// ─────────────────────────────────────────────────────────────
// Screen states
// ─────────────────────────────────────────────────────────────
enum _AnalyzeState { idle, recording, analyzing, result, error }

class AiAnalyzerScreen extends StatefulWidget {
  final TrackResult? initialResult;

  const AiAnalyzerScreen({super.key, this.initialResult});

  @override
  State<AiAnalyzerScreen> createState() => _AiAnalyzerScreenState();
}

class _AiAnalyzerScreenState extends State<AiAnalyzerScreen>
    with TickerProviderStateMixin {
  _AnalyzeState _state = _AnalyzeState.idle;
  TrackResult? _result;
  String? _errorMessage;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  StreamSubscription? _amplitudeSubscription;
  double _amplitudeLevel = 0.05;

  final _recorder = AudioRecorderService();
  final _recognizer = RecognitionService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSubscription;
  String? _audioPath;
  String? _audioUrl;
  bool _isPlaying = false;

  // Outer pulse ring
  late AnimationController _outerPulse;
  late Animation<double> _outerScale;
  late Animation<double> _outerOpacity;

  // Inner pulse ring
  late AnimationController _innerPulse;
  late Animation<double> _innerScale;
  late Animation<double> _innerOpacity;

  @override
  void initState() {
    super.initState();
    if (widget.initialResult != null) {
      _result = widget.initialResult;
      _state = _AnalyzeState.result;
      _audioUrl = widget.initialResult!.audioUrl;
      unawaited(_restoreInitialAudio());
    }

    _outerPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _outerScale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _outerPulse, curve: Curves.easeInOut));
    _outerOpacity = Tween<double>(
      begin: 0.35,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _outerPulse, curve: Curves.easeInOut));

    _innerPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _innerPulse.repeat();
    });
    _innerScale = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _innerPulse, curve: Curves.easeInOut));
    _innerOpacity = Tween<double>(
      begin: 0.35,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _innerPulse, curve: Curves.easeInOut));

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
  }

  @override
  void dispose() {
    _outerPulse.dispose();
    _innerPulse.dispose();
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    final audioPath = _audioPath;
    if (audioPath != null) unawaited(_recognizer.cleanupFile(audioPath));
    _recorder.dispose();
    super.dispose();
  }

  // ── Flow ─────────────────────────────────────────────────────────

  Future<void> _startAnalysis() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    final hasPermission = await _recorder.requestPermission();
    if (!hasPermission) {
      _showError('Microphone permission denied. Please enable it in Settings.');
      return;
    }

    setState(() {
      _state = _AnalyzeState.recording;
      _recordingSeconds = 0;
      _errorMessage = null;
    });

    final started = await _recorder.startRecording();
    if (!started) {
      _showError('Could not start recording. Please try again.');
      return;
    }

    _amplitudeSubscription = _recorder.amplitudeStream.listen((amplitude) {
      if (!mounted || _state != _AnalyzeState.recording) return;
      final db = amplitude.current;
      final level = db.isFinite && db > -55
          ? ((db + 55) / 35).clamp(0.0, 1.0).toDouble()
          : 0.0;
      setState(() => _amplitudeLevel = level);
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _recordingSeconds++);
    });
  }

  Future<void> _finishAndSend() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final audioPath = await _recorder.stopRecording();

    setState(() => _state = _AnalyzeState.analyzing);

    try {
      final result = await _recognizer.analyzeSong(audioPath ?? '');

      if (!mounted) return;
      await context.read<AppState>().addIdentification(result);
      _audioPath = audioPath;
      _audioUrl = null;
      if (audioPath != null) {
        await _audioPlayer.setFilePath(audioPath);
      }

      setState(() {
        _result = result;
        _state = _AnalyzeState.result;
      });
    } catch (e) {
      await _recognizer.cleanupFile(audioPath);
      _showError(e.toString().replaceAll('RecognitionException: ', ''));
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _state = _AnalyzeState.error;
    });
  }

  void _reset() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _recorder.cancelRecording();
    final audioPath = _audioPath;
    _audioPath = null;
    _audioUrl = null;
    unawaited(_audioPlayer.stop());
    if (audioPath != null) unawaited(_recognizer.cleanupFile(audioPath));
    _amplitudeLevel = 0.05;
    setState(() {
      _state = _AnalyzeState.idle;
      _result = null;
      _errorMessage = null;
    });
  }

  Future<void> _togglePlayback() async {
    if (_audioPath == null && _audioUrl == null) return;
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.seek(Duration.zero);
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      _showError('Could not play the recording: $e');
    }
  }

  Future<void> _restoreInitialAudio() async {
    final result = widget.initialResult;
    if (result == null) return;
    final youtubeUrl = result.youtubeUrl ??
        result.analysisData['youtube_url']?.toString();
    try {
      String? audioUrl = result.audioUrl;
      if (youtubeUrl != null && youtubeUrl.isNotEmpty) {
        // YouTube stream URLs expire, so resolve a fresh one every time a
        // saved/history analysis is opened.
        audioUrl = await _recognizer.refreshYouTubeAudioUrl(youtubeUrl);
      }
      if (audioUrl == null || audioUrl.isEmpty) return;
      await _audioPlayer.setUrl(audioUrl);
      if (!mounted) return;
      setState(() {
        _audioUrl = audioUrl;
        _result = result.copyWith(audioUrl: audioUrl);
      });
    } catch (_) {
      // Keep the analysis view usable even if YouTube cannot refresh its
      // temporary stream URL right now.
    }
  }

  Future<void> _runTestAudio() async {
    String? testAudioPath;
    try {
      final audioData = await rootBundle.load('assets/1min.m4a');
      final tempDirectory = await getTemporaryDirectory();
      testAudioPath =
          '${tempDirectory.path}/sonic_pulse_test_1min_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await File(testAudioPath).writeAsBytes(
        audioData.buffer.asUint8List(
          audioData.offsetInBytes,
          audioData.lengthInBytes,
        ),
        flush: true,
      );
      final result = await _recognizer.analyzeSong(testAudioPath);
      await _audioPlayer.stop();
      final previousPath = _audioPath;
      _audioPath = null;
      _audioUrl = null;
      if (previousPath != null) {
        unawaited(_recognizer.cleanupFile(previousPath));
      }
      if (!mounted) {
        await _recognizer.cleanupFile(testAudioPath);
        return;
      }
      _audioPath = testAudioPath;
      await _audioPlayer.setFilePath(testAudioPath);
      setState(() {
        _result = result;
        _errorMessage = null;
        _state = _AnalyzeState.result;
      });
    } catch (e) {
      if (testAudioPath != null) {
        unawaited(_recognizer.cleanupFile(testAudioPath));
      }
      _showError('Could not analyze assets/1min.m4a: $e');
    }
  }

  Future<void> _openYouTubeSearch() async {
    final video = await Navigator.push<YouTubeVideo>(
      context,
      MaterialPageRoute(builder: (_) => const YouTubeSearchScreen()),
    );
    if (video != null && mounted) {
      await _analyzeYouTubeVideo(video);
    }
  }

  Future<void> _analyzeYouTubeVideo(YouTubeVideo video) async {
    setState(() {
      _state = _AnalyzeState.analyzing;
      _errorMessage = null;
    });
    try {
      final result = await _recognizer.analyzeYouTubeVideo(video);
      if (!mounted) return;
      await context.read<AppState>().addIdentification(result);
      await _audioPlayer.stop();
      final previousPath = _audioPath;
      _audioPath = null;
      _audioUrl = result.audioUrl;
      if (previousPath != null) {
        unawaited(_recognizer.cleanupFile(previousPath));
      }
      if (_audioUrl != null && _audioUrl!.isNotEmpty) {
        await _audioPlayer.setUrl(_audioUrl!);
      }
      setState(() {
        _result = result;
        _state = _AnalyzeState.result;
      });
    } catch (error) {
      _showError(error.toString().replaceAll('RecognitionException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _buildBody(),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((_audioPath != null || _audioUrl != null) && _result != null)
            _AnalysisMiniPlayer(
              player: _audioPlayer,
              isPlaying: _isPlaying,
              onPlayPause: _togglePlayback,
              title: _result!.title,
              artworkUrl: _result!.artworkUrl,
            ),
          AppBottomNavBar(
            currentIndex: 2,
            onTap: (i) {
              if (i == 0) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (_) => false,
                );
              } else if (i == 1) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const FindSongScreen()),
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
    switch (_state) {
      case _AnalyzeState.recording:
        return _RecordingView(
          key: const ValueKey('recording'),
          elapsedSeconds: _recordingSeconds,
          outerScale: _outerScale,
          outerOpacity: _outerOpacity,
          innerScale: _innerScale,
          innerOpacity: _innerOpacity,
          amplitudeLevel: _amplitudeLevel,
          onStop: _finishAndSend,
          onCancel: _reset,
        );
      case _AnalyzeState.analyzing:
        return _AnalyzingView(key: const ValueKey('analyzing'));
      case _AnalyzeState.result:
        return _ResultsView(
          key: const ValueKey('results'),
          result: _result!,
          player: _audioPlayer,
          onReset: _reset,
          onToggleSave: () => context.read<AppState>().toggleSave(_result!),
        );
      case _AnalyzeState.error:
        return _ErrorView(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Unknown error',
          onRetry: _reset,
        );
      case _AnalyzeState.idle:
        return _InitialView(
          key: const ValueKey('initial'),
          outerScale: _outerScale,
          outerOpacity: _outerOpacity,
          innerScale: _innerScale,
          innerOpacity: _innerOpacity,
          onTrigger: _startAnalysis,
          onSearchYouTube: _openYouTubeSearch,
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
        'Analyze Song',
        style: GoogleFonts.sora(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Settings',
          color: AppColors.onSurfaceVariant,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Initial / idle view
// ─────────────────────────────────────────────────────────────

class _InitialView extends StatelessWidget {
  final Animation<double> outerScale;
  final Animation<double> outerOpacity;
  final Animation<double> innerScale;
  final Animation<double> innerOpacity;
  final VoidCallback onTrigger;
  final VoidCallback onSearchYouTube;

  const _InitialView({
    super.key,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerOpacity,
    required this.onTrigger,
    required this.onSearchYouTube,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 18),
          Text(
            'Analyze chords with AI',
            style: GoogleFonts.sora(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'Record a song to identify its chords with AI, or search for a video on YouTube.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: InkWell(
              onTap: onSearchYouTube,
              borderRadius: BorderRadius.circular(16),
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
                    const Icon(Icons.search_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Search YouTube videos',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),

          GestureDetector(
            onTap: onTrigger,
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
                    painter: _AiDashedCirclePainter(
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
                        const Icon(
                          Icons.mic_rounded,
                          color: AppColors.secondary,
                          size: 44,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [8, 14, 10, 13].map((height) {
                            return Container(
                              width: 3,
                              height: height.toDouble(),
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Recording view
// ─────────────────────────────────────────────────────────────

class _AiDashedCirclePainter extends CustomPainter {
  final Color color;

  _AiDashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashCount = 24;
    final sweep = 2 * 3.14159 / dashCount;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AiDashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _LiveAmplitudeWaves extends StatelessWidget {
  final List<double> levels;

  const _LiveAmplitudeWaves({required this.levels});

  @override
  Widget build(BuildContext context) {
    final left = levels.take(6).toList();
    final right = levels.skip(6).take(6).toList();
    return SizedBox(
      width: 304,
      height: 120,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _WaveGroup(levels: left),
          _WaveGroup(levels: right.reversed.toList()),
        ],
      ),
    );
  }
}

class _WaveGroup extends StatelessWidget {
  final List<double> levels;

  const _WaveGroup({required this.levels});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: levels.map((level) {
        return Container(
          width: 3,
          height: 12 + (level * 38),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: AppColors.secondary.withOpacity(0.8),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }).toList(),
    );
  }
}

class _RecordingView extends StatelessWidget {
  final int elapsedSeconds;
  final Animation<double> outerScale;
  final Animation<double> outerOpacity;
  final Animation<double> innerScale;
  final Animation<double> innerOpacity;
  final double amplitudeLevel;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const _RecordingView({
    super.key,
    required this.elapsedSeconds,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerOpacity,
    required this.amplitudeLevel,
    required this.onStop,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.redAccent.withOpacity(0.1),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Text(
                'RECORDING NOW',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.redAccent,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Listening…',
              style: GoogleFonts.sora(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Stop when you have captured enough audio',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
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
                      color: AppColors.surfaceContainerHigh,
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(0.7),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 30,
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
                        Text(
                          '$elapsedSeconds',
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
            const SizedBox(height: 28),
            Text(
              'RECORDING AUDIO',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Keep the sound near your phone',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onStop,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.redAccent.withOpacity(0.15),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.55)),
                ),
                child: Text(
                  'STOP & ANALYZE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onCancel,
              child: Text(
                'CANCEL',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceVariant,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Analyzing spinner
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
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'AI PROCESSING',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Detecting chords in your recording…',
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
              'Analysis Failed',
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
                    color: AppColors.primary,
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
// Results view (real data)
// ─────────────────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  final TrackResult result;
  final AudioPlayer player;
  final VoidCallback onReset;
  final VoidCallback onToggleSave;

  const _ResultsView({
    super.key,
    required this.result,
    required this.player,
    required this.onReset,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(result);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Track identification bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.surfaceContainer.withOpacity(0.8),
              border: Border.all(
                color: AppColors.outlineVariant.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.surfaceContainerHighest,
                    border: Border.all(
                      color: AppColors.outlineVariant.withOpacity(0.3),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: result.artworkUrl?.isNotEmpty == true
                      ? Image.network(
                          result.artworkUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.album_rounded,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        )
                      : const Icon(
                          Icons.album_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                ),
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
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        result.artist,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          _TrackMetric(
                            label: 'BPM',
                            value: result.bpm > 0 ? '${result.bpm}' : '—',
                          ),
                          const SizedBox(width: 12),
                          _TrackMetric(
                            label: 'TIME',
                            value: result.timeSig,
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: result.key == '—'
                                ? null
                                : () => Navigator.push(
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
                            child: _TrackMetric(
                              label: 'KEY',
                              value: result.key,
                              accent: result.key != '—',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Bookmark
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
                            : AppColors.outlineVariant.withOpacity(0.3),
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
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ask AI is coming soon.')),
              ),
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
          const SizedBox(height: 14),

          // The beat/chord grid is the primary analysis result.
          _ChordProgressionCard(result: result, player: player),
          const SizedBox(height: 14),

          _AnalysisDetailsCard(result: result),
          const SizedBox(height: 14),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onReset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: AppColors.surfaceContainer,
                      border: Border.all(
                        color: AppColors.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.refresh_rounded,
                          color: AppColors.onSurface,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'ANALYZE NEW',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onToggleSave,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: saved
                          ? AppColors.primary.withOpacity(0.15)
                          : AppColors.primaryContainer,
                      border: saved
                          ? Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                            )
                          : null,
                      boxShadow: saved
                          ? null
                          : [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 16,
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_outline_rounded,
                          color: saved
                              ? AppColors.primary
                              : AppColors.onPrimaryContainer,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          saved ? 'SAVED' : 'SAVE TRACK',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: saved
                                ? AppColors.primary
                                : AppColors.onPrimaryContainer,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;

  const _TrackMetric({
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent ? AppColors.secondary : AppColors.primary,
            ),
          ),
          TextSpan(
            text: label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result sub-cards ───────────────────────────────────────────

class _HarmonicCard extends StatelessWidget {
  final TrackResult result;
  const _HarmonicCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HARMONICS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                  letterSpacing: 1.0,
                ),
              ),
              const Icon(
                Icons.music_note_rounded,
                color: AppColors.primary,
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.key,
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          Row(
            children: [
              Text(
                'Camelot: ',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                result.camelot,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.outlineVariant.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Confidence',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
                Text(
                  result.confidencePercent,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
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

class _RhythmCard extends StatelessWidget {
  final TrackResult result;
  const _RhythmCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RHYTHM',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                  letterSpacing: 1.0,
                ),
              ),
              const Icon(
                Icons.speed_rounded,
                color: AppColors.secondary,
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: result.bpm > 0 ? '${result.bpm} ' : '— ',
                  style: GoogleFonts.sora(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
                TextSpan(
                  text: 'BPM',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                'Time Sig: ',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                result.timeSig,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.outlineVariant.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Album',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
                Flexible(
                  child: Text(
                    result.album.isEmpty ? '—' : result.album,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
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

class _ChordProgressionCard extends StatelessWidget {
  final TrackResult result;
  final AudioPlayer player;
  const _ChordProgressionCard({required this.result, required this.player});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                color: AppColors.primary,
                size: 17,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CHORD GRID',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Open full screen',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _FullScreenChordGrid(
                      result: result,
                      player: player,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_hasChordData)
            _ChordTimelineGrid(result: result, player: player)
          else
            Text(
              'No chords detected',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasChordData =>
      result.chordSegments.isNotEmpty ||
      result.chordsByBeat.isNotEmpty ||
      result.chords.isNotEmpty;
}

class _ChordTimelineGrid extends StatelessWidget {
  final TrackResult result;
  final AudioPlayer player;
  const _ChordTimelineGrid({required this.result, required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        return _buildGrid(
          context,
          snapshot.data?.inMilliseconds.toDouble() ?? 0,
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, double positionMilliseconds) {
    final position = positionMilliseconds / 1000;
    final beats = result.beats.isNotEmpty
        ? result.beats
        : result.chordSegments.isNotEmpty
        ? result.chordSegments.map((segment) => segment.start).toList()
        : List<double>.generate(
            result.chordsByBeat.isNotEmpty
                ? result.chordsByBeat.length
                : result.chords.length,
            (index) => index * _fallbackBeatLength,
          );
    final beatsPerBar = int.tryParse(result.timeSig.split('/').first) ?? 4;
    final beatsPerRow = switch (beatsPerBar) {
      2 => 8,
      3 => 9,
      4 => 8,
      6 => 6,
      _ => beatsPerBar > 0 ? beatsPerBar * 2 : 8,
    };
    final chordChanges = List<String?>.filled(beats.length, null);
    if (result.chordsByBeat.length == beats.length) {
      for (var index = 0; index < beats.length; index++) {
        chordChanges[index] = result.chordsByBeat[index];
      }
    } else {
      for (final segment in result.chordSegments) {
        if (beats.isEmpty) break;
        var nearestBeat = 0;
        var nearestDistance = double.infinity;
        for (var index = 0; index < beats.length; index++) {
          final distance = (beats[index] - segment.start).abs();
          if (distance < nearestDistance) {
            nearestBeat = index;
            nearestDistance = distance;
          }
        }
        chordChanges[nearestBeat] = segment.chord == 'N' ? '' : segment.chord;
      }
    }
    final cells = <_ChordGridCellData>[];
    var currentChord = '';
    var previousDisplayedChord = '';
    for (var index = 0; index < beats.length; index++) {
      final time = beats[index];
      if (chordChanges[index] != null) {
        currentChord = chordChanges[index]!;
      }
      final displayChord = currentChord == previousDisplayedChord
          ? ''
          : currentChord;
      previousDisplayedChord = currentChord;
      final nextBeat = index + 1 < beats.length
          ? beats[index + 1]
          : (result.duration > time ? result.duration : time + _fallbackBeatLength);
      cells.add(
        _ChordGridCellData(
          chord: displayChord,
          active: position >= time && position < nextBeat,
          onTap: () =>
              player.seek(Duration(milliseconds: (time * 1000).round())),
        ),
      );
    }
    final bars = <List<_ChordGridCellData>>[];
    for (var index = 0; index < cells.length; index += beatsPerRow) {
      bars.add(
        cells.sublist(index, (index + beatsPerRow).clamp(0, cells.length)),
      );
    }

    if (bars.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No chord timeline available',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...bars.asMap().entries.map((entry) {
          final bar = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              bottom: entry.key == bars.length - 1 ? 0 : 8,
            ),
            child: _ChordGridRow(
              cells: bar,
              beatsPerBar: beatsPerBar,
              beatsPerLine: beatsPerRow,
            ),
          );
        }),
      ],
    );
  }

  static const _fallbackBeatLength = 0.5;
}

class _ChordGridCellData {
  final String chord;
  final bool active;
  final VoidCallback? onTap;

  const _ChordGridCellData({
    required this.chord,
    this.active = false,
    this.onTap,
  });
}

class _ChordGridRow extends StatelessWidget {
  final List<_ChordGridCellData> cells;
  final int beatsPerBar;
  final int beatsPerLine;

  const _ChordGridRow({
    required this.cells,
    required this.beatsPerBar,
    required this.beatsPerLine,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        const dividerWidth = 1.0;
        const dividerSpace = 3.0;
        final dividerCount = beatsPerBar > 0
            ? ((beatsPerLine - 1) / beatsPerBar).floor()
            : 0;
        final totalSpacing =
            gap * (beatsPerLine - 1) +
            (dividerWidth + dividerSpace * 2) * dividerCount;
        final cellSize = (constraints.maxWidth - totalSpacing)
            .clamp(0.0, double.infinity)
            .toDouble() /
            beatsPerLine;

        return SizedBox(
          height: cellSize,
          child: Row(
            children: [
              for (var index = 0; index < cells.length; index++) ...[
                if (index > 0)
                  index % beatsPerBar == 0
                      ? Container(
                          width: dividerWidth,
                          height: cellSize * 0.8,
                          margin: const EdgeInsets.symmetric(
                            horizontal: dividerSpace,
                          ),
                          color: AppColors.secondary.withOpacity(0.7),
                        )
                      : const SizedBox(width: gap),
                SizedBox(
                  width: cellSize,
                  height: cellSize,
                  child: _ChordGridCell(cell: cells[index]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChordGridCell extends StatelessWidget {
  final _ChordGridCellData cell;

  const _ChordGridCell({required this.cell});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: cell.onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: cell.active
              ? AppColors.primary.withOpacity(0.35)
              : AppColors.primary.withOpacity(0.12),
          border: Border.all(
            color: cell.active
                ? AppColors.secondary
                : AppColors.primary.withOpacity(0.35),
            width: cell.active ? 2 : 1,
          ),
          boxShadow: cell.active
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            cell.chord,
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cell.active ? AppColors.secondary : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenChordGrid extends StatelessWidget {
  final TrackResult result;
  final AudioPlayer player;

  const _FullScreenChordGrid({required this.result, required this.player});

  @override
  Widget build(BuildContext context) {
    Future<void> togglePlayback() async {
      if (player.playing) {
        await player.pause();
      } else {
        if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        await player.play();
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          result.title,
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Close chord grid',
            onPressed: () => Navigator.pop(context),
            color: AppColors.onSurface,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 120),
          child: _ChordTimelineGrid(result: result, player: player),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 104,
          child: StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            initialData: player.playerState,
            builder: (context, snapshot) => _AnalysisMiniPlayer(
              player: player,
              isPlaying: snapshot.data?.playing ?? player.playing,
              onPlayPause: togglePlayback,
              title: result.title,
              artworkUrl: result.artworkUrl,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalysisDetailsCard extends StatelessWidget {
  final TrackResult result;
  const _AnalysisDetailsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ANALYSIS DATA',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.outline,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          _dataLine('Beat model', result.beatModel),
          _dataLine('Chord model', result.chordModel),
          if (_analysisTime(result.analysisData) case final seconds?)
            _dataLine('Analysis time', '${seconds.toStringAsFixed(2)} sec'),
        ],
      ),
    );
  }

  double? _analysisTime(Map<String, dynamic> data) {
    for (final key in const [
      'analysis_time',
      'total_processing_time',
      'processing_time',
      'elapsed_time',
    ]) {
      final value = data[key];
      if (value is num && value > 0) return value.toDouble();
    }
    for (final value in data.values) {
      if (value is Map) {
        final nested = _analysisTime(value.cast<String, dynamic>());
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Widget _dataLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisMiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final String title;
  final String? artworkUrl;

  const _AnalysisMiniPlayer({
    required this.player,
    required this.isPlaying,
    required this.onPlayPause,
    required this.title,
    required this.artworkUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.primary.withOpacity(0.14),
              border: Border.all(color: AppColors.primary.withOpacity(0.35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: artworkUrl?.isNotEmpty == true
                ? Image.network(
                    artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.music_note_rounded,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(
                    Icons.music_note_rounded,
                    color: AppColors.primary,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  initialData: player.position,
                  builder: (context, positionSnapshot) {
                    return StreamBuilder<Duration?>(
                      stream: player.durationStream,
                      initialData: player.duration,
                      builder: (context, durationSnapshot) {
                        final position = positionSnapshot.data ?? Duration.zero;
                        final duration = durationSnapshot.data ?? Duration.zero;
                        final progress = duration.inMilliseconds == 0
                            ? 0.0
                            : (position.inMilliseconds /
                                      duration.inMilliseconds)
                                  .clamp(0.0, 1.0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.outlineVariant
                                    .withOpacity(0.25),
                                thumbColor: AppColors.primary,
                              ),
                              child: Slider(
                                min: 0,
                                max: 1,
                                value: progress,
                                onChanged: duration.inMilliseconds == 0
                                    ? null
                                    : (value) => player.seek(
                                        Duration(
                                          milliseconds: (value *
                                                  duration.inMilliseconds)
                                              .round(),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_formatAnalysisDuration(position)} / ${_formatAnalysisDuration(duration)}',
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
            visualDensity: VisualDensity.compact,
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

String _formatAnalysisDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _MoodTagsCard extends StatelessWidget {
  final TrackResult result;
  const _MoodTagsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MOOD & GENRE TAGS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                  letterSpacing: 1.0,
                ),
              ),
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.secondary,
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result.mood.isEmpty)
            Text(
              'No mood tags detected',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            )
          else
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
                      color: AppColors.secondary.withOpacity(0.3),
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
    );
  }
}
