import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>(
      (_) => LocaleController()..load(),
    );

class LocaleController extends StateNotifier<Locale?> {
  LocaleController() : super(null);

  Future<void> load() async {
    final value = (await SharedPreferences.getInstance()).getString('locale');
    state = _locale(value);
  }

  Future<void> setPreference(String value) async {
    state = _locale(value);
    await (await SharedPreferences.getInstance()).setString('locale', value);
  }

  Locale? _locale(String? value) => switch (value) {
    'zh' => const Locale('zh'),
    'en' => const Locale('en'),
    _ => null,
  };
}
