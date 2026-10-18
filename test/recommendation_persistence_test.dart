import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/recommendations/note_analyzer.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/daily_selection_cache.dart';
import 'package:mind_bubble/services/device_identity_service.dart';

class _Models extends ModelSettingsRepository
    implements GenerationModel, EmbeddingModel {
  _Models() : super(MemorySettingsStore(), MemorySettingsStore());
  int generations = 0, embeddings = 0;
  bool fail = false, failEmbedding = false;
  @override
  Future<ModelSettings> load() async => const ModelSettings();
  @override
  Future<GenerationModel?> generation(ModelSettings value) async => this;
  @override
  Future<EmbeddingModel?> embedding(ModelSettings value) async => this;
  @override
  String get identity => 'test-local';
  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    embeddings++;
    if (failEmbedding) throw const ModelException('embedding offline');
    return [
      for (final _ in texts) [1, 0],
    ];
  }

  @override
  Future<String> generate(ModelRequest request) async {
    generations++;
    if (fail) throw const ModelException('offline');
    final notes = (jsonDecode(request.input) as Map)['notes'] as List;
    return jsonEncode({
      'notes': [
        for (final note in notes)
          {
            'note_id': (note as Map)['note_id'],
            'cue_value': .8,
            'detail_need': .7,
            'cue_text': 'Remember',
            'summary': 'A summary',
          },
      ],
    });
  }
}

