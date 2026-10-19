import 'dart:math';

import '../../models/bubble.dart';
import 'note_profile.dart';
import 'recommendation_config.dart';

class RecommendationScore {
  const RecommendationScore({
    required this.bubble,
    required this.relativeValue,
    required this.generalization,
    required this.recovery,
    required this.similarity,
    required this.probability,
  });
  final Bubble bubble;
  final double relativeValue, generalization, recovery, similarity, probability;
}

class _Candidate {
  const _Candidate(this.note, this.rank, this.generalization, this.recovery);
  final Bubble note;
  final double rank, generalization, recovery;
}

/// Shared pure numerical implementation for every presentation channel.
class RecommendationEngine {
  RecommendationEngine({Random? random}) : _random = random ?? Random();
  final Random _random;

  List<Bubble> recommend(
    List<Bubble> notes, {
    required int count,
    required DateTime now,
    required RecommendationConfig config,
    List<RecommendationEvent> events = const [],
  }) {
    if (count <= 0) return [];
    // Ranking, recovery and feedback propagation stay fixed during a batch.
    final prepared = _prepare(notes, now, config, events);
    final selected = <Bubble>[];
    while (selected.length < count) {
      final scores = _probabilities(prepared, config, selected);
      if (scores.isEmpty) break;
      var roll = _random.nextDouble();
      var chosen = scores.last.bubble;
      for (final score in scores) {
        roll -= score.probability;
        if (roll < 0) {
          chosen = score.bubble;
          break;
        }
      }
      selected.add(chosen);
    }
    return selected;
  }

  List<RecommendationScore> probabilities(
    List<Bubble> notes, {
    required DateTime now,
    required RecommendationConfig config,
    List<RecommendationEvent> events = const [],
    List<Bubble> selected = const [],
  }) => _probabilities(_prepare(notes, now, config, events), config, selected);

  List<_Candidate> _prepare(
    List<Bubble> notes,
    DateTime now,
    RecommendationConfig config,
    List<RecommendationEvent> events,
  ) {
    final unique = {for (final note in notes) note.id: note};
    final candidates =
        unique.values
            .where((n) => !n.isDeleted && n.recommendationEnabled)
            .toList()
          ..sort((a, b) => _cue(a).compareTo(_cue(b)));
    if (candidates.isEmpty) return [];
    final ranks = <String, double>{};
    for (var start = 0; start < candidates.length;) {
      var end = start + 1;
      while (end < candidates.length &&
          _cue(candidates[end]) == _cue(candidates[start])) {
        end++;
      }
      final rank = (start + end) / (2 * candidates.length);
      for (var i = start; i < end; i++) {
        ranks[candidates[i].id] = rank;
      }
      start = end;
    }
    final boundary = now.subtract(const Duration(days: 14));
    final shown = events
        .where(
          (e) =>
              e.type == RecommendationEventType.shown &&
              e.timestamp.isAfter(boundary) &&
              !e.timestamp.isAfter(now),
        )
        .length;
    final tau = candidates.length / max(shown / 14, 1);
    final feedback = candidates.where((n) => _preference(n) != 0).toList();
    return [
      for (final note in candidates)
        _Candidate(
          note,
          ranks[note.id]!,
          _generalization(
            note,
            candidates,
            feedback,
            config.generalizationWeight,
          ),
          _recovery(note, now, tau),
        ),
    ];
  }

  static double _recovery(Bubble note, DateTime now, double tau) {
    if (note.lastShownAt == null) return 1;
    final days = max(
      0.0,
      now.difference(note.lastShownAt!).inMicroseconds /
          Duration.microsecondsPerDay,
    );
    return .05 + .95 * (1 - exp(-days / tau));
  }

  static double _cue(Bubble note) =>
      boundedNumber(note.effectiveProfile.cueValue, .5, 0, 1);
  static double _preference(Bubble note) =>
      boundedNumber(note.preference, 0, -.6, .6);

  static double _generalization(
    Bubble note,
    List<Bubble> all,
    List<Bubble> feedback,
    double weight,
  ) {
    if (feedback.isEmpty || weight == 0) return 0;
    final similarities = <String, double>{};
    var numerator = 0.0;
    for (final peer in feedback) {
      if (peer.id == note.id) continue;
      final a = max(0.0, similarity(note, peer) - .7);
      similarities[peer.id] = a;
      numerator += a * _preference(peer);
    }
    // With sparse feedback most notes have zero numerator; their exact G is 0.
    if (numerator == 0) return 0;
    var denominator = 3.0;
    for (final peer in all) {
      if (peer.id == note.id) continue;
      denominator +=
          similarities[peer.id] ?? max(0.0, similarity(note, peer) - .7);
    }
    return weight * numerator / denominator;
  }

  List<RecommendationScore> _probabilities(
    List<_Candidate> candidates,
    RecommendationConfig config,
    List<Bubble> selected,
  ) {
    final excluded = selected.map((n) => n.id).toSet();
    final pool = candidates
        .where((n) => !excluded.contains(n.note.id))
        .toList();
    if (pool.isEmpty) return [];
    final semantic = <double>[];
    final logWeights = <double>[];
    final logExploration = <double>[];
    for (final item in pool) {
      final note = item.note;
      final m = selected.fold<double>(
        0,
        (value, peer) => max(value, max(0, similarity(note, peer))),
      );
      semantic.add(m);
      final penalty = config.diversityWeight * m / config.temperature;
      logWeights.add(
        log(item.recovery) +
            (item.rank + _preference(note) + item.generalization) /
                config.temperature -
            penalty,
      );
      logExploration.add(
        log(item.recovery) - penalty - .5 * log(1 + max(0, note.shownCount)),
      );
    }
    final exploitation = _softmax(logWeights),
        exploration = _softmax(logExploration);
    return [
      for (var i = 0; i < pool.length; i++)
        RecommendationScore(
          bubble: pool[i].note,
          relativeValue: pool[i].rank,
          generalization: pool[i].generalization,
          recovery: pool[i].recovery,
          similarity: semantic[i],
          probability:
              (1 - config.explorationRate) * exploitation[i] +
              config.explorationRate * exploration[i],
        ),
    ];
  }

  static List<double> _softmax(List<double> logits) {
    final shift = logits.reduce(max);
    final weights = logits.map((w) => exp(w - shift)).toList();
    final sum = weights.fold<double>(0, (a, b) => a + b);
    return weights.map((w) => w / sum).toList();
  }

  static double similarity(Bubble a, Bubble b) {
    final pa = a.effectiveProfile, pb = b.effectiveProfile;
    final x = pa.embedding, y = pb.embedding;
    if (x.isEmpty ||
        x.length != y.length ||
        pa.embeddingModel != pb.embeddingModel) {
      return 0;
    }
    var dot = 0.0, xx = 0.0, yy = 0.0;
    for (var i = 0; i < x.length; i++) {
      if (!x[i].isFinite || !y[i].isFinite) return 0;
      dot += x[i] * y[i];
      xx += x[i] * x[i];
      yy += y[i] * y[i];
    }
    final norm = sqrt(xx) * sqrt(yy);
    if (!norm.isFinite || norm == 0) return 0;
    return (dot / norm).clamp(-1, 1);
  }
}
