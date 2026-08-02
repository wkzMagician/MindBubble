import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bubble.dart';
import '../models/daily_selection.dart';
import '../repositories/bubble_repository.dart';

final schedulerProvider = Provider<SchedulerService>(
  (ref) => SchedulerService(ref.watch(bubbleRepositoryProvider)),
);

class SchedulerService {
  SchedulerService(this._repository, {Random? random})
      : _random = random ?? Random();

  final BubbleRepository _repository;
  final Random _random;

  Future<List<Bubble>> getOrCreateDailyBubbles({
    DateTime? now,
    int count = 5,
  }) async {
    final timestamp = now ?? DateTime.now();
    final date = dateKey(timestamp);
    final cached = await _repository.getDailySelection(date);
    if (cached != null) return _loadSelection(cached);

    final bubbles = await _repository.getAll();
    final selected =
        generateDailyBubbles(bubbles, now: timestamp, count: count);
    final selection = DailySelection(
      date: date,
      bubbleIds: selected.map((bubble) => bubble.id).toList(),
      generatedAt: timestamp,
    );
    await _repository.saveDailySelection(selection);
    await _repository.recordShown(selection.bubbleIds, timestamp);
    return selected;
  }

  Future<List<Bubble>> _loadSelection(DailySelection selection) async {
    final bubbles = <Bubble>[];
    for (final id in selection.bubbleIds) {
      final bubble = await _repository.getById(id);
      if (bubble != null && !bubble.isDeleted) bubbles.add(bubble);
    }
    return bubbles;
  }

  List<Bubble> generateDailyBubbles(
    List<Bubble> bubbles, {
    required DateTime now,
    int count = 5,
  }) {
    final scored = bubbles
        .where((bubble) => !bubble.isDeleted)
        .map((bubble) => ScoredBubble(
              bubble,
              calculateScore(bubble,
                  now: now, randomValue: _random.nextDouble()),
            ))
        .toList();
    return weightedRandomSelect(scored, count, _random)
        .map((item) => item.bubble)
        .toList();
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static double calculateScore(
    Bubble bubble, {
    required DateTime now,
    required double randomValue,
  }) {
    const day = Duration(days: 1);
    final ageDays =
        now.difference(bubble.createdAt).inMilliseconds / day.inMilliseconds;
    final daysSinceShown = (bubble.lastShownAt == null
                ? now.difference(bubble.createdAt)
                : now.difference(bubble.lastShownAt!))
            .inMilliseconds /
        day.inMilliseconds;
    final newBubbleScore = ageDays >= 1 && bubble.shownCount == 0 ? 100 : 0;
    final overdueScore = min(daysSinceShown * 5, 50);
    const frequencyScores = [-30, -15, 0, 15, 30];
    final frequencyScore = frequencyScores[bubble.appearanceFrequency - 1];
    final recentPenalty = daysSinceShown < 1
        ? 50
        : daysSinceShown < 3
            ? 20
            : 0;
    return newBubbleScore +
        overdueScore +
        frequencyScore +
        randomValue * 20 -
        recentPenalty;
  }

  static List<ScoredBubble> weightedRandomSelect(
    List<ScoredBubble> candidates,
    int count,
    Random random,
  ) {
    final pool = List<ScoredBubble>.of(candidates);
    final selected = <ScoredBubble>[];
    while (pool.isNotEmpty && selected.length < count) {
      final lowest = pool.map((item) => item.score).reduce(min);
      final weights = pool.map((item) => item.score - lowest + 1).toList();
      final total = weights.reduce((sum, weight) => sum + weight);
      var threshold = random.nextDouble() * total;
      var index = 0;
      for (; index < weights.length - 1; index++) {
        threshold -= weights[index];
        if (threshold <= 0) break;
      }
      selected.add(pool.removeAt(index));
    }
    return selected;
  }
}

class ScoredBubble {
  const ScoredBubble(this.bubble, this.score);
  final Bubble bubble;
  final double score;
}
