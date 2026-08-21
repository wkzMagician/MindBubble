import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartloom_autostart/dartloom_autostart.dart';

final startupServiceProvider = Provider<StartupService>(
  (_) => StartupService(null),
);

/// Desktop login autostart is optional. Mobile platforms use the Dartloom
/// background sync scheduler and cannot launch the foreground app at boot.
class StartupService {
  StartupService(this._service);

  final AutostartService? _service;

  bool get isSupported => _service != null;
  String get platformLabel => 'desktop';
  void initialize() {}
  Future<bool> isEnabled() => _service?.isEnabled() ?? Future.value(false);
  Future<void> setEnabled(bool enabled) async {
    final service = _service;
    if (service == null) return;
    if (enabled) {
      await service.enable();
    } else {
      await service.disable();
    }
  }
}
