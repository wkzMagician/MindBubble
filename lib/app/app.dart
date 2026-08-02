import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/ocean/ocean_page.dart';
import '../l10n/app_localizations.dart';

class MindBubbleApp extends StatelessWidget {
  const MindBubbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7F91),
      brightness: Brightness.dark,
      surface: const Color(0xFF0B2531),
    );
    return MaterialApp(
      title: '浮念',
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFF061620),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF0B2733),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF123542),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF65D7CB), width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const OceanPage(),
    );
  }
}
