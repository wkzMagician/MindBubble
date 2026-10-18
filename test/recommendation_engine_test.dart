import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/recommendations/note_profile.dart';
import 'package:mind_bubble/features/recommendations/recommendation_config.dart';
import 'package:mind_bubble/features/recommendations/recommendation_engine.dart';
import 'package:mind_bubble/models/bubble.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17);
  Bubble note(
    String id, {
    double cue = .5,
    double preference = 0,
    List<double> embedding = const [],
    int exposures = 0,
    DateTime? lastShown,
    bool enabled = true,
  }) => Bubble(
    id: id,
    title: id,
    description: 'body',
    createdAt: now,
    updatedAt: now,
    preference: preference,
    recommendationEnabled: enabled,
    shownCount: exposures,
    lastShownAt: lastShown,
    profile: NoteProfile(
      cueValue: cue,
      embedding: embedding,
      embeddingModel: 'test',
    ),
  );
  final engine = RecommendationEngine(random: Random(42));

  test('average percentile ranks recompute across enabled candidates', () {
    final notes = [
      note('a', cue: .1),
      note('b', cue: .1),
      note('c', cue: .9),
      note('disabled', cue: 0, enabled: false),
    ];
    final scores = engine.probabilities(
      notes,
      now: now,
      config: RecommendationConfig(),
    );
    expect(scores.map((s) => s.relativeValue), [1 / 3, 1 / 3, 5 / 6]);
    final changed = engine.probabilities(
      notes.take(2).toList(),
      now: now,
      config: RecommendationConfig(),
    );
    expect(changed.map((s) => s.relativeValue), [.5, .5]);
    expect(
      scores.fold<double>(0, (sum, s) => sum + s.probability),
      closeTo(1, 1e-12),
    );
  });
  test('mixture matches hand-computed exploitation and exploration', () {
    final scores = engine.probabilities(
      [note('a', cue: 0), note('b', cue: 1)],
      now: now,
      config: RecommendationConfig(),
    );
    final high = exp(.75 / .4) / (exp(.25 / .4) + exp(.75 / .4));
    expect(scores.last.probability, closeTo(.85 * high + .15 / 2, 1e-12));
  });
  test('14-day real exposures determine tau, future and old events do not', () {
    final notes = [
      note('a', lastShown: now.subtract(const Duration(days: 1))),
      note('b'),
    ];
    final events = List.generate(
      56,
      (i) => RecommendationEvent(
        id: '$i',
        noteId: 'a',
        timestamp: now.subtract(const Duration(hours: 12)),
        type: RecommendationEventType.shown,
        channel: RecommendationChannel.home,
      ),
    );
    events.add(
      RecommendationEvent(
        id: 'future',
        noteId: 'b',
        timestamp: now.add(const Duration(days: 1)),
        type: RecommendationEventType.shown,
        channel: RecommendationChannel.notification,
      ),
    );
    events.add(
      RecommendationEvent(
        id: 'old',
        noteId: 'b',
        timestamp: now.subtract(const Duration(days: 20)),
        type: RecommendationEventType.shown,
        channel: RecommendationChannel.home,
      ),
    );
    final s = engine.probabilities(
      notes,
      now: now,
      config: RecommendationConfig(),
      events: events,
    );
    expect(s.first.recovery, closeTo(.05 + .95 * (1 - exp(-2)), 1e-12));
    expect(s.last.recovery, 1);
    final fresh = engine.probabilities(
      [note('a', lastShown: now)],
      now: now,
      config: RecommendationConfig(),
    );
    expect(fresh.single.recovery, closeTo(.05, 1e-12));
  });
  test('diversity penalizes both exploitation and pure exploration', () {
    final selected = note('selected', embedding: [1, 0]);
    final notes = [
      selected,
      note('similar', embedding: [1, 0]),
      note('different', embedding: [0, 1]),
    ];
    for (final epsilon in [0.0, 1.0]) {
      final scores = engine.probabilities(
        notes,
        now: now,
        config: RecommendationConfig(explorationRate: epsilon),
        selected: [selected],
      );
      expect(scores.first.probability, closeTo(exp(-1) / (1 + exp(-1)), 1e-12));
      expect(scores.last.probability, greaterThan(scores.first.probability));
    }
  });
  test(
    'direct preference dominates smoothed generalization and excludes self',
    () {
      final notes = [
        note('target', embedding: [1, 0]),
        note('peer', preference: .6, embedding: [1, 0]),
        note('unrelated', embedding: [0, 1]),
      ];
      final scores = engine.probabilities(
        notes,
        now: now,
        config: RecommendationConfig(),
      );
      expect(scores.first.generalization, closeTo(.2 * .3 * .6 / 3.3, 1e-12));
      expect(scores[1].generalization, 0);
      expect(scores[1].probability, greaterThan(scores.first.probability));
    },
  );
  test(
    'pure exploration favors lower exposure with no invalid probabilities',
    () {
      final scores = engine.probabilities(
        [note('new'), note('old', exposures: 8)],
        now: now,
        config: RecommendationConfig(explorationRate: 1, temperature: .01),
      );
      expect(scores.first.probability, closeTo(.75, 1e-12));
      expect(
        RecommendationEngine.similarity(
          note('zero', embedding: [0, 0]),
          note('a', embedding: [1, 0]),
        ),
        0,
      );
      expect(
        RecommendationEngine.similarity(
          note('bad', embedding: [double.nan]),
          note('a', embedding: [1]),
        ),
        0,
      );
      expect(() => RecommendationConfig(temperature: 0), throwsArgumentError);
      expect(
        () => RecommendationConfig(explorationRate: double.nan),
        throwsArgumentError,
      );
    },
  );
  test('zero, oversized and duplicate candidate lists are safe', () {
    final notes = [
      note('a'),
      note('a'),
      note('b'),
      note('off', enabled: false),
    ];
    expect(
      engine
          .recommend(notes, count: 10, now: now, config: RecommendationConfig())
          .map((n) => n.id)
          .toSet(),
      {'a', 'b'},
    );
    expect(
      engine.recommend(
        notes,
        count: 0,
        now: now,
        config: RecommendationConfig(),
      ),
      isEmpty,
    );
    expect(
      engine.recommend([], count: 5, now: now, config: RecommendationConfig()),
      isEmpty,
    );
  });
}
