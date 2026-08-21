import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_sync/dartloom_sync.dart' as dartloom;
import 'package:dartloom_sync_storage/dartloom_sync_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncServiceProvider = Provider<SyncService>(
  (_) => throw UnimplementedError('SyncService must be provided at startup.'),
);

final syncSnapshotProvider = StreamProvider<dartloom.SyncSnapshot>((ref) {
  return ref.watch(syncServiceProvider).states;
});

final syncConflictsProvider = FutureProvider<List<dartloom.SyncConflict>>((
  ref,
) async {
  ref.watch(syncSnapshotProvider);
  return ref.read(syncServiceProvider).listConflicts();
});

abstract interface class SyncPersistence {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final class MemorySyncPersistence implements SyncPersistence {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

enum ConflictResolution { local, remote }

class WebDavConfig {
  const WebDavConfig({required this.serverUrl, required this.username});

  final String serverUrl;
  final String username;
}

final class SyncService {
  SyncService({
    dartloom.SyncService? delegate,
    SettingsStore? settings,
    SettingsStore? secrets,
    SyncProfileScope? scope,
    AppLogger? logger,
    SyncPersistence? persistence,
  }) : _delegate = delegate,
       _settings = settings,
       _secrets = secrets,
       _scope = scope,
       _logger = logger ?? MemoryLogger(),
       _persistence = persistence;

  static const _serverKey = 'mindbubble.sync.webdav.server_url';
  static const _usernameKey = 'mindbubble.sync.webdav.username';
  static const _passwordKey = 'mindbubble.sync.webdav.app_password';

  final dartloom.SyncService? _delegate;
  final SettingsStore? _settings;
  final SettingsStore? _secrets;
  final SyncProfileScope? _scope;
  final AppLogger _logger;
  final SyncPersistence? _persistence;
  WebDavConfig? _config;

  dartloom.SyncSnapshot get snapshot =>
      _delegate?.snapshot ?? const dartloom.SyncSnapshot.initial();
  Stream<dartloom.SyncSnapshot> get states =>
      _delegate?.states ?? const Stream<dartloom.SyncSnapshot>.empty();
  DateTime? get lastSyncedAt => snapshot.lastSuccessAt;
  bool get isConfigured => _config != null;

  Future<WebDavConfig?> loadConfig() async {
    final delegate = _delegate;
    if (delegate == null) {
      final url = await _readString(_serverKey);
      final username = await _readString(_usernameKey);
      final password = await _readString(_passwordKey);
      _config = url.isEmpty || username.isEmpty || password.isEmpty
          ? null
          : WebDavConfig(serverUrl: url, username: username);
      return _config;
    }

    final profiles = await delegate.listProfiles();
    var active = profiles.where((profile) => profile.isActive).firstOrNull;
    final legacyUrl = await _readString(_serverKey);
    final legacyUsername = await _readString(_usernameKey);
    final legacyPassword = await _readString(_passwordKey);
    final hasLegacy =
        legacyUrl.isNotEmpty ||
        legacyUsername.isNotEmpty ||
        legacyPassword.isNotEmpty;

    if ((active == null || active.backend.isEmpty) && legacyUrl.isNotEmpty) {
      active = await delegate.saveProfile(
        _profileDraft(
          id: active?.id ?? 'default',
          url: legacyUrl,
          username: legacyUsername,
          password: legacyPassword,
        ),
      );
      await delegate.activateProfile(active.id);
      _logger.info('Migrated legacy WebDAV configuration to Dartloom.');
    } else if (active?.backend == 'webdav' && hasLegacy) {
      final options = <String, Object?>{...active!.options};
      if (legacyUrl.isNotEmpty) options['base_url'] = legacyUrl;
      if (legacyUsername.isNotEmpty) options['username'] = legacyUsername;
      active = await delegate.saveProfile(
        dartloom.SyncProfileDraft(
          id: active.id,
          label: active.label,
          backend: active.backend,
          options: options,
          secrets: {if (legacyPassword.isNotEmpty) 'password': legacyPassword},
        ),
      );
    }

    if (hasLegacy) {
      await Future.wait([
        _remove(_serverKey),
        _remove(_usernameKey),
        _remove(_passwordKey),
      ]);
    }
    final url = active?.options['base_url'];
    final username = active?.options['username'];
    if (active?.backend != 'webdav' ||
        url is! String ||
        username is! String ||
        url.trim().isEmpty) {
      _config = null;
      return null;
    }
    _config = WebDavConfig(serverUrl: url, username: username);
    return _config;
  }

