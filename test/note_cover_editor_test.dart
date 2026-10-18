import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartloom_model/dartloom_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mind_bubble/features/bubble_list/bubble_list_page.dart';
import 'package:mind_bubble/features/note_cover/cover_headline_service.dart';
import 'package:mind_bubble/features/note_cover/note_cover.dart';
import 'package:mind_bubble/features/note_cover/note_cover_editor.dart';
import 'package:mind_bubble/features/ocean/ocean_page.dart';
import 'package:mind_bubble/features/ocean/bubble_widget.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/device_identity_service.dart';
import 'package:mind_bubble/services/home_exposure_service.dart';
import 'package:mind_bubble/viewmodels/bubble_view_models.dart';

class _HeadlineModel implements GenerationModel {
  int calls = 0;
  Completer<String>? pending;
  @override
  Future<String> generate(ModelRequest request) async {
    calls++;
    return pending?.future ??
        Future.value(
          jsonEncode({
            'candidates': [
              {
                'headline': '你在提高效率，还是消灭探索？',
                'evidence': '试错和探索不是浪费',
                'phrases': ['提高效率', '消灭探索'],
              },
            ],
          }),
        );
  }
}

class _TrackedRepository implements BubbleRepository {
  Bubble? saved;
  Future<void>? lastSave;
  @override
  Future<void> save(Bubble note, {bool analyze = true}) {
    saved = note;
    return lastSave = Future<void>.value();
  }

  @override
  Future<Bubble?> getById(String id, {bool includeDeleted = false}) async =>
      saved;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final folder = Platform.environment['MINDBUBBLE_VISUAL_OUTPUT'];
  if (folder == null) return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$folder/$name').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  late Directory folder;
  late BubbleDocumentStore store;
  late TextEditingController title;
  late TextEditingController body;
  late _HeadlineModel model;
  setUpAll(() async {
    if (Platform.environment['MINDBUBBLE_VISUAL_OUTPUT'] == null) return;
    final file = File('C:/Windows/Fonts/msyh.ttc');
    if (await file.exists()) {
      await (FontLoader(
        'Microsoft YaHei',
      )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
    }
    final materialFont = Platform.environment['MINDBUBBLE_TEST_MATERIAL_FONT'];
    if (materialFont != null && await File(materialFont).exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            File(materialFont).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = await Directory.systemTemp.createTemp('mindbubble-cover-editor-');
    store = BubbleDocumentStore.forTesting(
      root: Directory('${folder.path}/notes')..createSync(),
      supportRoot: Directory('${folder.path}/support')..createSync(),
      deviceIdentity: const DeviceIdentity('test-device'),
    );
    title = TextEditingController(text: '开发不是生产');
    body = TextEditingController(
      text: '知识工作中的试错和探索不是浪费；把软件开发当流水线生产，会压制学习并制造虚假的确定性。',
    );
    model = _HeadlineModel();
  });
  tearDown(() async {
    title.dispose();
    body.dispose();
    await store.dispose();
    await folder.delete(recursive: true);
  });

  Future<void> showEditor(
    WidgetTester tester,
    ValueChanged<NoteCover> onChanged, {
    Size size = const Size(450, 900),
    NoteCover? cover,
    bool autoSelect = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bubbleDocumentStoreProvider.overrideWithValue(store),
          coverHeadlineServiceProvider.overrideWithValue(
            CoverHeadlineService(loadModel: () async => model),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF29594A),
            fontFamily: 'Microsoft YaHei',
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: NoteCoverEditor(
                noteId: 'draft',
                title: title,
                body: body,
                initialCover: cover ?? NoteCover.forNote('draft', body.text),
                onChanged: onChanged,
                autoSelectFirstImage: autoSelect,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'poster shuffle preserves text and headline generation is explicit',
    (tester) async {
      NoteCover? selected;
      await showEditor(tester, (value) => selected = value);
      expect(model.calls, 0);
      expect(find.text('正文金句'), findsNothing);
      final initial = NoteCover.forNote('draft', body.text);
      await tester.tap(find.text('换一张图'));
      await tester.pump();
      expect(selected!.seed, isNot(initial.seed));
      expect(selected!.headline(title.text), title.text);
      final seed = selected!.seed;
      await tester.tap(find.text('吸睛提炼'));
      await tester.pumpAndSettle();
      expect(model.calls, 1);
      expect(selected!.seed, seed);
      expect(selected!.textSource, NoteCoverTextSource.hook);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '你在提高效率，还是消灭探索？',
      );
      body.text = '正文改了，选定标题继续保留。';
      await tester.pump();
      expect(selected!.text, '你在提高效率，还是消灭探索？');
      expect(model.calls, 1);
      await tester.enterText(find.byType(TextField), '我自己写的封面标题');
      expect(selected!.textSource, NoteCoverTextSource.custom);
      await tester.tap(find.text('原标题'));
      await tester.pump();
      title.text = '修改后的原标题';
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        title.text,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale model results do not overwrite a changed note', (
    tester,
  ) async {
    NoteCover? selected;
    model.pending = Completer<String>();
    await showEditor(tester, (value) => selected = value);
    await tester.tap(find.text('吸睛提炼'));
    await tester.pump();
    body.text = '现在是另一篇笔记。';
    model.pending!.complete(
      '{"candidates":[{"headline":"旧正文的标题","evidence":"试错和探索不是浪费"}]}',
    );
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('正文已更新，请重新提炼。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'image selection, crop and first image discovery remain note-local',
    (tester) async {
      body.text =
          '![one](https://example.com/one.png)\n\n![two](https://example.com/two.png)';
      NoteCover? selected;
      await showEditor(tester, (value) => selected = value);
      await tester.tap(find.byType(OutlinedButton).last);
      await tester.pumpAndSettle();
      expect(selected!.imageUri, 'https://example.com/two.png');
      await tester.tap(find.text('铺满'));
      await tester.pump();
      expect(selected!.fit, NoteCoverFit.cover);
      await tester.drag(find.byType(ClipOval).first, const Offset(25, -20));
      await tester.pump();
      expect(selected!.focalX, lessThan(.5));
      expect(selected!.focalY, greaterThan(.5));
      await tester.tap(find.text('生成封面'));
      await tester.pump();
      expect(selected!.source, NoteCoverSource.generated);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving or canceling the note owns cover persistence on desktop and mobile',
    (tester) async {
      final repo = _TrackedRepository();
      final original = Bubble(
        id: 'saved',
        title: title.text,
        description: body.text,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        cover: const NoteCover(seed: 73),
      );
      await tester.runAsync(() => repo.save(original, analyze: false));
      final key = GlobalKey();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bubbleDocumentStoreProvider.overrideWithValue(store),
            bubbleRepositoryProvider.overrideWithValue(repo),
            coverHeadlineServiceProvider.overrideWithValue(
              CoverHeadlineService(loadModel: () async => model),
            ),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Microsoft YaHei'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('zh'),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      builder: (_) => BubbleEditorDialog(bubble: original),
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await _capture(tester, key, 'native-note-editor-desktop.png');
      await tester.tap(find.text('换一张图'));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => repo.getById(original.id)))!.cover!.seed,
        73,
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('换一张图'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithIcon(FilledButton, Icons.check));
        await repo.lastSave;
      });
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => repo.getById(original.id)))!.cover!.seed,
        isNot(73),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, key, 'native-note-editor-mobile.png');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'newly inserted images are selected once, explicit generated covers are retained',
    (tester) async {
      NoteCover? selected;
      await showEditor(tester, (value) => selected = value, autoSelect: true);
      body.text = '${body.text}\n\n![new](https://example.com/first.png)';
      await tester.pumpAndSettle();
      expect(selected!.source, NoteCoverSource.image);
      expect(selected!.imageUri, 'https://example.com/first.png');
      await tester.tap(find.text('生成封面'));
      await tester.pump();
      body.text = '${body.text}\n\n![another](https://example.com/second.png)';
      await tester.pumpAndSettle();
      expect(selected!.source, NoteCoverSource.generated);
    },
  );

