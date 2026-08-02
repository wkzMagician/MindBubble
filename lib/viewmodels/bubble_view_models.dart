import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';
import '../services/scheduler_service.dart';

final bubblesProvider =
    FutureProvider.family<List<Bubble>, String>((ref, query) async {
  ref.watch(bubbleRevisionProvider);
  ref.watch(databaseDataVersionProvider);
  return ref.watch(bubbleRepositoryProvider).getAll(query: query);
});

final todayBubblesProvider = FutureProvider<List<Bubble>>((ref) async {
  ref.watch(bubbleRevisionProvider);
  ref.watch(databaseDataVersionProvider);
  return ref.watch(schedulerProvider).getOrCreateDailyBubbles();
});
