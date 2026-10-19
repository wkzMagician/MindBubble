import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecommendationConfig {
  RecommendationConfig({
    this.temperature = .4,
    this.explorationRate = .15,
    this.diversityWeight = .4,
    this.feedbackStep = .15,
    this.generalizationWeight = .2,
    this.notificationCount = 1,
    this.bubbleCount = 5,
  }) {
    _range(temperature, .01, 10, 'temperature');
    _range(explorationRate, 0, 1, 'exploration_rate');
    _range(diversityWeight, 0, 10, 'diversity_weight');
    _range(feedbackStep, 0, .6, 'feedback_step');
    _range(generalizationWeight, 0, 1, 'generalization_weight');
    if (notificationCount < 1 || notificationCount > 10) {
      throw RangeError.range(notificationCount, 1, 10, 'notification_count');
    }
    if (bubbleCount < 5 || bubbleCount > 10) {
      throw RangeError.range(bubbleCount, 5, 10, 'bubble_count');
    }
  }

  final double temperature;
  final double explorationRate;
  final double diversityWeight;
  final double feedbackStep;
  final double generalizationWeight;
  final int notificationCount;
  final int bubbleCount;
  static const storageKey = 'recommendation.v1';

  static void _range(double value, double min, double max, String name) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(value, name, 'Expected $min–$max');
    }
  }

  Map<String, Object?> toJson() => {
    'temperature': temperature,
    'exploration_rate': explorationRate,
    'diversity_weight': diversityWeight,
    'feedback_step': feedbackStep,
    'generalization_weight': generalizationWeight,
    'notification_count': notificationCount,
    'bubble_count': bubbleCount,
  };

  factory RecommendationConfig.fromJson(Map<String, Object?> json) =>
      RecommendationConfig(
        temperature: (json['temperature'] as num?)?.toDouble() ?? .4,
        explorationRate: (json['exploration_rate'] as num?)?.toDouble() ?? .15,
        diversityWeight: (json['diversity_weight'] as num?)?.toDouble() ?? .4,
        feedbackStep: (json['feedback_step'] as num?)?.toDouble() ?? .15,
        generalizationWeight:
            (json['generalization_weight'] as num?)?.toDouble() ?? .2,
        notificationCount: (json['notification_count'] as num?)?.toInt() ?? 1,
        bubbleCount: (json['bubble_count'] as num?)?.toInt() ?? 5,
      );

  static Future<RecommendationConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    final legacyCount = (prefs.getInt('home.bubbleCount') ?? 5).clamp(5, 10);
    if (raw == null) return RecommendationConfig(bubbleCount: legacyCount);
    try {
      return RecommendationConfig.fromJson({
        'bubble_count': legacyCount,
        ...(jsonDecode(raw) as Map).cast<String, Object?>(),
      });
    } on Object {
      return RecommendationConfig();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(toJson()));
  }

  RecommendationConfig copyWith({int? bubbleCount}) => RecommendationConfig(
    temperature: temperature,
    explorationRate: explorationRate,
    diversityWeight: diversityWeight,
    feedbackStep: feedbackStep,
    generalizationWeight: generalizationWeight,
    notificationCount: notificationCount,
    bubbleCount: bubbleCount ?? this.bubbleCount,
  );
}

final recommendationConfigProvider =
    StateNotifierProvider<RecommendationConfigController, RecommendationConfig>(
      (_) => RecommendationConfigController()..load(),
    );

class RecommendationConfigController
    extends StateNotifier<RecommendationConfig> {
  RecommendationConfigController({RecommendationConfig? initial})
    : super(initial ?? RecommendationConfig());
  int _revision = 0;

  Future<void> load() async {
    final revision = _revision;
    final config = await RecommendationConfig.load();
    if (mounted && revision == _revision) state = config;
  }

  Future<void> update(RecommendationConfig config) async {
    _revision++;
    await config.save();
    if (mounted) state = config;
  }
}
