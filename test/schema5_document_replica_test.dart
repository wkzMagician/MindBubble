import 'dart:io';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/device_identity_service.dart';

void main() {
  late Directory sandbox;
  late FileDirectoryStore replica;
  late BubbleDocumentStore documents;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('mindbubble-schema5-');
    final root = Directory('${sandbox.path}${Platform.pathSeparator}bubbles');
    replica = await FileDirectoryStore.open(
      root: root.absolute,
      metadataRoot: Directory(
        '${sandbox.path}${Platform.pathSeparator}metadata',
      ).absolute,
      hierarchical: false,
    );
    documents = BubbleDocumentStore.forTesting(
      root: root,
      supportRoot: Directory('${sandbox.path}${Platform.pathSeparator}support'),
      deviceIdentity: const DeviceIdentity('device-a'),
      replicaStore: replica,
    );
  });

  tearDown(() async {
    await documents.dispose();
    await replica.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'Flutter create update and delete form durable replica intents',
    () async {
      final initial = _bubble(title: 'initial');
      await documents.save(initial);
      await documents.save(initial.copyWith(title: 'updated'));
      await documents.delete(initial.id);

      final intents = await replica.explicitIntents();
      expect(intents.map((intent) => intent.key), everyElement('bubble-1.md'));
      expect(intents.map((intent) => intent.kind), [
        StoreIntentKind.create,
        StoreIntentKind.update,
        StoreIntentKind.delete,
      ]);
      expect(
        intents.map((intent) => intent.origin),
        everyElement(StoreMutationOrigin.application),
      );
    },
  );

  test('external edit delete and new file never become intents', () async {
    await documents.save(_bubble(title: 'trusted'));
    for (final intent in await replica.explicitIntents()) {
      await replica.forgetExplicitIntent(intent.operationId);
    }

    await documents.fileFor('bubble-1').writeAsString('external edit');
    await _deleteWithRetry(documents.fileFor('bubble-1'));
    await File(
      '${documents.root.path}${Platform.pathSeparator}outside.md',
    ).writeAsString('outside');

    expect(await replica.explicitIntents(), isEmpty);
    final scan = {for (final item in await replica.scan()) item.key: item};
    expect(
      scan['bubble-1.md']!.observation,
      ReplicaObservation.unexpectedMissing,
    );
    expect(
      scan['outside.md']!.observation,
      ReplicaObservation.unregisteredLocalObject,
    );
  });

  test('document ids cannot escape the application-owned root', () async {
    expect(() => documents.fileFor('../escape'), throwsArgumentError);
    expect(() => documents.fileFor('nested/escape'), throwsArgumentError);
    expect(() => documents.fileFor(r'C:\escape'), throwsArgumentError);
  });
}

Future<void> _deleteWithRetry(File file) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    try {
      await file.delete();
      return;
    } on FileSystemException {
      if (attempt == 19) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}

Bubble _bubble({required String title}) => Bubble(
  id: 'bubble-1',
  title: title,
  description: 'body',
  createdAt: DateTime.utc(2026, 8, 14),
  updatedAt: DateTime.utc(2026, 8, 14),
);
