import 'package:flutter/material.dart';

/// One palette shared by the homepage OceanBubble and desktop reminders.
/// The independent reminder selection has no influence on homepage contents.
abstract final class OceanBubbleStyle {
  static const palettes = <List<Color>>[
    [Color(0xFFB8FAF0), Color(0xFF42BFD2), Color(0xFF17668E)],
    [Color(0xFFD6D4FF), Color(0xFF7D88E8), Color(0xFF394C9B)],
    [Color(0xFFFFD2EC), Color(0xFFD879BA), Color(0xFF754B91)],
    [Color(0xFFFFE2A7), Color(0xFFDF9C58), Color(0xFF8A5B53)],
    [Color(0xFFBFE8FF), Color(0xFF529DD0), Color(0xFF225B8A)],
  ];

  static const highlightCenter = Alignment(-.38, -.42);
  static const radialRadius = .9;
  static const gradientStops = <double>[0, .43, 1];
  static const outlineOpacity = .46;
  static const highlightOpacity = .24;
  static const glowOpacity = .34;

  static List<Color> palette(int index) => palettes[index % palettes.length];
}