void main() {
  late Directory folder;
  late BubbleRepository repo;
  late _Models models;
  final now = DateTime.utc(2026, 10, 17);
  Bubble note(String id) => Bubble(
    id: id,
    title: 'Idea $id',
    description: 'body',
    createdAt: now,
    updatedAt: now,
  );
  setUp(() async {
    folder = await Directory.systemTemp.createTemp(
      'mindbubble-recommendation-',
    );
    models = _Models();
    const identity = DeviceIdentity('device-a');
    repo = BubbleRepository(
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
  });
  tearDown(() => folder.delete(recursive: true));

  test(
    'creation analyzes once, editing retains profile, manual reanalysis is explicit',
    () async {
      await repo.save(note('a'));
      var saved = (await repo.getById('a'))!;
      expect(saved.effectiveProfile.analysisStatus, 'ready');
      expect(saved.effectiveProfile.embeddingModel, 'test-local');
      expect(models.generations, 1);
      await repo.save(saved.copyWith(description: 'edited'));
      saved = (await repo.getById('a'))!;
      expect(saved.effectiveProfile.cueValue, .8);
      expect(models.generations, 1);
      await repo.analyzeNotes([saved]);
      expect(models.generations, 2);
      expect(models.embeddings, 2);
    },
  );
  test(
    'bulk analysis batches notes and failure preserves data without automatic retries',
    () async {
      final notes = List.generate(20, (i) => note('$i'));
      for (final n in notes) {
        await repo.save(n, analyze: false);
      }
      await repo.analyzeNotes(notes);
      expect(models.generations, 2);
      models.fail = true;
      await repo.save(note('offline'));
      final failed = (await repo.getById('offline'))!;
      expect(failed.description, 'body');
      expect(failed.effectiveProfile.analysisStatus, 'failed');
      await repo.save(failed.copyWith(title: 'edited'));
      expect(models.generations, 3);
    },
  );
  test(
    'frequency feedback clamps, suitable logs without changes, stop excludes only recommendations',
    () async {
      await repo.save(note('a'));
      for (var i = 0; i < 8; i++) {
        await repo.feedback('a', FrequencyFeedback.more);
      }
      expect((await repo.getById('a'))!.preference, .6);
      await repo.feedback('a', FrequencyFeedback.suitable);
      expect((await repo.getById('a'))!.preference, .6);
      for (var i = 0; i < 10; i++) {
        await repo.feedback('a', FrequencyFeedback.less);
      }
      expect((await repo.getById('a'))!.preference, -.6);
      await repo.feedback(
        'a',
        FrequencyFeedback.stop,
        channel: RecommendationChannel.notification,
      );
      final saved = (await repo.getById('a'))!;
      expect(saved.recommendationEnabled, false);
      expect(await repo.getAll(), hasLength(1));
      final events = await repo.events.read();
      expect(events, hasLength(20));
      expect(events.last.channel, RecommendationChannel.notification);
      final decoded = BubbleDocumentCodec.decode(
        BubbleDocumentCodec.encode(saved, updatedBy: 'test'),
      ).bubble;
      expect(decoded.preference, -.6);
      expect(decoded.recommendationEnabled, false);
      expect(decoded.effectiveProfile.embedding, [1, 0]);
    },
  );
  test(
    'both channels share exposure state, delivery replay is idempotent, late events keep newest time',
    () async {
      await repo.save(note('a'));
      final later = now.add(const Duration(hours: 2));
      await repo.recordShown(['a'], later, eventId: 'home');
      await repo.recordShown(
        ['a'],
        now,
        channel: RecommendationChannel.notification,
        eventId: 'notification',
      );
      await repo.recordShown(
        ['a'],
        now,
        channel: RecommendationChannel.notification,
        eventId: 'notification',
      );
      final saved = (await repo.getById('a'))!;
      expect(saved.shownCount, 2);
      expect(saved.lastShownAt!.toUtc(), later);
      final shown = (await repo.events.read()).where(
        (e) => e.type == RecommendationEventType.shown,
      );
      expect(shown, hasLength(2));
    },
  );
  test(
    'reading adjusts detail_need slowly without changing recommendation value or preference',
    () async {
      await repo.save(note('a'));
      final before = (await repo.getById('a'))!;
      await repo.recordBehavior(
        'a',
        RecommendationEventType.opened,
        channel: RecommendationChannel.home,
      );
      await repo.recordBehavior(
        'a',
        RecommendationEventType.read,
        channel: RecommendationChannel.home,
        durationSeconds: 3,
      );
      expect((await repo.getById('a'))!.effectiveProfile.detailNeed, .7);
      await repo.recordBehavior(
        'a',
        RecommendationEventType.read,
        channel: RecommendationChannel.home,
        durationSeconds: 35,
      );
      final after = (await repo.getById('a'))!;
      expect(after.effectiveProfile.detailNeed, closeTo(.709, 1e-12));
      expect(after.effectiveProfile.cueValue, before.effectiveProfile.cueValue);
      expect(after.preference, before.preference);
    },
  );
  test('invalid batch output is rejected before any profile is applied', () {
    expect(
      () =>
          NoteAnalyzer.parseProfiles('{"notes":[{"note_id":"wrong"}]}', {'a'}),
      throwsFormatException,
    );
    expect(
      () => NoteAnalyzer.parseProfiles('{"notes":[]}', {'a'}),
      throwsFormatException,
    );
  });
  test(
    'embedding-only completion keeps analysis values and does not call generation',
    () async {
      await repo.save(note('a'));
      final ready = (await repo.getById('a'))!;
      await repo.save(
        ready.copyWith(
          profile: ready.effectiveProfile.copyWith(
            embedding: [],
            embeddingModel: '',
            analysisStatus: 'embedding_pending',
          ),
        ),
      );
      final pending = (await repo.getById('a'))!;
      final generationCount = models.generations;
      await repo.analyzeNotes([pending], embeddingsOnly: true);
      final after = (await repo.getById('a'))!;
      expect(models.generations, generationCount);
      expect(after.effectiveProfile.embedding, [1, 0]);
      expect(after.effectiveProfile.analysisStatus, 'ready');
      expect(after.effectiveProfile.cueText, pending.effectiveProfile.cueText);
      expect(after.effectiveProfile.summary, pending.effectiveProfile.summary);
      expect(
        after.effectiveProfile.cueValue,
        pending.effectiveProfile.cueValue,
      );
      expect(after.preference, pending.preference);
      expect(after.shownCount, pending.shownCount);
    },
  );

  test('failed embedding-only requests do not rewrite the note', () async {
    await repo.save(note('a'));
    final before = (await repo.getById('a'))!;
    models.failEmbedding = true;
    await repo.analyzeNotes([before], embeddingsOnly: true);
    final after = (await repo.getById('a'))!;
    expect(after.updatedAt, before.updatedAt);
    expect(after.effectiveProfile.toJson(), before.effectiveProfile.toJson());
    expect(models.generations, 1);
  });
}
