import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/daily_selection_cache.dart';
import 'package:mind_bubble/services/device_identity_service.dart';
import 'package:mind_bubble/services/scheduler_service.dart';

void main() {
  test(
    'legacy scheduler uses adaptive sampling and ignores obsolete daily cache',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'mindbubble-scheduler-',
      );
      addTearDown(() => folder.delete(recursive: true));
      const identity = DeviceIdentity('test');
      final repository = BubbleRepository(
        BubbleDocumentStore.forTesting(
          root: Directory('${folder.path}/notes')..createSync(),
          supportRoot: Directory('${folder.path}/support')..createSync(),
          deviceIdentity: identity,
        ),
        DailySelectionCache.forTesting(File('${folder.path}/daily.json')),
        identity,
        () {},
      );
      final now = DateTime(2026, 10, 17);
      for (var i = 0; i < 9; i++) {
        await repository.save(
          Bubble(
            id: '$i',
            title: '$i',
            description: 'body',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      final scheduler = SchedulerService(repository, random: Random(1));
      final result = await scheduler.getOrCreateDailyBubbles(
        now: now,
        count: 6,
      );
      expect(result, hasLength(6));
      expect(result.map((n) => n.id).toSet(), hasLength(6));
      // Selecting alone is not exposure; only presentation records it.
      expect(await repository.events.read(), isEmpty);
      expect(SchedulerService.dateKey(now), '2026-10-17');
      expect(await repository.getDailySelection('2026-10-17'), isNull);
    },
  );
}
