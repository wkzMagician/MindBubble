import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>(
      (_) => LocaleController()..load(),
    );

class LocaleController extends StateNotifier<Locale?> {
  LocaleController() : super(null);

  Future<void> load() async {
    final file = await _preferenceFile();
    if (!await file.exists()) return;
    final value = (await file.readAsString()).trim();
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
    final file = await _preferenceFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  Future<File> _preferenceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'locale_preference.txt'));
  }
}
