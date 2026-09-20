import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'providers/app_state.dart';
import 'services/http_overrides.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureHttpOverrides();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const SonicPulseApp(),
    ),
  );
}

class SonicPulseApp extends StatelessWidget {
  const SonicPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SonicPulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
