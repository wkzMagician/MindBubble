import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../l10n/l10n.dart';
import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import 'bubble_widget.dart';

class OceanFieldLayout {
  const OceanFieldLayout({
    required this.diameter,
    required this.columns,
    required this.rows,
    required this.fieldSize,
  });
  final double diameter;
  final int columns;
  final int rows;
  final Size fieldSize;
  int get capacity => columns * rows;
  factory OceanFieldLayout.forSize(Size size) {
    final available = Size(
      math.max(1, size.width),
      math.max(1, size.height - 44),
    );
    final desired = size.width < 600 ? 166.0 : 232.0;
    final diameter = math
        .min(desired, math.min(available.width - 28, available.height - 28))
        .clamp(48.0, desired)
        .toDouble();
    return OceanFieldLayout(
      diameter: diameter,
      columns: math.max(1, (available.width / (diameter + 24)).floor()),
      rows: math.max(1, (available.height / (diameter + 24)).floor()),
      fieldSize: available,
    );
  }
}

class BubbleField extends StatefulWidget {
  const BubbleField({
    required this.bubbles,
    required this.onBubbleTap,
    this.documentStore,
    this.onVisibleChanged,
    super.key,
  });
  final List<Bubble> bubbles;
  final ValueChanged<Bubble> onBubbleTap;
  final BubbleDocumentStore? documentStore;
  final ValueChanged<List<Bubble>>? onVisibleChanged;
  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _BubbleFieldState extends State<BubbleField>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Map<String, _BubbleBody> _bodies = {};
  Duration? _previousElapsed;
  Size _fieldSize = Size.zero;
  List<Bubble> _visible = const [];
  String _layoutKey = '';
  String _reported = '';
  int _page = 0;
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
    final ids = widget.bubbles.map((note) => note.id).toSet();
    _bodies.removeWhere((id, _) => !ids.contains(id));
    for (var i = 0; i < widget.bubbles.length; i++) {
      final note = widget.bubbles[i];
      _bodies.putIfAbsent(note.id, () => _BubbleBody.seeded(note, i));
    }
  }

  void _changePage(int value) {
    for (final body in _bodies.values) {
      body.hovered = false;
    }
    setState(() => _page = value);
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
    final bodies = _visible.map((note) => _bodies[note.id]!).toList();
    for (final body in bodies) {
      body.deformation *= math.pow(.025, dt).toDouble();
      if (body.hovered) {
        body.velocity = Offset.zero;
        continue;
      }
      final wander = Offset(
        math.sin(_time * .41 + body.noiseX) * 3.2,
        math.cos(_time * .37 + body.noiseY) * 3,
      );
      body.velocity =
          (body.velocity + wander * dt) * math.pow(.991, dt * 60).toDouble();
      if (body.velocity.distance > 27) {
        body.velocity = body.velocity / body.velocity.distance * 27;
      }
      body.center += body.velocity * dt;
    }
    for (var pass = 0; pass < 3; pass++) {
      for (var i = 0; i < bodies.length; i++) {
        for (var j = i + 1; j < bodies.length; j++) {
          _resolveCollision(bodies[i], bodies[j]);
        }
      }
      for (final body in bodies) {
        _resolveWalls(body);
      }
    }
  }

  void _resolveWalls(_BubbleBody body) {
    final radius = body.collisionRadius + 3;
    final left = math.min(radius, _fieldSize.width / 2);
    final right = math.max(left, _fieldSize.width - radius);
    final top = math.min(radius, _fieldSize.height / 2);
    final bottom = math.max(top, _fieldSize.height - radius);
    if (body.center.dx < left || body.center.dx > right) {
      body.center = Offset(body.center.dx.clamp(left, right), body.center.dy);
      body.velocity = Offset(
        body.center.dx == left
            ? body.velocity.dx.abs() * .82
            : -body.velocity.dx.abs() * .82,
        body.velocity.dy,
      );
      body.impact(0);
    }
    if (body.center.dy < top || body.center.dy > bottom) {
      body.center = Offset(body.center.dx, body.center.dy.clamp(top, bottom));
      body.velocity = Offset(
        body.velocity.dx,
        body.center.dy == top
            ? body.velocity.dy.abs() * .82
            : -body.velocity.dy.abs() * .82,
      );
      body.impact(math.pi / 2);
    }
  }

  void _resolveCollision(_BubbleBody first, _BubbleBody second) {
    var delta = second.center - first.center;
    var distance = delta.distance;
    final minimum = first.collisionRadius + second.collisionRadius;
    if (distance >= minimum) return;
    if (distance < .001) {
      delta = const Offset(1, 0);
      distance = 1;
    }
    final normal = delta / distance;
    final overlap = minimum - distance;
    if (first.hovered && !second.hovered) {
      second.center += normal * overlap;
    } else if (second.hovered && !first.hovered) {
      first.center -= normal * overlap;
    } else {
      first.center -= normal * overlap * .5;
      second.center += normal * overlap * .5;
    }
    final relative = second.velocity - first.velocity;
    final closingSpeed = relative.dx * normal.dx + relative.dy * normal.dy;
    if (closingSpeed < 0) {
      final impulse =
          -(1 + .82) * closingSpeed / (first.hovered || second.hovered ? 1 : 2);
      if (!first.hovered) first.velocity -= normal * impulse;
      if (!second.hovered) second.velocity += normal * impulse;
    }
    final angle = math.atan2(normal.dy, normal.dx);
    first.impact(angle);
    second.impact(angle);
  }

  void _arrange(OceanFieldLayout layout) {
    final key =
        '${layout.fieldSize}|$_page|${_visible.map((note) => note.id).join(',')}';
    if (key == _layoutKey) return;
    _layoutKey = key;
    _fieldSize = layout.fieldSize;
    final columns = math.min(layout.columns, math.max(1, _visible.length));
    final rows = (_visible.length / columns).ceil();
    final cellWidth = _fieldSize.width / columns;
    final cellHeight = _fieldSize.height / math.max(1, rows);
    for (var i = 0; i < _visible.length; i++) {
      final body = _bodies[_visible[i].id]!;
      final row = i ~/ columns;
      final rowCount = math.min(columns, _visible.length - row * columns);
      body.radius = layout.diameter * .5 * (1 + body.variation * .025);
      body.center = Offset(
        (_fieldSize.width - rowCount * cellWidth) / 2 +
            (i % columns + .5) * cellWidth,
        (row + .5) * cellHeight,
      );
      _resolveWalls(body);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = OceanFieldLayout.forSize(constraints.biggest);
      final pageCount = math.max(
        1,
        (widget.bubbles.length / layout.capacity).ceil(),
      );
      _page = _page.clamp(0, pageCount - 1);
      _visible = widget.bubbles
          .skip(_page * layout.capacity)
          .take(layout.capacity)
          .toList();
      _arrange(layout);
      final report = '$_page|${_visible.map((note) => note.id).join(',')}';
      if (_reported != report) {
        _reported = report;
        final notes = List<Bubble>.unmodifiable(_visible);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _reported == report) {
            widget.onVisibleChanged?.call(notes);
          }
        });
      }
      return Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _fieldSize.height,
            child: ClipRect(
              child: Stack(
                children: [
                  for (var i = 0; i < _visible.length; i++)
                    _buildBubble(_visible[i], i),
                ],
              ),
            ),
          ),
          if (pageCount > 1)
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: context.l10n.oceanPreviousPage,
                      onPressed: _page > 0
                          ? () => _changePage(_page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('${_page + 1} / $pageCount'),
                    IconButton(
                      tooltip: context.l10n.oceanNextPage,
                      onPressed: _page < pageCount - 1
                          ? () => _changePage(_page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget _buildBubble(Bubble note, int index) {
    final body = _bodies[note.id]!;
    final radius = body.visualRadius;
    return Positioned(
      left: body.center.dx - radius,
      top: body.center.dy - radius,
      child: OceanBubble(
        key: ValueKey(note.id),
        bubble: note,
        size: radius * 2,
        lift: math.sin(_time * .5 + body.noiseX),
        deformation: body.deformation,
        impactAngle: body.impactAngle,
        tintIndex: index,
        documentStore: widget.documentStore,
        onHoverChanged: (value) {
          if (mounted) setState(() => body.hovered = value);
        },
        onTap: () => widget.onBubbleTap(note),
      ),
    );
  }
}

class _BubbleBody {
  _BubbleBody({
    required this.velocity,
    required this.noiseX,
    required this.noiseY,
    required this.variation,
  });
  factory _BubbleBody.seeded(Bubble note, int index) {
    final random = math.Random(note.id.hashCode ^ (index * 7919));
    return _BubbleBody(
      velocity: Offset(
        (random.nextDouble() - .5) * 22,
        -5 - random.nextDouble() * 9,
      ),
      noiseX: random.nextDouble() * math.pi * 2,
      noiseY: random.nextDouble() * math.pi * 2,
      variation: random.nextDouble() * 2 - 1,
    );
  }
  final double noiseX;
  final double noiseY;
  final double variation;
  Offset center = Offset.zero;
  Offset velocity;
  double radius = 110;
  double deformation = 0;
  double impactAngle = 0;
  bool hovered = false;
  double get visualRadius => radius * (hovered ? 1.045 : 1);
  double get collisionRadius => visualRadius * (1 + deformation * .62) + 4;
  void impact(double angle) {
    impactAngle = angle;
    deformation = math.max(deformation, .035);
  }
}
