import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/bubble_list/import_source_spec.dart';
import 'package:mind_bubble/features/bubble_list/import_wizard.dart';

void main() {
  test('each source exposes only implemented import entry points', () {
    final ids = importSourceSpecs.map((source) => source.id).toList();
    expect(ids.toSet().length, ids.length);

    ImportSourceSpec spec(ImportSourceApp app) =>
        importSourceSpecs.singleWhere((source) => source.app == app);
    expect(
      spec(ImportSourceApp.obsidian).recommended,
      ImportEntryMethod.folder,
    );
    expect(
      spec(ImportSourceApp.logseq).allows(ImportEntryMethod.folder),
      isTrue,
    );
    expect(spec(ImportSourceApp.notion).methods, [
      ImportEntryMethod.files,
      ImportEntryMethod.notionApi,
    ]);
    expect(spec(ImportSourceApp.evernote).extensions, contains('enex'));
    expect(spec(ImportSourceApp.googleKeep).extensions, contains('json'));
    expect(spec(ImportSourceApp.spreadsheet).extensions, contains('xlsx'));
    for (final app in ImportSourceApp.values) {
      final config = spec(app);
      expect(config.methods, isNotEmpty);
      expect(config.methods.toSet().length, config.methods.length);
      expect(config.allows(config.recommended), isTrue);
      if (config.methods.contains(ImportEntryMethod.files)) {
        expect(config.extensions, isNotEmpty);
      }
    }
  });

  test('Vault identities are stable and applications do not collide', () {
    final obsidian = importSourceSpecs.first;
    final logseq = importSourceSpecs[1];
    final notion = importSourceSpecs[2];
    expect(obsidian.suggestedIdentity('ideas.zip'), 'obsidian:ideas');
    expect(obsidian.suggestedIdentity('ideas.zip'), 'obsidian:ideas');
    expect(logseq.suggestedIdentity('ideas.zip'), 'logseq:ideas');
    expect(notion.suggestedIdentity('export-2026.zip'), 'notion');
    expect(notion.suggestedIdentity(null), 'notion');
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

  testWidgets('selecting Notion reveals export and API methods separately', (
    tester,
  ) async {
    await pumpWizard(tester, const Size(1280, 900));
    expect(find.text('从其他应用导入'), findsOneWidget);
    expect(find.text('Obsidian'), findsWidgets);
    expect(find.text('Notion'), findsOneWidget);
    expect(find.text('Notion Integration Token'), findsNothing);

    await tester.tap(find.text('Notion'));
    await tester.pumpAndSettle();
    expect(find.text('选择文件 / 导出包'), findsOneWidget);
    expect(find.text('Notion API 连接'), findsOneWidget);
    expect(find.text('Notion Integration Token'), findsNothing);

    await tester.tap(find.text('Notion API 连接'));
    await tester.pumpAndSettle();
    expect(find.text('Notion Integration Token'), findsOneWidget);
    expect(find.text('读取 Notion 页面'), findsOneWidget);

    await tester.tap(find.text('Google Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Notion Integration Token'), findsNothing);
    expect(find.text('Notion API 连接'), findsNothing);
    expect(find.textContaining('Google Takeout'), findsOneWidget);
    expect(find.text('选择 Google Keep 导出文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow window retains platform selection and import controls', (
    tester,
  ) async {
    await pumpWizard(tester, const Size(620, 720));
    expect(find.text('来源应用'), findsNothing); // Horizontal source scroller.
    expect(find.text('Obsidian'), findsWidgets);
    expect(find.text('选择 Obsidian 文件夹'), findsOneWidget);
    expect(find.text('确认导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
