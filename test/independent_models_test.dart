import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/model_settings/model_settings.dart';
import 'package:mind_bubble/features/recommendations/note_analyzer.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/models/bubble.dart';

class _Models extends ModelSettingsRepository implements EmbeddingModel {
  _Models() : super(MemorySettingsStore(), MemorySettingsStore());
  @override
  Future<EmbeddingModel?> embedding(ModelSettings value) async => this;
  @override
  String get identity => 'test:independent';
  @override
  Future<List<List<double>>> embed(List<String> texts) async => [
    for (final _ in texts) [1, 0],
  ];
  @override
  Future<GenerationModel?> generation(ModelSettings value) =>
      throw StateError('Generation must not run');
}

void main() {
  test('legacy local embeddings migrate while API generation stays active', () {
    final value = ModelSettings.fromJson({
      'generation': const ModelConnection(
        access: ModelAccess.api,
        endpoint: 'https://text.example/v1',
        model: 'text',
      ).toJson(),
      'embedding_endpoint': 'http://127.0.0.1:11500',
      'embedding_model': 'vectors',
    });
    expect(value.generation.access, ModelAccess.api);
    expect(value.embedding.access, ModelAccess.local);
    expect(value.embedding.endpoint, 'http://127.0.0.1:11500');
    expect(ModelSettings.fromJson(value.toJson()).embedding.model, 'vectors');
  });

  test(
    'text and embedding API credentials remain independent even at same endpoint',
    () async {
      final settings = MemorySettingsStore(), secrets = MemorySettingsStore();
      final repository = ModelSettingsRepository(settings, secrets);
      const connection = ModelConnection(
        access: ModelAccess.api,
        endpoint: 'https://api.example/v1',
        model: 'selected',
      );
      const value = ModelSettings(
        generation: connection,
        embedding: connection,
      );
      await repository.save(
        value,
        credential: 'text-key',
        embeddingCredential: 'vector-key',
      );
      expect(
        await secrets.read(ModelSettingsRepository.secretKeyFor(connection)),
        'text-key',
      );
      expect(
        await secrets.read(
          ModelSettingsRepository.secretKeyFor(connection, forEmbedding: true),
        ),
        'vector-key',
      );
      await repository.save(value, clearEmbeddingCredential: true);
      expect(await repository.hasCredential(connection: connection), isTrue);
      expect(
        await repository.hasCredential(
          connection: connection,
          forEmbedding: true,
        ),
        isFalse,
      );
      expect(
        await settings.read(ModelSettingsRepository.settingsKey),
        isNot(contains('key')),
      );
    },
  );

  test('mobile runtime rejects legacy CLI and local models', () async {
    final repository = ModelSettingsRepository(
      MemorySettingsStore(),
      MemorySettingsStore(),
      desktop: false,
    );
    const local = ModelConnection(
      access: ModelAccess.local,
      endpoint: 'http://127.0.0.1:11434',
      model: 'local',
    );
    expect(
      repository.generation(const ModelSettings(generation: local)),
      throwsA(isA<ModelException>()),
    );
    expect(
      repository.embedding(const ModelSettings(embedding: local)),
      throwsA(isA<ModelException>()),
    );
    expect(
      repository.generation(
        const ModelSettings(
          generation: ModelConnection(
            access: ModelAccess.subscription,
            model: '',
          ),
        ),
      ),
      throwsA(isA<ModelException>()),
    );
  });

  test(
    'embedding-only analysis preserves existing values without generation',
    () async {
      final notes = [
        Bubble(
          id: 'a',
          title: '中文标题',
          description: '中文正文',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          profile: const NoteProfile(
            cueValue: .83,
            detailNeed: .21,
            cueText: '已有提醒',
            summary: '已有摘要',
            analysisStatus: 'embedding_pending',
          ),
        ),
      ];
      final result = (await NoteAnalyzer(_Models()).embedOnly(notes))['a']!;
      expect(result.cueValue, .83);
      expect(result.detailNeed, .21);
      expect(result.cueText, '已有提醒');
      expect(result.summary, '已有摘要');
      expect(result.embedding, [1, 0]);
      expect(result.analysisStatus, 'ready');
    },
  );

  test(
    'account sessions are secret and concurrent ChatGPT refresh runs once',
    () async {
      var refreshes = 0;
      final repository = ModelSettingsRepository(
        MemorySettingsStore(),
        MemorySettingsStore(),
        accountAuth: ModelAccountAuth(
          request: (url, body, {form = false}) async {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return const AccountHttpResponse(200, {
              'access_token': 'new-access',
              'expires_in': 3600,
            });
          },
        ),
      );
      await repository.saveAccount(
        ModelAccountProvider.chatgpt,
        AccountSession(
          accessToken: 'expired',
          refreshToken: 'refresh',
          accountId: 'test-account',
          expiresAt: DateTime.utc(2020),
        ),
      );
      final sessions = await Future.wait(
        List.generate(
          4,
          (_) => repository.accountSession(ModelAccountProvider.chatgpt),
        ),
      );
      expect(refreshes, 1);
      expect(sessions.map((s) => s.accessToken), everyElement('new-access'));
      expect(sessions.first.refreshToken, 'refresh');
      expect(
        await repository.settings.read(ModelSettingsRepository.settingsKey),
        isNull,
      );
      await repository.signOut(ModelAccountProvider.chatgpt);
      expect(
        await repository.hasAccount(ModelAccountProvider.chatgpt),
        isFalse,
      );
      expect(
        repository.accountSession(ModelAccountProvider.chatgpt),
        throwsA(isA<ModelException>()),
      );
    },
  );
}
