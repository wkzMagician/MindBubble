import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings_secure_storage/dartloom_settings_secure_storage.dart';
import 'package:mind_bubble/services/model_preferences_store.dart';
import 'package:flutter/widgets.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/recommendations/note_analyzer.dart';
import 'package:mind_bubble/models/bubble.dart';

// Native connection check. Uses the configured text credential for one
// synthetic note, then checks the actual embedding and account auth endpoints.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const outputPath = String.fromEnvironment('MODEL_CHECK_OUTPUT');
  if (outputPath.isEmpty) exit(2);
  final result = <String, Object?>{};
  var succeeded = false;
  try {
    final models = ModelSettingsRepository(
      await ModelPreferencesStore.open(),
      const SecureSettingsStore(),
    );
    var settings = await models.load();
    if (const bool.fromEnvironment('CONFIGURE_LOCAL_EMBEDDING')) {
      const embedding = ModelConnection(
        access: ModelAccess.local,
        endpoint: 'http://127.0.0.1:11434',
        model: 'qwen3-embedding:0.6b',
      );
      await models.save(
        ModelSettings(
          generation: settings.generation,
          connections: settings.connections,
          generationAccount: settings.generationAccount,
          embedding: embedding,
          embeddingConnections: {
            ...settings.embeddingConnections,
            ModelAccess.local: embedding,
          },
        ),
      );
      settings = await models.load();
    }
    final now = DateTime.now();
    final note = Bubble(
      id: 'model-connection-test',
      title: '运动与睡眠',
      description: '规律运动有助于改善睡眠、缓解压力，让情绪更稳定。',
      createdAt: now,
      updatedAt: now,
    );
    final profile = (await NoteAnalyzer(models).analyze([note]))[note.id]!;
    result.addAll({
      'text_model': settings.generation.model,
      'text_access': settings.generation.access.name,
      'analysis_status': profile.analysisStatus,
      'embedding_identity': profile.embeddingModel,
      'dimensions': profile.embedding.length,
    });
    final grant = await models.accountAuth.beginChatGpt();
    result['chatgpt_device_grant_received'] = grant.deviceId.isNotEmpty;
    try {
      await models.accountAuth.finishOpenRouter(
        models.accountAuth.beginOpenRouter(),
        'invalid-connectivity-probe',
      );
    } on AccountHttpException catch (error) {
      result['openrouter_invalid_code_status'] = error.status;
    }
    succeeded =
        profile.analysisStatus == 'ready' &&
        profile.embedding.length == 1024 &&
        result['chatgpt_device_grant_received'] == true &&
        result['openrouter_invalid_code_status'] == 400;
  } on Object catch (error) {
    result['error_type'] = error.runtimeType.toString();
  }
  await File(outputPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'success': succeeded,
      ...result,
      'human_account_consent_tested': false,
    }),
    flush: true,
  );
  exit(succeeded ? 0 : 1);
}
