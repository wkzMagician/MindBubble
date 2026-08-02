import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/widgets/markdown_block_editor.dart';

void main() {
  Widget editor(TextEditingController controller) => MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
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

    await tester.enterText(find.byType(TextField), '## 核心观点');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '## 核心观点');
    expect(find.text('核心观点'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final nextField = tester.widget<TextField>(find.byType(TextField));
    expect(nextField.focusNode!.hasFocus, isTrue);
    expect(nextField.controller!.selection.baseOffset, 0);

    tester.testTextInput.enterText('下一行可以直接输入');
    await tester.pump();
    expect(controller.text, '## 核心观点\n\n下一行可以直接输入');
  });

  testWidgets('a complete fenced code block renders after Enter',
      (tester) async {
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

  testWidgets('code block toolbar inserts a complete fence', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(editor(controller));

    await tester.tap(find.byTooltip('代码块'));
    await tester.pump();

    expect(controller.text, '```\n在这里输入代码\n```');
  });
}
