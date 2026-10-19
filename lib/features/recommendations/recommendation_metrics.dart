import '../../models/bubble.dart';
import 'note_profile.dart';
import 'recommendation_engine.dart';

class RecommendationMetrics {
  RecommendationMetrics(List<Bubble> notes, List<RecommendationEvent> events) {
    titles.addAll({for (final note in notes) note.id: note.cueTitle});
    final active = notes
        .where((n) => !n.isDeleted && n.recommendationEnabled)
        .map((n) => n.id)
        .toSet();
    final sorted = [...events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final latest = <String, DateTime>{};
    final batches = <String, List<Bubble>>{};
    final byId = {for (final note in notes) note.id: note};
    for (final event in sorted) {
      if (event.type == RecommendationEventType.shown) {
        exposures.update(event.noteId, (n) => n + 1, ifAbsent: () => 1);
        final previous = latest[event.noteId];
        if (previous != null) {
          intervalsHours.add(
            event.timestamp.difference(previous).inSeconds / 3600,
          );
        }
        latest[event.noteId] = event.timestamp;
        final note = byId[event.noteId];
        if (note != null) {
          final key =
              '${event.channel.name}:${event.timestamp.millisecondsSinceEpoch}';
          batches.putIfAbsent(key, () => []).add(note);
        }
      }
      if (event.type == RecommendationEventType.feedback &&
          event.feedback != null) {
        feedback.update(event.feedback!.name, (n) => n + 1, ifAbsent: () => 1);
        if (event.channel == RecommendationChannel.notification) {
          notificationFeedback.update(
            event.feedback!.name,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      }
      if (event.type == RecommendationEventType.opened) opens++;
      if (event.type == RecommendationEventType.read) {
        readingSeconds += event.durationSeconds;
      }
      if (event.type == RecommendationEventType.searched) searches++;
    }
    coverage = active.isEmpty
        ? 0
        : active.where(exposures.containsKey).length / active.length;
    var sum = 0.0, pairs = 0;
    for (final batch in batches.values) {
      for (var i = 0; i < batch.length; i++) {
        for (var j = i + 1; j < batch.length; j++) {
          final a = batch[i].effectiveProfile, b = batch[j].effectiveProfile;
          if (a.embedding.isEmpty ||
              a.embedding.length != b.embedding.length ||
              a.embeddingModel != b.embeddingModel) {
            continue;
          }
          sum += RecommendationEngine.similarity(batch[i], batch[j]);
          pairs++;
        }
      }
    }
    meanSimilarity = pairs == 0 ? null : sum / pairs;
  }

  final Map<String, int> exposures = {};
  final Map<String, String> titles = {};
  final Map<String, int> feedback = {};
  final Map<String, int> notificationFeedback = {};
  final List<double> intervalsHours = [];
  double coverage = 0, readingSeconds = 0;
  double? meanSimilarity;
  int opens = 0, searches = 0;

  Map<String, Object?> toJson() => {
    'positive_feedback_rate': feedback.isEmpty
        ? 0
        : (feedback['more'] ?? 0) /
              feedback.values.fold<int>(0, (a, b) => a + b),
    'negative_feedback_rate': feedback.isEmpty
        ? 0
        : ((feedback['less'] ?? 0) + (feedback['stop'] ?? 0)) /
              feedback.values.fold<int>(0, (a, b) => a + b),
    'coverage': coverage,
    'feedback': feedback,
    'notification_feedback': notificationFeedback,
    'exposure_distribution': exposures,
    'repeat_intervals_hours': intervalsHours,
    'mean_semantic_similarity': meanSimilarity,
    'body_opens': opens,
    'reading_seconds': readingSeconds,
    'search_visits': searches,
  };
}
