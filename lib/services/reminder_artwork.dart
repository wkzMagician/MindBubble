import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../features/ocean/ocean_bubble_style.dart';
import 'visual_theme_service.dart';

/// Draws a transparent PNG with the SAME Ocean radial shader, palette,
/// border and highlights used by the Flutter homepage OceanBubble. Rendering
/// occurs off-screen: the main Flutter window can remain hidden in the tray.
abstract final class ReminderArtwork {
  static Future<Uint8List> render({
    required String title,
    required bool redNote,
    required int tintIndex,
  }) async {
    final dimensions = redNote ? const Size(420, 212) : const Size(344, 344);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (redNote) {
      _drawPaper(canvas, title);
    } else {
      _drawBubble(canvas, title, tintIndex);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      dimensions.width.toInt(),
      dimensions.height.toInt(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Failed to encode reminder artwork');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  static void _drawBubble(Canvas canvas, String title, int index) {
    final palette = OceanBubbleStyle.palette(index);
    const center = Offset(172, 164);
    const radius = 122.0;
    final bounds = Rect.fromCircle(center: center, radius: radius);

    // Keep shadow and glow outside the bubble, so the window has naturally
    // transparent hit-free corners and the background can show through.
    canvas.drawCircle(
      center + const Offset(7, 12),
      radius + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: .38)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 17),
    );
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..color = palette[1].withValues(alpha: OceanBubbleStyle.glowOpacity)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 20),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: OceanBubbleStyle.highlightCenter,
          radius: OceanBubbleStyle.radialRadius,
          colors: palette,
          stops: OceanBubbleStyle.gradientStops,
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      radius - .65,
      Paint()
        ..color = Colors.white.withValues(
          alpha: OceanBubbleStyle.outlineOpacity,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );

    // Homepage's soft oval glint at the top-left of the bubble.
    final glint = RRect.fromRectAndRadius(
      const Rect.fromLTWH(110, 98, 63, 28),
      const Radius.circular(40),
    );
    canvas.drawRRect(
      glint,
      Paint()
        ..color = Colors.white.withValues(
          alpha: OceanBubbleStyle.highlightOpacity,
        ),
    );

    // The same relative headline font (roughly 10.5% of bubble diameter).
    _text(
      canvas,
      title,
      Rect.fromCenter(center: center, width: 185, height: 164),
      const TextStyle(
        fontSize: 25,
        height: 1.18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
      ),
      maxLines: 4,
      align: TextAlign.center,
    );
  }

  static void _drawPaper(Canvas canvas, String title) {
    const body = Rect.fromLTWH(26, 20, 368, 166);
    final card = RRect.fromRectAndRadius(body, const Radius.circular(12));
    canvas.drawRRect(
      card.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: .18)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 14),
    );
    canvas.drawRRect(card, Paint()..color = RedNoteColors.surface);
    // A quiet paper-color title area, just like the text-first RedNote feed.
    const cover = Rect.fromLTWH(27, 21, 366, 105);
    canvas.save();
    canvas.clipRRect(card);
    canvas.drawRect(cover, Paint()..color = const Color(0xFFF2F0EB));
    canvas.restore();
    canvas.drawRRect(
      card,
      Paint()
        ..color = RedNoteColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    _text(
      canvas,
      '“',
      const Rect.fromLTWH(47, 33, 20, 26),
      const TextStyle(color: Color(0xFFB9B6B0), fontSize: 25),
      maxLines: 1,
    );
    _text(
      canvas,
      title,
      const Rect.fromLTWH(67, 45, 299, 78),
      const TextStyle(
        color: Color(0xFF4E4A46),
        fontSize: 18,
        height: 1.32,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 3,
      align: TextAlign.left,
    );
    canvas.drawCircle(
      const Offset(51, 155),
      12,
      Paint()..color = RedNoteColors.field,
    );
    canvas.drawCircle(
      const Offset(51, 155),
      4,
      Paint()
        ..color = RedNoteColors.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    _text(
      canvas,
      '浮念',
      const Rect.fromLTWH(72, 147, 145, 24),
      const TextStyle(fontSize: 13, color: RedNoteColors.muted),
      maxLines: 1,
    );
    canvas.drawCircle(
      const Offset(369, 154),
      3,
      Paint()..color = RedNoteColors.accent.withValues(alpha: .72),
    );
  }

  static void _text(
    Canvas canvas,
    String value,
    Rect bounds,
    TextStyle style, {
    required int maxLines,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    );
    try {
      painter.layout(maxWidth: bounds.width);
      final dy = bounds.top + (bounds.height - painter.height) / 2;
      painter.paint(canvas, Offset(bounds.left, dy));
    } finally {
      painter.dispose();
    }
  }
}
