import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/bubble.dart';
import 'bubble_widget.dart';

class BubbleField extends StatefulWidget {
  const BubbleField({
    required this.bubbles,
    required this.onBubbleTap,
    super.key,
  });

  final List<Bubble> bubbles;
  final ValueChanged<Bubble> onBubbleTap;

  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _BubbleFieldState extends State<BubbleField>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<String, _BubbleBody> _bodies = {};
  Duration? _previousElapsed;
  Size _fieldSize = Size.zero;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _syncBodies();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(BubbleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBodies();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncBodies() {
    final ids = widget.bubbles.map((bubble) => bubble.id).toSet();
    _bodies.removeWhere((id, _) => !ids.contains(id));
    for (var index = 0; index < widget.bubbles.length; index++) {
      final bubble = widget.bubbles[index];
      _bodies.putIfAbsent(bubble.id, () => _BubbleBody.seeded(bubble, index));
    }
  }

  void _tick(Duration elapsed) {
    final previous = _previousElapsed;
    _previousElapsed = elapsed;
    if (previous == null || _fieldSize.isEmpty || !mounted) return;
    final dt = ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, .035);
    _time += dt;
    _simulate(dt);
    setState(() {});
  }

  void _simulate(double dt) {
    final bodies = widget.bubbles
        .map((bubble) => _bodies[bubble.id])
        .whereType<_BubbleBody>()
        .toList();

    for (final body in bodies) {
      if (!body.initialized) body.initialize(_fieldSize);
      final wander = Offset(
        math.sin(_time * .61 + body.noiseX) * 5.5 +
            math.sin(_time * .23 + body.noiseY) * 2.6,
        math.cos(_time * .53 + body.noiseY) * 5.2 +
            math.sin(_time * .29 + body.noiseX) * 2.2,
      );
      body.velocity += wander * dt;
      body.velocity *= math.pow(.993, dt * 60).toDouble();
      final speed = body.velocity.distance;
      if (speed > 42) body.velocity = body.velocity / speed * 42;
      body.center += body.velocity * dt;
      body.deformation *= math.pow(.025, dt).toDouble();
      _resolveWalls(body);
    }

    for (var i = 0; i < bodies.length; i++) {
      for (var j = i + 1; j < bodies.length; j++) {
        _resolveCollision(bodies[i], bodies[j]);
      }
    }
  }

  void _resolveWalls(_BubbleBody body) {
    final left = body.radius + 8;
    final right = _fieldSize.width - body.radius - 8;
    final top = body.radius + 10;
    final bottom = _fieldSize.height - body.radius - 12;
    if (body.center.dx < left) {
      body.center = Offset(left, body.center.dy);
      body.velocity = Offset(body.velocity.dx.abs() * .86, body.velocity.dy);
      body.impact(0);
    } else if (body.center.dx > right) {
      body.center = Offset(right, body.center.dy);
      body.velocity = Offset(-body.velocity.dx.abs() * .86, body.velocity.dy);
      body.impact(0);
    }
    if (body.center.dy < top) {
      body.center = Offset(body.center.dx, top);
      body.velocity = Offset(body.velocity.dx, body.velocity.dy.abs() * .86);
      body.impact(math.pi / 2);
    } else if (body.center.dy > bottom) {
      body.center = Offset(body.center.dx, bottom);
      body.velocity = Offset(body.velocity.dx, -body.velocity.dy.abs() * .86);
      body.impact(math.pi / 2);
    }
  }

  void _resolveCollision(_BubbleBody first, _BubbleBody second) {
    var delta = second.center - first.center;
    var distance = delta.distance;
    final minimum = first.radius + second.radius - 3;
    if (distance >= minimum) return;
    if (distance < .001) {
      delta = const Offset(1, 0);
      distance = 1;
    }
    final normal = delta / distance;
    final overlap = minimum - distance;
    first.center -= normal * (overlap * .5);
    second.center += normal * (overlap * .5);

    final relative = second.velocity - first.velocity;
    final closingSpeed = relative.dx * normal.dx + relative.dy * normal.dy;
    if (closingSpeed < 0) {
      final impulse = -(1.0 + .88) * closingSpeed / 2;
      first.velocity -= normal * impulse;
      second.velocity += normal * impulse;
    }
    final angle = math.atan2(normal.dy, normal.dx);
    final strength = (.075 + overlap / minimum * .18).clamp(.075, .18);
    first.impact(angle, strength);
    second.impact(angle, strength);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          _fieldSize = constraints.biggest;
          return ClipRect(
            child: Stack(
              children: [
                for (var index = 0; index < widget.bubbles.length; index++)
                  _buildBubble(widget.bubbles[index], index),
              ],
            ),
          );
        },
      );

  Widget _buildBubble(Bubble bubble, int index) {
    final body = _bodies[bubble.id]!;
    if (!body.initialized && !_fieldSize.isEmpty) body.initialize(_fieldSize);
    final lift = math.sin(_time * body.bobSpeed + body.bobPhase);
    final visualSize = body.radius * 2;
    return Positioned(
      left: body.center.dx - body.radius,
      top: body.center.dy - body.radius,
      child: OceanBubble(
        key: ValueKey(bubble.id),
        bubble: bubble,
        size: visualSize,
        lift: lift,
        deformation: body.deformation,
        impactAngle: body.impactAngle,
        tintIndex: index,
        onTap: () => widget.onBubbleTap(bubble),
      ),
    );
  }
}

class _BubbleBody {
  _BubbleBody({
    required this.bubble,
    required this.radius,
    required this.fraction,
    required this.velocity,
    required this.noiseX,
    required this.noiseY,
    required this.bobPhase,
    required this.bobSpeed,
  });

  factory _BubbleBody.seeded(Bubble bubble, int index) {
    final random = math.Random(bubble.id.hashCode ^ (index * 7919));
    return _BubbleBody(
      bubble: bubble,
      radius: 66 + random.nextDouble() * 12,
      fraction: Offset(
          .16 + random.nextDouble() * .68, .17 + random.nextDouble() * .66),
      velocity: Offset(
        (random.nextDouble() - .5) * 45,
        (random.nextDouble() - .5) * 45,
      ),
      noiseX: random.nextDouble() * math.pi * 2,
      noiseY: random.nextDouble() * math.pi * 2,
      bobPhase: random.nextDouble() * math.pi * 2,
      bobSpeed: .75 + random.nextDouble() * .55,
    );
  }

  final Bubble bubble;
  final double radius;
  final Offset fraction;
  final double noiseX;
  final double noiseY;
  final double bobPhase;
  final double bobSpeed;
  Offset center = Offset.zero;
  Offset velocity;
  double deformation = 0;
  double impactAngle = 0;
  bool initialized = false;

  void initialize(Size size) {
    center = Offset(size.width * fraction.dx, size.height * fraction.dy);
    initialized = true;
  }

  void impact(double angle, [double strength = .1]) {
    impactAngle = angle;
    deformation = math.max(deformation, strength);
  }
}
