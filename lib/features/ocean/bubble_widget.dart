import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import '../note_cover/note_cover_artwork.dart';

class OceanBubble extends StatefulWidget {
  const OceanBubble({
    required this.bubble,
    required this.size,
    required this.lift,
    required this.deformation,
    required this.impactAngle,
    required this.tintIndex,
    required this.onTap,
    this.documentStore,
    this.onHoverChanged,
    super.key,
  });
  final Bubble bubble;
  final double size;
  final double lift;
  final double deformation;
  final double impactAngle;
  final int tintIndex;
  final VoidCallback onTap;
  final BubbleDocumentStore? documentStore;
  final ValueChanged<bool>? onHoverChanged;
  @override
  State<OceanBubble> createState() => _OceanBubbleState();
}

class _OceanBubbleState extends State<OceanBubble> {
  bool _hovered = false;
  void _hover(bool value) {
    setState(() => _hovered = value);
    widget.onHoverChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final squash = widget.deformation.clamp(0.0, .08);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Semantics(
        container: true,
        label: widget.bubble.title,
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _hover(true),
          onExit: (_) => _hover(false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Transform.rotate(
              angle: widget.impactAngle,
              child: Transform.scale(
                scaleX: 1 - squash,
                scaleY: 1 + squash * .62,
                child: Transform.rotate(
                  angle: -widget.impactAngle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x70D8F7EE),
                          Color(0x126399AD),
                          Color(0x46E2B6EE),
                        ],
                      ),
                      border: Border.all(
                        color: Color(_hovered ? 0xE6E6FFF7 : 0xA8C5ECEE),
                        width: _hovered ? 1.7 : 1.1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x7000111D),
                          blurRadius: 20 + widget.lift * 2,
                          offset: const Offset(0, 12),
                        ),
                        if (_hovered)
                          const BoxShadow(
                            color: Color(0x2677CEC6),
                            blurRadius: 26,
                          ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(widget.size * .042),
                          child: ClipOval(
                            child: ExcludeSemantics(
                              child: NoteCoverArtwork(
                                note: widget.bubble,
                                documentStore: widget.documentStore,
                              ),
                            ),
                          ),
                        ),
                        const IgnorePointer(
                          child: CustomPaint(painter: _BubbleRimPainter()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleRimPainter extends CustomPainter {
  const _BubbleRimPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final edge = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    paint
      ..color = const Color(0xC5F3FFFC)
      ..strokeWidth = math.max(1.2, size.width * .006);
    canvas.drawArc(
      edge.deflate(size.width * .045),
      math.pi * 1.12,
      math.pi * .43,
      false,
      paint,
    );
    paint
      ..color = const Color(0x78F1C5EE)
      ..strokeWidth = .8;
    canvas.drawArc(edge.deflate(3), .08, math.pi * .62, false, paint);
  }

  @override
  bool shouldRepaint(_BubbleRimPainter oldDelegate) => false;
}
