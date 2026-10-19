import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/recommendations/recommendation_config.dart';
import '../features/recommendations/recommendation_engine.dart';
import '../features/recommendations/recommendation_service.dart';
import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';

final bubbleRefreshServiceProvider = Provider<BubbleRefreshService>(
  (ref) => BubbleRefreshService(
    ref.watch(bubbleRepositoryProvider),
    recommendations: ref.watch(recommendationServiceProvider),
  ),
);

class BubbleRefreshService {
  BubbleRefreshService(
    this._repository, {
    BubbleRefreshSelector? selector,
    RecommendationService? recommendations,
  }) : _selector = selector ?? BubbleRefreshSelector(),
       _recommendations = recommendations;
  final BubbleRepository _repository;
  final BubbleRefreshSelector _selector;
  final RecommendationService? _recommendations;

  Future<List<Bubble>> refresh({int count = 5}) async {
    if (_recommendations != null) return _recommendations.recommend(count);
    return _selector.draw(await _repository.getAll(), count: count);
  }
}

/// Compatibility facade for callers that only need pure numerical sampling.
class BubbleRefreshSelector {
  BubbleRefreshSelector({Random? random})
    : _engine = RecommendationEngine(random: random);
  final RecommendationEngine _engine;
  List<Bubble> draw(List<Bubble> bubbles, {int count = 5}) => _engine.recommend(
    bubbles,
    count: count,
    now: DateTime.now(),
    config: RecommendationConfig(),
  );
}
