import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ocean/ocean_page.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../services/bubble_document_store.dart';
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
  late Future<void> _initialSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(documentStoreRevisionProvider, (_, next) {
      if (next.hasValue) ref.read(syncServiceProvider).scheduleSync();
    });
    _initialSync = _syncIfConfigured();
    _periodicSync = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _runAutomaticSync(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _runAutomaticSync();
  }

  Future<void> _syncIfConfigured() async {
    final service = ref.read(syncServiceProvider);
    final config = await service.loadConfig();
    if (config != null) await service.syncNow();
  }

  void _runAutomaticSync() {
    unawaited(
      _syncIfConfigured().catchError((Object _) {
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
      home: FutureBuilder<void>(
        future: _initialSync,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _SyncBootstrapPage();
          }
          return _BootstrapResult(
            error: snapshot.error,
            onRetry: () {
              setState(() => _initialSync = _syncIfConfigured());
            },
          );
        },
      ),
    );
  }
}

class _SyncBootstrapPage extends StatelessWidget {
  const _SyncBootstrapPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(context.l10n.initialSync),
        ],
      ),
    ),
  );
}

class _BootstrapResult extends StatelessWidget {
  const _BootstrapResult({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const OceanPage(),
      if (error != null)
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(context.l10n.initialSyncFailed('$error')),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      child: Text(context.l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
