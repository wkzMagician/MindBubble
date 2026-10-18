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
  late Directory root;
  late BubbleDocumentStore documents;
  late BulkImportService imports;
  late BubbleRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mind-bubble-html');
    final docs = Directory('${root.path}/docs')..createSync(recursive: true);
    final support = Directory('${root.path}/support')
      ..createSync(recursive: true);
    documents = BubbleDocumentStore.forTesting(
      root: docs,
      supportRoot: support,
      deviceIdentity: const DeviceIdentity('test'),
    );
    repository = BubbleRepository(
      documents,
      DailySelectionCache.forTesting(File('${support.path}/daily.json')),
      const DeviceIdentity('test'),
      () {},
    );
    imports = BulkImportService(repository, documents);
  });
  tearDown(() async {
    await documents.dispose();
    await root.delete(recursive: true);
  });

  test(
    'flomo ZIP produces separate stable memo IDs, markdown and an image',
    () async {
      final html = '''
<html><body>
<div class="memo"><div class="time">2026-10-15 12:00:00</div>
<div class="content"><p>第一个点子</p><p>这里是内容</p></div>
<div class="files"><img src="file/images/cat.png"></div></div>
<div class="memo"><div class="time">2026-10-16 08:00:00</div>
<div class="content"><p>第二个点子</p><p>另外一条</p></div>
</div>
</body></html>
''';
      final htmlBytes = utf8.encode(html);
      final fileBytes = [137, 80, 78, 71];
      final archive = Archive()
        ..addFile(
          ArchiveFile('takeout/notes.html', htmlBytes.length, htmlBytes),
        )
        ..addFile(
          ArchiveFile(
            'takeout/file/images/cat.png',
            fileBytes.length,
            fileBytes,
          ),
        );
      final zip = File('${root.path}/flomo.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive)!);

      final notes = await imports.readFile(zip);
      expect(notes, hasLength(2));
      expect(notes.first.title, '第一个点子');
      expect(notes.last.title, '第二个点子');
      expect(notes.first.markdown, contains('这里是内容'));
      expect(notes.first.assets, contains('file/images/cat.png'));
      final source = await imports.preview('flomo', notes);
      expect(source.count(ImportAction.add), 2);
      expect(await imports.commit(source), 2);
      final imported = await repository.getAll();
      expect(imported, hasLength(2));
      final note = imported.singleWhere((e) => e.title == '第一个点子');
      expect(note.description, contains('](assets/'));
      final repeat = await imports.preview(
        'flomo',
        await imports.readFile(zip),
      );
      expect(repeat.count(ImportAction.unchanged), 2);
    },
  );

  test(
    'single HTML page can be imported by generic or other named sources',
    () async {
      final file = File('${root.path}/converted.html')
        ..writeAsStringSync(
          '<html><head><title>Converted</title></head>'
          '<body><h1>Hello</h1><p>Sample <strong>content</strong></p></body></html>',
        );
      final notes = await imports.readFile(file);
      expect(notes, hasLength(1));
      expect(notes.single.title, 'Converted');
      expect(notes.single.markdown, contains('# Hello'));
      expect(await imports.commit(await imports.preview('feishu', notes)), 1);
      expect((await repository.getAll()).single.title, 'Converted');
    },
  );
}
