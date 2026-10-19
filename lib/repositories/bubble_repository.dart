import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../features/recommendations/note_analyzer.dart';
import '../features/note_cover/note_cover_service.dart';
import '../features/recommendations/note_profile.dart';
import '../features/recommendations/recommendation_event_store.dart';

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
    analyzer: ref.watch(noteAnalyzerProvider),
    covers: ref.watch(noteCoverServiceProvider),
    onCoverCached: () => ref.read(syncServiceProvider).scheduleSync(),
  );
});

class BubbleRepository {
  BubbleRepository(
    this._store,
    this._dailyCache,
    this._identity,
    this._changed, {
    NoteAnalyzer? analyzer,
    NoteCoverService? covers,
    void Function()? onCoverCached,
    RecommendationEventStore? events,
  }) : _analyzer = analyzer,
       _covers = covers,
       _onCoverCached = onCoverCached,
       events =
           events ??
           RecommendationEventStore(
             File('${_store.supportRoot.path}/recommendation-events.jsonl'),
           );

  final BubbleDocumentStore _store;
  final DailySelectionCache _dailyCache;
  final DeviceIdentity _identity;
  final void Function() _changed;
  final NoteAnalyzer? _analyzer;
  final NoteCoverService? _covers;
  final void Function()? _onCoverCached;
  final RecommendationEventStore events;
  Future<void> _mutation = Future.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _mutation.then((_) => action());
    _mutation = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

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

  Future<void> save(Bubble bubble, {bool analyze = true}) async {
    bubble = await _covers?.prepare(bubble) ?? bubble;
    final isNew = await getById(bubble.id) == null;
    await _serialize(() => _store.save(bubble));
    _changed();
    if (isNew && analyze && bubble.profile == null) {
      await analyzeNotes([bubble]);
    }
  }

  /// Cache derived artwork without replacing concurrent feedback/exposure data
  /// or invalidating the current homepage recommendation batch.
  Future<void> ensureCover(Bubble original) async {
    final covers = _covers;
    if (covers == null) return;
    final prepared = await covers.prepare(original);
    if (jsonEncode(prepared.cover?.toJson()) ==
        jsonEncode(original.cover?.toJson())) {
      return;
    }
    var changed = false;
    await _serialize(() async {
      final current = await getById(original.id);
      if (current == null ||
          current.title != original.title ||
          current.description != original.description ||
          jsonEncode(current.cover?.toJson()) !=
              jsonEncode(original.cover?.toJson())) {
        return;
      }
      await _store.save(current.copyWith(cover: prepared.cover));
      changed = true;
    });
    if (changed) _onCoverCached?.call();
  }

  Future<void> analyzeNotes(
    List<Bubble> notes, {
    bool embeddingsOnly = false,
  }) async {
    final analyzer = _analyzer;
    if (analyzer == null || notes.isEmpty) return;
    Map<String, NoteProfile> profiles;
    try {
      profiles = embeddingsOnly
          ? await analyzer.embedOnly(notes)
          : await analyzer.analyze(notes);
    } on Object {
      if (embeddingsOnly) return;
      profiles = {
        for (final note in notes)
          note.id: note.effectiveProfile.copyWith(analysisStatus: 'failed'),
      };
    }
    await _serialize(() async {
      for (final original in notes) {
        final current = await getById(original.id);
        if (current == null ||
            current.title != original.title ||
            current.description != original.description ||
            jsonEncode(current.profile?.toJson()) !=
                jsonEncode(original.profile?.toJson())) {
          continue;
        }
        final profile = profiles[current.id];
        if (profile != null) {
          await _store.save(
            current.copyWith(profile: profile, updatedAt: DateTime.now()),
          );
        }
      }
    });
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

  Future<void> recordShown(
    List<String> ids,
    DateTime shownAt, {
    RecommendationChannel channel = RecommendationChannel.home,
    String? eventId,
  }) => _serialize(() async {
    final existingEvents = (await events.read()).map((e) => e.id).toSet();
    for (final id in ids.toSet()) {
      final key =
          '${eventId ?? '${_identity.id}:${shownAt.microsecondsSinceEpoch}'}:$id';
      if (existingEvents.contains(key)) continue;
      final bubble = await getById(id);
      if (bubble == null) continue;
      final current =
          bubble.shownByDevice[_identity.id] ?? const BubbleShowStats(count: 0);
      await _store.save(
        bubble.copyWith(
          updatedAt: shownAt.isAfter(bubble.updatedAt)
              ? shownAt
              : bubble.updatedAt,
          shownByDevice: {
            ...bubble.shownByDevice,
            _identity.id: BubbleShowStats(
              count: current.count + 1,
              lastShownAt:
                  current.lastShownAt != null &&
                      current.lastShownAt!.isAfter(shownAt)
                  ? current.lastShownAt
                  : shownAt,
            ),
          },
        ),
      );
      await events.append(
        RecommendationEvent(
          id: key,
          noteId: id,
          timestamp: shownAt,
          type: RecommendationEventType.shown,
          channel: channel,
        ),
      );
      existingEvents.add(key);
    }
    // Exposure updates must not trigger another homepage recommendation draw.
  });

  Future<void> feedback(
    String id,
    FrequencyFeedback feedback, {
    RecommendationChannel channel = RecommendationChannel.home,
    double step = .15,
  }) => _serialize(() async {
    final note = await getById(id);
    if (note == null) return;
    final delta = switch (feedback) {
      FrequencyFeedback.more => step,
      FrequencyFeedback.less => -step,
      _ => 0.0,
    };
    final now = DateTime.now();
    final preference = (note.preference + delta).clamp(-.6, .6);
    final enabled = feedback == FrequencyFeedback.stop
        ? false
        : note.recommendationEnabled;
    final changed =
        preference != note.preference || enabled != note.recommendationEnabled;
    if (changed) {
      await _store.save(
        note.copyWith(
          preference: preference,
          recommendationEnabled: enabled,
          updatedAt: now,
        ),
      );
    }
    await events.append(
      RecommendationEvent(
        id: '${_identity.id}:feedback:${now.microsecondsSinceEpoch}',
        noteId: id,
        timestamp: now,
        type: RecommendationEventType.feedback,
        channel: channel,
        feedback: feedback,
      ),
    );
    if (changed) _changed();
  });

  Future<void> recordBehavior(
    String id,
    RecommendationEventType type, {
    required RecommendationChannel channel,
    double durationSeconds = 0,
  }) => _serialize(() async {
    final note = await getById(id);
    if (note == null) return;
    final now = DateTime.now();
    await events.append(
      RecommendationEvent(
        id: '${_identity.id}:${type.name}:${now.microsecondsSinceEpoch}',
        noteId: id,
        timestamp: now,
        type: type,
        channel: channel,
        durationSeconds: durationSeconds.clamp(0, 86400),
      ),
    );
    // Opening alone is weak evidence; learn only after at least eight seconds.
    if (type == RecommendationEventType.read && durationSeconds >= 8) {
      final target = durationSeconds >= 30 ? 1.0 : .7;
      final profile = note.effectiveProfile;
      await _store.save(
        note.copyWith(
          profile: profile.copyWith(
            detailNeed:
                (profile.detailNeed + .03 * (target - profile.detailNeed))
                    .clamp(0, 1),
          ),
          updatedAt: now,
        ),
      );
    }
  });
}
