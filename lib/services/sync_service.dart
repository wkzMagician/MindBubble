import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final syncServiceProvider = Provider<SyncService>((_) => SyncService());

class WebDavConfig {
  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.appPassword,
  });

  final String serverUrl;
  final String username;
  final String appPassword;

  Map<String, String> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'appPassword': appPassword,
      };

  factory WebDavConfig.fromJson(Map<String, Object?> json) => WebDavConfig(
        serverUrl: json['serverUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        appPassword: json['appPassword'] as String? ?? '',
      );
}

/// Persists the WebDAV connection settings in the app support directory.
/// The password is obscured in the UI but intentionally uses ordinary app
/// configuration storage, matching the product requirement.
class SyncService {
  WebDavConfig? _config;

  WebDavConfig? get config => _config;
  bool get isConfigured => _config != null;

  Future<WebDavConfig?> loadConfig() async {
    if (_config != null) return _config;
    final file = await _configFile();
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return null;
    _config = WebDavConfig.fromJson(decoded);
    return _config;
  }

  Future<void> configureWebDav({
    required String serverUrl,
    required String username,
    required String appPassword,
  }) async {
    _config = WebDavConfig(
      serverUrl: serverUrl.trim(),
      username: username.trim(),
      appPassword: appPassword,
    );
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_config!.toJson()), flush: true);
  }

  Future<File> writeSyncLog(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) async {
    final directory = await getApplicationSupportDirectory();
    final outbox = Directory(path.join(directory.path, 'sync_outbox'));
    await outbox.create(recursive: true);
    final file = File(path.join(outbox.path, '$deviceId.mbsync'));
    await file.writeAsString(
      jsonEncode({'deviceId': deviceId, 'operations': operations}),
      flush: true,
    );
    return file;
  }

  Future<File> _configFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'webdav_config.json'));
  }
}
