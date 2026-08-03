import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database.dart';
import 'webdav_transport.dart';

final syncRevisionProvider = StateProvider<int>((_) => 0);
final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(databaseProvider).connection,
    () => ref.read(syncRevisionProvider.notifier).state++,
  ),
);

class WebDavConfig {
  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.appPassword,
    required this.deviceId,
  });

  final String serverUrl;
  final String username;
  final String appPassword;
  final String deviceId;

  Map<String, String> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'appPassword': appPassword,
    'deviceId': deviceId,
  };

  factory WebDavConfig.fromJson(Map<String, Object?> json) => WebDavConfig(
    serverUrl: json['serverUrl'] as String? ?? '',
    username: json['username'] as String? ?? '',
    appPassword: json['appPassword'] as String? ?? '',
    deviceId: json['deviceId'] as String? ?? '',
  );
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Stores WebDAV settings and synchronizes last-write-wins device snapshots.
///
/// Each device owns one remote file, avoiding concurrent PUTs to the same path.
/// Deleted bubbles remain as tombstones so deletion also reaches offline peers.
class SyncService {
  SyncService(this._database, this._dataChanged);

  static const _deviceDirectory = '/MindBubble/devices';

  final Database _database;
  final void Function() _dataChanged;
  WebDavConfig? _config;
  Timer? _debounce;
  Future<void> _syncQueue = Future<void>.value();

  WebDavConfig? get config => _config;
  bool get isConfigured => _config != null;

  Future<WebDavConfig?> loadConfig() async {
    if (_config != null) return _config;
    final file = await _configFile();
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return null;
    final loaded = WebDavConfig.fromJson(decoded);
    if (loaded.serverUrl.isEmpty ||
        loaded.username.isEmpty ||
        loaded.appPassword.isEmpty) {
      return null;
    }
    if (loaded.deviceId.isEmpty) {
      _config = WebDavConfig(
        serverUrl: loaded.serverUrl,
        username: loaded.username,
        appPassword: loaded.appPassword,
        deviceId: _newDeviceId(),
      );
      await _saveConfig();
    } else {
      _config = loaded;
    }
    return _config;
  }

  Future<void> configureWebDav({
    required String serverUrl,
    required String username,
    required String appPassword,
  }) async {
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const SyncException('WebDAV 服务器地址必须是有效的 HTTP 或 HTTPS 地址。');
    }
    _config = WebDavConfig(
      serverUrl: serverUrl.trim(),
      username: username.trim(),
      appPassword: appPassword,
      deviceId: _config?.deviceId ?? _newDeviceId(),
    );
    await _saveConfig();
  }

  /// Debounces repository writes so a multi-row import triggers one sync.
  void scheduleSync() {
    if (!isConfigured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      unawaited(
        syncNow().catchError((Object _) {
          // Automatic sync is retried after a later change/resume/timer tick.
          // Explicit setup reports errors in the settings dialog.
        }),
      );
    });
  }

  /// Serializes attempts to avoid overlapping syncs within this process.
  Future<void> syncNow() {
    final result = Completer<void>();
    _syncQueue = _syncQueue.catchError((Object _) {}).then((_) async {
      try {
        await _synchronize();
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _synchronize() async {
    final config = await loadConfig();
    if (config == null) return;

    final transport = HttpWebDavTransport(
      serverUrl: config.serverUrl,
      username: config.username,
      password: config.appPassword,
    );
    try {
      await transport.ensureDirectory(_deviceDirectory);
      final remoteRows = <Map<String, Object?>>[];
      final files = await transport.list(_deviceDirectory);
      for (final file in files) {
        if (file.isDirectory || !file.name.endsWith('.json')) {
          continue;
        }
        remoteRows.addAll(_decodeSnapshot(await transport.read(file.path)));
      }

      final localRows = await _database.query('bubbles');
      final merged = mergeRows(localRows, remoteRows);
      await _applyMergedRows(merged);
      await transport.write(
        '$_deviceDirectory/${config.deviceId}.json',
        utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
            'deviceId': config.deviceId,
            'bubbles': merged,
          }),
        ),
      );
    } on FormatException catch (error) {
      throw SyncException('云端同步文件格式无效：${error.message}');
    } catch (error) {
      final text = error.toString();
      if (text.contains('401') || text.contains('403')) {
        throw const SyncException('WebDAV 认证失败，请检查账号和应用密码。');
      }
      throw SyncException('WebDAV 同步失败：$text');
    } finally {
      transport.close();
    }
  }

  static List<Map<String, Object?>> _decodeSnapshot(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?> || decoded['bubbles'] is! List) {
      throw const FormatException('缺少 bubbles 数组');
    }
    return (decoded['bubbles'] as List)
        .whereType<Map>()
        .map((row) => _normalizeRow(row.cast<String, Object?>()))
        .toList();
  }

  Future<void> _applyMergedRows(List<Map<String, Object?>> merged) async {
    await _database.transaction((transaction) async {
      for (final row in merged) {
        final currentRows = await transaction.query(
          'bubbles',
          where: 'id = ?',
          whereArgs: [row['id']],
          limit: 1,
        );
        if (currentRows.isNotEmpty &&
            !_isNewer(row, _normalizeRow(currentRows.single))) {
          continue;
        }
        await transaction.insert(
          'bubbles',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _dataChanged();
  }

  static List<Map<String, Object?>> mergeRows(
    List<Map<String, Object?>> local,
    List<Map<String, Object?>> remote,
  ) {
    final merged = <String, Map<String, Object?>>{};
    for (final candidate in [...local, ...remote]) {
      final row = _normalizeRow(candidate);
      final id = row['id']! as String;
      final current = merged[id];
      if (current == null || _isNewer(row, current)) merged[id] = row;
    }
    final result = merged.values.toList();
    result.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    return result;
  }

  static bool _isNewer(
    Map<String, Object?> candidate,
    Map<String, Object?> current,
  ) {
    final candidateTime = candidate['updated_at']! as int;
    final currentTime = current['updated_at']! as int;
    if (candidateTime != currentTime) return candidateTime > currentTime;
    return jsonEncode(candidate).compareTo(jsonEncode(current)) > 0;
  }

  static Map<String, Object?> _normalizeRow(Map<String, Object?> row) {
    final id = row['id'];
    final title = row['title'];
    final description = row['description'];
    final createdAt = row['created_at'];
    final updatedAt = row['updated_at'];
    if (id is! String ||
        title is! String ||
        description is! String ||
        createdAt is! int ||
        updatedAt is! int) {
      throw const FormatException('泡泡记录缺少必要字段');
    }
    int? optionalInt(String key) {
      final value = row[key];
      if (value == null) return null;
      if (value is int) return value;
      throw FormatException('$key 必须是整数');
    }

    return {
      'id': id,
      'title': title,
      'description': description,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_shown_at': optionalInt('last_shown_at'),
      'shown_count': optionalInt('shown_count') ?? 0,
      'appearance_frequency': (optionalInt('appearance_frequency') ?? 3).clamp(
        1,
        5,
      ),
      'deleted_at': optionalInt('deleted_at'),
      'field_versions': row['field_versions'] is String
          ? row['field_versions']!
          : '',
    };
  }

  Future<File> _configFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'webdav_config.json'));
  }

  Future<void> _saveConfig() async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_config!.toJson()), flush: true);
  }

  static String _newDeviceId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
