import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/model_settings/model_settings_panel.dart';
import 'package:mind_bubble/features/recommendations/analyze_pending_notes_button.dart';
import 'package:mind_bubble/features/recommendations/note_analyzer.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/features/recommendations/pending_note_analysis.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/daily_selection_cache.dart';
import 'package:mind_bubble/services/device_identity_service.dart';
import 'package:mind_bubble/viewmodels/bubble_view_models.dart';

class _Models extends ModelSettingsRepository implements GenerationModel {
  _Models() : super(MemorySettingsStore(), MemorySettingsStore());

  ModelSettings value = const ModelSettings(
    generation: ModelConnection(
      access: ModelAccess.local,
      endpoint: 'http://127.0.0.1:11434',
      model: 'test-model',
    ),
  );
  int calls = 0;
  int failOn = 0;
  bool malformed = false;
  Completer<void>? gate;
  final started = Completer<void>();

  @override
  Future<ModelSettings> load() async => value;
  @override
  Future<GenerationModel?> generation(ModelSettings value) async => this;
  @override
  Future<EmbeddingModel?> embedding(ModelSettings value) async => null;
  @override
  Future<String> generate(ModelRequest request) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (calls == failOn) throw const ModelException('Service unavailable');
    if (malformed) return 'Invalid model response';
    final notes = (jsonDecode(request.input) as Map)['notes'] as List;
    return jsonEncode({
      'notes': [
        for (final note in notes)
          {
            'note_id': (note as Map)['note_id'],
            'cue_value': .8,
            'detail_need': .7,
            'cue_text': 'Reminder',
            'summary': 'Analyzed summary',
          },
      ],
    });
  }
}

class _UiController extends PendingNoteAnalysisController {
  _UiController(super.repository, super.models);

  PendingNoteAnalysisState result = const PendingNoteAnalysisState(
    total: 2,
    issue: PendingAnalysisIssue.unconfigured,
  );
  int calls = 0;

  void showProgress(PendingNoteAnalysisState value) => state = value;

  @override
  Future<PendingNoteAnalysisState> analyzePending() async {
    calls++;
    return result;
  }
}

