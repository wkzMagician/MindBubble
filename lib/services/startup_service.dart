import 'package:flutter_riverpod/flutter_riverpod.dart';

final startupServiceProvider = Provider<StartupService>(
  (_) => StartupService(),
);

/// Autostart is an optional platform capability and is not enabled for the
/// current package-only application build.
class StartupService {
  bool get isSupported => false;
  String get platformLabel => 'current platform';
  void initialize() {}
  Future<bool> isEnabled() async => false;
  Future<void> setEnabled(bool enabled) async {}
}
