import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final syncStateStoreProvider = Provider<SyncStateStore>(
  (_) => throw UnimplementedError(),
);

class ObjectSyncState {
  const ObjectSyncState({
    required this.etag,
    required this.baseHash,
    required this.baseRaw,
  });

  final String etag;
  final String baseHash;
  final String baseRaw;

  Map<String, Object?> toJson() => {
    'etag': etag,
    'baseHash': baseHash,
    'baseRaw': baseRaw,
  };

  factory ObjectSyncState.fromJson(Map<String, Object?> json) =>
      ObjectSyncState(
        etag: json['etag'] as String,
        baseHash: json['baseHash'] as String,
        baseRaw: json['baseRaw'] as String,
      );
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.localRaw,
    required this.remoteRaw,
    required this.remoteEtag,
    required this.reason,
  });

  final String id;
  final String? localRaw;
  final String? remoteRaw;
  final String? remoteEtag;
  final String reason;

  Map<String, Object?> toJson() => {
    'id': id,
    'localRaw': localRaw,
    'remoteRaw': remoteRaw,
    'remoteEtag': remoteEtag,
    'reason': reason,
  };

  factory SyncConflict.fromJson(Map<String, Object?> json) => SyncConflict(
    id: json['id'] as String,
    localRaw: json['localRaw'] as String?,
    remoteRaw: json['remoteRaw'] as String?,
    remoteEtag: json['remoteEtag'] as String?,
    reason: json['reason'] as String? ?? 'conflict',
  );
}

class SyncStateStore {
  SyncStateStore._(this.file);

  final File file;
  final Map<String, ObjectSyncState> objects = {};
  final Map<String, SyncConflict> conflicts = {};
  final Set<String> pendingDeletes = {};
  DateTime? lastSyncedAt;

  factory SyncStateStore.forTesting(File file) => SyncStateStore._(file);

  static Future<SyncStateStore> open() async {
    final support = await getApplicationSupportDirectory();
    final store = SyncStateStore._(
      File(path.join(support.path, 'MindBubble', 'sync-state.json')),
    );
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return;
      final rawObjects = decoded['objects'];
      if (rawObjects is Map) {
        for (final entry in rawObjects.entries) {
          if (entry.key is String && entry.value is Map) {
            objects[entry.key as String] = ObjectSyncState.fromJson(
              (entry.value as Map).cast<String, Object?>(),
            );
          }
        }
      }
      final rawConflicts = decoded['conflicts'];
      if (rawConflicts is Map) {
        for (final entry in rawConflicts.entries) {
          if (entry.key is String && entry.value is Map) {
            conflicts[entry.key as String] = SyncConflict.fromJson(
              (entry.value as Map).cast<String, Object?>(),
            );
          }
        }
      }
      final rawPendingDeletes = decoded['pendingDeletes'];
      if (rawPendingDeletes is List) {
        pendingDeletes.addAll(rawPendingDeletes.whereType<String>());
      }
      final timestamp = decoded['lastSyncedAt'];
      if (timestamp is String) lastSyncedAt = DateTime.tryParse(timestamp);
    } catch (_) {
      // A missing state file causes a conservative full comparison on the next
      // sync. User documents are never derived from this cache.
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
        'objects': {
          for (final entry in objects.entries) entry.key: entry.value.toJson(),
        },
        'conflicts': {
          for (final entry in conflicts.entries)
            entry.key: entry.value.toJson(),
        },
        'pendingDeletes': pendingDeletes.toList()..sort(),
      }),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}
