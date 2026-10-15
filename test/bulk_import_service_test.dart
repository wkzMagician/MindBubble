import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/bulk_import_service.dart';
import 'package:mind_bubble/services/daily_selection_cache.dart';
import 'package:mind_bubble/services/device_identity_service.dart';

void main() {
  late Directory temp;
  late BubbleDocumentStore store;
  late BubbleRepository repo;
  late BulkImportService imports;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bubble-bulk-import');
    final root = Directory('${temp.path}/docs')..createSync(recursive: true);
    final support = Directory('${temp.path}/support')
      ..createSync(recursive: true);
    store = BubbleDocumentStore.forTesting(
      root: root,
      supportRoot: support,
      deviceIdentity: const DeviceIdentity('test-device'),
    );
    repo = BubbleRepository(
      store,
      DailySelectionCache.forTesting(File('${support.path}/daily.json')),
      const DeviceIdentity('test-device'),
      () {},
    );
    imports = BulkImportService(repo, store);
  });
  tearDown(() async {
    await store.dispose();
    await temp.delete(recursive: true);
  });

  test('new, unchanged, source update and concurrent conflict', () async {
    const source = 'my-obsidian-vault';
    final original = [
      const ImportCandidate(
        externalId: 'file/one.md',
        title: 'My idea',
        markdown: '# First',
      ),
    ];
    var preview = await imports.preview(source, original);
    expect(preview.count(ImportAction.add), 1);
    expect(await imports.commit(preview), 1);

    preview = await imports.preview(source, original);
    expect(preview.count(ImportAction.unchanged), 1);
    expect(await imports.commit(preview), 0);
    final bubble = (await repo.getAll()).single;

    final changed = [
      const ImportCandidate(
        externalId: 'file/one.md',
        title: 'My idea',
        markdown: '# Second',
      ),
    ];
    preview = await imports.preview(source, changed);
    expect(preview.count(ImportAction.update), 1);
    await imports.commit(preview);
    final saved = (await repo.getAll()).single;
    expect(saved.description, '# Second');
    await repo.save(saved.copyWith(description: '# My own changes'));
    preview = await imports.preview(source, changed);
    expect(preview.count(ImportAction.unchanged), 1);
    expect(await imports.commit(preview), 0);
    expect((await repo.getById(bubble.id))!.description, '# My own changes');

    preview = await imports.preview(source, [
      const ImportCandidate(
        externalId: 'file/one.md',
        title: 'My idea',
        markdown: '# Third',
      ),
    ]);
    expect(preview.count(ImportAction.conflict), 1);
    expect(await imports.commit(preview), 0);
    expect((await repo.getById(bubble.id))!.description, '# My own changes');
    expect(
      await imports.commit(
        preview,
        conflictChoice: ImportConflictChoice.useSource,
      ),
      1,
    );
    expect((await repo.getById(bubble.id))!.description, '# Third');
  });

  test('directory markdown and relative images import together', () async {
    final dir = Directory('${temp.path}/vault')..createSync();
    File(
      '${dir.path}/note.md',
    ).writeAsStringSync('## Hello\n\n![photo](pic.png)');
    File('${dir.path}/pic.png').writeAsBytesSync([137, 80, 78, 71]);
    final notes = await imports.readDirectory(dir);
    expect(notes, hasLength(1));
    expect(notes.single.assets, contains('pic.png'));
    await imports.commit(await imports.preview('vault', notes));
    final body = (await repo.getAll()).single.description;
    expect(body, contains('](assets/'));
    final assetName = RegExp(
      r'assets/[a-f0-9]{64}\.png',
    ).firstMatch(body)!.group(0)!;
    expect(await store.readAttachment(assetName), [137, 80, 78, 71]);
  });

  test('Notion-like ZIP can import Markdown and CSV entries', () async {
    final markdown = utf8.encode('# From Markdown');
    final csv = utf8.encode('Name,Description\nPaper,My paper notes\n');
    final archive = Archive()
      ..addFile(
        ArchiveFile('Notes/From Markdown.md', markdown.length, markdown),
      )
      ..addFile(ArchiveFile('Database.csv', csv.length, csv));
    final zipped = ZipEncoder().encode(archive)!;
    final file = File('${temp.path}/export.zip')..writeAsBytesSync(zipped);
    final notes = await imports.readFile(file);
    expect(notes.map((e) => e.title), containsAll(['From Markdown', 'Paper']));
    await imports.commit(await imports.preview('notion', notes));
    expect(await repo.getAll(), hasLength(2));
  });

  test('Keep JSON and Evernote ENEX exports can be read', () async {
    final keep = File('${temp.path}/keep.json');
    await keep.writeAsString(
      jsonEncode({
        'id': 'keep-1',
        'title': 'Shopping',
        'textContent': 'Milk\nEggs',
      }),
    );
    final keeps = await imports.readFile(keep);
    expect(keeps.single.title, 'Shopping');
    expect(keeps.single.externalId, 'keep-1');

    final enex = File('${temp.path}/notes.enex');
    await enex.writeAsString(
      '<en-export><note><title>Evernote</title>'
      '<guid>abc</guid><content><![CDATA[<en-note>Hello</en-note>]]></content>'
      '</note></en-export>',
    );
    final notes = await imports.readFile(enex);
    expect(notes.single.title, 'Evernote');
    expect(notes.single.markdown, 'Hello');
  });
}
