import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:dartloom_sync/dartloom_sync.dart' as dartloom;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'bubble_document_store.dart';
import 'webdav_transport.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final facade = SyncService(
    delegate: Dartloom.get<dartloom.SyncService>(name: 'default'),
    supportRoot: ref.watch(bubbleDocumentStoreProvider).supportRoot,
  );
  ref.onDispose(facade.dispose);
  return facade;
});

/// The typed Dartloom snapshot stream consumed by MindBubble's sync UI.
final syncSnapshotProvider = StreamProvider<dartloom.SyncSnapshot>((
  ref,
) async* {
  final service = ref.watch(syncServiceProvider);
  yield service.snapshot;
  yield* service.states;
});

/// Typed conflicts are refreshed whenever Dartloom publishes a sync snapshot.
final syncConflictsProvider = FutureProvider<List<dartloom.SyncConflict>>((
  ref,
) {
  ref.watch(syncSnapshotProvider);
  return ref.watch(syncServiceProvider).listConflicts();
});

class WebDavConfig {
  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    this.appPassword = '',
  });

  final String serverUrl;
  final String username;

  /// Populated only while importing old plaintext configuration or accepting
  /// user input. Dartloom never returns persisted secrets to this UI facade.
  final String appPassword;

  factory WebDavConfig.fromJson(Map<String, Object?> json) => WebDavConfig(
    serverUrl: json['serverUrl'] as String? ?? '',
    username: json['username'] as String? ?? '',
    appPassword: json['appPassword'] as String? ?? '',
  );
}

enum SyncErrorKind {
  authentication,
  permission,
  network,
  conflict,
  migration,
  localCorruption,
  configuration,
  unknown,
}

class SyncException implements Exception {
  const SyncException(this.message, {this.kind = SyncErrorKind.unknown});

  final String message;
  final SyncErrorKind kind;

  @override
  String toString() => message;
}

enum ConflictResolution { local, remote }

typedef WebDavTransportFactory =
    WebDavTransport Function(WebDavConfig configuration);

final class RemoteMigrationReport {
  const RemoteMigrationReport({
    required this.version,
    required this.source,
    required this.target,
    required this.discovered,
    required this.copied,
    required this.newWins,
    required this.failures,
  });

  final int version;
  final String source;
  final String target;
  final int discovered;
  final int copied;
  final int newWins;
  final List<Map<String, String>> failures;

  bool get isComplete => failures.isEmpty;

  Map<String, Object?> toJson() => {
    'version': version,
    'source': source,
    'target': target,
    'discovered': discovered,
    'copied': copied,
    'newWins': newWins,
    'failures': failures,
    'completedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory RemoteMigrationReport.fromJson(Map<String, Object?> json) =>
      RemoteMigrationReport(
        version: json['version'] as int? ?? 0,
        source: json['source'] as String? ?? '',
        target: json['target'] as String? ?? '',
        discovered: json['discovered'] as int? ?? 0,
        copied: json['copied'] as int? ?? 0,
        newWins: json['newWins'] as int? ?? 0,
        failures: [
          for (final item in (json['failures'] as List? ?? const []))
            if (item is Map) item.cast<String, String>(),
        ],
      );
}

/// UI compatibility facade over Dartloom's typed sync contracts.
///
/// Reconciliation, lifecycle triggers, ETags, merge dispatch, state, and
/// conflict persistence are owned exclusively by Dartloom. Direct WebDAV
/// access exists only for the immutable legacy-directory copy migration.
class SyncService {
  SyncService({
    required dartloom.SyncService delegate,
    required Directory supportRoot,
    WebDavTransportFactory? transportFactory,
    File? configFile,
    File? legacyConfigFile,
    File? migrationMarkerFile,
  }) : _delegate = delegate,
       _supportRoot = supportRoot,
       _transportFactory = transportFactory,
       _configFileOverride = configFile,
       _legacyConfigFileOverride = legacyConfigFile,
       _migrationMarkerFileOverride = migrationMarkerFile;

