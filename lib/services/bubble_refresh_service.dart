import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';

/// The homepage refresh selector has no calendar or daily-cache dependency.
final bubbleRefreshServiceProvider = Provider<BubbleRefreshService>(
  (ref) => BubbleRefreshService(ref.watch(bubbleRepositoryProvider)),
);

class BubbleRefreshService {
  BubbleRefreshService(this._repository, {BubbleRefreshSelector? selector})
    : _selector = selector ?? BubbleRefreshSelector();

  final BubbleRepository _repository;
  final BubbleRefreshSelector _selector;

  Future<List<Bubble>> refresh({int count = 5}) async {
    return _selector.draw(await _repository.getAll(), count: count);
  }
}

/// Picks a new weighted sample. Unseen-in-previous-batch bubbles come first,
/// so refresh visibly changes the sample whenever the note pool allows it.
class BubbleRefreshSelector {
  BubbleRefreshSelector({Random? random}) : _random = random ?? Random();

  final Random _random;
  List<String> _previousIds = const [];

  List<Bubble> draw(List<Bubble> bubbles, {int count = 5}) {
    if (count <= 0) return const [];
    final active = bubbles.where((bubble) => !bubble.isDeleted).toList();
    final targetCount = min(count, active.length);
    if (targetCount == 0) {
      _previousIds = const [];
      return const [];
    }

    final previous = _previousIds.toSet();
    final fresh = active.where((bubble) => !previous.contains(bubble.id));
    final selected = _takeWeighted(fresh.toList(), targetCount);
    final selectedIds = selected.map((bubble) => bubble.id).toSet();
    if (selected.length < targetCount) {
      selected.addAll(
        _takeWeighted(
          active.where((bubble) => !selectedIds.contains(bubble.id)).toList(),
          targetCount - selected.length,
        ),
      );
    }

    selected.shuffle(_random);
    if (selected.length > 1 &&
        _previousIds.length == selected.length &&
        List.generate(
          selected.length,
          (index) => selected[index].id == _previousIds[index],
        ).every((same) => same)) {
      // Even when every note is displayed, refresh should change the layout.
      selected.add(selected.removeAt(0));
    }
    _previousIds = selected.map((bubble) => bubble.id).toList();
    return selected;
  }

  List<Bubble> _takeWeighted(List<Bubble> candidates, int count) {
    final pool = List<Bubble>.of(candidates);
    final result = <Bubble>[];
    while (pool.isNotEmpty && result.length < count) {
      final sum = pool.fold<int>(
        0,
        (total, bubble) => total + bubble.appearanceFrequency,
      );
      var position = _random.nextInt(sum);
      var chosen = 0;
      for (; chosen < pool.length - 1; chosen++) {
        position -= pool[chosen].appearanceFrequency;
        if (position < 0) break;
      }
      result.add(pool.removeAt(chosen));
    }
    return result;
  }
}
