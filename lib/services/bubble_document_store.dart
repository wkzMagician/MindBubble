import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/bubble.dart';
import 'device_identity_service.dart';

final bubbleDocumentStoreProvider = Provider<BubbleDocumentStore>(
  (_) => throw UnimplementedError(),
);

final documentStoreRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(bubbleDocumentStoreProvider).revisions;
});

class DocumentStoreIssue {
  const DocumentStoreIssue(this.path, this.message);

  final String path;
  final String message;
}

class StoredBubbleDocument {
  const StoredBubbleDocument({
    required this.bubble,
    required this.raw,
    required this.hash,
  });

  final Bubble bubble;
  final String raw;
  final String hash;
}

class BubbleDocumentCodec {
  static const schemaVersion = 2;

  static String encode(Bubble bubble, {required String updatedBy}) {
    final metadata = <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': bubble.id,
      'title': bubble.title,
      'createdAt': bubble.createdAt.millisecondsSinceEpoch,
      'updatedAt': bubble.updatedAt.millisecondsSinceEpoch,
      'appearanceFrequency': bubble.appearanceFrequency,
      'updatedBy': updatedBy,
      'shownByDevice': {
        for (final entry in bubble.shownByDevice.entries)
          entry.key: entry.value.toJson(),
      },
    };
    return '---\n'
        '${const JsonEncoder.withIndent('  ').convert(metadata)}\n'
        '---\n\n'
        '${bubble.description}';
  }

  static StoredBubbleDocument decode(String raw, {String? expectedId}) {
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('Missing JSON front matter');
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end < 0) throw const FormatException('Unclosed JSON front matter');
    final metadata = jsonDecode(normalized.substring(4, end));
    if (metadata is! Map<String, Object?>) {
      throw const FormatException('Front matter must be a JSON object');
    }
    final id = metadata['id'];
    final title = metadata['title'];
    final createdAt = metadata['createdAt'];
    final updatedAt = metadata['updatedAt'];
    if (metadata['schemaVersion'] != schemaVersion ||
        id is! String ||
        title is! String ||
        createdAt is! num ||
        updatedAt is! num) {
      throw const FormatException('Invalid MindBubble document metadata');
    }
    if (expectedId != null && id != expectedId) {
      throw FormatException('Document id $id does not match $expectedId.md');
    }
    final shownByDevice = <String, BubbleShowStats>{};
    final rawStats = metadata['shownByDevice'];
    if (rawStats is Map) {
      for (final entry in rawStats.entries) {
        if (entry.key is String && entry.value is Map) {
          shownByDevice[entry.key as String] = BubbleShowStats.fromJson(
            (entry.value as Map).cast<String, Object?>(),
          );
        }
      }
    }
    var bodyStart = end + '\n---\n'.length;
    if (normalized.startsWith('\n', bodyStart)) bodyStart++;
    final bubble = Bubble(
      id: id,
      title: title,
      description: normalized.substring(bodyStart),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt.toInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt()),
      appearanceFrequency:
          (metadata['appearanceFrequency'] as num?)?.toInt().clamp(1, 5) ?? 3,
      shownByDevice: Map.unmodifiable(shownByDevice),
    );
    return StoredBubbleDocument(
      bubble: bubble,
      raw: normalized,
      hash: hash(normalized),
    );
  }

  static String hash(String raw) => sha256.convert(utf8.encode(raw)).toString();
}

class BubbleDocumentStore {
  BubbleDocumentStore._({
    required this.root,
    required this.supportRoot,
    required this.deviceIdentity,
  });

  final Directory root;
  final Directory supportRoot;
  final DeviceIdentity deviceIdentity;
  final _revisions = StreamController<int>.broadcast();
  final List<DocumentStoreIssue> _issues = [];
  StreamSubscription<FileSystemEvent>? _watcher;
  int _revision = 0;
  Timer? _watchDebounce;

  factory BubbleDocumentStore.forTesting({
    required Directory root,
    required Directory supportRoot,
    required DeviceIdentity deviceIdentity,
  }) => BubbleDocumentStore._(
    root: root,
    supportRoot: supportRoot,
    deviceIdentity: deviceIdentity,
  );

  Stream<int> get revisions => _revisions.stream;
  List<DocumentStoreIssue> get issues => List.unmodifiable(_issues);
  Directory get pendingDeleteRoot =>
      Directory(path.join(root.parent.path, '.sync', 'pending-deletes'));

