import 'dart:async';

import 'package:dartloom_sync/dartloom_sync.dart' as dartloom;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/app/sync_status_overlay.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/services/sync_service.dart';

class _BackgroundSync implements dartloom.SyncService {
  final events = StreamController<dartloom.SyncSnapshot>.broadcast();
  final profileGate = Completer<List<dartloom.SyncProfile>>();
  final manualGate = Completer<dartloom.SyncRunReport>();
  var manualCalls = 0;
  @override
  dartloom.SyncSnapshot snapshot = const dartloom.SyncSnapshot(
    phase: dartloom.SyncPhase.syncing,
    localRevision: 0,
    activeProfileId: 'default',
  );

  void emit(dartloom.SyncPhase phase, {dartloom.SyncFailure? failure}) {
    snapshot = snapshot.copyWith(
      phase: phase,
      lastReport: dartloom.SyncRunReport(
        trigger: dartloom.SyncTrigger.startup,
        failure: failure,
      ),
    );
    events.add(snapshot);
  }

  @override
  Stream<dartloom.SyncSnapshot> get states => events.stream;
  @override
  Future<List<dartloom.SyncProfile>> listProfiles() => profileGate.future;
  @override
  Future<dartloom.SyncRunReport> syncNow() {
    manualCalls++;
    return manualGate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'local notes remain editable throughout setup, failure and retry',
    (tester) async {
      final background = _BackgroundSync();
      final service = SyncService(delegate: background);
      final text = TextEditingController(text: '本地笔记');
      addTearDown(text.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SyncStatusOverlay(
              child: Scaffold(
                body: Center(child: TextField(controller: text)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('本地笔记'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.enterText(find.byType(TextField), '同步时也能编辑');
      expect(background.manualCalls, 0);

      background.profileGate.complete([]);
      await tester.pump();
      const failure = dartloom.SyncFailure(
        dartloom.SyncFailureKind.timeout,
        'Sync timed out.',
        retryable: true,
      );
      background.emit(dartloom.SyncPhase.failed, failure: failure);
      await tester.pump();
      expect(find.textContaining('云端同步未完成'), findsOneWidget);
      expect(text.text, '同步时也能编辑');
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(background.manualCalls, 1);
      await tester.enterText(find.byType(TextField), '重试时仍可编辑');
      background.manualGate.complete(
        const dartloom.SyncRunReport(trigger: dartloom.SyncTrigger.manual),
      );
      background.emit(dartloom.SyncPhase.succeeded);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('云端同步未完成'), findsNothing);
      expect(text.text, '重试时仍可编辑');
      await tester.pumpWidget(const SizedBox.shrink());
      await background.events.close();
    },
  );

  test(
    'sync status immediately exposes a run already started by Dartloom',
    () async {
      final background = _BackgroundSync();
      final service = SyncService(delegate: background);
      final container = ProviderContainer(
        overrides: [syncServiceProvider.overrideWithValue(service)],
      );
      try {
        final snapshot = await container.read(syncSnapshotProvider.future);
        expect(snapshot.phase, dartloom.SyncPhase.syncing);
        expect(background.manualCalls, 0);
      } finally {
        container.dispose();
        await background.events.close();
      }
    },
  );
}
