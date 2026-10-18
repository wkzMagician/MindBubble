import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/services/model_preferences_store.dart';

void main() {
  late Directory folder;
  late FileObjectStore objects;
  late MemorySettingsStore legacy;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp(
      'mindbubble-model-settings-',
    );
    objects = await FileObjectStore.open(root: folder);
    legacy = MemorySettingsStore();
  });
  tearDown(() async {
    await objects.close();
    await folder.delete(recursive: true);
  });

  test(
    'model settings migrate and survive reopening and stale legacy writes',
    () async {
      const old =
          '{"generation":{"access":"api","endpoint":"https://text.example/v1","model":"text"},"embedding_model":""}';
      await legacy.write(ModelSettingsRepository.settingsKey, old);
      final repository = ModelSettingsRepository(
        ModelPreferencesStore(objects, legacy),
        MemorySettingsStore(),
      );
      final initial = await repository.load();
      expect(initial.generation.model, 'text');
      await repository.save(
        ModelSettings(
          generation: initial.generation,
          embedding: const ModelConnection(
            access: ModelAccess.local,
            endpoint: 'http://127.0.0.1:11434',
            model: 'qwen3-embedding:0.6b',
          ),
        ),
      );
      await legacy.write(ModelSettingsRepository.settingsKey, old);
      await objects.close();
      objects = await FileObjectStore.open(root: folder);
      final reopened = ModelSettingsRepository(
        ModelPreferencesStore(objects, legacy),
        MemorySettingsStore(),
      );
      final value = await reopened.load();
      expect(value.embedding.model, 'qwen3-embedding:0.6b');
      expect(value.generation.model, 'text');
      expect(await reopened.embedding(value), isNotNull);
    },
  );

  test(
    'removed model settings do not reappear from the legacy snapshot',
    () async {
      await legacy.write('key', 'legacy');
      final store = ModelPreferencesStore(objects, legacy);
      expect(await store.read('key'), 'legacy');
      await store.remove('key');
      await legacy.write('key', 'stale');
      expect(await store.read('key'), isNull);
    },
  );
}
