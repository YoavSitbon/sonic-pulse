SonicPulse Flutter App Implementation
Overview
Implement the SonicPulse music recognition app UI in Flutter, faithfully translating the 3 Stitch design screens into a polished Flutter app. No backend functionality — all UI/navigation only (mock data).

Screens to Implement
Home Screen (sonicpulse_home) — Main hub with stats, action cards, recent identifications
Find Existing Song (find_existing_song_standard) — Acoustic fingerprint screen with listening sphere → result card
AI Song Analyzer (ai_song_analyzer) — AI analysis screen with mic button → detailed results (key, BPM, chords, stems, mood tags)
Design System
Color palette: Dark nocturnal theme (#0f131c background, #c0c1ff primary, #4cd7f6 secondary, #ddb7ff tertiary)
Fonts: Sora (headlines), Plus Jakarta Sans (body), Space Grotesk (labels/metrics) — via google_fonts package
Animations: Pulsing rings, wave bars, bounce animations
Icons: Material Icons (built-in Flutter) for all UI icons
Proposed Changes
Dependencies — pubspec.yaml
[MODIFY] 
pubspec.yaml
Add google_fonts: ^6.2.1
App Structure — lib/
[MODIFY] 
main.dart
Set up MaterialApp with dark theme using the Nocturnal Resonance color palette
Set home to HomeScreen
Configure ThemeData with all custom colors, typography
[NEW] lib/theme/app_theme.dart
Central theme definition with all design tokens (colors, text styles, border radii, spacing)
[NEW] lib/theme/app_colors.dart
All color constants from the Nocturnal Resonance design system
[NEW] lib/widgets/bottom_nav_bar.dart
Shared bottom navigation bar (Home, Identify, Analyzer, Library)
Handles active tab indicator
[NEW] lib/widgets/wave_bars.dart
Animated equalizer wave bar widget (reusable, used in Home and Analyzer)
[NEW] lib/screens/home_screen.dart
Top app bar with SonicPulse logo + settings icon
"Live Acoustic Hub" status badge + animated wave bars
Hero heading: "What's playing around you?"
Quick stats bento (Scans Today, Saved Tracks)
Two action cards: "Find Existing Song" and "AI Song Analyzer" (navigate on tap)
Recent Identifications list (3 mock tracks with album art placeholder, title, artist, BPM, timestamp)
[NEW] lib/screens/find_song_screen.dart
Two states: Listening and Result
Listening: animated concentric pulse rings with mic button hero sphere, tap-to-listen prompt, frequency indicator pill
Result: glassmorphic card with track info (Midnight City / M83), acoustic chips (Key, Tempo, Confidence), waveform scrubber, quick action buttons (Spotify, Apple, Share, Lyrics), "Scan Another" button
[NEW] lib/screens/ai_analyzer_screen.dart
Two states: Initial and Results
Initial: animated pulse rings + mic button, wave bounce bars, "Record for AI Analysis" text, simulate button
Results: track identification bar (After Dark / Mr. Kitty), Key+Harmonic card, Rhythm+Tempo card, chord progression grid (Dm/Bb/F/C), stem matrix with progress bars (Synths/Vocals/Bass/Drums), mood tags (Darkwave/Nostalgic/Atmospheric/Reverb-Heavy), action buttons (Analyze New, Export Report)
Verification Plan
Automated Tests
flutter analyze — no lint errors
flutter build apk --debug — successful compile
Manual Verification
Run flutter run and verify:
All 3 screens render correctly on a device/emulator
Animations (pulse rings, wave bars, bouncing bars) run smoothly
Navigation between screens works (bottom nav + card taps)
State transitions (listening → result) are smooth
Dark theme looks faithful to the Stitch screenshots
