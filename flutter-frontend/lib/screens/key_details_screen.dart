import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../theme/app_colors.dart';

class KeyDetailsScreen extends StatelessWidget {
  final String keyName;
  final String? songTitle;
  final String? artworkUrl;
  final AudioPlayer? player;

  const KeyDetailsScreen({
    super.key,
    required this.keyName,
    this.songTitle,
    this.artworkUrl,
    this.player,
  });

  @override
  Widget build(BuildContext context) {
    final theory = _KeyTheory.fromName(keyName);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface.withOpacity(0.9),
        elevation: 0,
        title: Text(
          'KEY THEORY',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          Text(
            keyName,
            style: GoogleFonts.sora(
              color: AppColors.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (songTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              songTitle!,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _SectionLabel('DIATONIC CHORDS'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 24) / 4;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: theory.chords
                    .map(
                      (chord) => SizedBox(
                        width: cardWidth,
                        child: _ChordTheoryTile(chord: chord),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionLabel('GUITAR NECK'),
              IconButton(
                tooltip: 'Maximize guitar neck',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullScreenNeck(
                      theory: theory,
                      player: player,
                      title: songTitle,
                      artworkUrl: artworkUrl,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded),
                color: AppColors.secondary,
              ),
            ],
          ),
          Text('Standard tuning · frets 0–22', style: GoogleFonts.plusJakartaSans(
            color: AppColors.onSurfaceVariant, fontSize: 11,
          )),
          const SizedBox(height: 12),
          _GuitarNeck(theory: theory),
        ],
      ),
      bottomNavigationBar: player == null
          ? null
          : SafeArea(
              top: false,
              child: SizedBox(
                height: 104,
                child: _KeyMiniPlayer(
                  player: player!,
                  title: songTitle ?? 'Analyzed song',
                  artworkUrl: artworkUrl,
                ),
              ),
            ),
    );
  }
}

class _KeyTheory {
  final String tonic;
  final int tonicPc;
  final bool minor;
  final List<String> notes;
  final List<_DiatonicChord> chords;

  const _KeyTheory({
    required this.tonic,
    required this.tonicPc,
    required this.minor,
    required this.notes,
    required this.chords,
  });

  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F',
    'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];
  static const _roots = <String, int>{
    'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3,
    'E': 4, 'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8,
    'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11,
  };

  factory _KeyTheory.fromName(String value) {
    final match = RegExp(r'^([A-Ga-g](?:#|b)?)\s*(major|minor|maj|min|m)?')
        .firstMatch(value.trim());
    final rootText = match?.group(1) ?? 'C';
    final tonicPc = _roots[rootText[0].toUpperCase() + rootText.substring(1)] ?? 0;
    final minor = {'minor', 'min', 'm'}.contains(match?.group(2)?.toLowerCase());
    final intervals = minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11];
    final roman = minor
        ? ['i', 'ii°', 'III', 'iv', 'v', 'VI', 'VII']
        : ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°'];
    final notes = intervals.map((interval) => _noteNames[(tonicPc + interval) % 12]).toList();
    final chords = <_DiatonicChord>[];
    for (var i = 0; i < notes.length; i++) {
      final symbol = notes[i] + (roman[i].contains('°') ? 'dim' : roman[i].toLowerCase() == roman[i] ? 'm' : '');
      chords.add(_DiatonicChord(degree: roman[i], symbol: symbol, note: notes[i]));
    }
    return _KeyTheory(
      tonic: _noteNames[tonicPc],
      tonicPc: tonicPc,
      minor: minor,
      notes: notes,
      chords: chords,
    );
  }
}

class _DiatonicChord {
  final String degree;
  final String symbol;
  final String note;

