import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/recommendations/recommendation_config.dart';
import '../features/recommendations/recommendation_engine.dart';
import '../features/recommendations/recommendation_service.dart';
import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';

final schedulerProvider = Provider<SchedulerService>(
  (ref) => SchedulerService(
    ref.watch(bubbleRepositoryProvider),
    recommendations: ref.watch(recommendationServiceProvider),
  ),
);

/// Legacy entry point, now using the shared adaptive engine without a daily cache.
class SchedulerService {
  SchedulerService(
    this._repository, {
    Random? random,
    RecommendationService? recommendations,
  }) : _engine = RecommendationEngine(random: random),
       _recommendations = recommendations;
  final BubbleRepository _repository;
  final RecommendationEngine _engine;
  final RecommendationService? _recommendations;

  Future<List<Bubble>> getOrCreateDailyBubbles({
    DateTime? now,
    int count = 5,
  }) async =>
      (_recommendations ?? RecommendationService(_repository, engine: _engine))
          .recommend(count, now: now);

  List<Bubble> generateDailyBubbles(
    List<Bubble> bubbles, {
    required DateTime now,
    int count = 5,
  }) => _engine.recommend(
    bubbles,
    count: count,
    now: now,
    config: RecommendationConfig(),
  );

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
