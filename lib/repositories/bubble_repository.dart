import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bubble.dart';
import '../models/daily_selection.dart';
import '../services/bubble_document_store.dart';
import '../services/daily_selection_cache.dart';
import '../services/device_identity_service.dart';
import '../services/sync_service.dart';

final bubbleRevisionProvider = StateProvider<int>((_) => 0);

final bubbleRepositoryProvider = Provider<BubbleRepository>((ref) {
  return BubbleRepository(
    ref.watch(bubbleDocumentStoreProvider),
    ref.watch(dailySelectionCacheProvider),
    ref.watch(deviceIdentityProvider),
    () {
      ref.read(bubbleRevisionProvider.notifier).state++;
      ref.read(syncServiceProvider).scheduleSync();
    },
  );
});

class BubbleRepository {
  BubbleRepository(
    this._store,
    this._dailyCache,
    this._identity,
    this._changed,
  );

  final BubbleDocumentStore _store;
  final DailySelectionCache _dailyCache;
  final DeviceIdentity _identity;
  final void Function() _changed;

  Future<List<Bubble>> getAll({
    String query = '',
    bool includeDeleted = false,
  }) async {
    final normalized = query.trim().toLowerCase();
    final bubbles = await _store.readAll();
    return bubbles.where((bubble) {
      if (!includeDeleted && bubble.isDeleted) return false;
      if (normalized.isEmpty) return true;
      return bubble.title.toLowerCase().contains(normalized) ||
          bubble.description.toLowerCase().contains(normalized);
    }).toList();
  }

  Future<void> save(Bubble bubble) async {
    await _store.save(bubble);
    _changed();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    _changed();
  }

  Future<Bubble?> getById(String id, {bool includeDeleted = false}) async {
    final document = await _store.readDocument(id);
    final bubble = document?.bubble;
    if (bubble == null || (!includeDeleted && bubble.isDeleted)) return null;
    return bubble;
  }

  Future<void> updateFrequency(String id, int frequency) async {
    if (frequency < 1 || frequency > 5) {
      throw ArgumentError.value(frequency, 'frequency');
    }
    final bubble = await getById(id);
    if (bubble == null) return;
    await save(
      bubble.copyWith(
        appearanceFrequency: frequency,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<DailySelection?> getDailySelection(String date) =>
      _dailyCache.read(date);

  Future<void> saveDailySelection(DailySelection selection) =>
      _dailyCache.write(selection);

  Future<void> recordShown(List<String> ids, DateTime shownAt) async {
    for (final id in ids) {
      final bubble = await getById(id);
      if (bubble == null) continue;
      final current =
          bubble.shownByDevice[_identity.id] ?? const BubbleShowStats(count: 0);
      await _store.save(
        bubble.copyWith(
          updatedAt: shownAt,
          shownByDevice: {
            ...bubble.shownByDevice,
            _identity.id: BubbleShowStats(
              count: current.count + 1,
              lastShownAt: shownAt,
            ),
          },
        ),
      );
    }
    _changed();
  }
}