  const _DiatonicChord({required this.degree, required this.symbol, required this.note});
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.spaceGrotesk(
        color: AppColors.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _ChordTheoryTile extends StatelessWidget {
  final _DiatonicChord chord;

  const _ChordTheoryTile({required this.chord});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chord.degree,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            chord.symbol,
            style: GoogleFonts.sora(
              color: AppColors.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuitarNeck extends StatelessWidget {
  final _KeyTheory theory;

  const _GuitarNeck({required this.theory});

  static const _tuning = [4, 9, 2, 7, 11, 4];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withOpacity(0.55)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 28),
                for (var fret = 0; fret <= 22; fret++)
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: Text(
                        '$fret',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (var stringIndex = 0; stringIndex < _tuning.length; stringIndex++)
              _GuitarString(
                openPc: _tuning[stringIndex],
                notes: theory.notes,
                tonicPc: theory.tonicPc,
                label: ['E', 'A', 'D', 'G', 'B', 'e'][stringIndex],
              ),
          ],
        ),
      ),
    );
  }
}

class _GuitarString extends StatelessWidget {
  final int openPc;
  final List<String> notes;
  final int tonicPc;
  final String label;

  const _GuitarString({
    required this.openPc,
    required this.notes,
    required this.tonicPc,
    required this.label,
  });

  static const _noteNames = _KeyTheory._noteNames;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (var fret = 0; fret <= 22; fret++)
          _FretCell(
            note: _noteNames[(openPc + fret) % 12],
            active: notes.contains(_noteNames[(openPc + fret) % 12]),
            tonic: (openPc + fret) % 12 == tonicPc,
          ),
      ],
    );
  }
}

class _FretCell extends StatelessWidget {
  final String note;
  final bool active;
  final bool tonic;

  const _FretCell({required this.note, required this.active, required this.tonic});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 17,
            child: Container(height: 1, color: AppColors.outlineVariant),
          ),
          if (active)
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tonic ? AppColors.primaryContainer : AppColors.secondaryContainer,
                border: Border.all(
                  color: tonic ? AppColors.primary : AppColors.secondary,
                  width: tonic ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  note,
                  style: GoogleFonts.spaceGrotesk(
                    color: AppColors.onSurface,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullScreenNeck extends StatefulWidget {
  final _KeyTheory theory;
  final AudioPlayer? player;
  final String? title;
  final String? artworkUrl;

  const _FullScreenNeck({
    required this.theory,
    this.player,
    this.title,
    this.artworkUrl,
  });

  @override
  State<_FullScreenNeck> createState() => _FullScreenNeckState();
}

class _FullScreenNeckState extends State<_FullScreenNeck> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          'GUITAR NECK',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Center(child: _GuitarNeck(theory: widget.theory)),
          if (widget.player != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: _FloatingPlaybackControls(player: widget.player!),
            ),
        ],
      ),
    );
  }
}

class _FloatingPlaybackControls extends StatelessWidget {
  final AudioPlayer player;

  const _FloatingPlaybackControls({required this.player});

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
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? player.playing;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh.withOpacity(0.95),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.primary.withOpacity(0.35)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                padding: EdgeInsets.zero,
                onPressed: _togglePlayback,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 21,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                padding: EdgeInsets.zero,
                onPressed: () => player.stop(),
                icon: const Icon(
                  Icons.stop_rounded,
                  color: AppColors.secondary,
                  size: 19,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KeyMiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final String title;
  final String? artworkUrl;

  const _KeyMiniPlayer({
    required this.player,
    required this.title,
    this.artworkUrl,
  });

  Future<void> _toggle() async {
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
      builder: (context, snapshot) {
        final state = snapshot.data ?? player.playerState;
        return Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: artworkUrl?.isNotEmpty == true
                      ? Image.network(
                          artworkUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.album_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        )
                      : const Icon(
                          Icons.album_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                                : (position.inMilliseconds / duration.inMilliseconds)
                                    .clamp(0.0, 1.0)
                                    .toDouble();
                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 4,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                              ),
                              child: Slider(
                                value: progress,
                                min: 0,
                                max: 1,
                                onChanged: duration.inMilliseconds == 0
                                    ? null
                                    : (value) => player.seek(
                                          Duration(
                                            milliseconds: (value * duration.inMilliseconds)
                                                .round(),
                                          ),
                                        ),
                              ),
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
                onPressed: _toggle,
                icon: Icon(
                  state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 25,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
