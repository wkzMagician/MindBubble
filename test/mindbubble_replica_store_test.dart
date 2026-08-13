import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/mindbubble_replica_store.dart';
import 'package:mind_bubble/services/shared_mcp_journal.dart';

void main() {
  test(
    'Flutter and MCP writes expose the same durable intent contract',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'mindbubble-adapter-',
      );
      final documentRoot = Directory(
        '${sandbox.path}${Platform.pathSeparator}docs',
      );
      final journal = SharedMcpJournal(
        documentRoot: documentRoot.absolute,
        journalRoot: Directory(
          '${sandbox.path}${Platform.pathSeparator}journal',
        ).absolute,
      );
      final files = await FileDirectoryStore.open(
        root: documentRoot.absolute,
        metadataRoot: Directory(
          '${sandbox.path}${Platform.pathSeparator}metadata',
        ).absolute,
        hierarchical: false,
      );
      final store = MindBubbleReplicaStore(files: files, journal: journal);
      addTearDown(() async {
        await store.close();
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
      });

      final flutterChange = store.changes.first;
      await store.writeBytes('flutter.md', Uint8List.fromList([1, 2, 3]));
      expect(
        await flutterChange,
        isA<StoreChange>()
            .having((change) => change.key, 'key', 'flutter.md')
            .having(
              (change) => change.origin,
              'origin',
              StoreMutationOrigin.application,
            ),
      );
      await journal.mutate(
        operationId: 'mcp/create/1',
        objectId: 'mcp',
        kind: SharedJournalIntentKind.create,
        expectedContentHash: null,
        documentBytes: [4, 5, 6],
        request: {'source': 'mcp'},
        result: {'id': 'mcp'},
      );

      final intents = await store.explicitIntents();
      expect(intents.map((intent) => intent.key).toSet(), {
        'flutter.md',
        'mcp.md',
      });
      expect(
        intents.map((intent) => intent.origin),
        everyElement(StoreMutationOrigin.application),
      );
      expect(
        intents.map((intent) => intent.kind),
        everyElement(StoreIntentKind.create),
      );

      final mcp = intents.singleWhere(
        (intent) => intent.operationId == 'mcp/create/1',
      );
      await store.forgetExplicitIntent(mcp.operationId);
      expect(
        (await store.explicitIntents()).map((intent) => intent.operationId),
        isNot(contains('mcp/create/1')),
      );
    },
  );

  test('MCP writes are classified as authorized journal changes', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'mindbubble-adapter-mcp-',
    );
    final documentRoot = Directory(
      '${sandbox.path}${Platform.pathSeparator}docs',
    );
    final journal = SharedMcpJournal(
      documentRoot: documentRoot.absolute,
      journalRoot: Directory(
        '${sandbox.path}${Platform.pathSeparator}journal',
      ).absolute,
    );
    final files = await FileDirectoryStore.open(
      root: documentRoot.absolute,
      metadataRoot: Directory(
        '${sandbox.path}${Platform.pathSeparator}metadata',
      ).absolute,
      hierarchical: false,
    );
    final store = MindBubbleReplicaStore(files: files, journal: journal);
    addTearDown(() async {
      await store.close();
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    final observed = store.changes.firstWhere(
      (change) => change.key == 'mcp.md',
    );
    await journal.mutate(
      operationId: 'mcp/create/change-classification',
      objectId: 'mcp',
      kind: SharedJournalIntentKind.create,
      expectedContentHash: null,
      documentBytes: [4, 5, 6],
      request: {'source': 'mcp'},
      result: {'id': 'mcp'},
    );

    expect(
      await observed.timeout(const Duration(seconds: 5)),
      isA<StoreChange>()
          .having(
            (change) => change.origin,
            'origin',
            StoreMutationOrigin.application,
          )
          .having((change) => change.kind, 'kind', StoreChangeKind.mutation),
    );
  });
}
