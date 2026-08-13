import 'dart:convert';
import 'dart:io';

import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:path/path.dart' as p;

import '../services/mindbubble_merge_policy.dart';
import '../services/mindbubble_replica_store.dart';
import '../services/shared_mcp_journal.dart';
import 'app_paths.dart';

Future<DartloomBinding<Object>> createMarkdownReplicaStore(
  DartloomFactoryContext context,
) async {
  final paths = await MindBubblePaths.resolve();
  final files = await FileDirectoryStore.open(
    root: paths.businessRoot,
    metadataRoot: paths.metadataRoot,
    hierarchical: false,
  );
  final journal = SharedMcpJournal(
    documentRoot: paths.businessRoot,
    journalRoot: Directory(p.join(paths.supportRoot.path, 'mcp-journal')),
  );
  await _importVerifiedLegacyDeletes(paths, journal);
  final store = MindBubbleReplicaStore(files: files, journal: journal);
  await _attachExistingDocumentsOnce(store, paths.metadataRoot);
  return DartloomBinding<ReplicaStore>(store, dispose: store.close);
}

Future<void> _importVerifiedLegacyDeletes(
  MindBubblePaths paths,
  SharedMcpJournal journal,
) async {
  final marker = File(
    p.join(paths.supportRoot.path, 'dartloom', 'legacy-deletes-imported-v1'),
  );
  if (await marker.exists()) return;
  final stateFile = File(p.join(paths.supportRoot.path, 'sync-state.json'));
  final pendingRoot = Directory(
    p.join(paths.businessRoot.parent.path, '.sync', 'pending-deletes'),
  );
  final verified = <String>{};
  if (await stateFile.exists() && await pendingRoot.exists()) {
    final decoded = jsonDecode(await stateFile.readAsString());
    if (decoded is Map && decoded['pendingDeletes'] is List) {
      final pending = (decoded['pendingDeletes'] as List)
          .whereType<String>()
          .toSet();
      await for (final entity in pendingRoot.list(followLinks: false)) {
        if (entity is! File) continue;
        final id = p.basename(entity.path);
        if (!pending.contains(id)) continue;
        final stat = await entity.stat();
        await journal.importAppliedDeleteIntent(
          operationId: 'legacy-delete/$id',
          objectId: id,
          createdAt: stat.modified,
        );
        verified.add(id);
      }
    }
  }
  await marker.parent.create(recursive: true);
  final temporary = File('${marker.path}.tmp');
  await temporary.writeAsString(
    jsonEncode({
      'version': 1,
      'verifiedDeleteIds': verified.toList()..sort(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    }),
    flush: true,
  );
  await temporary.rename(marker.path);
}

Future<void> _attachExistingDocumentsOnce(
  ReplicaStore store,
  Directory metadataRoot,
) async {
  final marker = File(p.join(metadataRoot.path, 'existing-data-attached-v1'));
  if (await marker.exists()) return;
  for (final object in await store.scan()) {
    if (!object.exists || !object.key.toLowerCase().endsWith('.md')) continue;
    final bytes = await store.readBytes(object.key);
    if (bytes != null) {
      await store.writeBytes(
        object.key,
        bytes,
        origin: StoreMutationOrigin.migration,
      );
    }
  }
  await marker.parent.create(recursive: true);
  final temporary = File('${marker.path}.tmp');
  await temporary.writeAsString(
    DateTime.now().toUtc().toIso8601String(),
    flush: true,
  );
  await temporary.rename(marker.path);
}

Future<DartloomBinding<Object>> createMindBubbleMergePolicy(
  DartloomFactoryContext context,
) async => DartloomBinding<SyncMergePolicy>(mindBubbleMergePolicy);

final dartloomApplicationFactories = <String, DartloomFactory>{
  'createMarkdownReplicaStore': createMarkdownReplicaStore,
  'createMindBubbleMergePolicy': createMindBubbleMergePolicy,
};
