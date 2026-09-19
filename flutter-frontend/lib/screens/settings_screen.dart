import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();
  Map<String, List<String>> _selected = {'en': [], 'he': []};
  bool _loaded = false;

  static const _sources = {
    'en': [('ultimate_guitar', 'Ultimate Guitar')],
    'he': [('tab4u', 'Tab4U')],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _storage.loadTabPreferences();
    if (!mounted) return;
    setState(() {
      _selected = {
        'en': saved['en']!.isEmpty ? ['ultimate_guitar'] : saved['en']!,
        'he': saved['he']!.isEmpty ? ['tab4u'] : saved['he']!,
      };
      _loaded = true;
    });
  }

  Future<void> _toggle(String language, String source, bool value) async {
    final updated = Map<String, List<String>>.from(
      _selected.map((key, values) => MapEntry(key, [...values])),
    );
    if (value) {
      updated[language]!.add(source);
    } else {
      updated[language]!.remove(source);
    }
    setState(() => _selected = updated);
    await _storage.saveTabPreferences(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.sora(fontSize: 18)),
        backgroundColor: AppColors.surface,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'TAB SOURCES',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose which sites SonicPulse checks for guitar chords.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                ..._sources.entries.map((entry) {
                  final languageName = entry.key == 'he' ? 'Hebrew' : 'English';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        languageName,
                        style: GoogleFonts.sora(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...entry.value.map((source) {
                        final selected =
                            _selected[entry.key]!.contains(source.$1);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (value) => _toggle(
                            entry.key,
                            source.$1,
                            value ?? false,
                          ),
                          title: Text(source.$2),
                          activeColor: AppColors.primary,
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                      const SizedBox(height: 24),
                    ],
                  );
                }),
              ],
            ),
    );
  }
}