  Future<void> configureWebDav({
    required String serverUrl,
    required String username,
    required String appPassword,
  }) async {
    final normalizedServer = serverUrl.trim();
    final normalizedUsername = username.trim();
    if (normalizedServer.isEmpty || normalizedUsername.isEmpty) {
      throw const FormatException('WebDAV server and account are required.');
    }
    final password = appPassword.trim().isNotEmpty
        ? appPassword
        : await _profilePassword();
    if (password == null || password.isEmpty) {
      throw const FormatException('WebDAV app password is required.');
    }

    final delegate = _delegate;
    if (delegate == null) {
      await _write(_serverKey, normalizedServer);
      await _write(_usernameKey, normalizedUsername);
      await _write(_passwordKey, password);
    } else {
      final active = (await delegate.listProfiles())
          .where((profile) => profile.isActive)
          .firstOrNull;
      final saved = await delegate.saveProfile(
        _profileDraft(
          id: active?.id ?? 'default',
          url: normalizedServer,
          username: normalizedUsername,
          password: password,
        ),
      );
      await delegate.activateProfile(saved.id);
    }
    _config = WebDavConfig(
      serverUrl: normalizedServer,
      username: normalizedUsername,
    );
    _logger.info('WebDAV profile configured.');
  }

  void scheduleSync() {}

  Future<dartloom.SyncRunReport> syncNow() async {
    final delegate = _delegate;
    if (delegate == null) {
      throw StateError('Dartloom sync is not available in this test service.');
    }
    if (_config == null) await loadConfig();
    _logger.info('Starting manual sync.');
    final report = await delegate.syncNow();
    if (report.failure != null) {
      _logger.error('Sync failed.', report.failure);
      throw StateError(report.failure!.message);
    }
    _logger.info(
      'Sync completed: downloaded=${report.downloaded}, uploaded=${report.uploaded}, conflicts=${report.conflicts}.',
    );
    return report;
  }

  Future<List<dartloom.SyncConflict>> listConflicts() =>
      _delegate?.listConflicts() ?? Future.value(const []);

  Future<void> resolveConflict(String id, ConflictResolution resolution) =>
      _delegate!.resolveConflict(
        id,
        dartloom.SyncConflictResolution(
          resolution == ConflictResolution.local
              ? dartloom.SyncConflictChoice.useLocal
              : dartloom.SyncConflictChoice.useRemote,
        ),
      );

  Future<void> dispose() => _delegate?.dispose() ?? Future.value();

  dartloom.SyncProfileDraft _profileDraft({
    required String id,
    required String url,
    required String username,
    required String password,
  }) => dartloom.SyncProfileDraft(
    id: id,
    label: 'MindBubble WebDAV',
    backend: 'webdav',
    options: {'base_url': url, 'username': username},
    secrets: {'password': password},
  );

  Future<String> _readString(String key) async {
    final value = _settings != null
        ? await _settings.read(key)
        : await _persistence?.read(key);
    return value is String ? value : '';
  }

  Future<void> _write(String key, String value) async {
    if (_settings != null) {
      await _settings.write(key, value);
    } else {
      await _persistence?.write(key, value);
    }
  }

  Future<void> _remove(String key) async {
    if (_settings != null) await _settings.remove(key);
  }

  Future<String?> _profilePassword() async {
    final delegate = _delegate;
    if (delegate == null) return _readString(_passwordKey);
    final profile = (await delegate.listProfiles())
        .where((value) => value.isActive)
        .firstOrNull;
    final secrets = _secrets;
    final scope = _scope;
    if (profile == null || secrets == null || scope == null) return null;
    final value = await secrets.read(
      'sync.mindbubble.profile.${scope.activeProfileId}.secret.password',
    );
    return value is String ? value : null;
  }
}
