import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/bubble.dart';
import 'bubble_document_store.dart';
import 'device_identity_service.dart';
import 'sync_state_store.dart';
import 'webdav_transport.dart';

final syncRevisionProvider = StateProvider<int>((_) => 0);
final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(bubbleDocumentStoreProvider),
    ref.watch(syncStateStoreProvider),
    ref.watch(deviceIdentityProvider),
    () => ref.read(syncRevisionProvider.notifier).state++,
  ),
);

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

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum ConflictResolution { local, remote }

typedef WebDavTransportFactory =
    WebDavTransport Function(WebDavConfig configuration);

class SyncService {
  SyncService(
    this._store,
    this._state,
    this._identity,
    this._dataChanged, {
    WebDavTransportFactory? transportFactory,
    File? configFile,
    File? legacyConfigFile,
  }) : _transportFactory = transportFactory,
       _configFileOverride = configFile,
       _legacyConfigFileOverride = legacyConfigFile;

  static const _rootDirectory = '/MindBubble/v2';
  static const _bubbleDirectory = '$_rootDirectory/bubbles';
  static const _legacyDirectory = '/MindBubble/devices';

  final BubbleDocumentStore _store;
  final SyncStateStore _state;
  final DeviceIdentity _identity;
  final void Function() _dataChanged;
  final WebDavTransportFactory? _transportFactory;
  final File? _configFileOverride;
  final File? _legacyConfigFileOverride;
  WebDavConfig? _config;
  Timer? _debounce;
  Future<void> _syncQueue = Future<void>.value();

  WebDavConfig? get config => _config;
  bool get isConfigured => _config != null;
  List<SyncConflict> get conflicts => _state.conflicts.values.toList();
  DateTime? get lastSyncedAt => _state.lastSyncedAt;

