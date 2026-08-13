import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';

void main() {
  test('round trips five-level frequency and sync timestamps', () {
    final bubble = Bubble(
      id: '1',
      title: 'Title',
      description: 'Body',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 1, 2),
      appearanceFrequency: 5,
    );
    final restored = Bubble.fromMap(bubble.toMap());
    expect(restored.appearanceFrequency, 5);
    expect(restored.updatedAt, DateTime(2026, 1, 2));
    expect(restored.isDeleted, isFalse);
  });
}
