import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ocean/ocean_page.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/sync_service.dart';

class MindBubbleApp extends ConsumerStatefulWidget {
  const MindBubbleApp({super.key});

  @override
  ConsumerState<MindBubbleApp> createState() => _MindBubbleAppState();
}

class _MindBubbleAppState extends ConsumerState<MindBubbleApp>
    with WidgetsBindingObserver {
  Timer? _periodicSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runAutomaticSync();
    _periodicSync = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _runAutomaticSync(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _runAutomaticSync();
  }

  void _runAutomaticSync() {
    final service = ref.read(syncServiceProvider);
    unawaited(
      service
          .loadConfig()
          .then((config) {
            if (config != null) return service.syncNow();
          })
          .catchError((Object _) {
            // Background failures are retried at the next local change, resume, or
            // periodic interval. Explicit setup displays errors to the user.
          }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicSync?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeControllerProvider);
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7F91),
      brightness: Brightness.dark,
      surface: const Color(0xFF0B2531),
    );
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
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
