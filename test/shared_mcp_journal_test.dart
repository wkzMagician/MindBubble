import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/shared_mcp_journal.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  late Directory documents;
  late Directory journalRoot;
  late SharedMcpJournal journal;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'mind-bubble-shared-journal-',
    );
    documents = Directory(p.join(temporary.path, '文档 with spaces', 'bubbles'));
    journalRoot = Directory(p.join(temporary.path, '应用支持', 'mcp-journal'));
    journal = SharedMcpJournal(
      documentRoot: documents,
      journalRoot: journalRoot,
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'create/update/delete expose Dartloom-shaped authorized intents',
    () async {
      final create = await journal.mutate(
        operationId: 'dart-create',
        objectId: 'bubble-1',
        kind: SharedJournalIntentKind.create,
        expectedContentHash: null,
        documentBytes: utf8.encode('one'),
        request: const {'title': 'one'},
        result: const {'id': 'bubble-1'},
      );
      expect(create.replayed, isFalse);

      final firstHash = sha256.convert(utf8.encode('one')).toString();
      await journal.mutate(
        operationId: 'dart-update',
        objectId: 'bubble-1',
        kind: SharedJournalIntentKind.update,
        expectedContentHash: firstHash,
        documentBytes: utf8.encode('two'),
        request: const {'title': 'two'},
        result: const {'id': 'bubble-1'},
      );
      final secondHash = sha256.convert(utf8.encode('two')).toString();
      await journal.mutate(
        operationId: 'dart-delete',
        objectId: 'bubble-1',
        kind: SharedJournalIntentKind.delete,
        expectedContentHash: secondHash,
        documentBytes: null,
        request: const {'id': 'bubble-1'},
        result: const {'deleted': 'bubble-1'},
      );

      final intents = await journal.pendingIntents();
      expect(
        intents.map((intent) => intent.kind),
        SharedJournalIntentKind.values,
      );
      expect(intents.map((intent) => intent.origin).toSet(), {'application'});
      expect(intents.map((intent) => intent.key).toSet(), {'bubble-1.md'});

      await journal.acknowledge('dart-create');
      await journal.acknowledge('dart-create');
      expect(
        (await journal.pendingIntents()).map((intent) => intent.operationId),
        ['dart-update', 'dart-delete'],
      );
    },
  );

  test('retry is idempotent and conflicting operation reuse fails', () async {
    Future<SharedJournalMutationResult> write(String title) => journal.mutate(
      operationId: 'stable-operation',
      objectId: 'stable-object',
      kind: SharedJournalIntentKind.create,
      expectedContentHash: null,
      documentBytes: utf8.encode(title),
      request: {'title': title},
      result: {'title': title},
    );

    expect((await write('same')).replayed, isFalse);
    expect((await write('same')).replayed, isTrue);
    expect(() => write('different'), throwsA(isA<SharedJournalConflict>()));
    expect(
      await File(p.join(documents.path, 'stable-object.md')).readAsString(),
      'same',
    );
  });

  test(
    'prepared transaction is replayed after simulated process crash',
    () async {
      await journal.prepareForTesting(
        operationId: 'crashed-operation',
        objectId: 'crashed-object',
        kind: SharedJournalIntentKind.create,
        expectedContentHash: null,
        documentBytes: utf8.encode('recover me'),
        request: const {'value': 1},
        result: const {'id': 'crashed-object'},
      );
      expect(
        File(p.join(documents.path, 'crashed-object.md')).existsSync(),
        isFalse,
      );

      final reopened = SharedMcpJournal(
        documentRoot: documents,
        journalRoot: journalRoot,
      );
      await reopened.recover();

      expect(
        await File(p.join(documents.path, 'crashed-object.md')).readAsString(),
        'recover me',
      );
      expect(
        (await reopened.pendingIntents()).single.operationId,
        'crashed-operation',
      );
    },
  );

  test(
    'two stale updates on the same ID have one deterministic conflict',
    () async {
      await documents.create(recursive: true);
      final target = File(p.join(documents.path, 'same-id.md'));
      await target.writeAsString('base', flush: true);
      final baseHash = sha256.convert(utf8.encode('base')).toString();

      Future<String> update(String operationId, String value) async {
        try {
          await journal.mutate(
            operationId: operationId,
            objectId: 'same-id',
            kind: SharedJournalIntentKind.update,
            expectedContentHash: baseHash,
            documentBytes: utf8.encode(value),
            request: {'value': value},
            result: {'value': value},
          );
          return 'applied';
        } on SharedJournalConflict {
          return 'conflict';
        }
      }

      final outcomes = await Future.wait([
        update('writer-a', 'A'),
        update('writer-b', 'B'),
      ]);
      expect(outcomes.where((value) => value == 'applied'), hasLength(1));
      expect(outcomes.where((value) => value == 'conflict'), hasLength(1));
      expect(await target.readAsString(), anyOf('A', 'B'));
      expect(await journal.pendingIntents(), hasLength(1));

      final winnerHash = sha256.convert(await target.readAsBytes()).toString();
      await journal.mutate(
        operationId: 'writer-after-conflict',
        objectId: 'same-id',
        kind: SharedJournalIntentKind.update,
        expectedContentHash: winnerHash,
        documentBytes: utf8.encode('after'),
        request: const {'value': 'after'},
        result: const {'value': 'after'},
      );
      expect(await target.readAsString(), 'after');
    },
  );

  test(
    'Python event checksum and Unicode paths are readable by Dart',
    () async {
      final modulePath = p.join(
        Directory.current.path,
        'tools',
        'mind_bubble_mcp.py',
      );
      final script =
          '''
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("mcp_interop", r"$modulePath")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
journal = module.SharedJournal(Path(r"${documents.path}"), Path(r"${journalRoot.path}"))
journal.mutate(operation_id="python-create", object_id="python-object", kind="create", expected_content_hash=None, document="跨语言".encode("utf-8"), request={"title": "跨语言"}, result={"id": "python-object"})
''';
      final process = await Process.run('python', ['-c', script]);
      expect(process.exitCode, 0, reason: '${process.stderr}');

      final intents = await journal.pendingIntents();
      expect(intents.single.operationId, 'python-create');
      expect(
        await File(p.join(documents.path, 'python-object.md')).readAsString(),
        '跨语言',
      );
    },
  );

  test('tampered event checksum fails closed', () async {
    await journal.mutate(
      operationId: 'checksum-operation',
      objectId: 'checksum-object',
      kind: SharedJournalIntentKind.create,
      expectedContentHash: null,
      documentBytes: utf8.encode('safe'),
      request: const {'value': 'safe'},
      result: const {'id': 'checksum-object'},
    );
    final event = (await Directory(
      p.join(journalRoot.path, 'entries'),
    ).list().where((entity) => entity is File).cast<File>().toList()).first;
    final payload =
        jsonDecode(await event.readAsString()) as Map<String, Object?>;
    payload['operationId'] = 'tampered';
    await event.writeAsString(jsonEncode(payload), flush: true);

    expect(journal.pendingIntents, throwsA(isA<SharedJournalCorruption>()));
  });

  test('verified legacy delete import creates one applied intent', () async {
    await journal.importAppliedDeleteIntent(
      operationId: 'legacy-delete/bubble-1',
      objectId: 'bubble-1',
      createdAt: DateTime.utc(2026, 8, 14),
    );
    await journal.importAppliedDeleteIntent(
      operationId: 'legacy-delete/bubble-1',
      objectId: 'bubble-1',
      createdAt: DateTime.utc(2026, 8, 14),
    );

    final intents = await journal.pendingIntents();
    expect(intents, hasLength(1));
    expect(intents.single.operationId, 'legacy-delete/bubble-1');
    expect(intents.single.kind, SharedJournalIntentKind.delete);
    expect(intents.single.key, 'bubble-1.md');
  });
}
