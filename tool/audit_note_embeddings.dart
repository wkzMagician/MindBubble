import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings_secure_storage/dartloom_settings_secure_storage.dart';
import 'package:mind_bubble/services/model_preferences_store.dart';
import 'package:flutter/widgets.dart';
import 'package:mind_bubble/app/app_paths.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/recommendations/note_analyzer.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/features/recommendations/recommendation_config.dart';
import 'package:mind_bubble/features/recommendations/recommendation_engine.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/device_identity_service.dart';

// Native diagnostic: uses real settings and notes, writes note copies in an
// isolated audit store, and never starts synchronization or text generation.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const outputPath = String.fromEnvironment('EMBEDDING_AUDIT_OUTPUT');
  if (outputPath.isEmpty) exit(2);
  final output = Directory(outputPath)..createSync(recursive: true);
  final progress = File('${output.path}/progress.jsonl');
  Future<void> log(Map<String, Object?> event) => progress.writeAsString(
    '${jsonEncode({...event, 'at': DateTime.now().toUtc().toIso8601String()})}\n',
    mode: FileMode.append,
    flush: true,
  );
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  try {
    final models = ModelSettingsRepository(
      await ModelPreferencesStore.open(),
      const SecureSettingsStore(),
    );
    final previous = await models.load();
    final credentialBefore = await models.hasCredential();
    const embedding = ModelConnection(
      access: ModelAccess.local,
      endpoint: 'http://127.0.0.1:11434',
      model: 'qwen3-embedding:0.6b',
    );
    final configured = ModelSettings(
      generation: previous.generation,
      generationAccount: previous.generationAccount,
      connections: previous.connections,
      embedding: embedding,
      embeddingConnections: {
        ...previous.embeddingConnections,
        ModelAccess.local: embedding,
      },
    );
    await models.save(configured);
    final saved = await models.load();
    check(
      jsonEncode(saved.generation.toJson()) ==
          jsonEncode(previous.generation.toJson()),
      'Text configuration changed',
    );
    check(
      await models.hasCredential() == credentialBefore,
      'Text credential changed',
    );
    final embedder = (await models.embedding(saved))!;
    await log({
      'event': 'configured',
      'identity': embedder.identity,
      'text_model': saved.generation.model,
      'text_credential_preserved': true,
    });

    final paths = await MindBubblePaths.resolve();
    final notes = <Bubble>[];
    await for (final entry in paths.businessRoot.list()) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final note = BubbleDocumentCodec.decode(
        await entry.readAsString(),
      ).bubble;
      if (!note.isDeleted) notes.add(note);
    }
    notes.sort((a, b) => a.id.compareTo(b.id));
    final beforeHashes = <String, String>{};
    await for (final entry in paths.businessRoot.list()) {
      if (entry is File && entry.path.endsWith('.md')) {
        beforeHashes[entry.path] = BubbleDocumentCodec.hash(
          await entry.readAsString(),
        );
      }
    }
    final store = BubbleDocumentStore.forTesting(
      root: Directory('${output.path}/notes')..createSync(recursive: true),
      supportRoot: Directory('${output.path}/support')
        ..createSync(recursive: true),
      deviceIdentity: DeviceIdentity('embedding-audit'),
    );
    final stopwatch = Stopwatch()..start();
    final analyzer = NoteAnalyzer(models);
    final enriched = <Bubble>[];
    var dimensions = 0;
    for (
      var offset = 0;
      offset < notes.length;
      offset += NoteAnalyzer.embeddingBatchSize
    ) {
      final batch = notes
          .skip(offset)
          .take(NoteAnalyzer.embeddingBatchSize)
          .toList();
      final profiles = await analyzer.embedOnly(batch);
      for (final note in batch) {
        final profile = profiles[note.id]!;
        if (dimensions == 0) dimensions = profile.embedding.length;
        check(
          dimensions > 0 &&
              profile.embedding.length == dimensions &&
              profile.embedding.every((v) => v.isFinite),
          'Invalid actual embedding',
        );
        final old = note.effectiveProfile;
        check(
          profile.cueValue == old.cueValue &&
              profile.detailNeed == old.detailNeed &&
              profile.cueText == old.cueText &&
              profile.summary == old.summary,
          'Analysis values changed',
        );
        final copy = note.copyWith(profile: profile);
        enriched.add(copy);
        await store.save(copy);
      }
      await log({
        'event': 'embedding_batch',
        'completed': enriched.length,
        'total': notes.length,
        'dimensions': dimensions,
        'elapsed_ms': stopwatch.elapsedMilliseconds,
      });
    }
    final reloaded = await store.readAll();
    check(reloaded.length == notes.length, 'Storage count mismatch');
    for (final note in reloaded) {
      final original = enriched.firstWhere((n) => n.id == note.id);
      check(
        jsonEncode(note.effectiveProfile.toJson()) ==
            jsonEncode(original.effectiveProfile.toJson()),
        'Embedding persistence mismatch',
      );
      check(
        note.preference == original.preference &&
            note.shownCount == original.shownCount,
        'Feedback or exposure changed during persistence',
      );
    }

    final probes = [
      '规律运动可以改善睡眠，缓解压力，让情绪更稳定。',
      '每天坚持锻炼，有助于睡得更好，也能减少焦虑。',
      '数据库建立索引可以减少查询扫描，提高检索效率。',
      '数据库查询变慢时，可以检查执行计划并添加合适的索引。',
      '规律运动可以改善睡眠，缓解压力，让情绪更稳定。',
    ];
    final vectors = await embedder.embed(probes);
    final now = DateTime.now();
    Bubble probe(int index, {double preference = 0, String? identity}) =>
        Bubble(
          id: 'probe-$index',
          title: probes[index],
          description: probes[index],
          createdAt: now,
          updatedAt: now,
          preference: preference,
          profile: NoteProfile(
            cueValue: .5,
            embedding: vectors[index],
            embeddingModel: identity ?? embedder.identity,
            analysisStatus: 'ready',
          ),
        );
    double sim(int a, int b) =>
        RecommendationEngine.similarity(probe(a), probe(b));
    final same = sim(0, 4),
        related = sim(0, 1),
        unrelated = sim(0, 2),
        databases = sim(2, 3);
    check(same > .999, 'Identical Chinese text did not match');
    check(
      related > unrelated && databases > unrelated,
      'Chinese semantic similarity ordering failed',
    );
    check(
      RecommendationEngine.similarity(
            probe(0),
            probe(1, identity: 'other-model'),
          ) ==
          0,
      'Model identities leaked across spaces',
    );
    check(
      RecommendationEngine.similarity(
            probe(0),
            probe(1).copyWith(
              profile: probe(1).effectiveProfile.copyWith(embedding: [1, 0]),
            ),
          ) ==
          0,
      'Dimensions were not isolated',
    );
    final engine = RecommendationEngine(random: Random(42));
    final generalization = engine.probabilities(
      [probe(0, preference: .9), probe(1), probe(2)],
      now: now,
      config: RecommendationConfig(),
    );
    check(
      generalization[1].generalization > generalization[2].generalization,
      'Preference did not propagate more strongly to the related note',
    );
    final diverse = engine.probabilities(
      [probe(0), probe(1), probe(2)],
      now: now,
      config: RecommendationConfig(explorationRate: 0),
      selected: [probe(0)],
    );
    check(
      diverse.first.probability < diverse.last.probability,
      'Diversity did not penalize similarity',
    );
    final probabilities = engine.probabilities(
      enriched,
      now: now,
      config: RecommendationConfig(),
    );
    check(
      probabilities.every((p) => p.probability.isFinite && p.probability >= 0),
      'Invalid recommendation probability',
    );
    final sum = probabilities.fold<double>(0, (s, p) => s + p.probability);
    check(
      (sum - 1).abs() < 1e-8,
      'Recommendation probabilities did not normalize',
    );
    for (final entry in beforeHashes.entries) {
      check(
        BubbleDocumentCodec.hash(await File(entry.key).readAsString()) ==
            entry.value,
        'A production note changed during the audit',
      );
    }
    await store.dispose();
    final report = {
      'success': true,
      'model': embedding.model,
      'identity': embedder.identity,
      'note_count': notes.length,
      'dimensions': dimensions,
      'elapsed_ms': stopwatch.elapsedMilliseconds,
      'text_model': saved.generation.model,
      'text_credential_preserved': true,
      'production_note_files_unchanged': true,
      'storage_round_trip': true,
      'similarity': {
        'identical': same,
        'related_exercise': related,
        'unrelated_database': unrelated,
        'related_database': databases,
      },
      'preference_propagation': true,
      'semantic_diversity': true,
      'model_identity_isolation': true,
      'dimension_isolation': true,
      'recommendation_probability_sum': sum,
    };
    await File('${output.path}/report.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await log({'event': 'complete', ...report});
    exit(0);
  } on Object catch (error) {
    // No provider bodies or credentials are included in diagnostic errors.
    await log({
      'event': 'failed',
      'type': error.runtimeType.toString(),
      if (error is StateError) 'reason': error.message,
    });
    exit(1);
  }
}
