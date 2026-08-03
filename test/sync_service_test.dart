import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/sync_service.dart';

Map<String, Object?> row(
  String id,
  int updatedAt, {
  String title = 'title',
  int? deletedAt,
}) => {
  'id': id,
  'title': title,
  'description': 'body',
  'created_at': 1,
  'updated_at': updatedAt,
  'last_shown_at': null,
  'shown_count': 0,
  'appearance_frequency': 3,
  'deleted_at': deletedAt,
  'field_versions': '',
};

void main() {
  test('mergeRows keeps the newest version from either device', () {
    final merged = SyncService.mergeRows(
      [row('local-newer', 20), row('remote-newer', 10, title: 'old')],
      [row('local-newer', 10), row('remote-newer', 20, title: 'new')],
    );

    expect(merged, hasLength(2));
    expect(
      merged.singleWhere((item) => item['id'] == 'local-newer')['updated_at'],
      20,
    );
    expect(
      merged.singleWhere((item) => item['id'] == 'remote-newer')['title'],
      'new',
    );
  });

  test('mergeRows preserves a newer deletion tombstone', () {
    final merged = SyncService.mergeRows(
      [row('deleted', 10)],
      [row('deleted', 30, deletedAt: 30)],
    );

    expect(merged.single['deleted_at'], 30);
  });
}
