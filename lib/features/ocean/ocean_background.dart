import 'dart:math' as math;

import 'package:flutter/material.dart';

class OceanBackground extends StatelessWidget {
  const OceanBackground({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _TopDownOceanPainter(progress), size: Size.infinite);
}

class _TopDownOceanPainter extends CustomPainter {
  const _TopDownOceanPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.3, -.45),
          radius: 1.25,
          colors: [Color(0xFF17637A), Color(0xFF082F43), Color(0xFF031522)],
          stops: [0, .52, 1],
        ).createShader(bounds),
    );

    _paintCaustics(canvas, size);
    _paintRipples(canvas, size);
    _paintParticles(canvas, size);

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.transparent, Color(0x99020D16)],
          stops: [.55, 1],
        ).createShader(bounds),
    );
  }

  void _paintCaustics(Canvas canvas, Size size) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF8AE8E1).withValues(alpha: .11)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final time = progress * math.pi * 2;
    for (var row = -1; row < 9; row++) {
      final path = Path();
      for (double x = -40; x <= size.width + 40; x += 14) {
        final baseY = row * 125 + 30.0;
        final y =
            baseY +
            math.sin(x / 70 + time + row * .8) * 15 +
            math.sin(x / 31 - time * .7) * 5;
        if (x == -40) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, glow);
    }

    final patches = Paint()
      ..blendMode = BlendMode.screen
      ..color = const Color(0xFF64D9DA).withValues(alpha: .035)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    for (var i = 0; i < 9; i++) {
      final x = (size.width * ((i * .273 + progress * .03) % 1));
      final y = size.height * ((i * .417 + .13) % 1);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(i * .72 + time * .04);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 180 + (i % 3) * 55,
          height: 44 + (i % 2) * 26,
        ),
        patches,
      );
      canvas.restore();
    }
  }

  void _paintRipples(Canvas canvas, Size size) {
    final time = progress * math.pi * 2;
    for (var i = 0; i < 4; i++) {
      final center = Offset(
        size.width * (.16 + i * .23),
        size.height * (.24 + (i.isEven ? .12 : .48)),
      );
      final radius = 34 + ((progress * 80 + i * 23) % 90);
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(math.sin(time + i) * 8, 0),
          width: radius * 2.2,
          height: radius * .72,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(
            alpha: .06 * (1 - ((radius - 34) / 90)),
          ),
      );
    }
  }

  void _paintParticles(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .15);
    for (var i = 0; i < 46; i++) {
      final x = size.width * ((i * .618033 + progress * .006) % 1);
      final y = size.height * ((i * .381966 + progress * .012) % 1);
      canvas.drawCircle(Offset(x, y), .6 + (i % 3) * .45, paint);
    }
  }

  @override
  bool shouldRepaint(_TopDownOceanPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
