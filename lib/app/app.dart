import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ocean/ocean_page.dart';
import '../repositories/bubble_repository.dart';
import '../services/reminder_runtime.dart';
import '../services/reminder_settings.dart';
import '../services/bubble_document_store.dart';
import '../widgets/bubble_detail_dialog.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../services/locale_service.dart';
import '../services/sync_service.dart';
import '../services/visual_theme_service.dart';

class StartupBootstrap extends StatelessWidget {
  const StartupBootstrap({super.key, required this.initialize});

  final Future<Widget> initialize;

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: initialize,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return StartupFailureApp(
          error: snapshot.error!,
          stackTrace: snapshot.stackTrace ?? StackTrace.empty,
        );
      }
      if (snapshot.connectionState != ConnectionState.done ||
          !snapshot.hasData) {
        return const _StartupLoadingApp();
      }
      return snapshot.data!;
    },
  );
}

class _StartupLoadingApp extends StatelessWidget {
  const _StartupLoadingApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const Scaffold(body: Center(child: CircularProgressIndicator())),
  );
}

class MindBubbleApp extends ConsumerStatefulWidget {
  const MindBubbleApp({super.key});

  @override
  ConsumerState<MindBubbleApp> createState() => _MindBubbleAppState();
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            'MindBubble 启动失败\n\n$error\n\n$stackTrace',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

class _MindBubbleAppState extends ConsumerState<MindBubbleApp>
    with WidgetsBindingObserver {
  late Future<void> _initialSync;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _launchHandled = false;

  @override
  void initState() {
    super.initState();
    _initialSync = _initializeSyncFacade();
    WidgetsBinding.instance.addObserver(this);
    ref.read(reminderPlatformProvider).onOpen = _showReminderBubble;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _updateReminders();
      final id = await ref.read(reminderPlatformProvider).consumeLaunchBubble();
      if (id != null && !_launchHandled) {
        _launchHandled = true;
        _showReminderBubble(id);
      }
    });
  }

  @override
  void dispose() {
    ref.read(reminderPlatformProvider).onOpen = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refill OS notification queue without resetting desktop timer cadence.
      ref.read(reminderRuntimeProvider).refreshMobileSchedule();
    }
  }

  Future<void> _updateReminders() async {
    if (!mounted) return;
    await ref
        .read(reminderRuntimeProvider)
        .configure(
          ref.read(reminderSettingsProvider),
          redNote: ref.read(visualThemeProvider) == VisualTheme.redNote,
        );
  }

  Future<void> _showReminderBubble(String bubbleId) async {
    // This is deliberately separate from homeRefreshVersionProvider.
    if (!mounted) return;
    final bubble = await ref.read(bubbleRepositoryProvider).getById(bubbleId);
    if (bubble == null || !mounted) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showReminderBubble(bubbleId),
      );
      return;
    }
    await showDialog<void>(
      context: navigator.context,
      builder: (_) => BubbleDetailDialog(
        bubble: bubble,
        documentStore: ref.read(bubbleDocumentStoreProvider),
        onFrequencyChanged: (frequency) => ref
            .read(bubbleRepositoryProvider)
            .updateFrequency(bubble.id, frequency),
      ),
    );
  }

  // Dartloom owns startup, resume, connectivity, polling, retry, and
  // local-write triggers. The app only performs compatibility migrations and
  // exposes the configured profile to the existing UI.
  Future<void> _initializeSyncFacade() async {
    final sync = ref.read(syncServiceProvider);
    final config = await sync.loadConfig();
    if (config != null) await sync.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reminderSettingsProvider, (_, __) => _updateReminders());
    ref.listen(visualThemeProvider, (_, __) => _updateReminders());
    ref.listen(bubbleRevisionProvider, (_, __) => _updateReminders());
    final locale = ref.watch(localeControllerProvider);
    final redNote = ref.watch(visualThemeProvider) == VisualTheme.redNote;
    final colors = ColorScheme.fromSeed(
      seedColor: redNote ? RedNoteColors.accent : const Color(0xFF2E7F91),
      brightness: redNote ? Brightness.light : Brightness.dark,
      surface: redNote ? RedNoteColors.surface : const Color(0xFF0B2531),
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
        scaffoldBackgroundColor: redNote
            ? RedNoteColors.background
            : const Color(0xFF061620),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: redNote
              ? RedNoteColors.surface
              : const Color(0xFF0B2733),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(redNote ? 16 : 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: redNote ? RedNoteColors.field : const Color(0xFF123542),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: redNote ? RedNoteColors.accent : const Color(0xFF65D7CB),
              width: 1.5,
            ),
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
              setState(() => _initialSync = _initializeSyncFacade());
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