  static const _profileLabel = 'MindBubble WebDAV';
  static const _legacyBubbleDirectory = '/MindBubble/v2/bubbles';
  static const _bubbleDirectory = '/MindBubble/bubbles';
  static const _migrationVersion = 1;

  final dartloom.SyncService _delegate;
  final Directory _supportRoot;
  final WebDavTransportFactory? _transportFactory;
  final File? _configFileOverride;
  final File? _legacyConfigFileOverride;
  final File? _migrationMarkerFileOverride;

  dartloom.SyncProfile? _profile;
  Future<void> _operationQueue = Future<void>.value();

  dartloom.SyncSnapshot get snapshot => _delegate.snapshot;
  Stream<dartloom.SyncSnapshot> get states => _delegate.states;
  DateTime? get lastSyncedAt => snapshot.lastSuccessAt;
  bool get isConfigured => _profile?.backend == 'webdav';

  Future<List<dartloom.SyncConflict>> listConflicts() =>
      _delegate.listConflicts();

  Future<WebDavConfig?> loadConfig() async {
    await _migratePlaintextConfigOnce();
    final profiles = await _delegate.listProfiles();
    _profile = profiles.where((profile) => profile.isActive).firstOrNull;
    if (_profile?.backend != 'webdav') {
      _profile = profiles
          .where((profile) => profile.backend == 'webdav')
          .firstOrNull;
    }
    final profile = _profile;
    if (profile == null || profile.backend != 'webdav') return null;
    return WebDavConfig(
      serverUrl: profile.options['base_url'] as String? ?? '',
      username: profile.options['username'] as String? ?? '',
    );
  }

  Future<void> configureWebDav({
    required String serverUrl,
    required String username,
    required String appPassword,
  }) async {
    final candidate = WebDavConfig(
      serverUrl: serverUrl.trim(),
      username: username.trim(),
      appPassword: appPassword,
    );
    final existing = await _webDavProfile();
    if (candidate.appPassword.isEmpty && existing != null) {
      final existingUrl = existing.options['base_url'] as String? ?? '';
      final existingUsername = existing.options['username'] as String? ?? '';
      if (candidate.serverUrl != existingUrl ||
          candidate.username != existingUsername) {
        throw const SyncException(
          '修改 WebDAV 地址或账号时，请重新输入应用密码。',
          kind: SyncErrorKind.configuration,
        );
      }
      _profile = existing;
      await _delegate.activateProfile(existing.id);
      return;
    }
    _validateConfig(candidate);
    await _saveProfileAndMigrate(candidate);
  }

  /// Retained for repository compatibility. Dartloom observes replica writes
  /// and owns local-write debouncing, so no second timer is scheduled here.
  void scheduleSync() {}

  Future<void> syncNow() => _serially(() async {
    if (await loadConfig() == null) return;
    final report = await _delegate.syncNow();
    if (report.failure != null) throw _mapFailure(report.failure!);
  });

  Future<void> resolveConflict(
    String conflictId,
    ConflictResolution resolution,
  ) => _serially(() async {
    await _delegate.resolveConflict(
      conflictId,
      dartloom.SyncConflictResolution(
        resolution == ConflictResolution.local
            ? dartloom.SyncConflictChoice.useLocal
            : dartloom.SyncConflictChoice.useRemote,
      ),
    );
  });

