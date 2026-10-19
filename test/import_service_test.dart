import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/import_service.dart';

void main() {
  test('reads the versioned MindBubble import format', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mind-bubble-import-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/notes.json')
      ..writeAsStringSync(
        jsonEncode({
          'format': 'mind-bubble-import',
          'schemaVersion': 1,
          'source': {
            'id': 'notion',
            'cursor': 'cursor-1',
            'nextCursor': 'cursor-2',
          },
          'items': [
            {
              'id': 'note-1',
              'title': 'A note',
              'description': '# Body',
              'appearanceFrequency': 4,
              'updatedAt': '2026-08-28T00:00:00Z',
            },
          ],
        }),
      );

    final batch = await ImportService().readImport(file);

    expect(batch.schemaVersion, 1);
    expect(batch.sourceId, 'notion');
    expect(batch.cursor, 'cursor-1');
    expect(batch.nextCursor, 'cursor-2');
    expect(batch.items.single.id, 'note-1');
    expect(batch.items.single.appearanceFrequency, 4);
    expect(batch.items.single.updatedAt, DateTime.utc(2026, 8, 28));
  });

  test('rejects unsafe IDs and unsupported schema versions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mind-bubble-import-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/notes.json');

    await file.writeAsString(
      jsonEncode({
        'format': 'mind-bubble-import',
        'schemaVersion': 1,
        'items': [
          {'id': '../escape', 'title': 'Bad', 'description': 'Bad'},
        ],
      }),
    );
    expect(ImportService().readImport(file), throwsFormatException);

    await file.writeAsString(
      jsonEncode({
        'format': 'mind-bubble-import',
        'schemaVersion': 2,
        'items': [],
      }),
    );
    expect(ImportService().readImport(file), throwsFormatException);
  });

  test('stores independent source checkpoints', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mind-bubble-import-',
    );
    addTearDown(() => directory.delete(recursive: true));

    await ImportCheckpointStore.write(directory, 'notion', 'cursor-2');
    await ImportCheckpointStore.write(directory, 'obsidian', 'cursor-a');

    expect(await ImportCheckpointStore.read(directory, 'notion'), 'cursor-2');
    expect(await ImportCheckpointStore.read(directory, 'obsidian'), 'cursor-a');
  });
}
