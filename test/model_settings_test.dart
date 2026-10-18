import 'dart:convert';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';

void main() {
  test(
    'API credentials stay in secure storage and are scoped to service URLs',
    () async {
      final settings = MemorySettingsStore();
      final secrets = MemorySettingsStore();
      final repository = ModelSettingsRepository(settings, secrets);
      const a = ModelSettings(
        generation: ModelConnection(
          access: ModelAccess.api,
          endpoint: 'https://one.example/v1',
          model: 'configured-model',
        ),
      );
      const b = ModelSettings(
        generation: ModelConnection(
          access: ModelAccess.api,
          endpoint: 'https://two.example/v1',
          model: 'configured-model',
        ),
      );
      await repository.save(a, credential: 'test-credential');
      final raw =
          await settings.read(ModelSettingsRepository.settingsKey) as String;
      expect(raw, isNot(contains('test-credential')));
      expect(
        (jsonDecode(raw) as Map)['generation']['model'],
        'configured-model',
      );
      expect(await repository.hasCredential(), true);
      await repository.save(b);
      expect(await repository.hasCredential(), false);
      await repository.save(a);
      expect(await repository.hasCredential(), true);
      await repository.save(a, clearCredential: true);
      expect(await repository.hasCredential(), false);
    },
  );
  test('unconfigured models do not attempt generation', () async {
    final repository = ModelSettingsRepository(
      MemorySettingsStore(),
      MemorySettingsStore(),
    );
    expect(await repository.generation(await repository.load()), isNull);
    expect(await repository.embedding(await repository.load()), isNull);
  });

  test(
    'connections and API credentials survive saving another access mode',
    () async {
      final repository = ModelSettingsRepository(
        MemorySettingsStore(),
        MemorySettingsStore(),
      );
      const api = ModelConnection(
        access: ModelAccess.api,
        endpoint: 'https://api.example/v1',
        model: 'api-model',
      );
      const local = ModelConnection(
        access: ModelAccess.local,
        endpoint: 'http://127.0.0.1:11500',
        model: 'local-model',
      );
      const subscription = ModelConnection(
        access: ModelAccess.subscription,
        model: 'subscription-model',
        executable: 'custom-codex',
      );
      const connections = {
        ModelAccess.api: api,
        ModelAccess.local: local,
        ModelAccess.subscription: subscription,
      };

      for (final active in [local, subscription, api]) {
        await repository.save(
          ModelSettings(
            generation: active,
            connections: connections,
            embedding: const ModelConnection(
              access: ModelAccess.local,
              endpoint: 'http://127.0.0.1:11500',
              model: 'embedding-model',
            ),
          ),
          credential: 'api-test-credential',
        );
        final saved = await repository.load();
        expect(saved.generation.access, active.access);
        for (final entry in connections.entries) {
          expect(saved.connectionFor(entry.key).toJson(), entry.value.toJson());
        }
        expect(await repository.hasCredential(connection: api), isTrue);
        expect(await repository.hasCredential(connection: local), isFalse);
        expect(saved.embeddingEndpoint, local.endpoint);
        expect(await repository.embedding(saved), isNotNull);
      }
    },
  );

  test(
    'legacy settings keep the selected connection without copying it to other modes',
    () {
      final settings = ModelSettings.fromJson({
        'generation': const ModelConnection(
          access: ModelAccess.api,
          endpoint: 'https://api.example/v1',
          model: 'api-model',
        ).toJson(),
        'embedding_endpoint': 'http://127.0.0.1:11500',
        'embedding_model': 'embedding-model',
      });

      expect(settings.connectionFor(ModelAccess.api).model, 'api-model');
      expect(
        settings.connectionFor(ModelAccess.local).endpoint,
        'http://127.0.0.1:11500',
      );
      expect(settings.connectionFor(ModelAccess.local).model, isEmpty);
      expect(settings.connectionFor(ModelAccess.subscription).model, isEmpty);
    },
  );
}
