import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/youtube_video.dart';
import '../services/recognition_service.dart';
import '../theme/app_colors.dart';

class YouTubeSearchScreen extends StatefulWidget {
  const YouTubeSearchScreen({super.key});

  @override
  State<YouTubeSearchScreen> createState() => _YouTubeSearchScreenState();
}

class _YouTubeSearchScreenState extends State<YouTubeSearchScreen> {
  final _controller = TextEditingController();
  final _recognizer = RecognitionService();
  YouTubeSearchResults _results = const YouTubeSearchResults(
    videos: [],
    shorts: [],
  );
  bool _showShorts = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _recognizer.searchYouTube(
        query,
        shorts: _showShorts,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceAll('RecognitionException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = _showShorts ? _results.shorts : _results.videos;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface.withOpacity(0.85),
        elevation: 0,
        title: Text(
          'Search YouTube',
          style: GoogleFonts.sora(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (value) {
                  final query = value.trim();
                  if (query.isNotEmpty) _search(query);
                },
                textInputAction: TextInputAction.search,
                style: GoogleFonts.plusJakartaSans(color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search YouTube',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: AppColors.onSurfaceVariant,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.primary,
                  ),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _controller.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _results = const YouTubeSearchResults(
                                videos: [],
                                shorts: [],
                              );
                              _error = null;
                            });
                          },
                          icon: const Icon(Icons.clear_rounded),
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: _searchBorder(),
                  enabledBorder: _searchBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _CategoryButton(
                      label: 'Videos',
                      selected: !_showShorts,
                      onTap: () => _changeCategory(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CategoryButton(
                      label: 'Shorts',
                      selected: _showShorts,
                      onTap: () => _changeCategory(true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent))
              else if (_controller.text.isEmpty)
                const Expanded(
                  child: Center(child: Text('Search for a YouTube video.')),
                )
              else if (!_loading && videos.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      _showShorts ? 'No Shorts found.' : 'No videos found.',
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: videos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _VideoTile(
                      video: videos[index],
                      onTap: () => Navigator.pop(context, videos[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeCategory(bool shorts) {
    if (_showShorts == shorts) return;
    setState(() => _showShorts = shorts);
  }

  OutlineInputBorder _searchBorder() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: AppColors.outlineVariant.withOpacity(0.5)),
  );
}

class _CategoryButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? AppColors.primary.withOpacity(0.18)
              : AppColors.surfaceContainer,
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withOpacity(0.45),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  final YouTubeVideo video;
  final VoidCallback onTap;

  const _VideoTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.surfaceContainer,
          border: Border.all(color: AppColors.outlineVariant.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(
                video.thumbnail,
                width: 100,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 100,
                  height: 58,
                  color: AppColors.surfaceContainerHigh,
                  child: const Icon(Icons.video_library_outlined),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            const Icon(Icons.play_circle_outline, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
