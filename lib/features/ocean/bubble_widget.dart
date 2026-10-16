import 'package:flutter/material.dart';

import '../../models/bubble.dart';
import 'ocean_bubble_style.dart';

class OceanBubble extends StatefulWidget {
  const OceanBubble({
    required this.bubble,
    required this.size,
    required this.lift,
    required this.deformation,
    required this.impactAngle,
    required this.tintIndex,
    required this.onTap,
    super.key,
  });

  final Bubble bubble;
  final double size;
  final double lift;
  final double deformation;
  final double impactAngle;
  final int tintIndex;
  final VoidCallback onTap;

  @override
  State<OceanBubble> createState() => _OceanBubbleState();
}

class _OceanBubbleState extends State<OceanBubble> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = OceanBubbleStyle.palette(widget.tintIndex);
    final liftScale = 1 + widget.lift * .045 + (_hovered ? .055 : 0);
    final squash = widget.deformation.clamp(0.0, .18);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Transform.scale(
          scale: liftScale,
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
                  padding: EdgeInsets.all(widget.size * .14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: OceanBubbleStyle.highlightCenter,
                      radius: OceanBubbleStyle.radialRadius,
                      colors: palette,
                      stops: OceanBubbleStyle.gradientStops,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: _hovered ? .8 : OceanBubbleStyle.outlineOpacity,
                      ),
                      width: _hovered ? 2.2 : 1.3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .42),
                        blurRadius: 20 + widget.lift * 8,
                        spreadRadius: -3,
                        offset: Offset(7, 12 + widget.lift * 5),
                      ),
                      BoxShadow(
                        color: palette[1].withValues(
                          alpha: OceanBubbleStyle.glowOpacity,
                        ),
                        blurRadius: _hovered ? 34 : 22,
                        spreadRadius: _hovered ? 3 : 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: widget.size * .08,
                        top: widget.size * .05,
                        child: Container(
                          width: widget.size * .24,
                          height: widget.size * .11,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: OceanBubbleStyle.highlightOpacity,
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          widget.bubble.title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: widget.size * .105,
                                fontWeight: FontWeight.w700,
                                height: 1.18,
                                color: Colors.white,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x66000000),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                        ),
                      ),
                    ],
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
