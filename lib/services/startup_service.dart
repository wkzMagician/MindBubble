import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

final startupServiceProvider =
    Provider<StartupService>((_) => StartupService());

class StartupService {
  bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void initialize() {
    if (!isSupported) return;
    launchAtStartup.setup(
      appName: 'MindBubble',
      appPath: Platform.resolvedExecutable,
      packageName: 'dev.mindbubble.desktop',
    );
  }

  Future<bool> isEnabled() =>
      isSupported ? launchAtStartup.isEnabled() : Future.value(false);

  Future<void> setEnabled(bool enabled) => !isSupported
      ? Future.value()
      : enabled
          ? launchAtStartup.enable()
          : launchAtStartup.disable();
}
