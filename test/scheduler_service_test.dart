import 'dart:math';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/models/daily_selection.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/daily_selection_cache.dart';
import 'package:mind_bubble/services/device_identity_service.dart';
import 'package:mind_bubble/services/scheduler_service.dart';
import 'package:mind_bubble/services/sync_state_store.dart';

void main() {
  final now = DateTime(2026, 7, 27, 12);
  Bubble bubble({
    required String id,
    int frequency = 3,
    DateTime? createdAt,
    DateTime? lastShownAt,
    int shownCount = 1,
  }) => Bubble(
    id: id,
    title: id,
    description: 'description',
    createdAt: createdAt ?? now.subtract(const Duration(days: 10)),
    updatedAt: now,
    lastShownAt: lastShownAt,
    shownCount: shownCount,
    appearanceFrequency: frequency,
  );

  test('new unseen bubbles receive the next-day priority', () {
    expect(
      SchedulerService.calculateScore(
        bubble(
          id: 'new',
          createdAt: now.subtract(const Duration(days: 2)),
          shownCount: 0,
        ),
        now: now,
        randomValue: 0,
      ),
      90,
    );
  });
  test('frequent bubbles score higher than rare bubbles', () {
    expect(
      SchedulerService.calculateScore(
        bubble(id: 'often', frequency: 5),
        now: now,
        randomValue: 0,
      ),
      greaterThan(
        SchedulerService.calculateScore(
          bubble(id: 'rare', frequency: 1),
          now: now,
          randomValue: 0,
        ),
      ),
    );
  });
  test('weighted selection does not duplicate bubbles', () {
    final selected = SchedulerService.weightedRandomSelect(
      List.generate(
        4,
        (index) => ScoredBubble(bubble(id: '$index'), (index + 1).toDouble()),
      ),
      3,
      Random(42),
    );
    expect(selected.map((item) => item.bubble.id).toSet(), hasLength(3));
  });
  test(
    'date key uses a stable local calendar date',
    () => expect(SchedulerService.dateKey(now), '2026-07-27'),
  );

  test('an empty daily cache is refilled after documents arrive', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'mind-bubble-scheduler-test-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final root = Directory('${temporary.path}/documents')
      ..createSync(recursive: true);
    final support = Directory('${temporary.path}/support')
      ..createSync(recursive: true);
    final cache = DailySelectionCache.forTesting(
      File('${support.path}/daily-selection.json'),
    );
    final repository = BubbleRepository(
      BubbleDocumentStore.forTesting(
        root: root,
        supportRoot: support,
        deviceIdentity: const DeviceIdentity('device-a'),
      ),
      cache,
      const DeviceIdentity('device-a'),
      SyncStateStore.forTesting(File('${support.path}/sync-state.json')),
      () {},
    );
    await cache.write(
      DailySelection(
        date: SchedulerService.dateKey(now),
        bubbleIds: const [],
        generatedAt: now,
      ),
    );
    await repository.save(bubble(id: 'arrived-after-sync'));

    final selected = await SchedulerService(
      repository,
      random: Random(1),
    ).getOrCreateDailyBubbles(now: now);

    expect(selected.map((item) => item.id), ['arrived-after-sync']);
  });
}
