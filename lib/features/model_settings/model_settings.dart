import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final modelSettingsStoreProvider = Provider<SettingsStore>(
  (_) => MemorySettingsStore(),
);
final modelSecretsStoreProvider = Provider<SettingsStore>(
  (_) => MemorySettingsStore(),
);
final modelSettingsRepositoryProvider = Provider<ModelSettingsRepository>(
  (ref) => ModelSettingsRepository(
    ref.watch(modelSettingsStoreProvider),
    ref.watch(modelSecretsStoreProvider),
  ),
);

class ModelSettings {
  const ModelSettings({
    this.generation = const ModelConnection(access: ModelAccess.api, model: ''),
    this.connections = const {},
    this.generationAccount,
    this.embedding = const ModelConnection(
      access: ModelAccess.local,
      endpoint: 'http://127.0.0.1:11434',
      model: '',
    ),
    this.embeddingConnections = const {},
  });
  final ModelConnection generation;
  final Map<ModelAccess, ModelConnection> connections;

  /// Null retains existing desktop Codex CLI configurations.
  final ModelAccountProvider? generationAccount;
  final ModelConnection embedding;
  final Map<ModelAccess, ModelConnection> embeddingConnections;
  String get embeddingEndpoint => embedding.endpoint;
  String get embeddingModel => embedding.model;
  bool get configured =>
      (generation.access == ModelAccess.subscription &&
          generationAccount == null) ||
      (generation.model.trim().isNotEmpty &&
          (generation.access == ModelAccess.subscription ||
              generation.endpoint.trim().isNotEmpty));
  bool get embeddingConfigured =>
      embedding.model.trim().isNotEmpty &&
      (embedding.access == ModelAccess.subscription ||
          embedding.endpoint.trim().isNotEmpty);

  ModelConnection connectionFor(
    ModelAccess access, {
    bool forEmbedding = false,
  }) {
    final selected = forEmbedding ? embedding : generation;
    final saved = forEmbedding ? embeddingConnections : connections;
    return selected.access == access
        ? selected
        : saved[access] ??
              ModelConnection(
                access: access,
                model: '',
                endpoint: access == ModelAccess.local
                    ? 'http://127.0.0.1:11434'
                    : '',
              );
  }

  Map<String, Object?> toJson() => {
    'generation': generation.toJson(),
    'generation_account': generationAccount?.name,
    'connections': {
      for (final access in ModelAccess.values)
        access.name: connectionFor(access).toJson(),
    },
    'embedding': embedding.toJson(),
    'embedding_connections': {
      for (final access in ModelAccess.values)
        access.name: connectionFor(access, forEmbedding: true).toJson(),
    },
  };

  factory ModelSettings.fromJson(Map<String, Object?> json) {
    Map<ModelAccess, ModelConnection> connections(String key) => {
      for (final access in ModelAccess.values)
        if ((json[key] as Map?)?[access.name] is Map)
          access: ModelConnection.fromJson(
            ((json[key] as Map)[access.name] as Map).cast<String, Object?>(),
          ),
    };
    final savedConnections = connections('connections');
    if (json['embedding'] is! Map &&
        !savedConnections.containsKey(ModelAccess.local)) {
      savedConnections[ModelAccess.local] = ModelConnection(
        access: ModelAccess.local,
        endpoint:
            json['embedding_endpoint'] as String? ?? 'http://127.0.0.1:11434',
        model: '',
      );
    }
    return ModelSettings(
      generation: ModelConnection.fromJson(
        (json['generation'] as Map).cast<String, Object?>(),
      ),
      connections: savedConnections,
      generationAccount: ModelAccountProvider.values
          .where((p) => p.name == json['generation_account'])
          .firstOrNull,
      embedding: json['embedding'] is Map
          ? ModelConnection.fromJson(
              (json['embedding'] as Map).cast<String, Object?>(),
            )
          : ModelConnection(
              access: ModelAccess.local,
              endpoint:
                  json['embedding_endpoint'] as String? ??
                  'http://127.0.0.1:11434',
              model: json['embedding_model'] as String? ?? '',
            ),
      embeddingConnections: connections('embedding_connections'),
    );
  }
}

class ModelSettingsRepository {
  ModelSettingsRepository(
    this.settings,
    this.secrets, {
    ModelAccountAuth? accountAuth,
    bool? desktop,
  }) : accountAuth = accountAuth ?? ModelAccountAuth(),
       desktop =
           desktop ??
           (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  final SettingsStore settings, secrets;
  final ModelAccountAuth accountAuth;
  final bool desktop;
  final _refreshes = <ModelAccountProvider, Future<AccountSession>>{};
  static const settingsKey = 'models.v1';
  static String secretKeyFor(
    ModelConnection connection, {
    bool forEmbedding = false,
  }) =>
      'models.${forEmbedding ? 'embeddingCredential' : 'apiCredential'}.${sha256.convert(utf8.encode(connection.endpoint.trim().replaceFirst(RegExp(r'/+$'), '')))}';
  static String _accountKey(ModelAccountProvider provider) =>
      'models.account.${provider.name}';

  Future<ModelSettings> load() async {
    final raw = await settings.read(settingsKey);
    return raw is String
        ? ModelSettings.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>(),
          )
        : const ModelSettings();
  }

