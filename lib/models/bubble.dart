class BubbleShowStats {
  const BubbleShowStats({required this.count, this.lastShownAt});

  final int count;
  final DateTime? lastShownAt;

  Map<String, Object?> toJson() => {
    'count': count,
    'lastShownAt': lastShownAt?.millisecondsSinceEpoch,
  };

  factory BubbleShowStats.fromJson(Map<String, Object?> json) =>
      BubbleShowStats(
        count: (json['count'] as num?)?.toInt() ?? 0,
        lastShownAt: json['lastShownAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['lastShownAt'] as num).toInt(),
              ),
      );
}

class Bubble {
  const Bubble({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.appearanceFrequency = 3,
    this.shownByDevice = const {},
    DateTime? lastShownAt,
    int shownCount = 0,
    this.deletedAt,
    this.fieldVersions = const {},
  }) : _legacyLastShownAt = lastShownAt,
       _legacyShownCount = shownCount,
       assert(appearanceFrequency >= 1 && appearanceFrequency <= 5);

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int appearanceFrequency;
  final Map<String, BubbleShowStats> shownByDevice;
  final DateTime? _legacyLastShownAt;
  final int _legacyShownCount;

  // Kept while reading the legacy database. Document v2 does not persist
  // tombstones or field_versions.
  final DateTime? deletedAt;
  final Map<String, int> fieldVersions;

  int get shownCount => shownByDevice.isEmpty
      ? _legacyShownCount
      : shownByDevice.values.fold(0, (sum, stats) => sum + stats.count);

  DateTime? get lastShownAt {
    if (shownByDevice.isEmpty) return _legacyLastShownAt;
    DateTime? latest;
    for (final stats in shownByDevice.values) {
      final value = stats.lastShownAt;
      if (value != null && (latest == null || value.isAfter(latest))) {
        latest = value;
      }
    }
    return latest;
  }

  bool get isDeleted => deletedAt != null;

  Bubble copyWith({
    String? title,
    String? description,
    DateTime? updatedAt,
    int? appearanceFrequency,
    Map<String, BubbleShowStats>? shownByDevice,
    DateTime? lastShownAt,
    int? shownCount,
    DateTime? deletedAt,
    Map<String, int>? fieldVersions,
  }) => Bubble(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    appearanceFrequency: appearanceFrequency ?? this.appearanceFrequency,
    shownByDevice: shownByDevice ?? this.shownByDevice,
    lastShownAt: lastShownAt ?? this.lastShownAt,
    shownCount: shownCount ?? this.shownCount,
    deletedAt: deletedAt ?? this.deletedAt,
    fieldVersions: fieldVersions ?? this.fieldVersions,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'description': description,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'last_shown_at': lastShownAt?.millisecondsSinceEpoch,
    'shown_count': shownCount,
    'appearance_frequency': appearanceFrequency,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'field_versions': fieldVersions.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(','),
  };

  factory Bubble.fromMap(Map<String, Object?> map) => Bubble(
    id: map['id']! as String,
    title: map['title']! as String,
    description: map['description']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['updated_at'] ?? map['created_at']) as int,
    ),
    lastShownAt: map['last_shown_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['last_shown_at']! as int),
    shownCount: (map['shown_count'] ?? 0) as int,
    appearanceFrequency: ((map['appearance_frequency'] ?? 3) as int)
        .clamp(1, 5)
        .toInt(),
    deletedAt: map['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(map['deleted_at']! as int),
    fieldVersions: _versions(map['field_versions'] as String? ?? ''),
  );

  static Map<String, int> _versions(String value) => Map.unmodifiable({
    for (final item in value.split(',').where((item) => item.contains(':')))
      item.split(':').first: int.tryParse(item.split(':').last) ?? 0,
  });
}

const frequencyLabelsZh = ['很少', '较少', '适中', '较多', '频繁'];
