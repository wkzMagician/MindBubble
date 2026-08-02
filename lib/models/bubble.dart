class Bubble {
  const Bubble({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.lastShownAt,
    this.shownCount = 0,
    this.appearanceFrequency = 3,
    this.deletedAt,
    this.fieldVersions = const {},
  }) : assert(appearanceFrequency >= 1 && appearanceFrequency <= 5);

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastShownAt;
  final int shownCount;
  final int appearanceFrequency;
  final DateTime? deletedAt;
  final Map<String, int> fieldVersions;

  bool get isDeleted => deletedAt != null;

  Bubble copyWith({
    String? title,
    String? description,
    DateTime? updatedAt,
    DateTime? lastShownAt,
    int? shownCount,
    int? appearanceFrequency,
    DateTime? deletedAt,
    Map<String, int>? fieldVersions,
  }) =>
      Bubble(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastShownAt: lastShownAt ?? this.lastShownAt,
        shownCount: shownCount ?? this.shownCount,
        appearanceFrequency: appearanceFrequency ?? this.appearanceFrequency,
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
        'field_versions':
            fieldVersions.entries.map((e) => '${e.key}:${e.value}').join(','),
      };

  factory Bubble.fromMap(Map<String, Object?> map) => Bubble(
        id: map['id']! as String,
        title: map['title']! as String,
        description: map['description']! as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['updated_at'] ?? map['created_at']) as int),
        lastShownAt: map['last_shown_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['last_shown_at']! as int),
        shownCount: (map['shown_count'] ?? 0) as int,
        appearanceFrequency:
            ((map['appearance_frequency'] ?? 3) as int).clamp(1, 5).toInt(),
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