  Future<bool> hasCredential({
    ModelConnection? connection,
    bool forEmbedding = false,
  }) async {
    final value = await load();
    final target =
        connection ?? (forEmbedding ? value.embedding : value.generation);
    return ((await secrets.read(
                  secretKeyFor(target, forEmbedding: forEmbedding),
                ))
                as String? ??
            '')
        .isNotEmpty;
  }

  Future<void> save(
    ModelSettings value, {
    String? credential,
    bool clearCredential = false,
    String? embeddingCredential,
    bool clearEmbeddingCredential = false,
  }) async {
    final previous = await load();
    Future<void> storeCredential(
      bool embedding,
      String? key,
      bool clear,
    ) async {
      final connection = value.connectionFor(
        ModelAccess.api,
        forEmbedding: embedding,
      );
      final secretKey = secretKeyFor(connection, forEmbedding: embedding);
      if (clear) {
        await secrets.remove(
          secretKeyFor(
            previous.connectionFor(ModelAccess.api, forEmbedding: embedding),
            forEmbedding: embedding,
          ),
        );
        await secrets.remove(secretKey);
      }
      if (key != null && key.trim().isNotEmpty) {
        await secrets.write(secretKey, key.trim());
      }
    }

    await storeCredential(false, credential, clearCredential);
    await storeCredential(true, embeddingCredential, clearEmbeddingCredential);
    await settings.write(settingsKey, jsonEncode(value.toJson()));
  }

  Future<bool> hasAccount(ModelAccountProvider provider) async =>
      await secrets.read(_accountKey(provider)) is String;
  Future<void> saveAccount(
    ModelAccountProvider provider,
    AccountSession session,
  ) => secrets.write(_accountKey(provider), jsonEncode(session.toJson()));
  Future<void> signOut(ModelAccountProvider provider) =>
      secrets.remove(_accountKey(provider));

  Future<AccountSession> accountSession(
    ModelAccountProvider provider, {
    bool forceRefresh = false,
  }) async {
    final raw = await secrets.read(_accountKey(provider));
    if (raw is! String) {
      throw const ModelException('Please sign in to your model account');
    }
    final session = AccountSession.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
    if (provider != ModelAccountProvider.chatgpt ||
        (!forceRefresh && !session.needsRefresh)) {
      return session;
    }
    return _refreshes.putIfAbsent(provider, () async {
      try {
        final refreshed = await accountAuth.refreshChatGpt(session);
        await saveAccount(provider, refreshed);
        return refreshed;
      } finally {
        _refreshes.remove(provider);
      }
    });
  }

  Future<GenerationModel?> generation(ModelSettings value) async {
    if (!value.configured) return null;
    switch (value.generation.access) {
      case ModelAccess.api:
        return ApiGenerationModel(
          connection: value.generation,
          credential:
              await secrets.read(secretKeyFor(value.generation)) as String?,
        );
      case ModelAccess.local:
        if (!desktop) throw const ModelException('Ollama requires a desktop');
        return OllamaGenerationModel(connection: value.generation);
      case ModelAccess.subscription:
        if (value.generationAccount == null) {
          if (!desktop) {
            throw const ModelException(
              'Please choose ChatGPT or OpenRouter account login',
            );
          }
          return CodexSubscriptionModel(connection: value.generation);
        }
        return _AccountGeneration(
          this,
          value.generationAccount!,
          value.generation.model,
        );
    }
  }

  Future<EmbeddingModel?> embedding(ModelSettings value) async {
    if (!value.embeddingConfigured) return null;
    final connection = value.embedding;
    switch (connection.access) {
      case ModelAccess.local:
        if (!desktop) throw const ModelException('Ollama requires a desktop');
        return OllamaEmbeddingModel(
          endpoint: connection.endpoint,
          model: connection.model,
          transport: ModelHttpTransport(timeout: const Duration(minutes: 3)),
        );
      case ModelAccess.api:
        return ApiEmbeddingModel(
          connection: connection,
          credential:
              await secrets.read(secretKeyFor(connection, forEmbedding: true))
                  as String?,
        );
      case ModelAccess.subscription:
        final account = await accountSession(ModelAccountProvider.openRouter);
        return ApiEmbeddingModel(
          connection: ModelConnection(
            access: ModelAccess.api,
            endpoint: 'https://openrouter.ai/api/v1',
            model: connection.model,
          ),
          credential: account.accessToken,
        );
    }
  }
}

class _AccountGeneration implements GenerationModel {
  _AccountGeneration(this.repository, this.provider, this.model);
  final ModelSettingsRepository repository;
  final ModelAccountProvider provider;
  final String model;
  @override
  Future<String> generate(ModelRequest request) async {
    Future<String> call(AccountSession session) =>
        provider == ModelAccountProvider.chatgpt
        ? ChatGptGenerationModel(
            model: model,
            session: session,
            originator: 'mindbubble',
          ).generate(request)
        : ApiGenerationModel(
            connection: ModelConnection(
              access: ModelAccess.api,
              endpoint: 'https://openrouter.ai/api/v1',
              model: model,
            ),
            credential: session.accessToken,
          ).generate(request);
    final session = await repository.accountSession(provider);
    try {
      return await call(session);
    } on AccountHttpException catch (error) {
      if (provider != ModelAccountProvider.chatgpt || error.status != 401) {
        rethrow;
      }
      return call(
        await repository.accountSession(provider, forceRefresh: true),
      );
    }
  }
}
