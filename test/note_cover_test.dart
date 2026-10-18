import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/note_cover/note_cover.dart';
import 'package:mind_bubble/features/note_cover/note_cover_artwork.dart';
import 'package:mind_bubble/features/note_cover/note_cover_generator.dart';
import 'package:mind_bubble/features/note_cover/note_cover_service.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/daily_selection_cache.dart';
import 'package:mind_bubble/services/device_identity_service.dart';

final coverTestPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZY0AAAAASUVORK5CYII=',
);

Bubble coverNote({
  String title = '开发不是生产',
  String body = '试错和探索不是浪费。',
  NoteCover? cover,
}) => Bubble(
  id: 'cover-note',
  title: title,
  description: body,
  createdAt: DateTime(2026, 10, 17),
  updatedAt: DateTime(2026, 10, 17),
  cover: cover,
);

void main() {
  test(
    'images are parsed in document order, deduplicated, and exclude code',
    () {
      const markdown = '''![first](assets/one.png)
![remote](<https://example.com/a(b).png> "caption")
![duplicate](assets/one.png)
`![example](assets/inline.png)`
~~~md
![example](assets/code.png)
~~~
![reference][photo]

[photo]: https://example.com/second.jpg
''';
      expect(noteImageUris(markdown), [
        'assets/one.png',
        'https://example.com/a(b).png',
        'https://example.com/second.jpg',
      ]);
    },
  );

  test('old notes receive stable seeds and select the first actual image', () {
    expect(
      NoteCover.forNote('one', '').seed,
      NoteCover.forNote('one', '').seed,
    );
    expect(
      NoteCover.forNote('one', '').seed,
      isNot(NoteCover.forNote('two', '').seed),
    );
    expect(NoteCover.forNote('one', '').source, NoteCoverSource.generated);
    final image = NoteCover.forNote('one', '![image](assets/photo.png)');
    expect(image.source, NoteCoverSource.image);
    expect(image.imageUri, 'assets/photo.png');
  });

  test('cover metadata survives both document and model serialization', () {
    const cover = NoteCover(
      seed: 72,
      source: NoteCoverSource.image,
      imageUri: 'https://example.com/image.png',
      textSource: NoteCoverTextSource.hook,
      text: '试错都被砍了，开发还剩什么？',
      phrases: ['试错'],
      fit: NoteCoverFit.cover,
      focalX: .2,
      focalY: .8,
      posterUri: 'assets/previous.png',
      posterSignature: 'previous',
    );
    final note = coverNote(cover: cover);
    final encoded = BubbleDocumentCodec.encode(note, updatedBy: 'test');
    expect(
      BubbleDocumentCodec.decode(encoded).bubble.cover!.toJson(),
      cover.toJson(),
    );
    expect(Bubble.fromMap(note.toMap()).cover!.toJson(), cover.toJson());
    expect(
      BubbleDocumentCodec.decode(
        BubbleDocumentCodec.encode(coverNote(), updatedBy: 'test'),
      ).bubble.cover,
      isNull,
    );
    expect(
      note.copyWith(appearanceFrequency: 5).cover!.toJson(),
      cover.toJson(),
    );
  });

  test('original titles follow title edits while hook text stays selected', () {
    const original = NoteCover(seed: 1);
    expect(original.signature('before'), isNot(original.signature('after')));
    const hook = NoteCover(
      seed: 1,
      textSource: NoteCoverTextSource.hook,
      text: '先看正文里的矛盾',
    );
    expect(hook.signature('before'), hook.signature('after'));
    expect(hook.headline('changed title'), '先看正文里的矛盾');
    final parsed = NoteCover.fromJson({
      'seed': 1,
      'focalX': -7,
      'focalY': double.infinity,
    });
    expect(parsed.focalX, 0);
    expect(parsed.focalY, .5);
  });

  testWidgets('generated covers stay opaque while PNG frames load', (
    tester,
  ) async {
    const cover = NoteCover(seed: 906);
    final note = coverNote(title: '封面始终可见', cover: cover);
    await tester.runAsync(() => NoteCoverGenerator.render(cover, note.title));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: 200,
              child: NoteCoverArtwork(note: note),
            ),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final center =
              ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
          expect(pixels!.getUint8(center + 3), 255, reason: 'frame $frame');
        } finally {
          image.dispose();
        }
      });
    }
  });

  testWidgets(
    'cover layout fits its circular safe area and produces PNG pixels',
    (tester) async {
      for (final text in [
        '开发越像流水线，确定性越像幻觉',
        '等到不害怕再行动，你要等多久？',
        'A useful agent observation',
        '👨‍👩‍👧‍👦 与组合字符 é',
      ]) {
        final layout = NoteCoverGenerator.layout(text);
        expect(layout.lines.length, inInclusiveRange(1, 4));
        expect(
          layout.lines.join().replaceAll(' ', ''),
          text.replaceAll(' ', ''),
        );
        expect(
          layout.lines.length * layout.lineHeight,
          lessThanOrEqualTo(NoteCoverGenerator.textHeight),
        );
        for (final line in layout.lines) {
          final painter = TextPainter(
            text: TextSpan(
              text: line,
              style: TextStyle(
                fontSize: layout.fontSize,
                fontWeight: FontWeight.w800,
                fontFamily: 'Microsoft YaHei',
                fontFamilyFallback: const [
                  'Microsoft YaHei',
                  'PingFang SC',
                  'Noto Sans CJK SC',
                ],
                height: 1,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          expect(
            painter.width,
            lessThanOrEqualTo(NoteCoverGenerator.textWidth + 1),
          );
          painter.dispose();
        }
      }
      await tester.runAsync(() async {
        final png = await NoteCoverGenerator.render(
          const NoteCover(seed: 27),
          '生成封面图片',
        );
        expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(png);
        expect(header.getUint32(16), 1024);
        expect(header.getUint32(20), 1024);
        expect(
          await NoteCoverGenerator.render(const NoteCover(seed: 27), '生成封面图片'),
          png,
        );
        expect(
          await NoteCoverGenerator.render(const NoteCover(seed: 28), '生成封面图片'),
          isNot(png),
        );
      });
    },
  );

  group('saved artwork', () {
    late Directory folder;
    late BubbleDocumentStore store;
    setUp(() async {
      folder = await Directory.systemTemp.createTemp('mindbubble-cover-');
      final root = Directory('${folder.path}/notes')..createSync();
      final support = Directory('${folder.path}/support')..createSync();
      store = BubbleDocumentStore.forTesting(
        root: root,
        supportRoot: support,
        deviceIdentity: const DeviceIdentity('test-device'),
      );
    });
    tearDown(() async {
      await store.dispose();
      await folder.delete(recursive: true);
    });

    test('lazy artwork never replaces an explicitly edited cover', () async {
      final gate = Completer<Uint8List>();
      var calls = 0;
      final covers = NoteCoverService(
        store,
        rasterize: (_, _) =>
            ++calls == 1 ? gate.future : Future.value(coverTestPng),
      );
      final repository = BubbleRepository(
        store,
        DailySelectionCache.forTesting(File('${folder.path}/daily.json')),
        const DeviceIdentity('test-device'),
        () {},
        covers: covers,
      );
      final original = coverNote();
      await store.save(original);
      final pending = repository.ensureCover(original);
      await repository.save(
        original.copyWith(
          cover: const NoteCover(
            seed: 900,
            textSource: NoteCoverTextSource.custom,
            text: '我选定的标题',
          ),
        ),
        analyze: false,
      );
      gate.complete(coverTestPng);
      await pending;
      expect((await repository.getById(original.id))!.cover!.text, '我选定的标题');
    });

    test(
      'PNG is stored as an ordinary attachment and reused across body edits',
      () async {
        var renders = 0;
        final service = NoteCoverService(
          store,
          rasterize: (_, _) async {
            renders++;
            return coverTestPng;
          },
        );
        final prepared = await service.prepare(coverNote());
        expect(prepared.cover!.posterUri, startsWith('assets/'));
        expect(
          await store.readAttachment(prepared.cover!.posterUri!),
          coverTestPng,
        );
        await store.save(prepared);
        final reopened = (await store.readAll()).single;
        await service.prepare(reopened.copyWith(description: '正文更新，仍使用原标题。'));
        expect(renders, 1);
        await service.prepare(reopened.copyWith(title: '新的原标题'));
        expect(renders, 2);
        final selected = await service.prepare(
          reopened.copyWith(
            cover: reopened.cover!.copyWith(
              source: NoteCoverSource.image,
              imageUri: 'https://example.com/chosen.png',
            ),
          ),
        );
        expect(selected.cover!.imageUri, 'https://example.com/chosen.png');
        expect(renders, 2);
      },
    );

    test(
      'lazy legacy artwork preserves concurrent exposure and does not redraw recommendations',
      () async {
        final gate = Completer<Uint8List>();
        var redraws = 0;
        var cached = 0;
        final service = NoteCoverService(
          store,
          rasterize: (_, _) => gate.future,
        );
        final repository = BubbleRepository(
          store,
          DailySelectionCache.forTesting(File('${folder.path}/daily.json')),
          const DeviceIdentity('test-device'),
          () => redraws++,
          covers: service,
          onCoverCached: () => cached++,
        );
        final original = coverNote();
        await store.save(original);
        final pending = repository.ensureCover(original);
        await repository.recordShown([original.id], DateTime(2026, 10, 18));
        gate.complete(coverTestPng);
        await pending;
        final current = (await repository.getById(original.id))!;
        expect(current.shownCount, 1);
        expect(current.cover!.hasPosterFor(current.title), true);
        expect(redraws, 0);
        expect(cached, 1);
      },
    );
  });
}
