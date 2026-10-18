import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/ocean/red_note_grid.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/visual_theme_service.dart';

void main() {
  final now = DateTime(2026, 10, 15);

  Bubble note(int index) => Bubble(
    id: 'note-$index',
    title: '笔记 $index',
    description: '这是第 $index 条笔记的正文，可以用来测试封面排版。',
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('RedNote feed shows neutral covers and opens selected note', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Bubble? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: RedNoteGrid(
              bubbles: List.generate(5, note),
              onBubbleTap: (bubble) => selected = bubble,
            ),
          ),
        ),
      );

      expect(find.text('灵感流'), findsOneWidget);
      expect(find.text('5 条笔记'), findsOneWidget);
      expect(find.bySemanticsLabel('笔记 0'), findsOneWidget);
      final whiteCards = tester
          .widgetList<Material>(find.byType(Material))
          .where((material) => material.color == RedNoteColors.surface);
      expect(whiteCards.length, greaterThanOrEqualTo(5));
      expect(tester.takeException(), isNull);

      await tester.tap(find.bySemanticsLabel('笔记 0'));
      expect(selected?.id, 'note-0');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('RedNote feed adapts to a narrow viewport without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: RedNoteGrid(
            bubbles: List.generate(4, note),
            onBubbleTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('4 条笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
