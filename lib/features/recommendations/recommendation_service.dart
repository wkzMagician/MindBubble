import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../repositories/bubble_repository.dart';
import 'note_profile.dart';
import 'recommendation_config.dart';
import 'recommendation_engine.dart';

final recommendationServiceProvider = Provider<RecommendationService>(
  (ref) => RecommendationService(
    ref.watch(bubbleRepositoryProvider),
    config: () => ref.read(recommendationConfigProvider),
  ),
);

class RecommendationService {
  RecommendationService(
    this.repository, {
    RecommendationConfig Function()? config,
    RecommendationEngine? engine,
  }) : _config = config ?? RecommendationConfig.new,
       engine = engine ?? RecommendationEngine();
  final BubbleRepository repository;
  final RecommendationConfig Function() _config;
  final RecommendationEngine engine;
  RecommendationConfig get config => _config();

  Future<List<Bubble>> recommend(
    int count, {
    DateTime? now,
    RecommendationChannel channel = RecommendationChannel.home,
    bool recordExposure = false,
  }) async {
    final at = now ?? DateTime.now();
    final result = engine.recommend(
      await repository.getAll(),
      count: count,
      now: at,
      config: config,
      events: await repository.events.read(),
    );
    if (recordExposure) {
      await repository.recordShown(
        result.map((n) => n.id).toList(),
        at,
        channel: channel,
      );
    }
    return result;
  }

  Future<void> feedback(
    String id,
    FrequencyFeedback value,
    RecommendationChannel channel,
  ) => repository.feedback(
    id,
    value,
    channel: channel,
    step: config.feedbackStep,
  );
}
