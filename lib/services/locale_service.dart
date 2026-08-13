import 'dart:async';

import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>(
      (_) => LocaleController()..load(),
    );

class LocaleController extends StateNotifier<Locale?> {
  LocaleController() : super(null);

  Future<void> load() async {
    final value = await _settings.read('locale') as String?;
    state = switch (value) {
      'zh' => const Locale('zh'),
      'en' => const Locale('en'),
      _ => null,
    };
  }

  Future<void> setPreference(String value) async {
    state = switch (value) {
      'zh' => const Locale('zh'),
      'en' => const Locale('en'),
      _ => null,
    };
    await _settings.write('locale', value);
  }

  SettingsStore get _settings => Dartloom.get<SettingsStore>();
}
