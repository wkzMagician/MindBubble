import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bubble.dart';
import '../features/recommendations/note_profile.dart';
import '../features/recommendations/recommendation_config.dart';
import '../features/recommendations/recommendation_engine.dart';

class ReminderIntervals {
  static const values = <int>[
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
    60,
    75,
    90,
    105,
    120,
    135,
    150,
    165,
    180,
    210,
    240,
    270,
    300,
    330,
    360,
    420,
    480,
    540,
    600,
    660,
    720,
    840,
    960,
    1080,
    1200,
    1320,
    1440,
  ];
  static const defaultMinutes = 120;
  static int nearest(int minutes) => values.reduce(
    (a, b) => (a - minutes).abs() <= (b - minutes).abs() ? a : b,
  );
  static String label(int m) => m < 60
      ? '$m 分钟'
      : m % 60 == 0
      ? '${m ~/ 60} 小时'
      : '${m ~/ 60} 小时 ${m % 60} 分钟';
}

class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.intervalMinutes = ReminderIntervals.defaultMinutes,
    this.quietEnabled = true,
    this.quietStartMinute = 1380,
    this.quietEndMinute = 480,
    this.overlaySeconds = 10,
    this.overlayCorner = 'bottomRight',
    this.keepInTray = true,
  });
  final bool enabled;
  final int intervalMinutes;
  final bool quietEnabled;
  final int quietStartMinute;
  final int quietEndMinute;
  final int overlaySeconds;
  final String overlayCorner;
  final bool keepInTray;

  ReminderSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    bool? quietEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
    int? overlaySeconds,
    String? overlayCorner,
    bool? keepInTray,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    overlaySeconds: overlaySeconds ?? this.overlaySeconds,
    overlayCorner: overlayCorner ?? this.overlayCorner,
    keepInTray: keepInTray ?? this.keepInTray,
  );
  bool isQuiet(DateTime time) {
    if (!quietEnabled || quietStartMinute == quietEndMinute) return false;
    final m = time.hour * 60 + time.minute;
    return quietStartMinute < quietEndMinute
        ? m >= quietStartMinute && m < quietEndMinute
        : m >= quietStartMinute || m < quietEndMinute;
  }

  static const _p = 'reminder.v1.';
  static Future<ReminderSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ReminderSettings(
      enabled: p.getBool('${_p}enabled') ?? false,
      intervalMinutes: ReminderIntervals.nearest(
        p.getInt('${_p}minutes') ?? 120,
      ),
      quietEnabled: p.getBool('${_p}quietEnabled') ?? true,
      quietStartMinute: p.getInt('${_p}quietStart') ?? 1380,
      quietEndMinute: p.getInt('${_p}quietEnd') ?? 480,
      overlaySeconds: p.getInt('${_p}overlaySeconds') ?? 10,
      overlayCorner: p.getString('${_p}corner') ?? 'bottomRight',
      keepInTray: p.getBool('${_p}keepInTray') ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setBool('${_p}enabled', enabled),
      p.setInt('${_p}minutes', intervalMinutes),
      p.setBool('${_p}quietEnabled', quietEnabled),
      p.setInt('${_p}quietStart', quietStartMinute),
      p.setInt('${_p}quietEnd', quietEndMinute),
      p.setInt('${_p}overlaySeconds', overlaySeconds),
      p.setString('${_p}corner', overlayCorner),
      p.setBool('${_p}keepInTray', keepInTray),
    ]);
  }
}

final reminderSettingsProvider =
    StateNotifierProvider<ReminderSettingsController, ReminderSettings>(
      (_) => ReminderSettingsController()..reload(),
    );

class ReminderSettingsController extends StateNotifier<ReminderSettings> {
  ReminderSettingsController() : super(const ReminderSettings());
  Future<void> reload() async {
    final s = await ReminderSettings.load();
    if (mounted) state = s;
  }

  Future<void> update(ReminderSettings value) async {
    state = value;
    await value.save();
  }
}

/// Compatibility facade over the shared adaptive recommendation engine.
class ReminderSelector {
  ReminderSelector({Random? random})
    : engine = RecommendationEngine(random: random);
  final RecommendationEngine engine;
  Bubble? pick(List<Bubble> bubbles) {
    return engine
        .recommend(
          bubbles,
          count: 1,
          now: DateTime.now(),
          config: RecommendationConfig(),
        )
        .firstOrNull;
  }
}

class ReminderOccurrence {
  const ReminderOccurrence({
    required this.at,
    required this.bubbleId,
    required this.title,
    this.summary = '',
    this.eventId = '',
  });
  final DateTime at;
  final String bubbleId;
  final String title;
  final String summary;
  final String eventId;
}

List<ReminderOccurrence> planReminders({
  required DateTime now,
  required ReminderSettings settings,
  required List<Bubble> bubbles,
  required ReminderSelector selector,
  int count = 48,
  RecommendationConfig? config,
  List<RecommendationEvent> events = const [],
}) {
  if (!settings.enabled || count <= 0 || bubbles.isEmpty) return const [];
  final planned = <ReminderOccurrence>[];
  final parameters = config ?? RecommendationConfig();
  final virtualNotes = {for (final n in bubbles) n.id: n};
  final virtualEvents = [...events];
  var time = now;
  for (
    var attempted = 0;
    attempted < count * 12 && planned.length < count;
    attempted++
  ) {
    time = time.add(Duration(minutes: settings.intervalMinutes));
    if (settings.isQuiet(time)) continue;
    final selected = selector.engine.recommend(
      virtualNotes.values.toList(),
      count: min(parameters.notificationCount, count - planned.length),
      now: time,
      config: parameters,
      events: virtualEvents,
    );
    if (selected.isEmpty) break;
    for (final bubble in selected) {
      final eventId =
          'notification:${time.millisecondsSinceEpoch}:${planned.length}:${bubble.id}';
      planned.add(
        ReminderOccurrence(
          at: time,
          bubbleId: bubble.id,
          title: bubble.cueTitle,
          summary: bubble.showSummary ? bubble.effectiveProfile.summary : '',
          eventId: eventId,
        ),
      );
      // Simulate earlier slots for planning, without persisting future exposure.
      virtualNotes[bubble.id] = bubble.copyWith(
        shownByDevice: {
          'planned': BubbleShowStats(
            count: bubble.shownCount + 1,
            lastShownAt: time,
          ),
        },
      );
      virtualEvents.add(
        RecommendationEvent(
          id: eventId,
          noteId: bubble.id,
          timestamp: time,
          type: RecommendationEventType.shown,
          channel: RecommendationChannel.notification,
        ),
      );
    }
  }
  return planned;
}
