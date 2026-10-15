import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_refresh_service.dart';

void main() {
  final timestamp = DateTime(2026, 10, 15);
  Bubble bubble(int index, {int frequency = 3}) => Bubble(
    id: 'note-$index',
    title: 'Note $index',
    description: 'Body $index',
    createdAt: timestamp,
    updatedAt: timestamp,
    appearanceFrequency: frequency,
  );

  test('refresh draws from the whole library without a daily cache', () {
    final selector = BubbleRefreshSelector(random: Random(42));
    final all = List.generate(10, bubble);
    final first = selector.draw(all);
    final second = selector.draw(all);

    expect(first, hasLength(5));
    expect(second, hasLength(5));
    expect(first.map((note) => note.id).toSet(), hasLength(5));
    expect(second.map((note) => note.id).toSet(), hasLength(5));
    expect(
      first
          .map((note) => note.id)
          .toSet()
          .intersection(second.map((note) => note.id).toSet()),
      isEmpty,
    );
  });

  test('refresh maximizes fresh notes when fewer than five are available', () {
    final selector = BubbleRefreshSelector(random: Random(7));
    final notes = List.generate(7, bubble);
    final before = selector.draw(notes).map((note) => note.id).toSet();
    final after = selector.draw(notes).map((note) => note.id).toSet();
    expect(after.difference(before), hasLength(2));
  });

  test(
    'refresh rearranges all-visible notes and ignores calendar boundaries',
    () {
      final selector = BubbleRefreshSelector(random: Random(3));
      final notes = List.generate(3, bubble);
      final first = selector.draw(notes).map((note) => note.id).toList();
      final second = selector.draw(notes).map((note) => note.id).toList();
      expect(first.toSet(), second.toSet());
      expect(first, isNot(second));
    },
  );

  test('empty, single, and zero count selections are safe', () {
    final selector = BubbleRefreshSelector(random: Random(1));
    expect(selector.draw(const []), isEmpty);
    expect(selector.draw([bubble(1)]), hasLength(1));
    expect(selector.draw([bubble(1)], count: 0), isEmpty);
  });
}
