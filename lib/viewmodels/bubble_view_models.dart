import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';
import '../services/bubble_document_store.dart';
import '../services/bubble_refresh_service.dart';
import '../services/home_bubble_count.dart';

final bubblesProvider = FutureProvider.family<List<Bubble>, String>((
  ref,
  query,
) async {
  ref.watch(bubbleRevisionProvider);
  ref.watch(documentStoreRevisionProvider);
  return ref.watch(bubbleRepositoryProvider).getAll(query: query);
});

/// Incrementing this value requests a fresh, date-independent homepage draw.
final homeRefreshVersionProvider = StateProvider<int>((_) => 0);

final displayBubblesProvider = FutureProvider<List<Bubble>>((ref) async {
  ref.watch(bubbleRevisionProvider);
  ref.watch(documentStoreRevisionProvider);
  ref.watch(homeRefreshVersionProvider);
  final count = ref.watch(homeBubbleCountProvider);
  return ref.watch(bubbleRefreshServiceProvider).refresh(count: count);
});
