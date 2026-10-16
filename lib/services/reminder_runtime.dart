import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/bubble_repository.dart';
import 'reminder_artwork.dart';
import 'reminder_settings.dart';

final reminderPlatformProvider = Provider<ReminderPlatform>(
  (_) => ReminderPlatform(),
);

/// Unified channel; native Android/iOS use pre-scheduled notifications and
/// desktops show an actual floating reminder window above other applications.
class ReminderPlatform {
  ReminderPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') {
        final value = call.arguments?.toString();
        if (value != null && value.isNotEmpty) onOpen?.call(value);
      }
    });
  }
  static const _channel = MethodChannel('mindbubble/reminder');
  void Function(String bubbleId)? onOpen;

  Future<String?> consumeLaunchBubble() async {
    try {
      return await _channel.invokeMethod<String>('consumeLaunchBubble');
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> cancel() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('cancelReminders');
    } on MissingPluginException {
      // Platform adapter may be unavailable in an older installed build.
    }
  }

  Future<void> schedule(List<ReminderOccurrence> events) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _channel.invokeMethod<void>('scheduleReminders', {
      'items': [
        for (var index = 0; index < events.length; index++)
          {
            'id': 6000 + index,
            'at': events[index].at.millisecondsSinceEpoch,
            'title': events[index].title,
            'bubbleId': events[index].bubbleId,
          },
      ],
    });
  }

  Future<void> setKeepInTray(bool enabled) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    try {
      await _channel.invokeMethod<void>('setKeepInTray', {'enabled': enabled});
    } on MissingPluginException {
      // No desktop adapter in this build.
    }
  }

  Future<void> showDesktop({
    required String title,
    required String id,
    required bool redNote,
    required ReminderSettings settings,
  }) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    try {
      // Rasterize with Flutter's original bubble materials and text engine;
      // native windows only position/animate a transparent bitmap surface.
      final png = await ReminderArtwork.render(
        title: title,
        redNote: redNote,
        tintIndex: (id.hashCode & 0x7fffffff) % 5,
      );
      await _channel.invokeMethod<void>('showOverlay', {
        'bubbleId': id,
        'title': title,
        'redNote': redNote,
        'artwork': png,
        'seconds': settings.overlaySeconds,
        'corner': settings.overlayCorner,
      });
    } on MissingPluginException {
      // Linux desktops without an overlay backend can use native notifications
      // once an adapter has been enabled.
    }
  }
}

/// Impure coordinator; never watches or writes the homepage's draw version.
class ReminderRuntime {
  ReminderRuntime({required this.repository, required this.platform});
  final BubbleRepository repository;
  final ReminderPlatform platform;
  final ReminderSelector selector = ReminderSelector();
  Timer? _timer;
  int _generation = 0;
  ReminderSettings _settings = const ReminderSettings();
  bool _redNote = false;
  bool _disposed = false;

  Future<void> configure(
    ReminderSettings settings, {
    required bool redNote,
  }) async {
    _settings = settings;
    _redNote = redNote;
    _timer?.cancel();
    final version = ++_generation;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await platform.setKeepInTray(settings.enabled && settings.keepInTray);
    }
    if (!settings.enabled) {
      await platform.cancel();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      // 48 unique titles, comfortably below iOS 64 pending notification slots.
      final notes = await repository.getAll();
      if (_disposed || version != _generation) return;
      final plan = planReminders(
        now: DateTime.now(),
        settings: settings,
        bubbles: notes,
        selector: selector,
      );
      await platform.schedule(plan);
    } else {
      _timer = Timer.periodic(
        Duration(minutes: settings.intervalMinutes),
        (_) => _desktopTick(),
      );
    }
  }

  Future<void> _desktopTick() async {
    if (_disposed || !_settings.enabled || _settings.isQuiet(DateTime.now())) {
      return;
    }
    final notes = await repository.getAll();
    final picked = selector.pick(notes);
    if (picked == null || _disposed) return;
    await platform.showDesktop(
      title: picked.title,
      id: picked.id,
      redNote: _redNote,
      settings: _settings,
    );
  }

  Future<void> previewDesktop() async {
    if (_disposed) return;
    final notes = await repository.getAll();
    final picked = selector.pick(notes);
    if (picked == null) return;
    await platform.showDesktop(
      title: picked.title,
      id: picked.id,
      redNote: _redNote,
      settings: _settings,
    );
  }

  Future<void> refreshMobileSchedule() async {
    if (Platform.isIOS || Platform.isAndroid) {
      await configure(_settings, redNote: _redNote);
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
  }
}

final reminderRuntimeProvider = Provider<ReminderRuntime>((ref) {
  final runtime = ReminderRuntime(
    repository: ref.read(bubbleRepositoryProvider),
    platform: ref.read(reminderPlatformProvider),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});
