import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/widgets/markdown_block_editor.dart';

void main() {
  Widget editor(TextEditingController controller) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 650,
        child: MarkdownBlockEditor(controller: controller),
      ),
    ),
  );

  testWidgets('Enter commits the active block and renders it', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.enterText(find.byType(TextField), '## Heading');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '## Heading');
    expect(find.text('Heading'), findsOneWidget);
    final nextField = tester.widget<TextField>(find.byType(TextField));
    expect(nextField.focusNode!.hasFocus, isTrue);
    expect(nextField.controller!.selection.baseOffset, 0);
  });

  testWidgets('a complete fenced code block renders after Enter', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    const markdown = '```dart\nvoid main() {}\n```';
    await tester.enterText(find.byType(TextField), markdown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, markdown);
    expect(find.textContaining('void main() {}'), findsOneWidget);
  });

  testWidgets('code block toolbar creates an empty fence', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pump();

    expect(controller.text, '```\n\n```');
  });

  testWidgets('bold wraps a selection and toggles it off', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.enterText(find.byType(TextField), 'hello');
    final active = tester.widget<TextField>(find.byType(TextField)).controller!;
    active.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();

    expect(controller.text, '**hello**');
    expect(
      active.selection,
      const TextSelection(baseOffset: 2, extentOffset: 7),
    );

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    expect(controller.text, 'hello');
    expect(
      active.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('bold starts and stops continuous formatted input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    final active = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(controller.text, '****');
    expect(active.selection, const TextSelection.collapsed(offset: 2));

    active.value = const TextEditingValue(
      text: '**bold**',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    expect(controller.text, '**bold**');
    expect(active.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('heading and quote toggle the current line prefix', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.enterText(find.byType(TextField), 'first\nsecond');
    final active = tester.widget<TextField>(find.byType(TextField)).controller!;
    active.selection = const TextSelection.collapsed(offset: 7);
    await tester.tap(find.byIcon(Icons.format_size));
    await tester.pump();
    expect(controller.text, 'first\n## second');

    await tester.tap(find.byIcon(Icons.format_size));
    await tester.pump();
    expect(controller.text, 'first\nsecond');

    await tester.tap(find.byIcon(Icons.format_quote));
    await tester.pump();
    expect(controller.text, 'first\n> second');

    await tester.tap(find.byIcon(Icons.format_quote));
    await tester.pump();
    expect(controller.text, 'first\nsecond');
  });

  testWidgets('inline code and code blocks handle selections and empty input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.enterText(find.byType(TextField), 'code');
    final active = tester.widget<TextField>(find.byType(TextField)).controller!;
    active.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.tap(find.byIcon(Icons.code));
    await tester.pump();
    expect(controller.text, '`code`');

    active.value = const TextEditingValue(
      text: 'code',
      selection: TextSelection(baseOffset: 0, extentOffset: 4),
    );
    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pump();
    expect(controller.text, '```\ncode\n```');

    active.clear();
    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pump();
    expect(controller.text, '```\n\n```');
    expect(active.selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('the toolbar no longer offers an unordered-list button', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    expect(find.byIcon(Icons.format_list_bulleted), findsNothing);
  });
}
