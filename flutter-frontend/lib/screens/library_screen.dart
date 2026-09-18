import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav_bar.dart';
import '../models/track_result.dart';
import '../providers/app_state.dart';
import 'home_screen.dart';
import 'find_song_screen.dart';
import 'ai_analyzer_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      appBar: AppBar(
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
          'Library',
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        centerTitle: true,
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            // Tab bar
            Container(
              color: AppColors.surface.withOpacity(0.85),
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.onSurfaceVariant,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
                tabs: const [
                  Tab(text: 'SAVED'),
                  Tab(text: 'HISTORY'),
                ],
              ),
            ),
            // Tab views
            Expanded(
              child: TabBarView(
                children: [
                  _SavedTab(),
                  _HistoryTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 3,
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
          } else if (i == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AiAnalyzerScreen()),
            );
          }
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Saved tab
// ─────────────────────────────────────────────────────────────

class _SavedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final saved = state.savedTracks;
        if (saved.isEmpty) {
          return _EmptyState(
            icon: Icons.bookmark_outline_rounded,
            title: 'No saved tracks',
            subtitle: 'Bookmark a song after identifying it to save it here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          itemCount: saved.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _LibraryCard(
            result: saved[i],
            accentColor: AppColors.primary,
            onRemove: () => state.toggleSave(saved[i]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// History tab
// ─────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final history = state.identifiedTracks;
        if (history.isEmpty) {
          return _EmptyState(
            icon: Icons.history_rounded,
            title: 'No history yet',
            subtitle: 'Every song you identify will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          itemCount: history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final colors = [
              AppColors.secondary,
              AppColors.primary,
              AppColors.tertiary,
              AppColors.secondaryFixedDim,
              AppColors.primaryFixedDim,
            ];
            return _LibraryCard(
              result: history[i],
              accentColor: colors[i % colors.length],
              onToggleSave: () => state.toggleSave(history[i]),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Library card
// ─────────────────────────────────────────────────────────────

class _LibraryCard extends StatelessWidget {
  final TrackResult result;
  final Color accentColor;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleSave;

  const _LibraryCard({
    required this.result,
    required this.accentColor,
    this.onRemove,
    this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceContainerLow.withOpacity(0.9),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // Album art
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withOpacity(0.3),
                  AppColors.surfaceContainerHighest,
                ],
              ),
            ),
            child: result.artworkUrl == null
                ? Icon(Icons.music_note_rounded, color: accentColor, size: 24)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      result.artworkUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.music_note_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  result.artist,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _Chip(label: result.key, color: accentColor),
                    const SizedBox(width: 6),
                    _Chip(label: '${result.bpm} BPM', color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      result.timeAgo,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action button
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerHigh,
                  border: Border.all(
                      color: AppColors.outlineVariant.withOpacity(0.3)),
                ),
                child: const Icon(Icons.bookmark_remove_rounded,
                    color: AppColors.primary, size: 16),
              ),
            )
          else if (onToggleSave != null)
            GestureDetector(
              onTap: onToggleSave,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: result.isSaved
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.surfaceContainerHigh,
                  border: Border.all(
                    color: result.isSaved
                        ? AppColors.primary.withOpacity(0.4)
                        : AppColors.outlineVariant.withOpacity(0.3),
                  ),
                ),
                child: Icon(
                  result.isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                  color: result.isSaved
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.outline, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.outline,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
