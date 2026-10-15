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

extension MindBubbleTheme on BuildContext {
  bool get isRedNote => Theme.of(this).brightness == Brightness.light;
  Color get appBackground =>
      isRedNote ? const Color(0xFFFFF8F7) : const Color(0xFF061620);
  Color get appPanel => isRedNote ? Colors.white : const Color(0xFF0B2733);
  Color get appField =>
      isRedNote ? const Color(0xFFFFF2F2) : const Color(0xFF123846);
  Color get appEditor =>
      isRedNote ? const Color(0xFFFFFBFA) : const Color(0xFF0D2A36);
  Color get appActive =>
      isRedNote ? const Color(0xFFFFE4E8) : const Color(0xFF123B49);
  Color get appAccent =>
      isRedNote ? const Color(0xFFFF2442) : const Color(0xFF65D7CB);
  Color get appBorder => isRedNote ? const Color(0xFFEBCFCF) : Colors.white24;
  List<Color> get appHeaderGradient => isRedNote
      ? const [Color(0xFFFF4761), Color(0xFFFF2442)]
      : const [Color(0xFF244DA9), Color(0xFF7648A9)];
}
