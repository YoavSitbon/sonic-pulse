import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/wave_bars.dart';
import '../models/track_result.dart';
import '../services/audio_recorder_service.dart';
import '../services/recognition_service.dart';
import '../providers/app_state.dart';
import '../config/api_config.dart';
import 'home_screen.dart';
import 'find_song_screen.dart';
import 'library_screen.dart';

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
  }

  @override
  void dispose() {
    _outerPulse.dispose();
    _innerPulse.dispose();
    _recordingTimer?.cancel();
    _amplitudeSubscription?.cancel();
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
      await _recognizer.cleanupFile(audioPath);

      if (!mounted) return;
      await context.read<AppState>().addIdentification(result);

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
    _amplitudeLevel = 0.05;
    setState(() {
      _state = _AnalyzeState.idle;
      _result = null;
      _errorMessage = null;
    });
  }

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
        'SonicPulse',
        style: GoogleFonts.sora(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: AppColors.surfaceContainerHigh,
            border: Border.all(
              color: AppColors.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                ApiConfig.useMockResponses ? 'MOCK MODE' : 'AI ENGINE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: ApiConfig.useMockResponses
                      ? AppColors.tertiary
                      : AppColors.secondary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
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

  const _InitialView({
    super.key,
    required this.outerScale,
    required this.outerOpacity,
    required this.innerScale,
    required this.innerOpacity,
    required this.onTrigger,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: AppColors.primary.withOpacity(0.1),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    'AI ENGINE READY',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'AI chord analyzer',
                  style: GoogleFonts.sora(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'Record as long as you need, then stop to identify the chord progression.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
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
                  tween: Tween(begin: 0.82, end: 0.82 + amplitudeLevel * 0.38),
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
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
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
  final VoidCallback onReset;
  final VoidCallback onToggleSave;

  const _ResultsView({
    super.key,
    required this.result,
    required this.onReset,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AppState>().isSaved(result);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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
                  child: const Icon(
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
                      Row(
                        children: [
                          Text(
                            result.title,
                            style: GoogleFonts.sora(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: AppColors.secondary.withOpacity(0.1),
                              border: Border.all(
                                color: AppColors.secondary.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              result.confidencePercent,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${result.artist} • ${result.album}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

          // Key + Rhythm bento
          Row(
            children: [
              Expanded(child: _HarmonicCard(result: result)),
              const SizedBox(width: 12),
              Expanded(child: _RhythmCard(result: result)),
            ],
          ),
          const SizedBox(height: 14),

          // Chord progression
          _ChordProgressionCard(result: result),
          const SizedBox(height: 14),

          // Mood tags
          _MoodTagsCard(result: result),
          const SizedBox(height: 16),

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
  const _ChordProgressionCard({required this.result});

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
                'CHORD PROGRESSION',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                  letterSpacing: 1.0,
                ),
              ),
              const Icon(
                Icons.piano_rounded,
                color: AppColors.tertiary,
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result.chords.isEmpty)
            Text(
              'No chords detected',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            )
          else
            Row(
              children: result.chords.map((chord) {
                final idx = result.chords.indexOf(chord);
                final colors = [
                  AppColors.primary,
                  AppColors.secondary,
                  AppColors.tertiary,
                  AppColors.primaryFixedDim,
                ];
                final color = colors[idx % colors.length];
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                      right: idx < result.chords.length - 1 ? 8 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: color.withOpacity(0.1),
                      border: Border.all(color: color.withOpacity(0.3)),
                    ),
                    child: Text(
                      chord,
                      style: GoogleFonts.sora(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                      textAlign: TextAlign.center,
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