void main() {
  late Directory folder;
  late BubbleRepository repository;
  late _Models models;
  late PendingNoteAnalysisController controller;
  final now = DateTime.utc(2026, 10, 17);

  Bubble note(String id, {String? status}) => Bubble(
    id: id,
    title: 'Note $id',
    description: 'Original body',
    createdAt: now,
    updatedAt: now,
    profile: status == null
        ? null
        : NoteProfile(analysisStatus: status, summary: 'Existing summary'),
  );

  setUp(() async {
    folder = await Directory.systemTemp.createTemp(
      'mindbubble-pending-analysis-',
    );
    models = _Models();
    const identity = DeviceIdentity('test-device');
    repository = BubbleRepository(
      BubbleDocumentStore.forTesting(
        root: Directory('${folder.path}/notes')..createSync(),
        supportRoot: Directory('${folder.path}/support')..createSync(),
        deviceIdentity: identity,
      ),
      DailySelectionCache.forTesting(File('${folder.path}/daily.json')),
      identity,
      () {},
      analyzer: NoteAnalyzer(models),
    );
    controller = PendingNoteAnalysisController(repository, models);
  });

  tearDown(() async {
    controller.dispose();
    await folder.delete(recursive: true);
  });

  test(
    'analyzes all pending and failed notes while preserving completed notes',
    () async {
      final notes = [
        for (var i = 0; i < 19; i++)
          note(
            '$i',
            status: i.isEven
                ? null
                : i == 1
                ? 'failed'
                : 'pending',
          ),
        note('ready', status: 'ready'),
        note('without-embedding', status: 'embedding_pending'),
        note('deleted'),
      ];
      for (final value in notes) {
        await repository.save(value, analyze: false);
      }
      await repository.delete('deleted');

      final result = await controller.analyzePending();

      expect(result.issue, isNull);
      expect(result.isRunning, isFalse);
      expect(result.total, 19);
      expect(result.processed, 19);
      expect(result.analyzed, 19);
      expect(models.calls, 2);
      expect((await repository.getAll()).where(noteNeedsAnalysis), isEmpty);
      for (final id in ['ready', 'without-embedding']) {
        expect(
          (await repository.getById(id))!.effectiveProfile.summary,
          'Existing summary',
        );
      }
      expect(await repository.getById('deleted'), isNull);
    },
  );

  test(
    'unconfigured and invalid models leave pending notes untouched',
    () async {
      await repository.save(note('a'), analyze: false);
      models.value = const ModelSettings();
      final missing = await controller.analyzePending();
      expect(missing.issue, PendingAnalysisIssue.unconfigured);
      expect(missing.total, 1);
      expect(models.calls, 0);
      expect((await repository.getById('a'))!.profile, isNull);

      models.value = const ModelSettings(
        generation: ModelConnection(
          access: ModelAccess.api,
          endpoint: 'invalid-service-url',
          model: 'test-model',
        ),
      );
      final invalid = await controller.analyzePending();
      expect(invalid.issue, PendingAnalysisIssue.invalidConfiguration);
      expect(models.calls, 0);
      expect((await repository.getById('a'))!.profile, isNull);
    },
  );

  test(
    'a failed batch stops later calls and retry only analyzes remaining notes',
    () async {
      for (var i = 0; i < 35; i++) {
        await repository.save(note('$i'), analyze: false);
      }
      models.failOn = 2;
      final result = await controller.analyzePending();
      expect(result.issue, PendingAnalysisIssue.modelFailed);
      expect(result.analyzed, 16);
      expect(result.failed, 16);
      expect(result.processed, 32);
      expect(models.calls, 2);
      expect((await repository.getAll()).where(noteNeedsAnalysis).length, 19);

      models.failOn = 0;
      final retry = await controller.analyzePending();
      expect(retry.issue, isNull);
      expect(retry.total, 19);
      expect(retry.analyzed, 19);
      expect(models.calls, 4);
    },
  );

  test(
    'invalid model output is reported as failure and preserves note data',
    () async {
      await repository.save(note('a', status: 'failed'), analyze: false);
      models.malformed = true;
      final result = await controller.analyzePending();
      expect(result.issue, PendingAnalysisIssue.modelFailed);
      expect(result.failed, 1);
      final saved = (await repository.getById('a'))!;
      expect(saved.description, 'Original body');
      expect(saved.effectiveProfile.summary, 'Existing summary');
    },
  );

  test(
    'subscription models may use their default model without a model name',
    () async {
      await repository.save(note('a'), analyze: false);
      models.value = const ModelSettings(
        generation: ModelConnection(
          access: ModelAccess.subscription,
          model: '',
        ),
      );
      final result = await controller.analyzePending();
      expect(result.issue, isNull);
      expect(result.analyzed, 1);
    },
  );

  test('a second run cannot duplicate an in-flight analysis', () async {
    await repository.save(note('a'), analyze: false);
    models.gate = Completer<void>();
    final first = controller.analyzePending();
    await models.started.future;

    final second = await controller.analyzePending();
    expect(second.isRunning, isTrue);
    expect(models.calls, 1);
    models.gate!.complete();
    expect((await first).analyzed, 1);
  });

  test(
    'editing and deleting notes during analysis skips stale results',
    () async {
      await repository.save(note('edited'), analyze: false);
      await repository.save(note('deleted'), analyze: false);
      models.gate = Completer<void>();
      final run = controller.analyzePending();
      await models.started.future;
      await repository.save(
        note('edited').copyWith(description: 'New body'),
        analyze: false,
      );
      await repository.delete('deleted');
      models.gate!.complete();

      final result = await run;
      expect(result.issue, isNull);
      expect(result.skipped, 2);
      expect(result.analyzed, 0);
      final saved = (await repository.getById('edited'))!;
      expect(saved.description, 'New body');
      expect(saved.profile, isNull);
      expect(await repository.getById('deleted'), isNull);
    },
  );

  test(
    'an empty library completes without requiring a configured model',
    () async {
      models.value = const ModelSettings();
      final result = await controller.analyzePending();
      expect(result.issue, isNull);
      expect(result.total, 0);
      expect(models.calls, 0);
    },
  );

  Future<void> showButton(WidgetTester tester, _UiController ui) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelSettingsRepositoryProvider.overrideWithValue(models),
          pendingNoteAnalysisProvider.overrideWith((_) => ui),
          bubblesProvider('').overrideWith(
            (_) async => [
              note('a'),
              note('b', status: 'failed'),
              note('ready', status: 'ready'),
            ],
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            appBar: AppBar(actions: const [AnalyzePendingNotesButton()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the pending count and model warning link to model settings', (
    tester,
  ) async {
    final ui = _UiController(repository, models);
    await showButton(tester, ui);
    expect(find.text('AI 分析 (2)'), findsOneWidget);
    await tester.tap(find.text('AI 分析 (2)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置分析模型'), findsOneWidget);
    expect(ui.calls, 1);
    await tester.tap(find.text('模型设置'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelSettingsDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow toolbar shows progress and prevents repeated taps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ui = _UiController(repository, models);
    await showButton(tester, ui);
    expect(find.byType(Badge), findsOneWidget);
    ui.showProgress(
      const PendingNoteAnalysisState(isRunning: true, total: 20, processed: 16),
    );
    await tester.pump();
    expect(find.byTooltip('分析中 16/20'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    ui.showProgress(const PendingNoteAnalysisState());
    await tester.pumpAndSettle();
  });
}