  Future<WebDavConfig?> loadConfig() async {
    if (_config != null) return _config;
    var file = await _configFile();
    if (!await file.exists()) {
      final legacy = await _legacyConfigFile();
      if (!await legacy.exists()) return null;
      file = legacy;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return null;
    final loaded = WebDavConfig.fromJson(decoded);
    if (loaded.serverUrl.isEmpty ||
        loaded.username.isEmpty ||
        loaded.appPassword.isEmpty) {
      return null;
    }
    _config = loaded;
    if (file.path != (await _configFile()).path) await _saveConfig();
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
    final candidate = WebDavConfig(
      serverUrl: serverUrl.trim(),
      username: username.trim(),
      appPassword: appPassword,
    );
    await _verifyCapabilities(candidate);
    _config = candidate;
    await _saveConfig();
  }

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 15), () {
      unawaited(
        loadConfig()
            .then((config) {
              if (config != null) return syncNow();
            })
            .catchError((Object _) {}),
      );
    });
  }

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
    final transport = _transport(config);
    try {
      await transport.ensureDirectory(_bubbleDirectory);
      await _migrateLegacySnapshotsOnce(transport);
      final documentsChanged = await _syncDocuments(transport);
      _state.lastSyncedAt = DateTime.now();
      await _state.save();
      if (documentsChanged) _store.notifyChanged();
      _dataChanged();
    } on FormatException catch (error) {
      throw SyncException('云端文档格式无效：${error.message}');
    } on WebDavTransportException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        throw const SyncException('WebDAV 认证失败，请检查账号和应用密码。');
      }
      throw SyncException('WebDAV 同步失败：$error');
    } finally {
      transport.close();
    }
  }

  Future<bool> _syncDocuments(WebDavTransport transport) async {
    final local = await _store.readAllDocuments();
    var documentsChanged = false;
    if (_store.issues.isNotEmpty) {
      final issue = _store.issues.first;
      throw SyncException(
        '本地文档格式无效，已停止同步以避免数据丢失：'
        '${path.basename(issue.path)}（${issue.message}）',
      );
    }
    _state.pendingDeletes.addAll(await _store.readDeleteIntents());
    for (final id in _state.pendingDeletes.toList()) {
      if (local.containsKey(id)) {
        await _clearPendingDelete(id);
      }
    }
    final resources = await transport.list(_bubbleDirectory);
    final remote = <String, WebDavResource>{};
    for (final resource in resources) {
      if (resource.isDirectory || !resource.name.endsWith('.md')) continue;
      final id = path.basenameWithoutExtension(resource.name);
      if (resource.etag == null || resource.etag!.isEmpty) {
        throw SyncException('WebDAV 服务器没有为 $id.md 返回 ETag，无法安全同步。');
      }
      remote[id] = resource;
    }

    final ids = {
      ...local.keys,
      ...remote.keys,
      ..._state.objects.keys,
      ..._state.pendingDeletes,
    }.toList()..sort();
    for (final id in ids) {
      if (_state.conflicts.containsKey(id)) continue;
      final localDocument = local[id];
      final remoteResource = remote[id];
      final state = _state.objects[id];

      if (state == null) {
        documentsChanged |= await _syncUntracked(
          transport,
          id,
          localDocument,
          remoteResource,
        );
        continue;
      }

      final localChanged = localDocument?.hash != state.baseHash;
      final remoteChanged =
          remoteResource == null || remoteResource.etag != state.etag;
      if (!localChanged && !remoteChanged) continue;

      if (localChanged && !remoteChanged) {
        if (localDocument == null) {
          if (!_state.pendingDeletes.contains(id)) {
            final downloaded = await _readRemote(transport, id, remoteResource);
            await _recordConflict(
              SyncConflict(
                id: id,
                localRaw: null,
                remoteRaw: downloaded.document.raw,
                remoteEtag: downloaded.etag,
                reason: 'unconfirmed-local-delete',
              ),
            );
            continue;
          }
          await transport.delete(
            '$_bubbleDirectory/$id.md',
            ifMatch: state.etag,
          );
          _state.objects.remove(id);
          await _clearPendingDelete(id);
        } else {
          documentsChanged |= await _upload(
            transport,
            id,
            localDocument.raw,
            ifMatch: state.etag,
          );
        }
        continue;
      }

      if (!localChanged && remoteChanged) {
        if (remoteResource == null) {
          await _store.delete(id, notify: false);
          _state.objects.remove(id);
          await _clearPendingDelete(id);
          documentsChanged = true;
        } else {
          documentsChanged |= await _downloadAndApply(
            transport,
            id,
            remoteResource,
          );
        }
        continue;
      }

      documentsChanged |= await _resolveConcurrentChange(
        transport,
        id,
        state,
        localDocument,
        remoteResource,
      );
    }
    await _state.save();
    return documentsChanged;
  }

  Future<bool> _syncUntracked(
    WebDavTransport transport,
    String id,
    StoredBubbleDocument? local,
    WebDavResource? remote,
  ) async {
    if (local == null && remote == null) {
      await _clearPendingDelete(id);
      return false;
    }
    if (local != null && remote == null) {
      return _upload(transport, id, local.raw, createOnly: true);
    }
    if (local == null && remote != null) {
      if (_state.pendingDeletes.contains(id)) {
        final downloaded = await _readRemote(transport, id, remote);
        await _recordConflict(
          SyncConflict(
            id: id,
            localRaw: null,
            remoteRaw: downloaded.document.raw,
            remoteEtag: downloaded.etag,
            reason: 'local-delete-remote-edit',
          ),
        );
        return false;
      }
      return _downloadAndApply(transport, id, remote);
    }
    final downloaded = await _readRemote(transport, id, remote!);
    if (downloaded.document.hash == local!.hash) {
      _remember(id, downloaded.document.raw, downloaded.etag);
      return false;
    }
    await _recordConflict(
      SyncConflict(
        id: id,
        localRaw: local.raw,
        remoteRaw: downloaded.document.raw,
        remoteEtag: downloaded.etag,
        reason: 'untracked-diverged',
      ),
    );
    return false;
  }

  Future<bool> _resolveConcurrentChange(
    WebDavTransport transport,
    String id,
    ObjectSyncState state,
    StoredBubbleDocument? local,
    WebDavResource? remote,
  ) async {
    if (local == null && remote == null) {
      _state.objects.remove(id);
      await _clearPendingDelete(id);
      return false;
    }
    if (local == null || remote == null) {
      String? remoteRaw;
      String? remoteEtag;
      if (remote != null) {
        final downloaded = await _readRemote(transport, id, remote);
        remoteRaw = downloaded.document.raw;
        remoteEtag = downloaded.etag;
      }
      await _recordConflict(
        SyncConflict(
          id: id,
          localRaw: local?.raw,
          remoteRaw: remoteRaw,
          remoteEtag: remoteEtag,
          reason: local == null
              ? 'local-delete-remote-edit'
              : 'remote-delete-local-edit',
        ),
      );
      return false;
    }

    final downloaded = await _readRemote(transport, id, remote);
    final merged = _threeWayMerge(
      id: id,
      baseRaw: state.baseRaw,
      localRaw: local.raw,
      remoteRaw: downloaded.document.raw,
    );
    if (merged == null) {
      await _recordConflict(
        SyncConflict(
          id: id,
          localRaw: local.raw,
          remoteRaw: downloaded.document.raw,
          remoteEtag: downloaded.etag,
          reason: 'same-field',
        ),
      );
      return false;
    }
    final changed = BubbleDocumentCodec.hash(merged) != local.hash;
    if (changed) await _store.writeRaw(id, merged, notify: false);
    final uploadChanged = await _upload(
      transport,
      id,
      merged,
      ifMatch: downloaded.etag,
    );
    return changed || uploadChanged;
  }

  String? _threeWayMerge({
    required String id,
    required String baseRaw,
    required String localRaw,
    required String remoteRaw,
  }) {
    final base = BubbleDocumentCodec.decode(baseRaw, expectedId: id).bubble;
    final local = BubbleDocumentCodec.decode(localRaw, expectedId: id).bubble;
    final remote = BubbleDocumentCodec.decode(remoteRaw, expectedId: id).bubble;

    T? mergeValue<T>(T baseValue, T localValue, T remoteValue) {
      if (localValue == remoteValue) return localValue;
      if (localValue == baseValue) return remoteValue;
      if (remoteValue == baseValue) return localValue;
      return null;
    }

    final title = mergeValue(base.title, local.title, remote.title);
    final description = mergeValue(
      base.description,
      local.description,
      remote.description,
    );
    final frequency = mergeValue(
      base.appearanceFrequency,
      local.appearanceFrequency,
      remote.appearanceFrequency,
    );
    if (title == null || description == null || frequency == null) return null;

    final stats = <String, BubbleShowStats>{};
    for (final device in {
      ...base.shownByDevice.keys,
      ...local.shownByDevice.keys,
      ...remote.shownByDevice.keys,
    }) {
      final localStats = local.shownByDevice[device];
      final remoteStats = remote.shownByDevice[device];
      if (localStats == null) {
        if (remoteStats != null) stats[device] = remoteStats;
      } else if (remoteStats == null) {
        stats[device] = localStats;
      } else {
        final localTime = localStats.lastShownAt;
        final remoteTime = remoteStats.lastShownAt;
        stats[device] = BubbleShowStats(
          count: localStats.count > remoteStats.count
              ? localStats.count
              : remoteStats.count,
          lastShownAt: localTime == null
              ? remoteTime
              : remoteTime == null || localTime.isAfter(remoteTime)
              ? localTime
              : remoteTime,
        );
      }
    }
    final merged = Bubble(
      id: id,
      title: title,
      description: description,
      createdAt: local.createdAt.isBefore(remote.createdAt)
          ? local.createdAt
          : remote.createdAt,
      updatedAt: DateTime.now(),
      appearanceFrequency: frequency,
      shownByDevice: stats,
    );
    return BubbleDocumentCodec.encode(merged, updatedBy: _identity.id);
  }

  Future<bool> _downloadAndApply(
    WebDavTransport transport,
    String id,
    WebDavResource resource,
  ) async {
    final downloaded = await _readRemote(transport, id, resource);
    final current = await _store.readDocument(id);
    final changed = current?.hash != downloaded.document.hash;
    if (changed) {
      await _store.writeRaw(id, downloaded.document.raw, notify: false);
    }
    _remember(id, downloaded.document.raw, downloaded.etag);
    await _clearPendingDelete(id);
    return changed;
  }

  Future<_RemoteDocument> _readRemote(
    WebDavTransport transport,
    String id,
    WebDavResource resource,
  ) async {
    final response = await transport.read(resource.path);
    final raw = utf8.decode(response.bytes);
    final document = BubbleDocumentCodec.decode(raw, expectedId: id);
    final etag = response.etag ?? resource.etag;
    if (etag == null || etag.isEmpty) {
      throw SyncException('WebDAV 服务器没有为 $id.md 返回 ETag。');
    }
    return _RemoteDocument(document, etag);
  }

  Future<bool> _upload(
    WebDavTransport transport,
    String id,
    String raw, {
    String? ifMatch,
    bool createOnly = false,
  }) async {
    final uploadedEtag = await transport.write(
      '$_bubbleDirectory/$id.md',
      utf8.encode(raw),
      ifMatch: ifMatch,
      createOnly: createOnly,
      contentType: 'text/markdown; charset=utf-8',
    );
    final result = await transport.read('$_bubbleDirectory/$id.md');
    final etag = result.etag ?? uploadedEtag;
    if (etag == null || etag.isEmpty) {
      throw SyncException('WebDAV 服务器上传后没有返回 $id.md 的 ETag。');
    }
    final canonicalRaw = utf8.decode(result.bytes);
    final document = BubbleDocumentCodec.decode(canonicalRaw, expectedId: id);
    final changed = document.hash != BubbleDocumentCodec.hash(raw);
    if (changed) {
      await _store.writeRaw(id, canonicalRaw, notify: false);
    }
    _remember(id, canonicalRaw, etag);
    return changed;
  }

  void _remember(String id, String raw, String etag) {
    _state.objects[id] = ObjectSyncState(
      etag: etag,
      baseHash: BubbleDocumentCodec.hash(raw),
      baseRaw: raw,
    );
    _state.conflicts.remove(id);
  }

  Future<void> _recordConflict(SyncConflict conflict) async {
    _state.conflicts[conflict.id] = conflict;
    await _state.save();
    _dataChanged();
  }

  Future<void> _clearPendingDelete(String id) async {
    _state.pendingDeletes.remove(id);
    await _store.clearDeleteIntent(id);
  }

  Future<void> resolveConflict(String id, ConflictResolution resolution) async {
    final conflict = _state.conflicts[id];
    final config = await loadConfig();
    if (conflict == null || config == null) return;
    final transport = _transport(config);
    try {
      final chosen = resolution == ConflictResolution.local
          ? conflict.localRaw
          : conflict.remoteRaw;
      if (resolution == ConflictResolution.local) {
        if (chosen == null) {
          await transport.delete(
            '$_bubbleDirectory/$id.md',
            ifMatch: conflict.remoteEtag,
          );
          await _store.delete(id, notify: false);
          _state.objects.remove(id);
          await _clearPendingDelete(id);
        } else {
          await _store.writeRaw(id, chosen, notify: false);
          await _upload(
            transport,
            id,
            chosen,
            ifMatch: conflict.remoteEtag,
            createOnly: conflict.remoteEtag == null,
          );
        }
      } else if (chosen == null) {
        await _store.delete(id, notify: false);
        _state.objects.remove(id);
        await _clearPendingDelete(id);
      } else {
        await _store.writeRaw(id, chosen, notify: false);
        final etag = conflict.remoteEtag;
        if (etag == null) {
          throw const SyncException('远端冲突版本缺少 ETag，请重新同步。');
        }
        _remember(id, chosen, etag);
      }
      _state.conflicts.remove(id);
      await _clearPendingDelete(id);
      await _state.save();
      _store.notifyChanged();
      _dataChanged();
    } finally {
      transport.close();
    }
  }

  Future<void> _verifyCapabilities(WebDavConfig config) async {
    final transport = _transport(config);
    final name =
        '.mindbubble-capability-${_identity.id}-'
        '${DateTime.now().microsecondsSinceEpoch}.tmp';
    final remotePath = '$_rootDirectory/$name';
    try {
      await transport.ensureDirectory(_rootDirectory);
      await transport.write(
        remotePath,
        utf8.encode('MindBubble capability check'),
        createOnly: true,
        contentType: 'text/plain; charset=utf-8',
      );
      final resources = await transport.list(_rootDirectory);
      final resource = resources.where((item) => item.name == name).firstOrNull;
      final etag = resource?.etag;
      if (etag == null || etag.isEmpty) {
        throw const SyncException('WebDAV 服务器不提供 ETag，无法安全同步。');
      }
      var rejected = false;
      try {
        await transport.write(
          remotePath,
          utf8.encode('must be rejected'),
          ifMatch: '"mindbubble-invalid-etag"',
          contentType: 'text/plain; charset=utf-8',
        );
      } on WebDavTransportException catch (error) {
        rejected = error.statusCode == 412;
      }
      if (!rejected) {
        throw const SyncException('WebDAV 服务器不支持 If-Match 条件写入。');
      }
      await transport.delete(remotePath, ifMatch: etag);
    } finally {
      try {
        await transport.delete(remotePath);
      } catch (_) {
        // Best-effort cleanup of the capability probe.
      }
      transport.close();
    }
  }

  Future<void> _migrateLegacySnapshotsOnce(WebDavTransport transport) async {
    final marker = File(
      path.join(_store.supportRoot.path, 'webdav-v1-imported'),
    );
    if (await marker.exists()) return;
    final newest = <String, Map<String, Object?>>{};
    try {
      final resources = await transport.list(_legacyDirectory);
      for (final resource in resources) {
        if (resource.isDirectory || !resource.name.endsWith('.json')) continue;
        final response = await transport.read(resource.path);
        final decoded = jsonDecode(utf8.decode(response.bytes));
        if (decoded is! Map<String, Object?> || decoded['bubbles'] is! List) {
          continue;
        }
        for (final value in decoded['bubbles'] as List) {
          if (value is! Map) continue;
          final row = value.cast<String, Object?>();
          final id = row['id'];
          final updatedAt = row['updated_at'];
          if (id is! String || updatedAt is! int) continue;
          final previous = newest[id];
          if (previous == null || (previous['updated_at'] as int) < updatedAt) {
            newest[id] = row;
          }
        }
      }
    } on WebDavTransportException catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    for (final row in newest.values) {
      final remoteBubble = Bubble.fromMap(row);
      final local = await _store.readDocument(remoteBubble.id);
      if (row['deleted_at'] != null) {
        if (local != null &&
            !local.bubble.updatedAt.isAfter(remoteBubble.updatedAt)) {
          await _store.delete(remoteBubble.id, notify: false);
        }
        continue;
      }
      if (local != null &&
          !remoteBubble.updatedAt.isAfter(local.bubble.updatedAt)) {
        continue;
      }
      final stats = remoteBubble.shownCount == 0
          ? const <String, BubbleShowStats>{}
          : {
              'legacy': BubbleShowStats(
                count: remoteBubble.shownCount,
                lastShownAt: remoteBubble.lastShownAt,
              ),
            };
      await _store.save(remoteBubble.copyWith(shownByDevice: stats));
    }
    await marker.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
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

  Future<void> _saveConfig() async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_config!.toJson()), flush: true);
  }
}

class _RemoteDocument {
  const _RemoteDocument(this.document, this.etag);

  final StoredBubbleDocument document;
  final String etag;
}
