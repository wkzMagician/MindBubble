import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/note_cover/note_cover.dart';
import 'package:mind_bubble/features/note_cover/note_cover_generator.dart';
import 'package:mind_bubble/features/ocean/bubble_widget.dart';
import 'package:mind_bubble/features/ocean/red_note_grid.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/models/bubble.dart';

void main() {
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader(
        'Microsoft YaHei',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  testWidgets(
    'short titles use the available width and keep Chinese units intact',
    (tester) async {
      expect(NoteCoverGenerator.layout('开发不是生产').lines, ['开发不是生产']);
      expect(NoteCoverGenerator.layout('每日三句话').lines, ['每日三句话']);
      expect(NoteCoverGenerator.layout('管理员创造环境').lines, ['管理员', '创造环境']);
      final why = NoteCoverGenerator.layout('为什么伟大不能被计划');
      expect(why.lines, ['为什么伟大', '不能被计划']);
      final intelligence = NoteCoverGenerator.layout('智能不等于意识');
      expect(intelligence.lines.length, 2);
      expect(intelligence.lines.any((line) => line.contains('不等于')), isTrue);
      final phrases = NoteCoverGenerator.layout(
        '试错都被砍了，开发还剩什么？',
        phrases: ['试错', '还剩什么'],
      );
      expect(phrases.lines.any((line) => line.contains('还剩什么')), isTrue);
      expect(why.fontSize + why.lineHeight, lessThan(320));
      expect(
        NoteCoverGenerator.textWidth * NoteCoverGenerator.textWidth +
            NoteCoverGenerator.textHeight * NoteCoverGenerator.textHeight,
        lessThan(1024 * 1024),
      );
    },
  );

  testWidgets('native card and bubble previews', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1266, 714);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final titles = [
      '开发不是生产',
      '管理员创造环境',
      '智能不等于意识',
      'agentix',
      '为什么伟大不能被计划',
      '完善的友爱',
      '所有回报来自复利',
      '研究地图',
      '每日三句话',
      'agent profiler metric',
    ];
    final notes = [
      for (var i = 0; i < titles.length; i++)
        Bubble(
          id: 'typography-$i',
          title: titles[i],
          description: titles[i],
          createdAt: DateTime(2026, 10, 17),
          updatedAt: DateTime(2026, 10, 17),
          cover: NoteCover(seed: i + 73),
        ),
    ];
    final key = GlobalKey();
    Widget preview(Widget child) => MaterialApp(
      theme: ThemeData(fontFamily: 'Microsoft YaHei', useMaterial3: true),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: key,
        child: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(
      preview(RedNoteGrid(bubbles: notes, onBubbleTap: (_) {})),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'compact-cover-grid.png');
    await tester.pumpWidget(
      preview(
        Center(
          child: Wrap(
            spacing: 30,
            runSpacing: 24,
            children: [
              for (final note in notes.take(8))
                OceanBubble(
                  bubble: note,
                  size: 232,
                  lift: 0,
                  deformation: 0,
                  impactAngle: 0,
                  tintIndex: 0,
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'compact-cover-bubbles.png');
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['MINDBUBBLE_VISUAL_OUTPUT'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$directory/$name').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