  Future<RemoteMigrationReport> migrateLegacyRemote(WebDavConfig config) async {
    final marker = await _migrationMarkerFile();
    final previous = await _readMigrationMarker(marker);
    if (previous != null &&
        previous.version == _migrationVersion &&
        previous.isComplete) {
      return previous;
    }

    final transport = _transport(config);
    final failures = <Map<String, String>>[];
    var discovered = 0;
    var copied = 0;
    var newWins = 0;
    try {
      await transport.ensureDirectory(_bubbleDirectory);
      final target = await transport.list(_bubbleDirectory);
      final targetNames = {
        for (final resource in target)
          if (!resource.isDirectory && resource.name.endsWith('.md'))
            resource.name,
      };

      List<WebDavResource> source;
      try {
        source = await transport.list(_legacyBubbleDirectory);
      } on WebDavTransportException catch (error) {
        if (error.statusCode != 404) rethrow;
        source = const [];
      }

      final documents =
          source
              .where(
                (resource) =>
                    !resource.isDirectory && resource.name.endsWith('.md'),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      discovered = documents.length;
      for (final resource in documents) {
        if (targetNames.contains(resource.name)) {
          newWins++;
          continue;
        }
        try {
          final old = await transport.read(resource.path);
          await transport.write(
            '$_bubbleDirectory/${resource.name}',
            old.bytes,
            createOnly: true,
            contentType: 'text/markdown; charset=utf-8',
          );
          copied++;
          targetNames.add(resource.name);
        } on WebDavTransportException catch (error) {
          if (error.statusCode == 412) {
            // A concurrent creator is equivalent to the target winning.
            newWins++;
            targetNames.add(resource.name);
          } else {
            failures.add({
              'key': resource.name,
              'category': _transportErrorKind(error).name,
            });
          }
        } catch (_) {
          failures.add({'key': resource.name, 'category': 'unknown'});
        }
      }
    } on WebDavTransportException catch (error) {
      failures.add({'key': '*', 'category': _transportErrorKind(error).name});
    } catch (_) {
      failures.add({'key': '*', 'category': 'unknown'});
    } finally {
      transport.close();
    }

    final report = RemoteMigrationReport(
      version: _migrationVersion,
      source: _legacyBubbleDirectory,
      target: _bubbleDirectory,
      discovered: discovered,
      copied: copied,
      newWins: newWins,
      failures: List.unmodifiable(failures),
    );
    await _writeMigrationMarker(marker, report);
    return report;
  }

  Future<void> _migratePlaintextConfigOnce() async {
    final profiles = await _delegate.listProfiles();
    final configured = profiles
        .where((profile) => profile.backend == 'webdav')
        .firstOrNull;
    if (configured != null) {
      _profile = configured;
      final candidates = [await _configFile(), await _legacyConfigFile()];
      final plaintext = candidates
          .where((file) => file.existsSync())
          .firstOrNull;
      if (plaintext == null) return;
      try {
        final decoded = jsonDecode(await plaintext.readAsString());
        if (decoded is! Map<String, Object?>) return;
        final config = WebDavConfig.fromJson(decoded);
        _validateConfig(config);
        await _saveProfileAndMigrate(config);
        await _removePlaintextFiles();
      } catch (error) {
        if (error is SyncException) rethrow;
        throw const SyncException(
          'WebDAV 旧配置无法安全迁移。',
          kind: SyncErrorKind.configuration,
        );
      }
      return;
    }

    final candidates = [await _configFile(), await _legacyConfigFile()];
    for (final file in candidates) {
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, Object?>) continue;
        final config = WebDavConfig.fromJson(decoded);
        _validateConfig(config);
        await _saveProfileAndMigrate(config);
        await _removePlaintextFiles();
        return;
      } catch (error) {
        if (error is SyncException) rethrow;
        throw const SyncException(
          'WebDAV 旧配置无法安全迁移。',
          kind: SyncErrorKind.configuration,
        );
      }
    }
  }

  Future<void> _saveProfileAndMigrate(WebDavConfig config) async {
    final profiles = await _delegate.listProfiles();
    final active = profiles.where((profile) => profile.isActive).firstOrNull;
    final existing = profiles
        .where((profile) => profile.backend == 'webdav')
        .firstOrNull;
    final profile = await _delegate.saveProfile(
      dartloom.SyncProfileDraft(
        id: existing?.id ?? active?.id ?? 'default',
        label: existing?.label ?? _profileLabel,
        backend: 'webdav',
        options: {'base_url': config.serverUrl, 'username': config.username},
        secrets: {'password': config.appPassword},
      ),
    );
    _profile = profile;

    final migration = await migrateLegacyRemote(config);
    if (!migration.isComplete) {
      throw const SyncException(
        'WebDAV 旧远端目录迁移未完成，可稍后重试。',
        kind: SyncErrorKind.migration,
      );
    }
    await _delegate.activateProfile(profile.id);
  }

