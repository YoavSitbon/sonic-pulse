import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../theme/app_colors.dart';

/// Compact playback bar shared by analyzed songs, identified songs, and the
/// key-theory screens.
class SongPlayBar extends StatelessWidget {
  final AudioPlayer player;
  final String title;
  final String? artworkUrl;
  final bool compact;

  const SongPlayBar({
    super.key,
    required this.player,
    required this.title,
    this.artworkUrl,
    this.compact = false,
  });

  Future<void> _togglePlayback() async {
    if (player.playing) {
      await player.pause();
    } else {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      initialData: player.playerState,
      builder: (context, stateSnapshot) {
        final isPlaying = stateSnapshot.data?.playing ?? player.playing;
        return Container(
          margin: EdgeInsets.all(compact ? 6 : 8),
          padding: EdgeInsets.fromLTRB(
            10,
            compact ? 5 : 7,
            10,
            compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
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
              _Artwork(url: artworkUrl, compact: compact),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.sora(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    StreamBuilder<Duration>(
                      stream: player.positionStream,
                      initialData: player.position,
                      builder: (context, positionSnapshot) {
                        final position = positionSnapshot.data ?? Duration.zero;
                        return StreamBuilder<Duration?>(
                          stream: player.durationStream,
                          initialData: player.duration,
                          builder: (context, durationSnapshot) {
                            final duration =
                                durationSnapshot.data ?? Duration.zero;
                            final progress = duration.inMilliseconds == 0
                                ? 0.0
                                : (position.inMilliseconds /
                                          duration.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                      .toDouble();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 4,
                                    ),
                                    overlayShape: RoundSliderOverlayShape(
                                      overlayRadius: compact ? 8 : 9,
                                    ),
                                    activeTrackColor: AppColors.primary,
                                    inactiveTrackColor: AppColors.outlineVariant
                                        .withOpacity(0.25),
                                    thumbColor: AppColors.primary,
                                  ),
                                  child: Slider(
                                    value: progress,
                                    min: 0,
                                    max: 1,
                                    onChanged: duration.inMilliseconds == 0
                                        ? null
                                        : (value) => player.seek(
                                            Duration(
                                              milliseconds:
                                                  (value *
                                                          duration
                                                              .inMilliseconds)
                                                      .round(),
                                            ),
                                          ),
                                  ),
                                ),
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
                visualDensity: VisualDensity.compact,
                constraints: BoxConstraints.tightFor(
                  width: compact ? 32 : 36,
                  height: compact ? 32 : 36,
                ),
                padding: EdgeInsets.zero,
                onPressed: _togglePlayback,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: compact ? 23 : 26,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? url;
  final bool compact;

  const _Artwork({this.url, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 30 : 34,
      height: compact ? 30 : 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        color: AppColors.primary.withOpacity(0.14),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url?.isNotEmpty == true
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.music_note_rounded,
                color: AppColors.primary,
              ),
            )
          : const Icon(Icons.music_note_rounded, color: AppColors.primary),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString();
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