  testWidgets(
    'ocean pages expose only visible notes, preserve readable circles, and pause on hover',
    (tester) async {
      final recorder = <List<String>>[];
      final notes = List.generate(
        9,
        (index) => Bubble(
          id: 'page-$index',
          title: [
            '开发不是生产',
            '勇气不是不害怕',
            '所有回报来自复利',
            '愤怒驱动的参与度算法',
            '新奇性搜索',
            '管理者创造环境',
            '使命、念力与品味',
            '意志力',
            '谢谢你，大脑！',
          ][index],
          description: body.text,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      final key = GlobalKey();
      tester.view.physicalSize = const Size(900, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeExposureRecorderProvider.overrideWithValue(
              (visible) async =>
                  recorder.add(visible.map((note) => note.id).toList()),
            ),
            displayBubblesProvider.overrideWith((ref) async {
              ref.watch(homeRefreshVersionProvider);
              return List.of(notes);
            }),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData.dark(useMaterial3: true).copyWith(
                textTheme: ThemeData.dark().textTheme.apply(
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('zh'),
              home: const OceanPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final firstCount = find.byType(OceanBubble).evaluate().length;
      expect(firstCount, inInclusiveRange(1, 8));
      expect(recorder.single.length, firstCount);
      for (final widget in tester.widgetList<OceanBubble>(
        find.byType(OceanBubble),
      )) {
        expect(widget.size, greaterThan(210));
      }
      await _capture(tester, key, 'native-ocean-desktop.png');
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.byType(OceanBubble).first));
      await tester.pump(const Duration(milliseconds: 180));
      final center = tester.getCenter(find.byType(OceanBubble).first);
      await tester.pump(const Duration(seconds: 1));
      expect(
        (tester.getCenter(find.byType(OceanBubble).first) - center).distance,
        lessThan(.5),
      );
      await mouse.removePointer();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(recorder.expand((page) => page).toSet().length, notes.length);
      await tester.tap(find.byTooltip('上一页'));
      await tester.pump();
      await tester.pump();
      expect(recorder.length, 2);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await _capture(tester, key, 'native-ocean-mobile.png');
    },
  );
}
