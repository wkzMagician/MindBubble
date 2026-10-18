import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/reminder_settings.dart';

void main() {
  Bubble note(int n, [int frequency = 3]) => Bubble(
    id: 'n$n',
    title: '想法 $n',
    description: 'content',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    appearanceFrequency: frequency,
  );

  test(
    'nonlinear interval ticks cover 15 minutes to 24 hours and default 2 hours',
    () {
      final steps = ReminderIntervals.values;
      expect(steps.first, 15);
      expect(steps.last, 1440);
      expect(ReminderIntervals.defaultMinutes, 120);
      expect(steps, orderedEquals(steps.toSet().toList()..sort()));
      expect(steps.where((m) => m <= 60), [
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
      ]);
      expect(ReminderIntervals.nearest(119), 120);
      expect(ReminderIntervals.nearest(4), 15);
      expect(ReminderIntervals.nearest(1500), 1440);
      expect(ReminderIntervals.label(15), '15 分钟');
      expect(ReminderIntervals.label(90), '1 小时 30 分钟');
      expect(ReminderIntervals.label(1440), '24 小时');
    },
  );

  test('DND overnight 23:00 - 08:00 and same-day 12:00 - 14:00', () {
    const s = ReminderSettings(quietStartMinute: 1380, quietEndMinute: 480);
    expect(s.isQuiet(DateTime(2026, 10, 16, 23)), isTrue);
    expect(s.isQuiet(DateTime(2026, 10, 17, 7, 59)), isTrue);
    expect(s.isQuiet(DateTime(2026, 10, 17, 8)), isFalse);
    expect(s.isQuiet(DateTime(2026, 10, 16, 22, 59)), isFalse);
    final day = s.copyWith(quietStartMinute: 720, quietEndMinute: 840);
    expect(day.isQuiet(DateTime(2026, 10, 16, 12)), isTrue);
    expect(day.isQuiet(DateTime(2026, 10, 16, 14)), isFalse);
    expect(
      day.copyWith(quietEnabled: false).isQuiet(DateTime(2026, 10, 16, 13)),
      isFalse,
    );
  });

  test(
    'rolling 48 notifications respect DND, keep source identity and spacing',
    () {
      final s = const ReminderSettings(enabled: true, intervalMinutes: 15);
      final bubbles = List.generate(10, note);
      final first = planReminders(
        now: DateTime(2026, 10, 16, 22, 30),
        settings: s,
        bubbles: bubbles,
        selector: ReminderSelector(random: Random(8)),
      );
      expect(first, hasLength(48));
      expect(first.first.at, DateTime(2026, 10, 16, 22, 45));
      expect(first[1].at, DateTime(2026, 10, 17, 8));
      expect(first.every((event) => !s.isQuiet(event.at)), isTrue);
      expect(
        first.every(
          (event) => bubbles.any(
            (bubble) =>
                bubble.id == event.bubbleId && bubble.title == event.title,
          ),
        ),
        isTrue,
      );
      for (var i = 1; i < first.length; i++) {
        expect(first[i].at.isAfter(first[i - 1].at), isTrue);
        expect(first[i].at.difference(first[i - 1].at).inMinutes % 15, 0);
        expect(first[i].eventId, isNotEmpty);
      }
    },
  );

  test('selector is independent and remembers previous reminder only', () {
    final bubbles = List.generate(5, note);
    final a = ReminderSelector(random: Random(2));
    final b = ReminderSelector(random: Random(2));
    final first = a.pick(bubbles)!.id;
    expect(first, b.pick(bubbles)!.id);
    a.pick(bubbles);
    expect(a.pick([]), isNull);
    expect(b.pick(bubbles), isNotNull);
    expect(const ReminderSettings().enabled, isFalse);
    expect(
      planReminders(
        now: DateTime.now(),
        settings: const ReminderSettings(),
        bubbles: bubbles,
        selector: a,
      ),
      isEmpty,
    );
  });

  test('settings persist on current device', () async {
    SharedPreferences.setMockInitialValues({});
    const initial = ReminderSettings(
      enabled: true,
      intervalMinutes: 90,
      quietStartMinute: 1300,
      quietEndMinute: 450,
      overlaySeconds: 20,
      overlayCorner: 'topLeft',
      keepInTray: false,
    );
    await initial.save();
    final restored = await ReminderSettings.load();
    expect(restored.enabled, true);
    expect(restored.intervalMinutes, 90);
    expect(restored.quietStartMinute, 1300);
    expect(restored.quietEndMinute, 450);
    expect(restored.overlaySeconds, 20);
    expect(restored.overlayCorner, 'topLeft');
    expect(restored.keepInTray, false);
  });
}
