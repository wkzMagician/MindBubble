import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/reminder_artwork.dart';

Future<List<int>> rgbaAt(List<int> png, int x, int y) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  final color = bytes!.buffer.asUint8List().sublist(offset, offset + 4);
  image.dispose();
  codec.dispose();
  return color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Ocean artwork uses transparent corners and the homepage palette',
    () async {
      final png = await ReminderArtwork.render(
        title: '想法会再度浮现',
        redNote: false,
        tintIndex: 0,
      );
      expect(png, isNotEmpty);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 344);
      expect(frame.image.height, 344);
      frame.image.dispose();
      codec.dispose();
      final corner = await rgbaAt(png, 0, 0);
      final highlight = await rgbaAt(png, 130, 126);
      final lower = await rgbaAt(png, 172, 260);
      expect(corner[3], 0);
      expect(highlight[3], greaterThan(200));
      expect(lower[3], greaterThan(200));
      expect(highlight.sublist(0, 3), isNot(equals(lower.sublist(0, 3))));
    },
  );

  test(
    'RedNote reminder renders a paper card with transparent edges',
    () async {
      final png = await ReminderArtwork.render(
        title: '回顾值得保存的想法',
        redNote: true,
        tintIndex: 0,
      );
      final corner = await rgbaAt(png, 0, 0);
      final card = await rgbaAt(png, 320, 35);
      expect(corner[3], 0);
      expect(card[3], greaterThan(200));
      expect(card[0], greaterThan(220));
    },
  );
}
