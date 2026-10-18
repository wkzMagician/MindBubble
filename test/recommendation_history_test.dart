import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/features/recommendations/recommendation_event_store.dart';
import 'package:mind_bubble/features/recommendations/recommendation_metrics.dart';
import 'package:mind_bubble/models/bubble.dart';

void main() {
  test(
    'history tolerates a truncated record and deduplicates delivery replays after restart',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'mindbubble-history-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/events.jsonl');
      final now = DateTime(2026, 10, 17);
      final event = RecommendationEvent(
        id: 'one',
        noteId: 'a',
        timestamp: now,
        type: RecommendationEventType.shown,
        channel: RecommendationChannel.home,
      );
      final first = RecommendationEventStore(file);
      expect(await first.append(event), true);
      await file.writeAsString('{"incomplete":', mode: FileMode.append);
      final second = RecommendationEventStore(file);
      expect(await second.read(), hasLength(1));
      expect(await second.append(event), false);
      expect(
        await second.append(
          RecommendationEvent(
            id: 'two',
            noteId: 'a',
            timestamp: now.add(const Duration(hours: 2)),
            type: RecommendationEventType.shown,
            channel: RecommendationChannel.notification,
          ),
        ),
        true,
      );
      expect(await RecommendationEventStore(file).read(), hasLength(2));
      final metric = RecommendationMetrics([
        Bubble(
          id: 'a',
          title: '',
          description: '',
          createdAt: now,
          updatedAt: now,
        ),
      ], await second.read());
      expect(metric.coverage, 1);
      expect(metric.exposures['a'], 2);
      expect(metric.intervalsHours, [2]);
    },
  );
}