  Future<dartloom.SyncProfile?> _webDavProfile() async {
    final profiles = await _delegate.listProfiles();
    return profiles.where((profile) => profile.backend == 'webdav').firstOrNull;
  }

  void _validateConfig(WebDavConfig config) {
    final uri = Uri.tryParse(config.serverUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const SyncException(
        'WebDAV 服务器地址必须是有效的 HTTP 或 HTTPS 地址。',
        kind: SyncErrorKind.configuration,
      );
    }
    if (config.username.isEmpty || config.appPassword.isEmpty) {
      throw const SyncException(
        'WebDAV 账号和应用密码不能为空。',
        kind: SyncErrorKind.configuration,
      );
    }
  }

  SyncException _mapFailure(dartloom.SyncFailure failure) {
    final kind = switch (failure.kind) {
      dartloom.SyncFailureKind.authentication => SyncErrorKind.authentication,
      dartloom.SyncFailureKind.permission => SyncErrorKind.permission,
      dartloom.SyncFailureKind.connectivity ||
      dartloom.SyncFailureKind.timeout => SyncErrorKind.network,
      dartloom.SyncFailureKind.conflict ||
      dartloom.SyncFailureKind.precondition => SyncErrorKind.conflict,
      dartloom.SyncFailureKind.configuration => SyncErrorKind.configuration,
      _ => SyncErrorKind.unknown,
    };
    return SyncException(failure.message, kind: kind);
  }

  SyncErrorKind _transportErrorKind(WebDavTransportException error) =>
      switch (error.statusCode) {
        401 => SyncErrorKind.authentication,
        403 => SyncErrorKind.permission,
        409 || 412 => SyncErrorKind.conflict,
        _ => SyncErrorKind.network,
      };

  Future<T> _serially<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationQueue = _operationQueue.catchError((Object _) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  WebDavTransport _transport(WebDavConfig config) =>
      _transportFactory?.call(config) ??
      HttpWebDavTransport(
        serverUrl: config.serverUrl,
        username: config.username,
        password: config.appPassword,
      );

  Future<File> _configFile() async {
    if (_configFileOverride != null) return _configFileOverride;
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'MindBubble', 'webdav-config.json'));
  }

  Future<File> _legacyConfigFile() async {
    if (_legacyConfigFileOverride != null) return _legacyConfigFileOverride;
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'webdav_config.json'));
  }

  Future<File> _migrationMarkerFile() async =>
      _migrationMarkerFileOverride ??
      File(
        path.join(
          _supportRoot.path,
          'sync-migrations',
          'remote-v2-bubbles-to-v3.json',
        ),
      );

  Future<RemoteMigrationReport?> _readMigrationMarker(File marker) async {
    if (!await marker.exists()) return null;
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is Map<String, Object?>) {
        return RemoteMigrationReport.fromJson(decoded);
      }
    } catch (_) {
      // A damaged marker is safe to retry: writes are create-only and the new
      // directory always wins.
    }
    return null;
  }

  Future<void> _writeMigrationMarker(
    File marker,
    RemoteMigrationReport report,
  ) async {
    await marker.parent.create(recursive: true);
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(jsonEncode(report.toJson()), flush: true);
    if (await marker.exists()) await marker.delete();
    await temporary.rename(marker.path);
  }

  Future<void> _removePlaintextFiles() async {
    final paths = <String>{
      (await _configFile()).absolute.path,
      (await _legacyConfigFile()).absolute.path,
    };
    for (final value in paths) {
      final file = File(value);
      if (await file.exists()) await file.delete();
    }
  }

  void dispose() {}
}
