import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/scheduler_service.dart';

void main() {
  final now = DateTime(2026, 7, 27, 12);
  Bubble bubble(
          {required String id,
          int frequency = 3,
          DateTime? createdAt,
          DateTime? lastShownAt,
          int shownCount = 1}) =>
      Bubble(
          id: id,
          title: id,
          description: 'description',
          createdAt: createdAt ?? now.subtract(const Duration(days: 10)),
          updatedAt: now,
          lastShownAt: lastShownAt,
          shownCount: shownCount,
          appearanceFrequency: frequency);

  test('new unseen bubbles receive the next-day priority', () {
    expect(
        SchedulerService.calculateScore(
            bubble(
                id: 'new',
                createdAt: now.subtract(const Duration(days: 2)),
                shownCount: 0),
            now: now,
            randomValue: 0),
        90);
  });
  test('frequent bubbles score higher than rare bubbles', () {
    expect(
        SchedulerService.calculateScore(bubble(id: 'often', frequency: 5),
            now: now, randomValue: 0),
        greaterThan(SchedulerService.calculateScore(
            bubble(id: 'rare', frequency: 1),
            now: now,
            randomValue: 0)));
  });
  test('weighted selection does not duplicate bubbles', () {
    final selected = SchedulerService.weightedRandomSelect(
        List.generate(
            4,
            (index) =>
                ScoredBubble(bubble(id: '$index'), (index + 1).toDouble())),
        3,
        Random(42));
    expect(selected.map((item) => item.bubble.id).toSet(), hasLength(3));
  });
  test('date key uses a stable local calendar date',
      () => expect(SchedulerService.dateKey(now), '2026-07-27'));
}
