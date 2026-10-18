import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VisualTheme { ocean, redNote }

final visualThemeProvider =
    StateNotifierProvider<VisualThemeController, VisualTheme>(
      (_) => VisualThemeController()..load(),
    );

class VisualThemeController extends StateNotifier<VisualTheme> {
  VisualThemeController() : super(VisualTheme.ocean);

  Future<void> load() async {
    final value = (await SharedPreferences.getInstance()).getString(
      'visualTheme',
    );
    state = value == 'redNote' ? VisualTheme.redNote : VisualTheme.ocean;
  }

  Future<void> setTheme(VisualTheme value) async {
    state = value;
    await (await SharedPreferences.getInstance()).setString(
      'visualTheme',
      value.name,
    );
  }

  Future<void> toggle() => setTheme(
    state == VisualTheme.ocean ? VisualTheme.redNote : VisualTheme.ocean,
  );
}

/// Muted, content-first palette shared by the RedNote feed and management UI.
abstract final class RedNoteColors {
  static const background = Color(0xFFF7F7F7);
  static const surface = Color(0xFFFFFFFF);
  static const field = Color(0xFFF5F5F5);
  static const editor = Color(0xFFFAFAFA);
  static const active = Color(0xFFFFF0F2);
  static const border = Color(0xFFE9E9E9);
  static const text = Color(0xFF222222);
  static const secondary = Color(0xFF666666);
  static const muted = Color(0xFF929292);
  static const accent = Color(0xFFFF2442);
}

extension MindBubbleTheme on BuildContext {
  bool get isRedNote => Theme.of(this).brightness == Brightness.light;
  Color get appBackground =>
      isRedNote ? RedNoteColors.background : const Color(0xFF061620);
  Color get appPanel =>
      isRedNote ? RedNoteColors.surface : const Color(0xFF0B2733);
  Color get appField =>
      isRedNote ? RedNoteColors.field : const Color(0xFF123846);
  Color get appEditor =>
      isRedNote ? RedNoteColors.editor : const Color(0xFF0D2A36);
  Color get appActive =>
      isRedNote ? RedNoteColors.active : const Color(0xFF123B49);
  Color get appAccent =>
      isRedNote ? RedNoteColors.accent : const Color(0xFF65D7CB);
  Color get appBorder => isRedNote ? RedNoteColors.border : Colors.white24;
  List<Color> get appHeaderGradient => isRedNote
      ? const [Color(0xFFFF4761), RedNoteColors.accent]
      : const [Color(0xFF244DA9), Color(0xFF7648A9)];
}