  static Future<BubbleDocumentStore> open(DeviceIdentity identity) async {
    final documents = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final store = BubbleDocumentStore._(
      root: Directory(path.join(documents.path, 'MindBubble', 'bubbles')),
      supportRoot: Directory(path.join(support.path, 'MindBubble')),
      deviceIdentity: identity,
    );
    await store.root.create(recursive: true);
    await store.pendingDeleteRoot.create(recursive: true);
    await store.supportRoot.create(recursive: true);
    await store._migrateLegacyDatabase(documents);
    store._watcher = store.root.watch().listen((_) {
      store._watchDebounce?.cancel();
      store._watchDebounce = Timer(
        const Duration(milliseconds: 300),
        store.notifyChanged,
      );
    });
    return store;
  }

  File fileFor(String id) => File(path.join(root.path, '$id.md'));

  Future<Map<String, StoredBubbleDocument>> readAllDocuments() async {
    _issues.clear();
    final result = <String, StoredBubbleDocument>{};
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
        continue;
      }
      final id = path.basenameWithoutExtension(entity.path);
      try {
        result[id] = BubbleDocumentCodec.decode(
          await entity.readAsString(),
          expectedId: id,
        );
      } catch (error) {
        _issues.add(DocumentStoreIssue(entity.path, '$error'));
      }
    }
    return result;
  }

  Future<List<Bubble>> readAll() async {
    final documents = await readAllDocuments();
    final bubbles = documents.values.map((document) => document.bubble).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return bubbles;
  }

  Future<StoredBubbleDocument?> readDocument(String id) async {
    final file = fileFor(id);
    if (!await file.exists()) return null;
    return BubbleDocumentCodec.decode(
      await file.readAsString(),
      expectedId: id,
    );
  }

  Future<void> save(Bubble bubble) async {
    await writeRaw(
      bubble.id,
      BubbleDocumentCodec.encode(bubble, updatedBy: deviceIdentity.id),
    );
  }

  Future<void> writeRaw(String id, String raw, {bool notify = true}) async {
    BubbleDocumentCodec.decode(raw, expectedId: id);
    final target = fileFor(id);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(raw, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    }
    if (notify) notifyChanged();
  }

  Future<void> delete(String id, {bool notify = true}) async {
    final file = fileFor(id);
    if (await file.exists()) await file.delete();
    if (notify) notifyChanged();
  }

  Future<void> markDeleteIntent(String id) async {
    await pendingDeleteRoot.create(recursive: true);
    await File(
      path.join(pendingDeleteRoot.path, id),
    ).writeAsString(DateTime.now().toUtc().toIso8601String(), flush: true);
  }

  Future<void> clearDeleteIntent(String id) async {
    final marker = File(path.join(pendingDeleteRoot.path, id));
    if (await marker.exists()) await marker.delete();
  }

  Future<Set<String>> readDeleteIntents() async {
    if (!await pendingDeleteRoot.exists()) return {};
    return pendingDeleteRoot
        .list()
        .where((entity) => entity is File)
        .map((entity) => path.basename(entity.path))
        .toSet();
  }

  void notifyChanged() {
    _revision++;
    _revisions.add(_revision);
  }

  Future<void> _migrateLegacyDatabase(Directory documents) async {
    final marker = File(path.join(supportRoot.path, 'document-v2-migrated'));
    if (await marker.exists()) return;
    final databaseFile = File(path.join(documents.path, 'mind_bubble.db'));
    if (!await databaseFile.exists()) {
      await marker.writeAsString('no legacy database', flush: true);
      return;
    }

    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      databaseFile.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final rows = await database.query('bubbles', where: 'deleted_at IS NULL');
      for (final row in rows) {
        final legacy = Bubble.fromMap(row);
        if (await fileFor(legacy.id).exists()) continue;
        final shownByDevice =
            legacy.shownCount == 0 && legacy.lastShownAt == null
            ? const <String, BubbleShowStats>{}
            : {
                deviceIdentity.id: BubbleShowStats(
                  count: legacy.shownCount,
                  lastShownAt: legacy.lastShownAt,
                ),
              };
        await save(legacy.copyWith(shownByDevice: shownByDevice));
      }
    } finally {
      await database.close();
    }
    await marker.writeAsString(
      'migrated ${DateTime.now().toUtc().toIso8601String()}',
      flush: true,
    );
  }

  Future<void> migrateLegacyDatabaseForTesting(Directory documents) =>
      _migrateLegacyDatabase(documents);

  Future<void> dispose() async {
    _watchDebounce?.cancel();
    await _watcher?.cancel();
    await _revisions.close();
  }
}
