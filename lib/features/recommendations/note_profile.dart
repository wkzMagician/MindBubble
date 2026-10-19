double boundedNumber(Object? value, double fallback, double min, double max) {
  final number = value is num ? value.toDouble() : fallback;
  return number.isFinite ? number.clamp(min, max) : fallback;
}

class NoteProfile {
  const NoteProfile({
    this.cueValue = .5,
    this.detailNeed = .5,
    this.embedding = const [],
    this.embeddingModel = '',
    this.cueText = '',
    this.summary = '',
    this.analysisStatus = 'pending',
  });

  final double cueValue;
  final double detailNeed;
  final List<double> embedding;
  final String embeddingModel;
  final String cueText;
  final String summary;
  final String analysisStatus;

  NoteProfile copyWith({
    double? cueValue,
    double? detailNeed,
    List<double>? embedding,
    String? embeddingModel,
    String? cueText,
    String? summary,
    String? analysisStatus,
  }) => NoteProfile(
    cueValue: cueValue ?? this.cueValue,
    detailNeed: detailNeed ?? this.detailNeed,
    embedding: embedding ?? this.embedding,
    embeddingModel: embeddingModel ?? this.embeddingModel,
    cueText: cueText ?? this.cueText,
    summary: summary ?? this.summary,
    analysisStatus: analysisStatus ?? this.analysisStatus,
  );

  Map<String, Object?> toJson() => {
    'cue_value': cueValue,
    'detail_need': detailNeed,
    'embedding': embedding,
    'embedding_model': embeddingModel,
    'cue_text': cueText,
    'summary': summary,
    'analysis_status': analysisStatus,
  };

  factory NoteProfile.fromJson(Map<String, Object?> json) {
    final raw = json['embedding'];
    final vector = raw is List && raw.every((n) => n is num && n.isFinite)
        ? raw.cast<num>().map((n) => n.toDouble()).toList()
        : <double>[];
    return NoteProfile(
      cueValue: boundedNumber(json['cue_value'], .5, 0, 1),
      detailNeed: boundedNumber(json['detail_need'], .5, 0, 1),
      embedding: List.unmodifiable(vector),
      embeddingModel: json['embedding_model'] as String? ?? '',
      cueText: json['cue_text'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      analysisStatus: json['analysis_status'] as String? ?? 'pending',
    );
  }
}

enum RecommendationChannel { home, notification, search, library }

class RecommendationState {
  const RecommendationState({
    required this.noteId,
    this.preference = 0,
    this.lastShown,
    this.exposureCount = 0,
    this.enabled = true,
  });
  final String noteId;
  final double preference;
  final DateTime? lastShown;
  final int exposureCount;
  final bool enabled;
  Map<String, Object?> toJson() => {
    'note_id': noteId,
    'preference': preference,
    'last_shown': lastShown?.millisecondsSinceEpoch,
    'exposure_count': exposureCount,
    'enabled': enabled ? 1 : 0,
  };
}

enum RecommendationEventType { shown, opened, read, searched, feedback }

enum FrequencyFeedback { more, suitable, less, stop }

class RecommendationEvent {
  const RecommendationEvent({
    required this.id,
    required this.noteId,
    required this.timestamp,
    required this.type,
    required this.channel,
    this.feedback,
    this.durationSeconds = 0,
  });

  final String id;
  final String noteId;
  final DateTime timestamp;
  final RecommendationEventType type;
  final RecommendationChannel channel;
  final FrequencyFeedback? feedback;
  final double durationSeconds;

  Map<String, Object?> toJson() => {
    'id': id,
    'note_id': noteId,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'event_type': type.index,
    'channel': channel.index,
    'feedback_value': feedback?.index,
    'duration': durationSeconds,
  };

  factory RecommendationEvent.fromJson(
    Map<String, Object?> json,
  ) => RecommendationEvent(
    id: json['id']! as String,
    noteId: json['note_id']! as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (json['timestamp']! as num).toInt(),
    ),
    type: RecommendationEventType.values[(json['event_type']! as num).toInt()],
    channel: RecommendationChannel.values[(json['channel']! as num).toInt()],
    feedback: json['feedback_value'] == null
        ? null
        : FrequencyFeedback.values[(json['feedback_value']! as num).toInt()],
    durationSeconds: boundedNumber(json['duration'], 0, 0, 86400),
  );
}
