import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:dartloom_settings_secure_storage/dartloom_settings_secure_storage.dart';
import 'package:mind_bubble/services/model_preferences_store.dart';
import 'package:flutter/widgets.dart';
import 'package:mind_bubble/app/app_paths.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/recommendations/note_analyzer.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';

// Run as a separate native Flutter entry point. It reads production settings and
// notes, calls the production analyzer, and writes an audit outside the note store.
// It never starts synchronization or writes note attributes.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const outputPath = String.fromEnvironment('AUDIT_OUTPUT_DIR');
  if (outputPath.isEmpty) exit(2);
  final output = Directory(outputPath);
  await output.create(recursive: true);
  final progress = File('${output.path}/progress.jsonl');
  Future<void> log(Map<String, Object?> event) => progress.writeAsString(
    '${jsonEncode({...event, 'at': DateTime.now().toUtc().toIso8601String()})}\n',
    mode: FileMode.append,
    flush: true,
  );
  final calls = <Map<String, Object?>>[];
  final models = _AuditModels(
    await ModelPreferencesStore.open(),
    const SecureSettingsStore(),
    calls,
  );
  try {
    final settings = await models.load();
    final hasCredential = await models.hasCredential();
    await log({
      'event': 'configuration',
      'access': settings.generation.access.name,
      'model': settings.generation.model,
      'has_credential': hasCredential,
      'configured': settings.configured,
    });
    if (!settings.configured || !hasCredential) {
      throw StateError(
        'The configured API model or its saved credential is unavailable.',
      );
    }
    final paths = await MindBubblePaths.resolve();
    final notes = <Bubble>[];
    await for (final entry in paths.businessRoot.list()) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final note = BubbleDocumentCodec.decode(
        await entry.readAsString(),
      ).bubble;
      if (!note.isDeleted) notes.add(note);
    }
    notes.sort((a, b) => a.title.compareTo(b.title));
    final report = <String, Object?>{
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'read_only': true,
      'model': settings.generation.model,
      'access': settings.generation.access.name,
      'note_count': notes.length,
      'calls': calls,
      'notes': [
        for (final note in notes)
          {
            'id': note.id,
            'title': note.title,
            'body': note.description,
            'before': note.effectiveProfile.toJson(),
          },
      ],
    };
    final rows = report['notes']! as List<Map<String, Object?>>;
    final reportFile = File('${output.path}/profiles.json');
    Future<void> save() => reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await save();
    await log({'event': 'loaded', 'notes': notes.length});
    final analyzer = NoteAnalyzer(models);
    for (var start = 0; start < notes.length; start += NoteAnalyzer.batchSize) {
      final batch = notes.skip(start).take(NoteAnalyzer.batchSize).toList();
      await log({
        'event': 'batch_started',
        'offset': start,
        'count': batch.length,
      });
      final profiles = await analyzer.analyze(batch);
      var passed = 0;
      for (var i = 0; i < batch.length; i++) {
        final profile = profiles[batch[i].id]!;
        rows[start + i]['after'] = profile.toJson();
        if (profile.analysisStatus == 'ready' ||
            profile.analysisStatus == 'embedding_pending') {
          passed++;
        }
      }
      await save();
      await log({
        'event': 'batch_finished',
        'offset': start,
        'passed': passed,
        'count': batch.length,
      });
      if (passed != batch.length) {
        await log({'event': 'stopped_on_failed_batch'});
        exit(1);
      }
    }
    report['completed'] = true;
    await save();
    await log({'event': 'completed', 'notes': notes.length});
    exit(0);
  } catch (error) {
    await log({
      'event': 'error',
      'type': error.runtimeType.toString(),
      'message': models.redact('$error'),
    });
    exit(1);
  }
}

class _AuditModels extends ModelSettingsRepository {
  _AuditModels(super.settings, super.secrets, this.calls);
  final List<Map<String, Object?>> calls;
  final _redactions = <String>[];
  String redact(String value) {
    for (final secret in _redactions) {
      value = value.replaceAll(secret, '[REDACTED]');
    }
    return value;
  }

  @override
  Future<GenerationModel?> generation(ModelSettings value) async {
    final model = await super.generation(value);
    if (model == null) return null;
    if (model is ApiGenerationModel &&
        (model.credential?.isNotEmpty ?? false)) {
      _redactions.add(model.credential!);
    }
    return _RecordedGeneration(model, calls, redact);
  }
}

class _RecordedGeneration implements GenerationModel {
  _RecordedGeneration(this.model, this.calls, this.redact);
  final GenerationModel model;
  final List<Map<String, Object?>> calls;
  final String Function(String) redact;
  @override
  Future<String> generate(ModelRequest request) async {
    final call = <String, Object?>{
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'input_chars': request.input.length,
    };
    calls.add(call);
    final timer = Stopwatch()..start();
    try {
      final response = await model.generate(request);
      call['response'] = redact(response);
      return response;
    } catch (error) {
      call['error_type'] = error.runtimeType.toString();
      call['error'] = redact('$error');
      rethrow;
    } finally {
      call['duration_ms'] = timer.elapsedMilliseconds;
    }
  }
}
