import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/bubble_list/import_source_spec.dart';
import 'package:mind_bubble/features/bubble_list/import_wizard.dart';

void main() {
  test('exactly ten named software entries plus generic import', () {
    expect(importSourceSpecs, hasLength(11));
    expect(
      importSourceSpecs.map((e) => e.app).toSet(),
      ImportSourceApp.values.toSet(),
    );
    expect(
      importSourceSpecs.where(
        (e) => e.group == ImportSourceGroup.international,
      ),
      hasLength(5),
    );
    expect(
      importSourceSpecs.where((e) => e.group == ImportSourceGroup.china),
      hasLength(5),
    );
    expect(
      importSourceSpecs.where((e) => e.group == ImportSourceGroup.generic),
      hasLength(1),
    );
    expect(importSourceSpecs.last.app, ImportSourceApp.generic);
    expect(importSourceSpecs.any((e) => e.title == 'Logseq'), isFalse);
  });

  test('source-specific methods map to actual adapters and file formats', () {
    ImportSourceSpec source(ImportSourceApp app) =>
        importSourceSpecs.singleWhere((e) => e.app == app);
    expect(
      source(ImportSourceApp.obsidian).recommended,
      ImportEntryMethod.folder,
    );
    expect(source(ImportSourceApp.notion).methods, [
      ImportEntryMethod.files,
      ImportEntryMethod.notionApi,
    ]);
    expect(
      source(ImportSourceApp.oneNote).recommended,
      ImportEntryMethod.oneNoteGraph,
    );
    expect(
      source(ImportSourceApp.siyuan).recommended,
      ImportEntryMethod.siyuanApi,
    );
    expect(
      source(ImportSourceApp.flomo).extensions,
      containsAll(['html', 'zip']),
    );
    expect(
      source(ImportSourceApp.generic).extensions,
      containsAll(['md', 'csv', 'xlsx', 'json', 'enex']),
    );
    for (final spec in importSourceSpecs) {
      expect(spec.methods, isNotEmpty);
      expect(spec.methods.toSet().length, spec.methods.length);
      if (spec.allows(ImportEntryMethod.files)) {
        expect(spec.extensions, isNotEmpty);
      }
    }
  });

  test('same vault keeps identity across file exports', () {
    final obsidian = importSourceSpecs.first;
    final notion = importSourceSpecs[1];
    final generic = importSourceSpecs.last;
    expect(obsidian.suggestedIdentity('ideas.zip'), 'obsidian:ideas');
    expect(generic.suggestedIdentity('my-notes.zip'), 'generic:my-notes');
    expect(notion.suggestedIdentity('export-2026.zip'), 'notion');
  });

  Future<void> pumpWizard(WidgetTester tester, Size viewport) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ImportWizard())),
      ),
    );
  }

  testWidgets(
    'Notion selects between ZIP and authorized API, Google Keep stays separate',
    (tester) async {
      await pumpWizard(tester, const Size(1280, 900));
      expect(find.text('国际软件'), findsOneWidget);
      expect(find.text('国内软件'), findsOneWidget);
      await tester.tap(find.text('Notion'));
      await tester.pumpAndSettle();
      expect(find.text('Notion API 连接'), findsOneWidget);
      expect(find.text('Notion Integration Token'), findsNothing);
      await tester.tap(find.text('Notion API 连接'));
      await tester.pumpAndSettle();
      expect(find.text('Notion Integration Token'), findsOneWidget);
      await tester.tap(find.text('Google Keep'));
      await tester.pumpAndSettle();
      expect(find.text('Notion API 连接'), findsNothing);
      expect(find.text('Notion Integration Token'), findsNothing);
      expect(find.text('选择 Google Keep 导出文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Graph connection exposes scoped token and reverts to HTML import',
    (tester) async {
      await pumpWizard(tester, const Size(1280, 900));
      await tester.scrollUntilVisible(
        find.text('Microsoft OneNote'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Microsoft OneNote'));
      await tester.pumpAndSettle();
      expect(find.text('Microsoft Graph Access Token'), findsOneWidget);
      expect(find.text('读取 OneNote 页面'), findsOneWidget);
      await tester.tap(find.text('选择文件 / 导出包'));
      await tester.pumpAndSettle();
      expect(find.text('Microsoft Graph Access Token'), findsNothing);
      expect(find.text('选择 Microsoft OneNote 导出文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact window shows horizontal source picker', (tester) async {
    await pumpWizard(tester, const Size(620, 720));
    expect(find.text('Obsidian'), findsWidgets);
    expect(find.text('选择 Obsidian 文件夹'), findsOneWidget);
    expect(find.text('确认导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
