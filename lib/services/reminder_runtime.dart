import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/bubble_repository.dart';
import '../features/recommendations/note_profile.dart';
import '../features/recommendations/recommendation_service.dart';
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
            'summary': events[index].summary,
            'eventId': events[index].eventId,
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

  Future<bool> showDesktop({
    required String title,
    required String id,
    required bool redNote,
    required ReminderSettings settings,
  }) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return false;
    }
    try {
      // Rasterize with Flutter's original bubble materials and text engine;
      // native windows only position/animate a transparent bitmap surface.
      final png = await ReminderArtwork.render(
        title: title,
        redNote: redNote,
        tintIndex: (id.hashCode & 0x7fffffff) % 5,
      );
      final result = await _channel.invokeMethod<Object?>('showOverlay', {
        'bubbleId': id,
        'title': title,
        'redNote': redNote,
        'artwork': png,
        'seconds': settings.overlaySeconds,
        'corner': settings.overlayCorner,
      });
      return result != false;
    } on MissingPluginException {
      // Linux desktops without an overlay backend can use native notifications
      // once an adapter has been enabled.
      return false;
    }
  }

  Future<List<Map<String, Object?>>> delivered() async {
    if (!Platform.isAndroid && !Platform.isIOS) return [];
    try {
      final values =
          await _channel.invokeListMethod<Object?>('deliveredReminders') ?? [];
      return values
          .whereType<Map>()
          .map((v) => v.cast<String, Object?>())
          .toList();
    } on MissingPluginException {
      return [];
    }
  }

  Future<void> acknowledge(List<String> ids) async {
    if (ids.isEmpty) return;
    await _channel.invokeMethod<void>('acknowledgeReminders', {'ids': ids});
  }
}

/// Impure coordinator; never watches or writes the homepage's draw version.
class ReminderRuntime {
  ReminderRuntime({
    required this.repository,
    required this.platform,
    RecommendationService? recommendations,
  }) : recommendations = recommendations ?? RecommendationService(repository);
  final BubbleRepository repository;
  final ReminderPlatform platform;
  final RecommendationService recommendations;
  final ReminderSelector selector = ReminderSelector();
  Timer? _timer;
  int _generation = 0;
  ReminderSettings _settings = const ReminderSettings();
  bool _redNote = false;
  bool _disposed = false;
  bool _showing = false;

  Future<void> configure(
    ReminderSettings settings, {
    required bool redNote,
  }) async {
    final sameCadence =
        _settings.enabled == settings.enabled &&
        _settings.intervalMinutes == settings.intervalMinutes;
    _settings = settings;
    _redNote = redNote;
    if (!sameCadence || !settings.enabled) {
      _timer?.cancel();
      _timer = null;
    }
    final version = ++_generation;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await platform.setKeepInTray(settings.enabled && settings.keepInTray);
    }
    if (!settings.enabled) {
      await platform.cancel();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      await reconcileDeliveries();
      // 48 pending notifications, below iOS's 64-request limit.
      final notes = await repository.getAll();
      if (_disposed || version != _generation) return;
      final plan = planReminders(
        now: DateTime.now(),
        settings: settings,
        bubbles: notes,
        selector: selector,
        config: recommendations.config,
        events: await repository.events.read(),
      );
      if (_disposed || version != _generation) return;
      await platform.schedule(plan);
    } else {
      _timer ??= Timer.periodic(
        Duration(minutes: settings.intervalMinutes),
        (_) => _desktopTick(),
      );
    }
  }

  Future<void> _desktopTick() async {
    if (_disposed || !_settings.enabled || _settings.isQuiet(DateTime.now())) {
      return;
    }
    await _showBatch(recommendations.config.notificationCount);
  }

  Future<void> previewDesktop() async {
    if (_disposed) return;
    await _showBatch(1, preview: true);
  }

  Future<void> _showBatch(int count, {bool preview = false}) async {
    if (_showing) return;
    _showing = true;
    try {
      final notes = await recommendations.recommend(
        count,
        channel: RecommendationChannel.notification,
      );
      for (var i = 0; i < notes.length; i++) {
        if (_disposed ||
            (!preview &&
                (!_settings.enabled || _settings.isQuiet(DateTime.now())))) {
          break;
        }
        final picked = await repository.getById(notes[i].id);
        if (picked == null || !picked.recommendationEnabled) continue;
        final sent = await platform.showDesktop(
          title: picked.showSummary
              ? '${picked.cueTitle}\n${picked.effectiveProfile.summary}'
              : picked.cueTitle,
          id: picked.id,
          redNote: _redNote,
          settings: _settings,
        );
        if (sent) {
          await repository.recordShown(
            [picked.id],
            DateTime.now(),
            channel: RecommendationChannel.notification,
          );
        }
        if (i < notes.length - 1) {
          await Future<void>.delayed(
            Duration(seconds: _settings.overlaySeconds),
          );
        }
      }
    } finally {
      _showing = false;
    }
  }

  Future<void> reconcileDeliveries() async {
    final delivered = await platform.delivered();
    final acknowledged = <String>[];
    for (final event in delivered) {
      final id = event['eventId'], note = event['bubbleId'], at = event['at'];
      if (id is! String || note is! String || at is! num) continue;
      await repository.recordShown(
        [note],
        DateTime.fromMillisecondsSinceEpoch(at.toInt()),
        channel: RecommendationChannel.notification,
        eventId: id,
      );
      acknowledged.add(id);
    }
    await platform.acknowledge(acknowledged);
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
    recommendations: ref.read(recommendationServiceProvider),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});
