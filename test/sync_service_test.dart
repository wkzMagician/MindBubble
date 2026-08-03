import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/device_identity_service.dart';
import 'package:mind_bubble/services/sync_service.dart';
import 'package:mind_bubble/services/sync_state_store.dart';
import 'package:mind_bubble/services/webdav_transport.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('a bubble round trips through one Markdown document', () {
    final bubble = Bubble(
      id: 'bubble-1',
      title: 'Title',
      description: '## Body\n\nText\n\n---\n\nMore text',
      createdAt: DateTime.fromMillisecondsSinceEpoch(10),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(20),
      appearanceFrequency: 5,
      shownByDevice: {
        'device-a': BubbleShowStats(
          count: 2,
          lastShownAt: DateTime.fromMillisecondsSinceEpoch(15),
        ),
      },
    );

    final raw = BubbleDocumentCodec.encode(bubble, updatedBy: 'device-a');
    final restored = BubbleDocumentCodec.decode(raw, expectedId: 'bubble-1');

    expect(restored.bubble.title, 'Title');
    expect(restored.bubble.description, bubble.description);
    expect(restored.bubble.appearanceFrequency, 5);
    expect(restored.bubble.shownCount, 2);
    expect(restored.bubble.lastShownAt?.millisecondsSinceEpoch, 15);
    expect(restored.hash, BubbleDocumentCodec.hash(raw));
  });

  test('document id must match its filename', () {
    final raw = BubbleDocumentCodec.encode(
      Bubble(
        id: 'inside',
        title: 'Title',
        description: 'Body',
        createdAt: DateTime.fromMillisecondsSinceEpoch(10),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(20),
      ),
      updatedBy: 'device-a',
    );

    expect(
      () => BubbleDocumentCodec.decode(raw, expectedId: 'outside'),
      throwsFormatException,
    );
  });

  group('per-document sync', () {
    late Directory temporary;
    late BubbleDocumentStore store;
    late SyncStateStore state;
    late _MemoryWebDav server;
    late SyncService sync;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'mind-bubble-sync-test-',
      );
      final documents = Directory('${temporary.path}/documents')
        ..createSync(recursive: true);
      final support = Directory('${temporary.path}/support')
        ..createSync(recursive: true);
      store = BubbleDocumentStore.forTesting(
        root: documents,
        supportRoot: support,
        deviceIdentity: const DeviceIdentity('device-a'),
      );
      state = SyncStateStore.forTesting(
        File('${support.path}/sync-state.json'),
      );
      server = _MemoryWebDav();
      sync = SyncService(
        store,
        state,
        const DeviceIdentity('device-a'),
        () {},
        transportFactory: (_) => server,
        configFile: File('${support.path}/webdav-config.json'),
        legacyConfigFile: File('${support.path}/legacy-config.json'),
      );
      await sync.configureWebDav(
        serverUrl: 'https://example.test/dav/',
        username: 'user',
        appPassword: 'password',
      );
    });

    tearDown(() async {
      await temporary.delete(recursive: true);
    });

    Future<void> saveBubble({
      String title = 'Base title',
      String description = 'Base body',
    }) => store.save(
      Bubble(
        id: 'bubble-1',
        title: title,
        description: description,
        createdAt: DateTime.fromMillisecondsSinceEpoch(10),
        updatedAt: DateTime.now(),
      ),
    );

    test(
      'uploads one local Markdown and later downloads a remote edit',
      () async {
        await saveBubble();
        await sync.syncNow();

        expect(
          server.files.keys,
          contains('/MindBubble/v2/bubbles/bubble-1.md'),
        );

        server.editBubble(
          'bubble-1',
          (bubble) =>
              bubble.copyWith(title: 'Remote title', updatedAt: DateTime.now()),
        );
        await sync.syncNow();

        expect(
          (await store.readDocument('bubble-1'))!.bubble.title,
          'Remote title',
        );
      },
    );

    test('a no-op fetch does not publish a document refresh', () async {
      await saveBubble();
      await sync.syncNow();
      final revisions = <int>[];
      final subscription = store.revisions.listen(revisions.add);
      addTearDown(subscription.cancel);

      await sync.syncNow();
      expect(revisions, isEmpty);

      server.editBubble(
        'bubble-1',
        (bubble) =>
            bubble.copyWith(title: 'Remote title', updatedAt: DateTime.now()),
      );
      await sync.syncNow();
      expect(revisions, hasLength(1));

      await sync.syncNow();
      expect(revisions, hasLength(1));
    });

    test('merges non-overlapping local and remote fields', () async {
      await saveBubble();
      await sync.syncNow();
      await saveBubble(title: 'Local title');
      server.editBubble(
        'bubble-1',
        (bubble) => bubble.copyWith(
          description: 'Remote body',
          updatedAt: DateTime.now(),
        ),
      );

      await sync.syncNow();

      final merged = (await store.readDocument('bubble-1'))!.bubble;
      expect(merged.title, 'Local title');
      expect(merged.description, 'Remote body');
      expect(sync.conflicts, isEmpty);
    });

    test('records same-field edits as a conflict', () async {
      await saveBubble();
      await sync.syncNow();
      await saveBubble(title: 'Local title');
      server.editBubble(
        'bubble-1',
        (bubble) =>
            bubble.copyWith(title: 'Remote title', updatedAt: DateTime.now()),
      );

      await sync.syncNow();

      expect(sync.conflicts.single.reason, 'same-field');
    });

    test('an explicit local deletion removes the remote document', () async {
      await saveBubble();
      await sync.syncNow();
      await store.markDeleteIntent('bubble-1');
      await store.delete('bubble-1');

      await sync.syncNow();

      expect(
        server.files.keys,
        isNot(contains('/MindBubble/v2/bubbles/bubble-1.md')),
      );
      expect(state.objects, isEmpty);
      expect(await store.readDeleteIntents(), isEmpty);
    });

    test('remote edit versus local delete is resolved explicitly', () async {
      await saveBubble();
      await sync.syncNow();
      await store.markDeleteIntent('bubble-1');
      await store.delete('bubble-1');
      server.editBubble(
        'bubble-1',
        (bubble) =>
            bubble.copyWith(title: 'Remote title', updatedAt: DateTime.now()),
      );

      await sync.syncNow();
      expect(sync.conflicts.single.reason, 'local-delete-remote-edit');

      await sync.resolveConflict('bubble-1', ConflictResolution.remote);
      expect(
        (await store.readDocument('bubble-1'))!.bubble.title,
        'Remote title',
      );
      expect(sync.conflicts, isEmpty);
      expect(await store.readDeleteIntents(), isEmpty);
    });

    test(
      'concurrent deletion on both devices does not create a conflict',
      () async {
        await saveBubble();
        await sync.syncNow();
        await store.markDeleteIntent('bubble-1');
        await store.delete('bubble-1');
        server.files.remove('/MindBubble/v2/bubbles/bubble-1.md');

        await sync.syncNow();

        expect(sync.conflicts, isEmpty);
        expect(state.objects, isEmpty);
        expect(await store.readDeleteIntents(), isEmpty);
      },
    );

    test(
      'an unexplained missing local file never deletes remote data',
      () async {
        await saveBubble();
        await sync.syncNow();
        await store.delete('bubble-1');

        await sync.syncNow();

        expect(sync.conflicts.single.reason, 'unconfirmed-local-delete');
        expect(
          server.files.keys,
          contains('/MindBubble/v2/bubbles/bubble-1.md'),
        );
      },
    );
  });

  test('legacy SQLite rows migrate once into Markdown documents', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'mind-bubble-migration-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final documents = Directory('${temporary.path}/documents')
      ..createSync(recursive: true);
    final support = Directory('${temporary.path}/support')
      ..createSync(recursive: true);
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      '${documents.path}/mind_bubble.db',
    );
    await database.execute('''
      CREATE TABLE bubbles (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        last_shown_at INTEGER, shown_count INTEGER NOT NULL DEFAULT 0,
        appearance_frequency INTEGER NOT NULL DEFAULT 3,
        deleted_at INTEGER, field_versions TEXT NOT NULL DEFAULT ''
      )
    ''');
    await database.insert('bubbles', {
      'id': 'legacy-1',
      'title': 'Legacy',
      'description': 'Legacy body',
      'created_at': 10,
      'updated_at': 20,
      'last_shown_at': 15,
      'shown_count': 3,
      'appearance_frequency': 4,
      'deleted_at': null,
      'field_versions': '',
    });
    await database.close();
    final store = BubbleDocumentStore.forTesting(
      root: Directory('${documents.path}/MindBubble/bubbles')
        ..createSync(recursive: true),
      supportRoot: support,
      deviceIdentity: const DeviceIdentity('device-a'),
    );

    await store.migrateLegacyDatabaseForTesting(documents);
    await store.migrateLegacyDatabaseForTesting(documents);

    final migrated = (await store.readDocument('legacy-1'))!.bubble;
    expect(migrated.title, 'Legacy');
    expect(migrated.description, 'Legacy body');
    expect(migrated.appearanceFrequency, 4);
    expect(migrated.shownCount, 3);
    expect(File('${support.path}/document-v2-migrated').existsSync(), isTrue);
  });
}

