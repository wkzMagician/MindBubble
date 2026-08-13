import 'dart:io';

import 'package:dartloom_autostart/dartloom_autostart.dart';
import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final startupServiceProvider = Provider<StartupService>(
  (_) => StartupService(),
);

class StartupService {
  bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String get platformLabel => Platform.isMacOS
      ? 'macOS'
      : Platform.isLinux
      ? 'Linux'
      : 'Windows';

  void initialize() {
    // Dartloom initializes the platform adapter and owns its lifecycle.
  }

  Future<bool> isEnabled() =>
      Dartloom.maybeGet<AutostartService>()?.isEnabled() ?? Future.value(false);

  Future<void> setEnabled(bool enabled) async {
    final service = Dartloom.maybeGet<AutostartService>();
    if (service == null) return;
    if (enabled) {
      await service.enable();
    } else {
      await service.disable();
    }
  }
}
