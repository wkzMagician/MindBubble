import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_refresh_service.dart';

void main() {
  final now = DateTime(2026, 10, 17);
  Bubble note(int id) => Bubble(
    id: '$id',
    title: '$id',
    description: '',
    createdAt: now,
    updatedAt: now,
  );
  test('refresh is probabilistic without replacement within each batch', () {
    final a = BubbleRefreshSelector(random: Random(7));
    final b = BubbleRefreshSelector(random: Random(7));
    final notes = List.generate(12, note);
    for (var i = 0; i < 10; i++) {
      final batch = a.draw(notes);
      expect(batch.map((n) => n.id).toSet(), hasLength(5));
      expect(batch.map((n) => n.id), b.draw(notes).map((n) => n.id));
    }
    // Cross-batch overlap is allowed by the specified probability distribution.
    expect(a.draw([]), isEmpty);
    expect(a.draw(notes, count: 0), isEmpty);
    expect(a.draw(notes.take(2).toList(), count: 10), hasLength(2));
  });
}