class _MemoryFile {
  _MemoryFile(this.bytes, this.etag);

  Uint8List bytes;
  String etag;
}

class _MemoryWebDav implements WebDavTransport {
  final Map<String, _MemoryFile> files = {};
  int _revision = 0;

  @override
  Future<void> ensureDirectory(String remotePath) async {}

  @override
  Future<List<WebDavResource>> list(String remotePath) async {
    final prefix = remotePath.endsWith('/') ? remotePath : '$remotePath/';
    return files.entries
        .where((entry) {
          if (!entry.key.startsWith(prefix)) return false;
          return !entry.key.substring(prefix.length).contains('/');
        })
        .map(
          (entry) => WebDavResource(
            path: entry.key,
            name: entry.key.substring(prefix.length),
            isDirectory: false,
            etag: entry.value.etag,
          ),
        )
        .toList();
  }

  @override
  Future<WebDavReadResult> read(String remotePath) async {
    final file = files[remotePath];
    if (file == null) {
      throw const WebDavTransportException('GET', statusCode: 404);
    }
    return WebDavReadResult(Uint8List.fromList(file.bytes), file.etag);
  }

  @override
  Future<String?> write(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool createOnly = false,
    String contentType = 'application/octet-stream',
  }) async {
    final current = files[remotePath];
    if ((createOnly && current != null) ||
        (ifMatch != null && current?.etag != ifMatch)) {
      throw const WebDavTransportException('PUT', statusCode: 412);
    }
    final etag = '"${++_revision}"';
    files[remotePath] = _MemoryFile(Uint8List.fromList(bytes), etag);
    return etag;
  }

  @override
  Future<void> delete(String remotePath, {String? ifMatch}) async {
    final current = files[remotePath];
    if (current == null) return;
    if (ifMatch != null && current.etag != ifMatch) {
      throw const WebDavTransportException('DELETE', statusCode: 412);
    }
    files.remove(remotePath);
  }

  void editBubble(String id, Bubble Function(Bubble bubble) update) {
    final remotePath = '/MindBubble/v2/bubbles/$id.md';
    final current = files[remotePath]!;
    final document = BubbleDocumentCodec.decode(utf8.decode(current.bytes));
    final raw = BubbleDocumentCodec.encode(
      update(document.bubble),
      updatedBy: 'device-b',
    );
    final etag = '"${++_revision}"';
    files[remotePath] = _MemoryFile(Uint8List.fromList(utf8.encode(raw)), etag);
  }

  @override
  void close() {}
}
