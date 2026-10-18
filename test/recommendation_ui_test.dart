import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/model_settings/model_settings_panel.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/widgets/bubble_detail_dialog.dart';

void main() {
  Future<void> switchMode(WidgetTester tester, String key, String label) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('text and embedding forms preserve independent modes and keys', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = MemorySettingsStore(), secrets = MemorySettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelSettingsStoreProvider.overrideWithValue(settings),
          modelSecretsStoreProvider.overrideWithValue(secrets),
        ],
        child: const MaterialApp(home: Scaffold(body: ModelSettingsDialog())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('generation-endpoint')),
      'https://model.example/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('generation-model')),
      'text-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('generation-key')),
      'fake-text-key',
    );
    await switchMode(tester, 'generation-access', 'Ollama');
    await tester.enterText(
      find.byKey(const ValueKey('generation-endpoint')),
      'http://127.0.0.1:11500',
    );
    await tester.enterText(
      find.byKey(const ValueKey('generation-model')),
      'local-chat',
    );
    await switchMode(tester, 'generation-access', 'API (OpenAI compatible)');
    expect(find.text('text-model'), findsOneWidget);
    final vectorEndpoint = find.byKey(const ValueKey('embedding-endpoint'));
    await tester.ensureVisible(vectorEndpoint);
    await tester.enterText(vectorEndpoint, 'http://127.0.0.1:11434');
    await tester.enterText(
      find.byKey(const ValueKey('embedding-model')),
      'qwen3-embedding:0.6b',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final repository = ModelSettingsRepository(settings, secrets);
    final saved = await repository.load();
    expect(saved.generation.access, ModelAccess.api);
    expect(saved.generation.model, 'text-model');
    expect(
      saved.connectionFor(ModelAccess.local).endpoint,
      'http://127.0.0.1:11500',
    );
    expect(saved.embedding.model, 'qwen3-embedding:0.6b');
    expect(saved.embedding.endpoint, 'http://127.0.0.1:11434');
    expect(await repository.embedding(saved), isNotNull);
    expect(await repository.hasCredential(), isTrue);
    expect(
      await settings.read(ModelSettingsRepository.settingsKey),
      isNot(contains('fake-text-key')),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'mobile offers API and ChatGPT OpenRouter accounts with no Ollama or CLI',
    (tester) async {
      tester.view.physicalSize = const Size(420, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(home: Scaffold(body: ModelSettingsDialog())),
        ),
      );
      await tester.pumpAndSettle();
      await switchMode(tester, 'generation-access', 'Account sign-in');
      expect(find.textContaining('Ollama'), findsNothing);
      expect(find.textContaining('Codex CLI'), findsNothing);
      final account = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(account);
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(find.text('ChatGPT'), findsWidgets);
      await tester.tap(find.text('OpenRouter').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Authorization code'), findsOneWidget);
      expect(find.text('Open authorization page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'embedding configuration can be saved with text generation disabled',
    (tester) async {
      tester.view.physicalSize = const Size(420, 920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = MemorySettingsStore(), secrets = MemorySettingsStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelSettingsStoreProvider.overrideWithValue(settings),
            modelSecretsStoreProvider.overrideWithValue(secrets),
          ],
          child: const MaterialApp(home: Scaffold(body: ModelSettingsDialog())),
        ),
      );
      await tester.pumpAndSettle();
      final endpoint = find.byKey(const ValueKey('embedding-endpoint'));
      await tester.ensureVisible(endpoint);
      await tester.enterText(endpoint, 'https://vectors.example/v1');
      await tester.enterText(
        find.byKey(const ValueKey('embedding-model')),
        'vector-model',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final repository = ModelSettingsRepository(
        settings,
        secrets,
        desktop: false,
      );
      final value = await repository.load();
      expect(value.configured, isFalse);
      expect(value.embeddingConfigured, isTrue);
      expect(await repository.embedding(value), isNotNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('detail exposes all feedback actions on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 10, 17);
    final note = Bubble(
      id: 'a',
      title: 'A thought',
      description: 'Readable body.',
      createdAt: now,
      updatedAt: now,
      profile: const NoteProfile(
        cueText: 'Remember this',
        summary: 'Brief summary',
        detailNeed: .8,
      ),
    );
    final feedback = <FrequencyFeedback>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: BubbleDetailDialog(
            bubble: note,
            onFrequencyChanged: (_) async {},
            onFeedback: (value) async {
              feedback.add(value);
              return note.copyWith(preference: .15);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in [
      'More often',
      'About right',
      'Less often',
      'Stop reminding',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('More often'));
    await tester.pumpAndSettle();
    expect(feedback, [FrequencyFeedback.more]);
    expect(find.text('Feedback recorded'), findsOneWidget);
    expect(find.text('Remember this'), findsOneWidget);
    expect(find.text('Brief summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
