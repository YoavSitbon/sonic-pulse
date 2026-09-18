import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated equalizer wave bars — used in the home screen header
/// and as an idle visualizer throughout the app.
class WaveBars extends StatefulWidget {
  final int barCount;
  final double barWidth;
  final double maxHeight;
  final List<Color>? colors;

  const WaveBars({
    super.key,
    this.barCount = 5,
    this.barWidth = 3,
    this.maxHeight = 18,
    this.colors,
  });

  @override
  State<WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<WaveBars> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  static const List<Duration> _delays = [
    Duration(milliseconds: 0),
    Duration(milliseconds: 200),
    Duration(milliseconds: 350),
    Duration(milliseconds: 120),
    Duration(milliseconds: 280),
    Duration(milliseconds: 450),
    Duration(milliseconds: 80),
    Duration(milliseconds: 320),
    Duration(milliseconds: 160),
    Duration(milliseconds: 400),
  ];

  static const List<int> _durations = [
    1400, 1200, 1550, 1100, 1350, 1250, 1450, 1300, 1050, 1500,
  ];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.barCount, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _durations[i % _durations.length]),
      );
      Future.delayed(_delays[i % _delays.length], () {
        if (mounted) ctrl.repeat(reverse: true);
      });
      return ctrl;
    });

    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultColors = [
      AppColors.primary,
      AppColors.secondary,
      AppColors.primary,
      AppColors.secondaryFixedDim,
      AppColors.primaryFixedDim,
    ];
    final colors = widget.colors ?? defaultColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(widget.barCount, (i) {
        final color = colors[i % colors.length];
        return Padding(
          padding: EdgeInsets.only(right: i < widget.barCount - 1 ? 3 : 0),
          child: AnimatedBuilder(
            animation: _animations[i],
            builder: (_, __) {
              return Container(
                width: widget.barWidth,
                height: widget.maxHeight * _animations[i].value,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(widget.barWidth),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

/// Full-width animated frequency bar visualizer (used inside cards/panels)
class FrequencyBars extends StatefulWidget {
  final int barCount;
  final double height;

  const FrequencyBars({super.key, this.barCount = 8, this.height = 40});

  @override
  State<FrequencyBars> createState() => _FrequencyBarsState();
}

class _FrequencyBarsState extends State<FrequencyBars>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  static const List<Color> _barColors = [
    AppColors.primaryContainer,
    AppColors.secondary,
    AppColors.primary,
    AppColors.secondaryContainer,
    AppColors.tertiary,
    AppColors.primaryFixedDim,
    AppColors.secondary,
    AppColors.primaryContainer,
  ];

  static const List<int> _durations = [1200, 1100, 1300, 900, 1400, 1000, 1300, 1100];
  static const List<int> _delayMs = [100, 400, 200, 600, 300, 500, 150, 350];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.barCount, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _durations[i % _durations.length]),
      );
      Future.delayed(Duration(milliseconds: _delayMs[i % _delayMs.length]), () {
        if (mounted) ctrl.repeat(reverse: true);
      });
      return ctrl;
    });
    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0.1, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (i) {
          final color = _barColors[i % _barColors.length];
          return Padding(
            padding: EdgeInsets.only(right: i < widget.barCount - 1 ? 6 : 0),
            child: AnimatedBuilder(
              animation: _animations[i],
              builder: (_, __) {
                return Container(
                  width: 4,
                  height: widget.height * _animations[i].value,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }
}
