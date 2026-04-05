import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'care_elder_screen.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _darkModePrefKey = 'ui.dark_mode';
  ThemeMode _themeMode = ThemeMode.light;
  int _themeModeWriteVersion = 0;

  @override
  void initState() {
    super.initState();
    _restoreThemeMode();
  }

  Future<void> _restoreThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool(_darkModePrefKey) ?? false;
    if (!mounted) return;
    setState(() {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _setDarkModeEnabled(bool enabled) async {
    final writeVersion = ++_themeModeWriteVersion;

    if (mounted) {
      setState(() {
        _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    if (writeVersion != _themeModeWriteVersion) {
      return;
    }

    await prefs.setBool(_darkModePrefKey, enabled);
  }

  @override
  Widget build(BuildContext context) {
    const goldSeed = Color(0xFFFFCC33);
    const warmLightBackground = Color(0xFFF8F2E3);
    const warmDarkBackground = Color(0xFF121212);
    final lightScheme = ColorScheme.fromSeed(
      seedColor: goldSeed,
      brightness: Brightness.light,
      surface: warmLightBackground,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: goldSeed,
      brightness: Brightness.dark,
      surface: warmDarkBackground,
    );

    return MaterialApp(
      title: 'CareElder',
       debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: warmLightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: goldSeed,
          foregroundColor: Colors.black87,
          centerTitle: true,
          elevation: 0,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF8A6A00)),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.96),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) return goldSeed;
            return Colors.grey.shade300;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return goldSeed.withValues(alpha: 0.35);
            }
            return Colors.grey.shade400;
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          filled: true,
          fillColor: Colors.white,
          labelStyle: TextStyle(color: lightScheme.onSurface),
          hintStyle: TextStyle(
            color: lightScheme.onSurface.withValues(alpha: 0.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: goldSeed.withValues(alpha: 0.26)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: goldSeed, width: 1.6),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: goldSeed,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: lightScheme.onSurface,
            side: BorderSide(color: goldSeed.withValues(alpha: 0.55)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: darkScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: warmDarkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1B16),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1B1B1B),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFF0D487)),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          filled: true,
          fillColor: const Color(0xFF222222),
          labelStyle: TextStyle(
            color: darkScheme.onSurface.withValues(alpha: 0.9),
          ),
          hintStyle: TextStyle(
            color: darkScheme.onSurface.withValues(alpha: 0.7),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: goldSeed.withValues(alpha: 0.28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: goldSeed, width: 1.6),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: goldSeed,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: CareElderScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleDarkMode: (enabled) {
          _setDarkModeEnabled(enabled);
        },
      ),
    );
  }
}
