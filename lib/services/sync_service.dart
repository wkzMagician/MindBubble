import 'dart:async';

import 'package:dartloom_sync/dartloom_sync.dart' as dartloom;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(persistence: SharedPreferencesSyncPersistence());
  ref.onDispose(service.dispose);
  return service;
});

final syncSnapshotProvider = StreamProvider<dartloom.SyncSnapshot>((ref) {
  return ref.watch(syncServiceProvider).states;
});

final syncConflictsProvider = FutureProvider<List<dartloom.SyncConflict>>((_) {
  return Future.value(const <dartloom.SyncConflict>[]);
});

enum ConflictResolution { local, remote }

class WebDavConfig {
  const WebDavConfig({required this.serverUrl, required this.username});

  final String serverUrl;
  final String username;
}

abstract interface class SyncPersistence {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// A small persistence adapter keeps the UI facade testable and avoids the
/// cached-instance behaviour of the legacy SharedPreferences API.
final class SharedPreferencesSyncPersistence implements SyncPersistence {
  SharedPreferencesSyncPersistence({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _preferences.setString(key, value);
  }
}

/// In-memory persistence used by unit tests and callers that provide their
/// own settings backend.
final class MemorySyncPersistence implements SyncPersistence {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

class SyncService {
  SyncService({SyncPersistence? persistence})
    : _persistence = persistence ?? SharedPreferencesSyncPersistence(),
      _snapshot = const dartloom.SyncSnapshot.initial();

  static const _serverKey = 'mindbubble.sync.webdav.server_url';
  static const _usernameKey = 'mindbubble.sync.webdav.username';
  static const _passwordKey = 'mindbubble.sync.webdav.app_password';

  final SyncPersistence _persistence;
  final dartloom.SyncSnapshot _snapshot;
  final StreamController<dartloom.SyncSnapshot> _states =
      StreamController<dartloom.SyncSnapshot>.broadcast();
  WebDavConfig? _config;
  bool _hasStoredPassword = false;

  dartloom.SyncSnapshot get snapshot => _snapshot;
  Stream<dartloom.SyncSnapshot> get states => _states.stream;
  DateTime? get lastSyncedAt => _snapshot.lastSuccessAt;
  bool get isConfigured => _config != null && _hasStoredPassword;

  Future<WebDavConfig?> loadConfig() async {
    final serverUrl = await _persistence.read(_serverKey);
    final username = await _persistence.read(_usernameKey);
    final password = await _persistence.read(_passwordKey);
    if (serverUrl == null ||
        username == null ||
        serverUrl.trim().isEmpty ||
        username.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      _config = null;
      _hasStoredPassword = false;
      return null;
    }
    _config = WebDavConfig(serverUrl: serverUrl, username: username);
    _hasStoredPassword = true;
    return _config;
  }

  void scheduleSync() {}
  Future<void> syncNow() async {}
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
    final existingPassword = await _persistence.read(_passwordKey);
    final password = appPassword.isNotEmpty ? appPassword : existingPassword;
    if (password == null || password.isEmpty) {
      throw const FormatException('WebDAV app password is required.');
    }

    await _persistence.write(_serverKey, normalizedServer);
    await _persistence.write(_usernameKey, normalizedUsername);
    await _persistence.write(_passwordKey, password);
    _config = WebDavConfig(
      serverUrl: normalizedServer,
      username: normalizedUsername,
    );
    _hasStoredPassword = true;
  }

  Future<void> resolveConflict(
    String id,
    ConflictResolution resolution,
  ) async {}

  Future<void> dispose() => _states.close();
}
