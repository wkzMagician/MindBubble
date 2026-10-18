import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'note_cover.dart';

class CoverTextLayout {
  const CoverTextLayout(this.lines, this.fontSize);
  final List<String> lines;
  final double fontSize;
  double get lineHeight => fontSize * 1.02;
}

class NoteCoverGenerator {
  static const dimension = 1024;
  static const textWidth = 760.0;
  static const textHeight = 580.0;
  static final _layouts = <String, CoverTextLayout>{};
  static final _pngs = <String, Future<Uint8List>>{};

  static TextStyle _style(double size, Color color) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    fontFamily: 'Microsoft YaHei',
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
    ],
    color: color,
    height: 1,
  );

  static CoverTextLayout layout(
    String text, {
    List<String> phrases = const [],
  }) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final bounded = normalized.characters.take(160).join();
    final value = bounded.isEmpty ? '…' : bounded;
    final key = [NoteCover.rendererVersion, value, ...phrases].join('|');
    final cached = _layouts[key];
    if (cached != null) return cached;
    final characters = value.characters.toList();
    final offsets = <int>[0];
    for (final character in characters) {
      offsets.add(offsets.last + character.length);
    }
    final words = TextPainter(
      text: TextSpan(text: value, style: _style(100, Colors.black)),
      textDirection: TextDirection.ltr,
    )..layout();
    final boundaries = <int>{0, characters.length};
    for (var i = 0; i < characters.length; i++) {
      final range = words.getWordBoundary(TextPosition(offset: offsets[i]));
      for (final offset in [range.start, range.end]) {
        final index = offsets.indexOf(offset);
        if (index >= 0) boundaries.add(index);
      }
    }
    words.dispose();
    _chineseBoundaries(value, offsets, boundaries, phrases);

    CoverTextLayout? result;
    for (final preserveWords in [true, false]) {
      final allowed = preserveWords
          ? boundaries
          : {for (var i = 0; i <= characters.length; i++) i};
      for (var lineCount = 1; lineCount <= 4; lineCount++) {
        CoverTextLayout? candidate;
        var low = 14;
        var high = 150;
        while (low <= high) {
          final size = (low + high) ~/ 2;
          final lines = _partition(
            characters,
            allowed,
            size.toDouble(),
            lineCount,
          );
          if (lines == null) {
            high = size - 1;
          } else {
            candidate = CoverTextLayout(lines, size.toDouble());
            low = size + 1;
          }
        }
        if (candidate == null) continue;
        if (result == null || candidate.fontSize > result.fontSize) {
          result = candidate;
        }
        // Prefer fewer complete lines once the text is comfortably readable.
        if (candidate.fontSize >= 112) {
          result = candidate;
          break;
        }
      }
      if (result != null && result.fontSize >= 42) break;
    }
    result ??= CoverTextLayout([value], 14);
    if (_layouts.length >= 64) _layouts.remove(_layouts.keys.first);
    _layouts[key] = result;
    return result;
  }

  /// Protect model phrases and common grammatical units at line boundaries.
  static void _chineseBoundaries(
    String value,
    List<int> offsets,
    Set<int> boundaries,
    List<String> phrases,
  ) {
    // Keep grammatical units intact; do not invent two-character word groups.
    for (final phrase in {
      '为什么',
      '怎么',
      '什么',
      '不等于',
      '不是',
      '不能',
      '不要',
      '不必',
      '不害怕',
      '可以',
      '应该',
      '来自',
      '管理员',
      '参与度',
      ...phrases.where((phrase) => phrase.isNotEmpty),
    }) {
      var start = value.indexOf(phrase);
      while (start >= 0) {
        for (var i = 1; i < offsets.length - 1; i++) {
          if (offsets[i] > start && offsets[i] < start + phrase.length) {
            boundaries.remove(i);
          }
        }
        start = value.indexOf(phrase, start + phrase.length);
      }
    }
  }

  static List<String>? _partition(
    List<String> characters,
    Set<int> boundaries,
    double size,
    int lines,
  ) {
    final layout = CoverTextLayout(const [], size);
    if (size + (lines - 1) * layout.lineHeight > textHeight) return null;
    final count = characters.length;
    final painter = TextPainter(textDirection: TextDirection.ltr);
    final widths = <String, double>{};
    double measure(String line) => widths.putIfAbsent(line, () {
      painter.text = TextSpan(text: line, style: _style(size, Colors.black));
      painter.layout();
      return painter.width;
    });
    final target = measure(characters.join()) / lines;
    final costs = List.generate(
      lines + 1,
      (_) => List.filled(count + 1, double.infinity),
    );
    final previous = List.generate(
      lines + 1,
      (_) => List.filled(count + 1, -1),
    );
    costs[0][0] = 0;
    for (var line = 1; line <= lines; line++) {
      for (var end = line; end <= count; end++) {
        if (!boundaries.contains(end)) continue;
        for (var start = end - 1; start >= line - 1; start--) {
          if (!boundaries.contains(start) || !costs[line - 1][start].isFinite) {
            continue;
          }
          final value = characters.sublist(start, end).join().trim();
          if (value.isEmpty ||
              RegExp(r'^[，。？！、：；,.!?;:）】》]').hasMatch(value) ||
              RegExp(r'[（【《]$').hasMatch(value)) {
            continue;
          }
          final width = measure(value);
          if (width > textWidth) continue;
          final cost =
              costs[line - 1][start] +
              math.pow(width - target, 2) +
              (value.characters.length == 1 && count > 3 ? 200000 : 0);
          // For equal balance, keep the final line fuller instead of leaving
          // a short tail or breaking a three-character opening phrase.
          if (cost <= costs[line][end]) {
            costs[line][end] = cost.toDouble();
            previous[line][end] = start;
          }
        }
      }
    }
    painter.dispose();
    if (!costs[lines][count].isFinite) return null;
    final result = <String>[];
    var end = count;
    for (var line = lines; line > 0; line--) {
      final start = previous[line][end];
      result.insert(0, characters.sublist(start, end).join().trim());
      end = start;
    }
    return result;
  }

  static void paint(Canvas canvas, Size size, NoteCover cover, String title) {
    final random = math.Random(cover.seed);
    const palettes = [
      [Color(0xFFE9D4A7), Color(0xFF3B372A), Color(0xFFC89445)],
      [Color(0xFFD9E8DC), Color(0xFF244B43), Color(0xFF8BB6A2)],
      [Color(0xFFE3D8EB), Color(0xFF43384E), Color(0xFFAD8FC2)],
      [Color(0xFFEECFC1), Color(0xFF693C32), Color(0xFFC5846B)],
      [Color(0xFFD5E5E8), Color(0xFF244750), Color(0xFF81B9C3)],
      [Color(0xFFE9DFBD), Color(0xFF45412D), Color(0xFFC8AA58)],
    ];
    final palette = palettes[random.nextInt(palettes.length)];
    canvas.save();
    canvas.scale(size.width / dimension, size.height / dimension);
    const bounds = Rect.fromLTWH(0, 0, 1024, 1024);
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = palette[0]);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(random.nextDouble() * 2 - 1, -1),
          radius: 1.7,
          colors: [
            Colors.white.withValues(alpha: .4),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    for (var i = 0; i < 2; i++) {
      final center = Offset(
        random.nextBool() ? 1040 : -40,
        random.nextDouble() * 1024,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: 350 + random.nextDouble() * 300,
          height: 500 + random.nextDouble() * 250,
        ),
        Paint()..color = palette[2].withValues(alpha: .12),
      );
    }
    final text = layout(cover.headline(title), phrases: cover.phrases);
    final blockHeight =
        text.fontSize + (text.lines.length - 1) * text.lineHeight;
    final top = (1024 - blockHeight) / 2;
    for (var i = 0; i < text.lines.length; i++) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.lines[i],
          style: _style(text.fontSize, palette[1]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset((dimension - painter.width) / 2, top + i * text.lineHeight),
      );
      painter.dispose();
    }
    canvas.restore();
  }

  static Future<Uint8List> render(NoteCover cover, String title) {
    final key = cover.signature(title);
    final existing = _pngs[key];
    if (existing != null) return existing;
    if (_pngs.length >= 32) _pngs.remove(_pngs.keys.first);
    final future = _render(cover, title);
    _pngs[key] = future;
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _pngs.remove(key);
      },
    );
    return future;
  }

  static Future<Uint8List> _render(NoteCover cover, String title) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), const Size(1024, 1024), cover, title);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(dimension, dimension);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode note cover');
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }
}

class NoteCoverPainter extends CustomPainter {
  const NoteCoverPainter({required this.cover, required this.title});
  final NoteCover cover;
  final String title;

  @override
  void paint(Canvas canvas, Size size) =>
      NoteCoverGenerator.paint(canvas, size, cover, title);

  @override
  bool shouldRepaint(NoteCoverPainter oldDelegate) =>
      cover.signature(title) != oldDelegate.cover.signature(oldDelegate.title);
}
